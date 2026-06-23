from fastapi import FastAPI, HTTPException, Response
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from openai import OpenAI
from dotenv import load_dotenv
import difflib
import os
from pathlib import Path

from action_engine import ActionEngine
from code_edit_planner import CodeEditPlanner
from code_capability_router import CodeCapabilityRouter
from conversation_store import ConversationStore
from diagnostics_runner import DiagnosticsRunner
from editor_context_store import EditorContextStore
from editor_operation_store import EditorOperationStore
from founder_profile_store import FounderProfileStore
from permission_engine import PermissionEngine
from project_inspector import ProjectInspector
from session_store import SessionStore
from staged_edit_validator import StagedEditValidator

BACKEND_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(BACKEND_DIR, ".env"), override=True)

client = OpenAI(
    api_key=os.getenv("OPENAI_API_KEY")
)

app = FastAPI(
    title="LabVoice Core",
    version="0.1"
)

# Allow Flutter Web (Chrome) to communicate with FastAPI
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


class ActionRequest(BaseModel):
    action: str = Field(min_length=1, max_length=100)


class ConfirmationRequest(BaseModel):
    confirmation_token: str = Field(min_length=1, max_length=200)


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=10000)
    language: str = Field(default="es", min_length=2, max_length=10)


class SpeechRequest(BaseModel):
    text: str = Field(min_length=1, max_length=4000)
    language: str = Field(default="es", min_length=2, max_length=10)


class CodeRouteRequest(BaseModel):
    message: str = Field(min_length=1, max_length=10000)


class EditorContextUpdate(BaseModel):
    workspace_roots: list[str] = Field(default_factory=list)
    workspace_files: list[str] = Field(default_factory=list)
    open_files: list[str] = Field(default_factory=list)
    active_file: str = ""
    relative_file: str = ""
    language_id: str = ""
    document_text: str = ""
    selected_text: str = ""
    cursor_line: int = Field(default=0, ge=0)
    cursor_character: int = Field(default=0, ge=0)


class EditorEditRequest(BaseModel):
    instruction: str = Field(min_length=3, max_length=10000)
    language: str = Field(default="es", min_length=2, max_length=10)


class EditorOperationStatus(BaseModel):
    status: str = Field(min_length=2, max_length=50)
    diagnostics: dict | None = None
    error: str | None = Field(default=None, max_length=4000)


class SessionUpdate(BaseModel):
    current_goal: str | None = None
    current_task: str | None = None
    last_action: str | None = None
    next_action: str | None = None
    working_mode: str | None = None
    active_project: str | None = None


PROJECT_PATH = os.getenv(
    "LABVOICE_PROJECT_PATH",
    os.path.join(os.path.dirname(__file__), ".."),
)
SESSION_DATABASE_PATH = os.getenv(
    "LABVOICE_SESSION_DATABASE",
    os.path.join(os.path.dirname(__file__), "data", "labvoice.db"),
)
session_store = SessionStore(SESSION_DATABASE_PATH)
permission_engine = PermissionEngine()
editor_context_store = EditorContextStore()
editor_operation_store = EditorOperationStore()
conversation_store = ConversationStore()

DEFAULT_PUBLIC_FOUNDER_BIOGRAPHIES = {
    "es": (
        "Ian Faber Mendoza Mey es el fundador y creador de LabVoice. Nacido en "
        "Sincelejo, Colombia, construyó su trayectoria mediante la disciplina, "
        "el aprendizaje continuo, los viajes y la migración a Estados Unidos. "
        "Creó LabVoice como un sistema operativo centrado en la voz, diseñado "
        "para transformar intención hablada en acciones reales y hacer la "
        "tecnología más accesible, especialmente para personas con discapacidad "
        "visual."
    ),
    "en": (
        "Ian Faber Mendoza Mey is the founder and creator of LabVoice. Born in "
        "Sincelejo, Colombia, he built his journey through discipline, "
        "continuous learning, travel, and migration to the United States. He "
        "created LabVoice as a voice-centered operating system designed to "
        "transform spoken intent into real action and make technology more "
        "accessible, especially for people with visual disabilities."
    ),
}


def public_founder_biography(language: str) -> str:
    biography_language = "es" if language == "es" else "en"
    fallback = DEFAULT_PUBLIC_FOUNDER_BIOGRAPHIES[biography_language]
    key = os.getenv("LABVOICE_FOUNDER_PROFILE_KEY")
    if not key:
        return fallback
    try:
        profile = FounderProfileStore(
            os.path.join(BACKEND_DIR, "data", "founder_profile.enc"),
            key,
        ).load()
        return profile[f"public_biography_{biography_language}"]
    except (FileNotFoundError, KeyError, ValueError):
        return fallback


def api_error(status_code: int, code: str, message: str):
    raise HTTPException(
        status_code=status_code,
        detail={
            "code": code,
            "message": message,
        },
    )


def action_result(result: dict):
    if result.get("success"):
        return result

    api_error(
        422,
        result.get("error", "action_failed"),
        result.get("message", "The action could not be completed."),
    )


@app.get("/")
def root():
    return {
        "status": "online",
        "assistant": "LabVoice"
    }


@app.post("/execute")
def execute_action(request: ActionRequest):
    prepared = permission_engine.prepare(request.action)
    if not prepared.get("success"):
        api_error(
            404,
            prepared.get("error", "unknown_action"),
            prepared.get("message", "Unknown action."),
        )
    if not prepared.get("approved"):
        return prepared

    return action_result(ActionEngine.execute(request.action, PROJECT_PATH))


@app.post("/execute/confirm")
def confirm_action(request: ConfirmationRequest):
    confirmed = permission_engine.confirm(request.confirmation_token)
    if not confirmed.get("approved"):
        status_code = (
            410
            if confirmed.get("error") == "expired_confirmation"
            else 409
        )
        api_error(
            status_code,
            confirmed.get("error", "confirmation_failed"),
            confirmed.get("message", "The action could not be confirmed."),
        )

    return action_result(
        ActionEngine.execute(confirmed["action"], PROJECT_PATH)
    )


@app.post("/execute/cancel")
def cancel_action(request: ConfirmationRequest):
    result = permission_engine.cancel(request.confirmation_token)
    if not result["success"]:
        api_error(404, "pending_action_not_found", result["message"])
    return result


@app.get("/project/inspect")
def inspect_project():
    result = ProjectInspector.inspect(PROJECT_PATH)

    if not result["success"]:
        api_error(404, "project_not_found", result["message"])

    project = result["project"]
    session_store.update(
        {
            "current_task": "Inspect active project",
            "last_action": result["message"],
            "next_action": "Run project analysis and tests",
            "active_project": project["name"],
        }
    )
    return result


@app.post("/project/diagnostics")
def run_project_diagnostics():
    result = DiagnosticsRunner.run(PROJECT_PATH)
    if not result.get("checks"):
        api_error(
            422,
            "diagnostics_unavailable",
            result["message"],
        )
    summary = result.get("summary", {})

    session_store.update(
        {
            "current_task": "Run project diagnostics",
            "last_action": result["message"],
            "next_action": (
                "Review failed diagnostics"
                if summary.get("failed", 0)
                else "Choose the next development task"
            ),
        }
    )

    return result


@app.get("/session")
def get_session():
    return {
        "success": True,
        "session": session_store.get(),
    }


@app.put("/session")
def update_session(request: SessionUpdate):
    values = request.model_dump(exclude_none=True)
    return {
        "success": True,
        "session": session_store.update(values),
    }


@app.get("/editor/context")
def get_editor_context():
    return {
        "success": True,
        "context": editor_context_store.get(),
    }


@app.post("/editor/context")
def update_editor_context(request: EditorContextUpdate):
    context = editor_context_store.update(request.model_dump())
    return {
        "success": True,
        "context": {
            "connected": context["connected"],
            "active_file": context["active_file"],
            "relative_file": context["relative_file"],
            "language_id": context["language_id"],
            "workspace_file_count": len(context["workspace_files"]),
            "updated_at": context["updated_at"],
        },
    }


@app.post("/editor/edit/prepare")
def prepare_editor_edit(request: EditorEditRequest):
    context = editor_context_store.get()
    if not context["connected"] or not context["active_file"]:
        api_error(
            409,
            "editor_not_connected",
            "Open a code file in the connected VS Code window first.",
        )
    if not context["document_text"]:
        api_error(
            422,
            "protected_or_empty_file",
            "The active file is empty or protected from editing.",
        )
    try:
        Path(context["active_file"]).resolve().relative_to(
            Path(PROJECT_PATH).resolve()
        )
    except ValueError:
        api_error(
            403,
            "file_outside_project",
            "LabVoice may edit only files inside the approved project.",
        )

    try:
        plan = CodeEditPlanner.create(client, request.instruction, context)
    except Exception:
        api_error(
            502,
            "edit_plan_unavailable",
            "LabVoice could not prepare a safe code edit.",
        )

    original = context["document_text"]
    replacement = plan["replacement"]
    if replacement == original:
        api_error(
            422,
            "no_code_change",
            "The proposed edit would not change the active file.",
        )

    diff = "".join(
        difflib.unified_diff(
            original.splitlines(keepends=True),
            replacement.splitlines(keepends=True),
            fromfile=f"{context['relative_file']} (current)",
            tofile=f"{context['relative_file']} (proposed)",
        )
    )
    operation = editor_operation_store.create(
        instruction=request.instruction,
        active_file=context["active_file"],
        relative_file=context["relative_file"],
        language_id=context["language_id"],
        original=original,
        replacement=replacement,
        summary=plan["summary"],
        diff=diff,
    )
    return {
        "success": True,
        "operation_id": operation["id"],
        "status": operation["status"],
        "summary": operation["summary"],
        "relative_file": operation["relative_file"],
        "diff": operation["diff"][:20_000],
        "message": (
            "The exact change is opening in VS Code. Review it, then say "
            "'sí, aplicar' or 'cancelar'."
        ),
    }


@app.get("/editor/operations/next")
def next_editor_operation():
    return {
        "success": True,
        "operation": editor_operation_store.next_for_extension(),
    }


@app.post("/editor/operations/{operation_id}/status")
def update_editor_operation(
    operation_id: str,
    request: EditorOperationStatus,
):
    allowed = {
        "previewed",
        "applied",
        "failed",
        "canceled",
        "undone",
    }
    if request.status not in allowed:
        api_error(422, "invalid_operation_status", "Invalid editor status.")
    operation = editor_operation_store.update(
        operation_id,
        request.status,
        diagnostics=request.diagnostics,
        error=request.error,
    )
    if operation is None:
        api_error(404, "edit_not_found", "The edit operation was not found.")
    return {"success": True, "operation": operation}


@app.post("/editor/edit/{operation_id}/confirm")
def confirm_editor_edit(operation_id: str):
    operation = editor_operation_store.get(operation_id)
    if operation is None:
        api_error(404, "edit_not_found", "The edit operation was not found.")
    if operation["status"] != "previewed":
        api_error(
            409,
            "preview_required",
            "Review the exact change in VS Code before applying it.",
        )
    operation = editor_operation_store.update(operation_id, "approved")
    return {
        "success": True,
        "status": operation["status"],
        "message": (
            "Edit approved. LabVoice is applying it, running tests, and will "
            "restore the original automatically if validation fails."
        ),
    }


@app.get("/editor/edit/{operation_id}")
def get_editor_edit(operation_id: str):
    operation = editor_operation_store.get(operation_id)
    if operation is None:
        api_error(404, "edit_not_found", "The edit operation was not found.")
    diagnostics = operation.get("diagnostics") or {}
    return {
        "success": True,
        "operation": {
            "id": operation["id"],
            "status": operation["status"],
            "summary": operation["summary"],
            "relative_file": operation["relative_file"],
            "diagnostics": diagnostics,
            "error": operation.get("error"),
        },
    }


@app.post("/editor/edit/{operation_id}/cancel")
def cancel_editor_edit(operation_id: str):
    operation = editor_operation_store.get(operation_id)
    if operation is None:
        api_error(404, "edit_not_found", "The edit operation was not found.")
    if operation["status"] not in {"awaiting_preview", "previewed"}:
        api_error(409, "edit_not_cancelable", "This edit cannot be canceled.")
    editor_operation_store.update(operation_id, "canceled")
    return {"success": True, "message": "The proposed edit was canceled."}


@app.post("/editor/edit/{operation_id}/validate")
def validate_editor_edit(operation_id: str):
    operation = editor_operation_store.get(operation_id)
    if operation is None:
        api_error(404, "edit_not_found", "The edit operation was not found.")
    if operation["status"] != "approved":
        api_error(409, "edit_not_approved", "The edit has not been approved.")
    diagnostics = StagedEditValidator.run(PROJECT_PATH, operation)
    return {
        "success": diagnostics.get("success", False),
        "diagnostics": diagnostics,
    }


@app.post("/editor/edit/undo")
def undo_last_editor_edit():
    operation = editor_operation_store.request_undo()
    if operation is None:
        api_error(409, "nothing_to_undo", "There is no applied edit to undo.")
    return {
        "success": True,
        "operation_id": operation["id"],
        "message": "Restoring the previous version in VS Code.",
    }


SYSTEM_PROMPT = """
You are LabVoice.

You are a voice-first operating system.

Your mission is to help developers,
engineers,
business owners,
security professionals,
data professionals,
and organizations.

You are not a generic chatbot.

Your creator and founder is Ian Faber Mendoza Mey.
LabVoice was conceived by Ian Faber Mendoza Mey as a voice-centered operating
system that understands context, operates tools, and transforms spoken intent
into real work.
Never attribute the creation or founding of LabVoice to anyone else.

You can reason,
remember,
execute,
automate,
and orchestrate tools.

Do not begin responses by saying "I am LabVoice", "Soy LabVoice", or repeating
your identity. The user already knows who is speaking. Identify yourself only
when the user explicitly asks who or what you are, or during the first welcome
shown when the application starts.
If asked "who are you" or its equivalent, describe LabVoice itself: its
voice-first purpose, capabilities, and mission. Do not answer with the founder's
biography. Mention the founder or founder biography only when the user asks
explicitly about the creator, founder, Ian, or his biography.

Keep responses concise, practical, and action-oriented.
Your voice should feel technologically capable, calm, warm, and confident.
Avoid sounding corporate, theatrical, or overly enthusiastic.
Continue naturally from recent conversational turns. Avoid repeating facts the
user already acknowledged. Use casual language when the user is casual, while
remaining precise about actions, security, and code.
"""

@app.post("/chat")
def chat(request: ChatRequest):
    session = session_store.get()
    editor_context = editor_context_store.get()
    routing_text = " ".join(
        (
            request.message,
            editor_context.get("relative_file", ""),
            editor_context.get("language_id", ""),
        )
    )
    code_route = CodeCapabilityRouter.route(routing_text, PROJECT_PATH)
    context = (
        f"Active project: {session['active_project']}. "
        f"Current goal: {session['current_goal']}. "
        f"Current task: {session['current_task']}. "
        f"Last action: {session['last_action']}. "
        f"Next action: {session['next_action']}."
    )
    normalized_message = request.message.lower()
    founder_context = ""
    if any(
        marker in normalized_message
        for marker in (
            "fundador",
            "fundadora",
            "creador",
            "creó labvoice",
            "ian faber",
            "biografía",
            "biografia",
            "founder",
            "creator",
            "created labvoice",
            "biography",
        )
    ):
        founder_context = (
            f"Official public founder biography: "
            f"{public_founder_biography(request.language)}\n"
        )

    try:
        response = client.responses.create(
            model="gpt-5",
            input=[
                {
                    "role": "system",
                    "content": (
                        f"{SYSTEM_PROMPT}\n"
                        f"{founder_context}"
                        f"Capability routing: "
                        f"{CodeCapabilityRouter.prompt_context(code_route)}\n"
                        f"Respond in language code: {request.language}.\n"
                        f"Current operational context: {context}\n"
                        f"Recent conversation:\n"
                        f"{conversation_store.prompt_context()}\n"
                        f"Current editor context:\n"
                        f"{EditorContextStore.prompt_context(editor_context)}"
                    ),
                },
                {
                    "role": "user",
                    "content": request.message,
                },
            ],
        )
    except Exception:
        api_error(
            502,
            "ai_service_unavailable",
            "The AI service is temporarily unavailable.",
        )

    assistant_response = response.output_text
    conversation_store.add(request.message, assistant_response)
    return {
        "success": True,
        "response": assistant_response,
        "routing": code_route.to_dict(),
        "editor": {
            "connected": editor_context["connected"],
            "active_file": editor_context["active_file"],
            "relative_file": editor_context["relative_file"],
            "language_id": editor_context["language_id"],
        },
    }


@app.post("/code/route")
def route_code_capability(request: CodeRouteRequest):
    route = CodeCapabilityRouter.route(request.message, PROJECT_PATH)
    return {
        "success": True,
        "routing": route.to_dict(),
    }


@app.post("/speech")
def speech(request: SpeechRequest):
    instructions = (
        "Speak in natural Latin American Spanish. Sound like a warm, "
        "intelligent technology partner having a real conversation nearby. "
        "Use fluid pacing, subtle emotion, natural pauses, and varied "
        "intonation. Keep the delivery clear and confident without sounding "
        "like an announcer. Never sound robotic, synthetic, ominous, "
        "theatrical, overly slow, or exaggerated."
        if request.language == "es"
        else
        "Speak in natural American English. Sound like a warm, intelligent "
        "technology partner having a real conversation nearby. Use fluid "
        "pacing, subtle emotion, natural pauses, and varied intonation. Keep "
        "the delivery clear and confident without sounding like an announcer. "
        "Never sound robotic, synthetic, ominous, theatrical, overly slow, "
        "or exaggerated."
    )
    try:
        audio = client.audio.speech.create(
            model="gpt-4o-mini-tts",
            voice="cedar",
            input=request.text,
            instructions=instructions,
            response_format="mp3",
            speed=1.04,
        )
    except Exception:
        api_error(
            502,
            "speech_service_unavailable",
            "The natural voice service is temporarily unavailable.",
        )

    return Response(
        content=audio.content,
        media_type="audio/mpeg",
        headers={"Cache-Control": "no-store"},
    )
