from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from openai import OpenAI
from dotenv import load_dotenv
import os

from action_engine import ActionEngine
from diagnostics_runner import DiagnosticsRunner
from permission_engine import PermissionEngine
from project_inspector import ProjectInspector
from session_store import SessionStore

load_dotenv()

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
    action: str


class ConfirmationRequest(BaseModel):
    confirmation_token: str


class ChatRequest(BaseModel):
    message: str


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


@app.get("/")
def root():
    return {
        "status": "online",
        "assistant": "LabVoice"
    }


@app.post("/execute")
def execute_action(request: ActionRequest):
    prepared = permission_engine.prepare(request.action)
    if not prepared.get("approved"):
        return prepared

    return ActionEngine.execute(request.action, PROJECT_PATH)


@app.post("/execute/confirm")
def confirm_action(request: ConfirmationRequest):
    confirmed = permission_engine.confirm(request.confirmation_token)
    if not confirmed.get("approved"):
        return confirmed

    return ActionEngine.execute(confirmed["action"], PROJECT_PATH)


@app.post("/execute/cancel")
def cancel_action(request: ConfirmationRequest):
    return permission_engine.cancel(request.confirmation_token)


@app.get("/project/inspect")
def inspect_project():
    result = ProjectInspector.inspect(PROJECT_PATH)

    if result["success"]:
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

You can reason,
remember,
execute,
automate,
and orchestrate tools.

Always identify yourself as LabVoice.

Keep responses concise, practical, and action-oriented.
"""

@app.post("/chat")
def chat(request: ChatRequest):

    response = client.responses.create(
        model="gpt-5",
       input=[
    {
        "role": "system",
        "content": SYSTEM_PROMPT
    },
    {
        "role": "user",
        "content": request.message
    }
]
    )

    return {
        "success": True,
        "response": response.output_text
    }
