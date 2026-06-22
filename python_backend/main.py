from fastapi import FastAPI, HTTPException, Response
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from openai import OpenAI
from dotenv import load_dotenv
import os

from action_engine import ActionEngine
from diagnostics_runner import DiagnosticsRunner
from founder_profile_store import FounderProfileStore
from permission_engine import PermissionEngine
from project_inspector import ProjectInspector
from session_store import SessionStore

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

DEFAULT_PUBLIC_FOUNDER_BIOGRAPHY = (
    "Ian Faber Mendoza Mey is the founder and creator of LabVoice. Born in "
    "Sincelejo, Colombia, he built his path through discipline, continuous "
    "learning, travel, and migration to the United States. He created LabVoice "
    "as a voice-centered operating system designed to transform spoken intent "
    "into real action and make technology more accessible, especially for "
    "people with visual disabilities."
)


def public_founder_biography() -> str:
    key = os.getenv("LABVOICE_FOUNDER_PROFILE_KEY")
    if not key:
        return DEFAULT_PUBLIC_FOUNDER_BIOGRAPHY
    try:
        profile = FounderProfileStore(
            os.path.join(BACKEND_DIR, "data", "founder_profile.enc"),
            key,
        ).load()
        return profile["public_biography"]
    except (FileNotFoundError, KeyError, ValueError):
        return DEFAULT_PUBLIC_FOUNDER_BIOGRAPHY


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

Always identify yourself as LabVoice.

Keep responses concise, practical, and action-oriented.
Your voice should feel technologically capable, calm, warm, and confident.
Avoid sounding corporate, theatrical, or overly enthusiastic.
"""

@app.post("/chat")
def chat(request: ChatRequest):
    session = session_store.get()
    context = (
        f"Active project: {session['active_project']}. "
        f"Current goal: {session['current_goal']}. "
        f"Current task: {session['current_task']}. "
        f"Last action: {session['last_action']}. "
        f"Next action: {session['next_action']}."
    )
    try:
        response = client.responses.create(
            model="gpt-5",
            input=[
                {
                    "role": "system",
                    "content": (
                        f"{SYSTEM_PROMPT}\n"
                        f"Official public founder biography: "
                        f"{public_founder_biography()}\n"
                        f"Respond in language code: {request.language}.\n"
                        f"Current operational context: {context}"
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

    return {
        "success": True,
        "response": response.output_text,
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
            response_format="wav",
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
        media_type="audio/wav",
        headers={"Cache-Control": "no-store"},
    )
