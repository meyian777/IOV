from dataclasses import asdict, dataclass

from command_interpreter import CommandInterpreter


@dataclass(frozen=True)
class WorkflowStep:
    id: str
    title: str
    capability: str
    risk: str
    requires_confirmation: bool
    validation: str

    def to_dict(self) -> dict:
        return asdict(self)


class WorkflowOrchestrator:
    @staticmethod
    def plan(transcript: str) -> dict:
        interpreted = CommandInterpreter.interpret(transcript)
        steps = WorkflowOrchestrator._steps_for_intent(interpreted.intent)
        return {
            "success": True,
            "transcript": transcript,
            "intent": interpreted.intent,
            "action": interpreted.action,
            "risk": WorkflowOrchestrator._workflow_risk(steps),
            "requires_confirmation": any(
                step.requires_confirmation for step in steps
            ),
            "state_policy": {
                "memory_required": True,
                "audit_required": True,
                "rollback_required": any(
                    step.risk in {"write", "process_execution", "system"}
                    for step in steps
                ),
            },
            "steps": [step.to_dict() for step in steps],
        }

    @staticmethod
    def _steps_for_intent(intent: str) -> list[WorkflowStep]:
        if intent == "inspect_project":
            return [
                WorkflowStep(
                    "understand",
                    "Understand active project request",
                    "intent_interpretation",
                    "read_only",
                    False,
                    "Intent and active project are known.",
                ),
                WorkflowStep(
                    "inspect",
                    "Inspect project metadata, Git state and files",
                    "project_inspector",
                    "read_only",
                    False,
                    "Project inspection returns success.",
                ),
                WorkflowStep(
                    "remember",
                    "Save session state and next action",
                    "session_memory",
                    "read_only",
                    False,
                    "Session next_action is updated.",
                ),
            ]

        if intent == "run_diagnostics":
            return [
                WorkflowStep(
                    "confirm",
                    "Confirm diagnostic execution",
                    "permission_engine",
                    "process_execution",
                    True,
                    "User confirmation is present for execution.",
                ),
                WorkflowStep(
                    "run",
                    "Run tests and analysis",
                    "diagnostics_runner",
                    "process_execution",
                    True,
                    "Every check reports exit code and output.",
                ),
                WorkflowStep(
                    "summarize",
                    "Explain failures and next step",
                    "workflow_summary",
                    "read_only",
                    False,
                    "Summary includes failed checks and recommended action.",
                ),
            ]

        if intent == "run_python_script":
            return [
                WorkflowStep(
                    "select_script",
                    "Resolve approved project-relative Python script",
                    "python_executor",
                    "read_only",
                    False,
                    "Script path stays inside the project.",
                ),
                WorkflowStep(
                    "confirm_execution",
                    "Confirm Python execution",
                    "permission_engine",
                    "process_execution",
                    True,
                    "Confirmation token is valid and single-use.",
                ),
                WorkflowStep(
                    "execute",
                    "Execute script in constrained Python executor",
                    "python_executor",
                    "process_execution",
                    True,
                    "Exit code, stdout and stderr are captured.",
                ),
                WorkflowStep(
                    "audit",
                    "Audit execution result",
                    "audit_store",
                    "read_only",
                    False,
                    "Audit event is appended without secrets.",
                ),
            ]

        if intent == "conversation":
            return [
                WorkflowStep(
                    "answer",
                    "Answer conversational request",
                    "conversation",
                    "read_only",
                    False,
                    "Response is produced without local side effects.",
                )
            ]

        return [
            WorkflowStep(
                "interpret",
                "Interpret command",
                "intent_interpretation",
                "read_only",
                False,
                "Intent is classified.",
            ),
            WorkflowStep(
                "authorize",
                "Apply permission policy",
                "permission_engine",
                "system" if intent.startswith("open_") else "read_only",
                intent.startswith("open_"),
                "Policy returns approved or confirmation required.",
            ),
        ]

    @staticmethod
    def _workflow_risk(steps: list[WorkflowStep]) -> str:
        priority = ["read_only", "write", "process_execution", "system"]
        highest = "read_only"
        for step in steps:
            if priority.index(step.risk) > priority.index(highest):
                highest = step.risk
        return highest
