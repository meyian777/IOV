import difflib
from collections import defaultdict, deque
from contextlib import asynccontextmanager
from hashlib import sha256
import os
from pathlib import Path
import tempfile
import time
from urllib.parse import urlparse

os.environ.setdefault("PYDANTIC_DISABLE_PLUGINS", "1")

from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from starlette.concurrency import run_in_threadpool

from dotenv import load_dotenv

from action_engine import ActionEngine
from audit_store import AuditStore
from capability_registry import CapabilityRegistry
from code_edit_planner import CodeEditPlanner
from code_capability_router import CodeCapabilityRouter
from command_interpreter import CommandInterpreter
from conversation_store import ConversationStore
from core_health import CoreHealth
from diagnostics_runner import DiagnosticsRunner
from editor_context_store import EditorContextStore
from editor_operation_store import EditorOperationStore
from enterprise_auth import EnterpriseAuthStore, ROLE_PERMISSIONS
from file_access_layer import FileAccessError, FileAccessLayer
from founder_profile_store import FounderProfileStore
from local_whisper_engine import LocalWhisperEngine, LocalWhisperError
from ml_framework_registry import MLFrameworkRegistry
from ml_provider import MLProviderManager
from native_policy_client import NativePolicyClient
from permission_engine import PermissionEngine
from project_inspector import ProjectInspector
from python_executor import PythonExecutor
from session_store import SessionStore
from speaker_identity import LocalVoiceprintProvider, SpeakerIdentityService
from staged_edit_validator import StagedEditValidator
from workflow_orchestrator import WorkflowOrchestrator

BACKEND_DIR = os.path.dirname(os.path.abspath(__file__))
if os.getenv("OSVOZ_ENV_PRELOADED") != "1":
    load_dotenv(os.path.join(BACKEND_DIR, ".env"), override=True)

_openai_client = None
_latency_samples = defaultdict(lambda: deque(maxlen=120))
_warmup_status = {
    "ready": False,
    "steps": {},
}


def openai_client():
    global _openai_client
    if _openai_client is None:
        from openai import OpenAI

        _openai_client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))
    return _openai_client


@asynccontextmanager
async def lifespan(app: FastAPI):
    warm_runtime_dependencies()
    yield


def warm_runtime_dependencies():
    steps = {}
    started_at = time.perf_counter()
    for name, loader in (
        ("native_authorization_core", native_policy_client.health),
        ("local_speech_recognition", local_whisper_engine.status),
        ("ml_framework_boundary", MLFrameworkRegistry.inspect),
    ):
        step_started_at = time.perf_counter()
        try:
            result = loader()
            steps[name] = {
                "success": bool(result.get("success")),
                "elapsed_ms": round((time.perf_counter() - step_started_at) * 1000, 2),
            }
        except Exception as error:
            steps[name] = {
                "success": False,
                "elapsed_ms": round((time.perf_counter() - step_started_at) * 1000, 2),
                "error": error.__class__.__name__,
            }
    _warmup_status.update(
        {
            "ready": True,
            "elapsed_ms": round((time.perf_counter() - started_at) * 1000, 2),
            "steps": steps,
        }
    )


app = FastAPI(
    title="OSvoz Core",
    version="0.1",
    lifespan=lifespan,
)

# Allow Flutter Web (Chrome) to communicate with FastAPI
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def add_latency_headers(request: Request, call_next):
    started_at = time.perf_counter()
    response = await call_next(request)
    elapsed_ms = (time.perf_counter() - started_at) * 1000
    _latency_samples[f"{request.method} {request.url.path}"].append(elapsed_ms)
    response.headers["X-OSvoz-Elapsed-Ms"] = f"{elapsed_ms:.2f}"
    response.headers["Server-Timing"] = f"app;dur={elapsed_ms:.2f}"
    return response


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    return JSONResponse(
        status_code=500,
        content={
            "detail": {
                "code": "internal_error",
                "message": "OSvoz backend hit an unexpected error.",
                "path": str(request.url.path),
            }
        },
    )


class ActionRequest(BaseModel):
    action: str = Field(min_length=1, max_length=100)


class BrowserOpenRequest(BaseModel):
    url: str = Field(min_length=8, max_length=2000)


class YouTubePlayRequest(BaseModel):
    query: str = Field(min_length=1, max_length=300)
    auto_skip_ads: bool = False


class MusicPlayRequest(BaseModel):
    query: str = Field(min_length=1, max_length=300)
    platform: str = Field(default="youtube", min_length=3, max_length=40)
    auto_skip_ads: bool = False


class ConfirmationRequest(BaseModel):
    confirmation_token: str = Field(min_length=1, max_length=200)


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=10000)
    language: str = Field(default="es", min_length=2, max_length=10)


class SpeechRequest(BaseModel):
    text: str = Field(min_length=1, max_length=4000)
    language: str = Field(default="es", min_length=2, max_length=10)


class VoiceInterpretRequest(BaseModel):
    transcript: str = Field(min_length=1, max_length=4000)
    language: str = Field(default="es", min_length=2, max_length=10)


class CodeRouteRequest(BaseModel):
    message: str = Field(min_length=1, max_length=10000)


class WorkflowPlanRequest(BaseModel):
    transcript: str = Field(min_length=1, max_length=10000)


class AuditEventRequest(BaseModel):
    event_type: str = Field(min_length=3, max_length=100)
    outcome: str = Field(min_length=2, max_length=50)
    metadata: dict = Field(default_factory=dict)


class EditorContextUpdate(BaseModel):
    workspace_name: str = Field(default="", max_length=200)
    workspace_roots: list[str] = Field(default_factory=list)
    workspace_files: list[str] = Field(default_factory=list)
    open_files: list[str] = Field(default_factory=list)
    active_file: str = ""
    relative_file: str = ""
    language_id: str = ""
    document_version: int = Field(default=0, ge=0)
    document_hash: str = Field(default="", max_length=128)
    document_text: str = ""
    selected_text: str = ""
    cursor_line: int = Field(default=0, ge=0)
    cursor_character: int = Field(default=0, ge=0)
    selection_start_line: int = Field(default=0, ge=0)
    selection_start_character: int = Field(default=0, ge=0)
    selection_end_line: int = Field(default=0, ge=0)
    selection_end_character: int = Field(default=0, ge=0)
    visible_start_line: int = Field(default=0, ge=0)
    visible_end_line: int = Field(default=0, ge=0)
    diagnostics: list[dict] = Field(default_factory=list)


class EditorEditRequest(BaseModel):
    instruction: str = Field(min_length=3, max_length=10000)
    language: str = Field(default="es", min_length=2, max_length=10)


class EditorFileEdit(BaseModel):
    active_file: str = Field(min_length=1, max_length=500)
    relative_file: str = Field(min_length=1, max_length=500)
    language_id: str = Field(default="", max_length=50)
    original: str = Field(max_length=200000)
    replacement: str = Field(max_length=200000)
    summary: str = Field(default="", max_length=1000)


class EditorBatchEditRequest(BaseModel):
    instruction: str = Field(min_length=3, max_length=10000)
    language: str = Field(default="es", min_length=2, max_length=10)
    files: list[EditorFileEdit] = Field(min_length=1, max_length=12)


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


class PythonExecutionRequest(BaseModel):
    script_path: str = Field(min_length=1, max_length=500)
    arguments: list[str] = Field(default_factory=list, max_length=12)
    timeout_seconds: int = Field(default=30, ge=1, le=120)


class AudioEmbeddingRequest(BaseModel):
    features: list[float] = Field(min_length=1, max_length=512)


class EnterpriseUserRegistration(BaseModel):
    organization_id: str = Field(default="osvoz-personal", min_length=2, max_length=120)
    email: str = Field(min_length=5, max_length=254)
    full_name: str = Field(min_length=2, max_length=180)
    phone: str = Field(default="+10000000000", min_length=7, max_length=40)
    role: str = Field(default="reader", min_length=4, max_length=20)


class EnterpriseSessionStart(BaseModel):
    email: str = Field(min_length=5, max_length=254)
    provider: str = Field(default="email_code", min_length=3, max_length=30)
    environment: str = Field(default="standard", min_length=3, max_length=40)
    device_id: str = Field(default="unknown-device", max_length=120)


class EnterpriseFactorVerification(BaseModel):
    session_id: str = Field(min_length=8, max_length=120)
    factor: str = Field(min_length=3, max_length=30)
    code: str | None = Field(default=None, max_length=20)


class EnterpriseCodeResend(BaseModel):
    session_id: str = Field(min_length=8, max_length=120)


class EnterpriseActionAuthorization(BaseModel):
    session_id: str = Field(min_length=8, max_length=120)
    action: str = Field(min_length=3, max_length=80)
    environment: str = Field(default="standard", min_length=3, max_length=40)


PROJECT_PATH = os.getenv(
    "OSVOZ_PROJECT_PATH",
    os.path.join(os.path.dirname(__file__), ".."),
)
SESSION_DATABASE_PATH = os.getenv(
    "OSVOZ_SESSION_DATABASE",
    os.path.join(os.path.dirname(__file__), "data", "labvoice.db"),
)
AUDIT_DATABASE_PATH = os.getenv(
    "OSVOZ_AUDIT_DATABASE",
    os.path.join(os.path.dirname(__file__), "data", "audit.db"),
)
ENTERPRISE_AUTH_DATABASE_PATH = os.getenv(
    "OSVOZ_ENTERPRISE_AUTH_DATABASE",
    os.path.join(os.path.dirname(__file__), "data", "enterprise_auth.db"),
)
session_store = SessionStore(SESSION_DATABASE_PATH)
audit_store = AuditStore(AUDIT_DATABASE_PATH)
enterprise_auth_store = EnterpriseAuthStore(
    ENTERPRISE_AUTH_DATABASE_PATH,
    audit_store=audit_store,
)
native_policy_client = NativePolicyClient()
permission_engine = PermissionEngine(native_client=native_policy_client)
local_whisper_engine = LocalWhisperEngine()
file_access_layer = FileAccessLayer(PROJECT_PATH)
editor_context_store = EditorContextStore()
editor_operation_store = EditorOperationStore()
conversation_store = ConversationStore()
SPEAKER_PROFILE_PATH = os.getenv(
    "OSVOZ_SPEAKER_PROFILE",
    os.path.join(os.path.dirname(__file__), "data", "speaker_voiceprint.json"),
)
speaker_identity_service = SpeakerIdentityService(
    LocalVoiceprintProvider(SPEAKER_PROFILE_PATH)
)
audit_store.append(
    "core.started",
    "success",
    {"version": app.version},
)

DEFAULT_PUBLIC_FOUNDER_BIOGRAPHIES = {
    "es": (
        "Ian Faber Mendoza Mey es el fundador y creador de OSvoz. Nacido en "
        "Sincelejo, Colombia, construyó su trayectoria mediante la disciplina, "
        "el aprendizaje continuo, los viajes y la migración a Estados Unidos. "
        "Creó OSvoz como un sistema operativo centrado en la voz, diseñado "
        "para transformar intención hablada en acciones reales y hacer la "
        "tecnología más accesible, especialmente para personas con discapacidad "
        "visual."
    ),
    "en": (
        "Ian Faber Mendoza Mey is the founder and creator of OSvoz. Born in "
        "Sincelejo, Colombia, he built his journey through discipline, "
        "continuous learning, travel, and migration to the United States. He "
        "created OSvoz as a voice-centered operating system designed to "
        "transform spoken intent into real action and make technology more "
        "accessible, especially for people with visual disabilities."
    ),
}


def public_founder_biography(language: str) -> str:
    biography_language = "es" if language == "es" else "en"
    fallback = DEFAULT_PUBLIC_FOUNDER_BIOGRAPHIES[biography_language]
    key = os.getenv("OSVOZ_FOUNDER_PROFILE_KEY")
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
        "assistant": "OSvoz"
    }


@app.get("/core/health")
def core_health():
    return CoreHealth.inspect(
        PROJECT_PATH,
        SESSION_DATABASE_PATH,
        editor_context_store.get(),
        audit_store.verify(),
        speaker_identity_service.status(),
        native_policy_client.health(),
        local_whisper_engine.status(),
        MLFrameworkRegistry.inspect(),
    )


@app.get("/core/latency")
def core_latency():
    routes = {}
    for route, samples in _latency_samples.items():
        values = sorted(samples)
        if not values:
            continue
        routes[route] = {
            "count": len(values),
            "min_ms": round(values[0], 2),
            "p50_ms": round(_percentile(values, 50), 2),
            "p95_ms": round(_percentile(values, 95), 2),
            "max_ms": round(values[-1], 2),
        }
    return {
        "success": True,
        "warmup": _warmup_status,
        "routes": routes,
    }


def _percentile(values: list[float], percentile: int) -> float:
    if not values:
        return 0.0
    index = (len(values) - 1) * (percentile / 100)
    lower = int(index)
    upper = min(lower + 1, len(values) - 1)
    if lower == upper:
        return values[lower]
    weight = index - lower
    return values[lower] * (1 - weight) + values[upper] * weight


@app.get("/core/capabilities")
def core_capabilities():
    operator_capabilities = CapabilityRegistry.status()
    return {
        "success": True,
        "capabilities": {
            "conversation_memory": True,
            "continuous_listening": True,
            "editor_bridge": editor_context_store.get()["connected"],
            "safe_code_editing": True,
            "project_file_access": file_access_layer.status(),
            "tamper_evident_audit": True,
            "native_authorization_core": native_policy_client.health(),
            "local_speech_recognition": local_whisper_engine.status(),
            "speaker_identity": speaker_identity_service.status(),
            "ml_framework_boundary": MLFrameworkRegistry.inspect(),
            "ml_provider": MLProviderManager.status()["provider"],
            "enterprise_auth": {
                "roles": sorted(ROLE_PERMISSIONS),
                "providers": ["email_code", "oauth", "sso", "biometric", "voice"],
                "adaptive_mfa": True,
                "audit_trail": True,
            },
            "operator_capabilities": operator_capabilities,
        },
    }


@app.get("/core/operator-capabilities")
def operator_capabilities():
    return CapabilityRegistry.status()


@app.get("/core/operator-status")
def operator_status(summary_mode: str = "quick"):
    mode = summary_mode.lower().strip()
    if mode not in {"quick", "detailed"}:
        mode = "quick"
    health = CoreHealth.inspect(
        PROJECT_PATH,
        SESSION_DATABASE_PATH,
        editor_context_store.get(),
        audit_store.verify(),
        speaker_identity_service.status(),
        native_policy_client.health(),
        local_whisper_engine.status(),
        MLFrameworkRegistry.inspect(),
    )
    capabilities = CapabilityRegistry.status()
    audit_verification = audit_store.verify()
    capability_items = capabilities["capabilities"]
    implemented = [
        capability for capability in capability_items
        if capability["status"] == "implemented"
    ]
    partial = [
        capability for capability in capability_items
        if capability["status"] == "partial"
    ]
    blocked = []
    if not health["checks"].get("audit_chain", False):
        blocked.append("audit_chain")
    if not health["checks"].get("local_speech_recognition", False):
        blocked.append("local_speech_recognition")
    if not health["checks"].get("native_authorization_core", False):
        blocked.append("native_authorization_core")

    status = "ready" if health["status"] == "ready" and not blocked else "degraded"
    summary_es, summary_en = _operator_status_summary(
        mode,
        status,
        implemented,
        partial,
        blocked,
        audit_verification["valid"],
        health["checks"],
    )
    event = audit_store.append(
        "operator.status_checked",
        status,
        {
            "source": "core.operator_status",
            "summary_mode": mode,
            "health_status": health["status"],
            "implemented_capabilities": len(implemented),
            "partial_capabilities": len(partial),
            "blocked_components": blocked,
            "audit_valid": audit_verification["valid"],
        },
    )
    return {
        "success": True,
        "status": status,
        "summary_mode": mode,
        "spoken_summary": {
            "es": summary_es,
            "en": summary_en,
        },
        "health": {
            "status": health["status"],
            "critical_ready": health["critical_ready"],
            "checks": health["checks"],
        },
        "capabilities": {
            "implemented": [capability["id"] for capability in implemented],
            "partial": [capability["id"] for capability in partial],
            "planned": [
                capability["id"] for capability in capability_items
                if capability["status"] == "planned"
            ],
        },
        "security": {
            "audit_valid": audit_verification["valid"],
            "speaker_identity": health["speaker_identity"],
            "native_core": health["native_core"],
        },
        "audit_event": {
            "id": event["id"],
            "event_type": event["event_type"],
            "outcome": event["outcome"],
        },
    }


def _operator_status_summary(
    mode: str,
    status: str,
    implemented: list[dict],
    partial: list[dict],
    blocked: list[str],
    audit_valid: bool,
    checks: dict,
) -> tuple[str, str]:
    labels_es = {
        "system.open_app": "abrir aplicaciones",
        "project.read": "leer el proyecto",
        "code.preview_edit": "preparar cambios de código",
        "code.apply_edit": "aplicar cambios confirmados",
        "project.run_diagnostics": "ejecutar diagnósticos",
        "browser.control": "control del navegador",
    }
    labels_en = {
        "system.open_app": "open apps",
        "project.read": "read the project",
        "code.preview_edit": "prepare code changes",
        "code.apply_edit": "apply confirmed changes",
        "project.run_diagnostics": "run diagnostics",
        "browser.control": "browser control",
    }

    if mode == "detailed":
        implemented_names_es = ", ".join(
            labels_es.get(capability["id"], capability["id"])
            for capability in implemented[:5]
        )
        implemented_names_en = ", ".join(
            labels_en.get(capability["id"], capability["id"])
            for capability in implemented[:5]
        )
        partial_names_es = ", ".join(
            labels_es.get(capability["id"], capability["id"]) for capability in partial
        )
        partial_names_en = ", ".join(
            labels_en.get(capability["id"], capability["id"]) for capability in partial
        )
        blocked_text_es = (
            " Sin bloqueos críticos detectados."
            if not blocked
            else f" Revisa: {', '.join(blocked)}."
        )
        blocked_text_en = (
            " No critical blocks detected."
            if not blocked
            else f" Review: {', '.join(blocked)}."
        )
        audit_es = "auditoría válida" if audit_valid else "auditoría degradada"
        audit_en = "audit valid" if audit_valid else "audit degraded"
        whisper_es = (
            "Whisper local listo"
            if checks.get("local_speech_recognition")
            else "Whisper local requiere revisión"
        )
        whisper_en = (
            "local Whisper ready"
            if checks.get("local_speech_recognition")
            else "local Whisper needs review"
        )
        return (
            f"Estoy {status}. Puedo {implemented_names_es}. "
            f"En progreso: {partial_names_es or 'ninguna capacidad pendiente'}. "
            f"Seguridad: {audit_es} y {whisper_es}.{blocked_text_es}",
            f"I am {status}. I can {implemented_names_en}. "
            f"In progress: {partial_names_en or 'no pending capability'}. "
            f"Security: {audit_en} and {whisper_en}.{blocked_text_en}",
        )

    if status == "ready":
        return (
            "Estoy operativo. "
            f"{len(implemented)} capacidades listas, {len(partial)} parcial. "
            "Auditoría válida y Whisper local listo.",
            "I am operational. "
            f"{len(implemented)} capabilities ready, {len(partial)} partial. "
            "Audit is valid and local Whisper is ready.",
        )
    return (
        "Estoy parcialmente operativo. "
        f"{len(implemented)} capacidades listas, {len(partial)} parcial. "
        "Hay componentes que requieren revisión.",
        "I am partially operational. "
        f"{len(implemented)} capabilities ready, {len(partial)} partial. "
        "Some components need attention.",
    )


@app.get("/auth/enterprise/capabilities")
def enterprise_auth_capabilities():
    return {
        "success": True,
        "roles": {
            role: sorted(permissions)
            for role, permissions in ROLE_PERMISSIONS.items()
        },
        "providers": ["email_code", "oauth", "sso", "biometric", "voice"],
        "environments": ["standard", "regulated", "hospital", "bank"],
        "messages": {
            "email_code": "Código enviado. Revisa tu correo para continuar.",
            "oauth": "Autoriza con tu proveedor.",
            "sso": "Autoriza con tu proveedor de identidad.",
            "biometric": "Confirma ahora con Face ID o Touch ID.",
            "voice": "Confirma tu voz para activar OSvoz.",
            "ready": "Acceso autorizado. OSvoz está listo.",
        },
    }


@app.post("/auth/enterprise/users")
def register_enterprise_user(request: EnterpriseUserRegistration):
    try:
        user = enterprise_auth_store.register_user(
            organization_id=request.organization_id,
            email=request.email,
            full_name=request.full_name,
            phone=request.phone,
            role=request.role,
        )
    except ValueError as error:
        api_error(422, str(error), "El rol solicitado no está soportado.")
    return {
        "success": True,
        "user": {
            "id": user["id"],
            "organization_id": user["organization_id"],
            "email": user["email"],
            "full_name": user["full_name"],
            "phone": user["phone"],
            "role": user["role"],
            "permissions": sorted(ROLE_PERMISSIONS[user["role"]]),
            "status": user["status"],
        },
        "message": "Usuario listo para iniciar una sesión segura.",
    }


@app.post("/auth/enterprise/session/start")
def start_enterprise_session(request: EnterpriseSessionStart, http_request: Request):
    client_host = http_request.client.host if http_request.client else "unknown"
    try:
        result = enterprise_auth_store.start_session(
            email=request.email,
            provider=request.provider,
            environment=request.environment,
            ip_address=client_host,
            device_id=request.device_id,
        )
    except ValueError as error:
        api_error(422, str(error), "El proveedor de autenticación no está soportado.")
    if not result.get("success"):
        api_error(403, "enterprise_session_blocked", result["message"])
    return result


@app.post("/auth/enterprise/session/verify")
def verify_enterprise_factor(request: EnterpriseFactorVerification):
    try:
        result = enterprise_auth_store.verify_factor(
            session_id=request.session_id,
            factor=request.factor,
            code=request.code,
        )
    except ValueError as error:
        api_error(422, str(error), "El factor de autenticación no está soportado.")
    if not result.get("success"):
        status = 409 if result.get("status") == "blocked" else 403
        api_error(status, "enterprise_factor_blocked", result["message"])
    return result


@app.post("/auth/enterprise/session/resend-code")
def resend_enterprise_code(request: EnterpriseCodeResend):
    result = enterprise_auth_store.resend_code(session_id=request.session_id)
    if not result.get("success"):
        api_error(409, "enterprise_code_resend_blocked", result["message"])
    return result


@app.post("/auth/enterprise/action/authorize")
def authorize_enterprise_action(request: EnterpriseActionAuthorization):
    result = enterprise_auth_store.authorize_action(
        session_id=request.session_id,
        action=request.action,
        environment=request.environment,
    )
    if result.get("status") == "blocked":
        api_error(403, "enterprise_action_blocked", result["message"])
    return result


@app.get("/ml/frameworks")
def ml_frameworks():
    return MLFrameworkRegistry.inspect()


@app.get("/ml/provider")
def ml_provider():
    return MLProviderManager.status()


@app.post("/ml/audio/embedding")
def ml_audio_embedding(request: AudioEmbeddingRequest):
    try:
        result = MLProviderManager.audio_embedding(request.features)
    except ValueError as error:
        api_error(422, "invalid_audio_features", str(error))
    if not result.get("success"):
        api_error(
            503,
            result.get("error", "ml_provider_unavailable"),
            result["message"],
        )
    return result


@app.post("/voice/transcribe")
async def transcribe_voice(request: Request, language: str = "es"):
    audio_bytes = await request.body()
    if not audio_bytes:
        api_error(400, "empty_audio", "A WAV audio body is required.")
    if len(audio_bytes) > LocalWhisperEngine.MAX_AUDIO_BYTES:
        api_error(413, "audio_too_large", "Audio exceeds the 20 MB limit.")
    if not (
        audio_bytes.startswith(b"RIFF")
        and len(audio_bytes) >= 12
        and audio_bytes[8:12] == b"WAVE"
    ):
        api_error(415, "invalid_audio_format", "Audio must be a WAV file.")

    temporary_path = None
    try:
        with tempfile.NamedTemporaryFile(
            prefix="labvoice-audio-",
            suffix=".wav",
            delete=False,
        ) as temporary_audio:
            temporary_audio.write(audio_bytes)
            temporary_path = temporary_audio.name
        result = await run_in_threadpool(
            local_whisper_engine.transcribe,
            temporary_path,
            language,
        )
    except LocalWhisperError as error:
        audit_store.append(
            "voice.transcription",
            "failed",
            {"engine": "whisper.cpp"},
        )
        api_error(422, "transcription_failed", str(error))
    finally:
        if temporary_path:
            Path(temporary_path).unlink(missing_ok=True)

    audit_store.append(
        "voice.transcription",
        "success",
        {
            "engine": result["engine"],
            "language": result["language"],
            "duration_seconds": result["audio"]["duration_seconds"],
        },
    )
    return result


@app.post("/voice/interpret")
def interpret_voice_command(request: VoiceInterpretRequest):
    interpretation = CommandInterpreter.interpret(request.transcript).to_dict()
    code_route = CodeCapabilityRouter.route(
        request.transcript,
        PROJECT_PATH,
    ).to_dict()
    return {
        "success": True,
        "language": request.language,
        "transcript": request.transcript,
        "interpretation": interpretation,
        "code_route": code_route,
        "safety": {
            "phase": "interpretation_only",
            "executed": False,
        },
    }


@app.post("/workflow/plan")
def plan_workflow(request: WorkflowPlanRequest):
    return WorkflowOrchestrator.plan(request.transcript)


@app.get("/core/audit/verify")
def verify_audit_chain():
    return {
        "success": True,
        "verification": audit_store.verify(),
    }


@app.post("/core/audit/events")
def append_audit_event(request: AuditEventRequest):
    event = audit_store.append(
        request.event_type,
        request.outcome,
        request.metadata,
    )
    return {
        "success": True,
        "event": {
            "id": event["id"],
            "occurred_at": event["occurred_at"],
            "event_type": event["event_type"],
            "outcome": event["outcome"],
            "event_hash": event["event_hash"],
        },
    }


@app.get("/speaker/status")
def speaker_identity_status():
    return {
        "success": True,
        "speaker_identity": speaker_identity_service.status(),
    }


@app.post("/speaker/enroll")
async def enroll_speaker(request: Request, phrase: str = ""):
    audio_bytes = await request.body()
    if not audio_bytes:
        api_error(400, "empty_audio", "A WAV audio body is required.")
    if len(audio_bytes) > LocalWhisperEngine.MAX_AUDIO_BYTES:
        api_error(413, "audio_too_large", "Audio exceeds the 20 MB limit.")
    result = speaker_identity_service.enroll(audio_bytes, phrase)
    audit_store.append(
        "speaker.enroll",
        "success" if result.get("success") else "failed",
        {
            "sample_count": result.get("sample_count", 0),
            "enrolled": result.get("enrolled", False),
        },
    )
    if not result.get("success"):
        api_error(422, result.get("error", "speaker_enroll_failed"), result["message"])
    return result


@app.post("/speaker/verify")
async def verify_speaker(request: Request):
    audio_bytes = await request.body()
    if not audio_bytes:
        api_error(400, "empty_audio", "A WAV audio body is required.")
    if len(audio_bytes) > LocalWhisperEngine.MAX_AUDIO_BYTES:
        api_error(413, "audio_too_large", "Audio exceeds the 20 MB limit.")
    result = speaker_identity_service.verify_details(audio_bytes)
    audit_store.append(
        "speaker.verify",
        "success" if result.get("verified") else "failed",
        {"verified": result.get("verified", False)},
    )
    return result


@app.post("/execute")
def execute_action(request: ActionRequest):
    prepared = permission_engine.prepare(request.action)
    if not prepared.get("success"):
        audit_store.append(
            "action.requested",
            "rejected",
            {"action": request.action, "reason": "unknown_action"},
        )
        api_error(
            404,
            prepared.get("error", "unknown_action"),
            prepared.get("message", "Unknown action."),
        )
    if not prepared.get("approved"):
        audit_store.append(
            "action.requested",
            "confirmation_required",
            {"action": request.action, "risk": prepared["policy"]["risk"]},
        )
        return prepared

    result = ActionEngine.execute(request.action, PROJECT_PATH)
    audit_store.append(
        "action.executed",
        "success" if result.get("success") else "failed",
        {"action": request.action},
    )
    return action_result(result)


@app.post("/execute/confirm")
def confirm_action(request: ConfirmationRequest):
    confirmed = permission_engine.confirm(request.confirmation_token)
    if not confirmed.get("approved"):
        audit_store.append(
            "action.confirmation",
            "rejected",
            {"reason": confirmed.get("error", "confirmation_failed")},
        )
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

    result = ActionEngine.execute(confirmed["action"], PROJECT_PATH)
    audit_store.append(
        "action.confirmed_and_executed",
        "success" if result.get("success") else "failed",
        {"action": confirmed["action"]},
    )
    return action_result(result)


@app.post("/execute/cancel")
def cancel_action(request: ConfirmationRequest):
    result = permission_engine.cancel(request.confirmation_token)
    if not result["success"]:
        api_error(404, "pending_action_not_found", result["message"])
    audit_store.append(
        "action.canceled",
        "success",
        {},
    )
    return result


@app.post("/browser/open")
def open_browser(request: BrowserOpenRequest):
    parsed = urlparse(request.url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        api_error(
            422,
            "invalid_url",
            "Only complete http or https URLs can be opened.",
        )

    result = ActionEngine.open_url(request.url)
    audit_store.append(
        "browser.open",
        "success" if result.get("success") else "failed",
        {"host": parsed.netloc},
    )
    return action_result(result)


@app.post("/browser/youtube/play")
def play_youtube(request: YouTubePlayRequest):
    result = ActionEngine.open_youtube_music(
        request.query,
        auto_skip_ads=request.auto_skip_ads,
    )
    audit_store.append(
        "browser.youtube.play",
        "success" if result.get("success") else "failed",
        {
            "query_length": len(request.query),
            "play_attempted": bool(result.get("play_attempted")),
        },
    )
    return action_result(result)


@app.post("/browser/youtube/skip-ad")
def skip_youtube_ad():
    result = ActionEngine.skip_youtube_ad()
    audit_store.append(
        "browser.youtube.skip_ad",
        "success" if result.get("success") else "failed",
        {"skipped": bool(result.get("skipped"))},
    )
    return action_result(result)


@app.post("/music/play")
def play_music(request: MusicPlayRequest):
    result = ActionEngine.open_music(
        request.query,
        request.platform,
        auto_skip_ads=request.auto_skip_ads,
    )
    audit_store.append(
        "music.play",
        "success" if result.get("success") else "failed",
        {
            "platform": request.platform,
            "query_length": len(request.query),
            "play_attempted": bool(result.get("play_attempted")),
        },
    )
    return action_result(result)


@app.get("/project/inspect")
def inspect_project(run_diagnostics: bool = False):
    diagnostics = DiagnosticsRunner.run(PROJECT_PATH) if run_diagnostics else None
    result = ProjectInspector.inspect(PROJECT_PATH, diagnostics=diagnostics)

    if not result["success"]:
        api_error(404, "project_not_found", result["message"])

    project = result["project"]
    explanation = result.get("explanation", {})
    session_store.update(
        {
            "current_task": (
                "Inspect active project and run diagnostics"
                if run_diagnostics
                else "Inspect active project"
            ),
            "last_action": result["message"],
            "next_action": explanation.get(
                "next_action",
                "Run project analysis and tests",
            ),
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


@app.get("/project/files")
def list_project_files(directory: str = "", limit: int = 120):
    try:
        return file_access_layer.list_files(directory, limit)
    except FileAccessError as error:
        api_error(403, error.code, error.message)


@app.get("/project/file")
def read_project_file(path: str):
    try:
        result = file_access_layer.read_file(path)
    except FileAccessError as error:
        api_error(403, error.code, error.message)
    audit_store.append(
        "project.file.read",
        "success",
        {"path": result["path"], "size_bytes": result["size_bytes"]},
    )
    return result


@app.post("/python/execute")
def execute_python(request: PythonExecutionRequest):
    result = PythonExecutor.run_script(
        PROJECT_PATH,
        request.script_path,
        request.arguments,
        request.timeout_seconds,
    )
    audit_store.append(
        "python.execute",
        "success" if result.get("success") else "failed",
        {
            "script": result.get("script", request.script_path),
            "exit_code": result.get("exit_code"),
        },
    )
    session_store.update(
        {
            "current_task": "Run Python executor",
            "last_action": result["message"],
            "next_action": (
                "Review Python execution output"
                if not result.get("success")
                else "Choose the next development task"
            ),
        }
    )
    if not result.get("success"):
        raise HTTPException(
            status_code=422,
            detail={
                "code": result.get("error", "python_execution_failed"),
                "message": result["message"],
                "script": result.get("script"),
                "exit_code": result.get("exit_code"),
                "output": result.get("output", ""),
            },
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
            "OSvoz may edit only files inside the approved project.",
        )

    try:
        plan = CodeEditPlanner.create(
            openai_client(),
            request.instruction,
            context,
        )
    except Exception:
        api_error(
            502,
            "edit_plan_unavailable",
            "OSvoz could not prepare a safe code edit.",
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
    audit_store.append(
        "editor.edit.prepared",
        "preview_required",
        {
            "operation_id": operation["id"],
            "relative_file": operation["relative_file"],
            "language_id": operation["language_id"],
        },
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


@app.post("/editor/edit/prepare-batch")
def prepare_editor_batch_edit(request: EditorBatchEditRequest):
    context = editor_context_store.get()
    if not context["connected"]:
        api_error(
            409,
            "editor_not_connected",
            "Connect VS Code before preparing a multi-file edit.",
        )

    project_root = Path(PROJECT_PATH).resolve()
    changes = []
    for file_request in request.files:
        active_file = Path(file_request.active_file).expanduser().resolve()
        try:
            active_file.relative_to(project_root)
        except ValueError:
            api_error(
                403,
                "file_outside_project",
                "OSvoz may edit only files inside the approved project.",
            )
        if file_request.replacement == file_request.original:
            continue
        diff = "".join(
            difflib.unified_diff(
                file_request.original.splitlines(keepends=True),
                file_request.replacement.splitlines(keepends=True),
                fromfile=f"{file_request.relative_file} (current)",
                tofile=f"{file_request.relative_file} (proposed)",
            )
        )
        changes.append(
            {
                "active_file": str(active_file),
                "relative_file": file_request.relative_file,
                "language_id": file_request.language_id,
                "original": file_request.original,
                "original_hash": sha256(file_request.original.encode()).hexdigest(),
                "replacement": file_request.replacement,
                "summary": file_request.summary or file_request.relative_file,
                "diff": diff,
            }
        )

    if not changes:
        api_error(
            422,
            "no_code_change",
            "The proposed multi-file edit would not change any file.",
        )

    combined_diff = "\n".join(change["diff"] for change in changes)
    summary = (
        f"{request.instruction.strip()[:180]} "
        f"({len(changes)} file{'s' if len(changes) != 1 else ''})"
    )
    first = changes[0]
    operation = editor_operation_store.create(
        instruction=request.instruction,
        active_file=first["active_file"],
        relative_file=first["relative_file"],
        language_id=first["language_id"],
        original=first["original"],
        replacement=first["replacement"],
        summary=summary,
        diff=combined_diff,
        files=changes,
    )
    audit_store.append(
        "editor.edit.batch_prepared",
        "preview_required",
        {
            "operation_id": operation["id"],
            "file_count": len(changes),
        },
    )
    return {
        "success": True,
        "operation_id": operation["id"],
        "status": operation["status"],
        "summary": operation["summary"],
        "relative_file": operation["relative_file"],
        "file_count": len(changes),
        "files": [
            {
                "relative_file": change["relative_file"],
                "summary": change["summary"],
                "diff": change["diff"][:20_000],
            }
            for change in changes
        ],
        "diff": operation["diff"][:20_000],
        "message": (
            "The multi-file change is opening in VS Code. Review every diff, "
            "then say 'sí, aplicar' or 'cancelar'."
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
    operation = editor_operation_store.get(operation_id)
    if operation is None:
        api_error(404, "edit_not_found", "The edit operation was not found.")
    if not _editor_status_transition_allowed(
        operation["status"],
        request.status,
    ):
        api_error(422, "invalid_operation_status", "Invalid editor status.")
    operation = editor_operation_store.update(
        operation_id,
        request.status,
        diagnostics=request.diagnostics,
        error=request.error,
    )
    if operation is None:
        api_error(404, "edit_not_found", "The edit operation was not found.")
    audit_store.append(
        "editor.edit.status",
        request.status,
        {
            "operation_id": operation_id,
            "relative_file": operation["relative_file"],
        },
    )
    return {"success": True, "operation": operation}


def _editor_status_transition_allowed(current_status: str, next_status: str) -> bool:
    allowed = {
        "awaiting_preview": {"previewed", "failed", "canceled"},
        "previewed": {"failed", "canceled"},
        "approved": {"applied", "failed"},
        "applied": set(),
        "undo_requested": {"undone", "failed"},
    }
    return next_status in allowed.get(current_status, set())


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
    audit_store.append(
        "editor.edit.approved",
        "success",
        {
            "operation_id": operation_id,
            "relative_file": operation["relative_file"],
        },
    )
    return {
        "success": True,
        "status": operation["status"],
        "message": (
            "Edit approved. OSvoz is applying it, running tests, and will "
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
    audit_store.append(
        "editor.edit.canceled",
        "success",
        {
            "operation_id": operation_id,
            "relative_file": operation["relative_file"],
        },
    )
    return {"success": True, "message": "The proposed edit was canceled."}


@app.post("/editor/edit/{operation_id}/validate")
def validate_editor_edit(operation_id: str):
    operation = editor_operation_store.get(operation_id)
    if operation is None:
        api_error(404, "edit_not_found", "The edit operation was not found.")
    if operation["status"] != "approved":
        api_error(409, "edit_not_approved", "The edit has not been approved.")
    diagnostics = StagedEditValidator.run(PROJECT_PATH, operation)
    audit_store.append(
        "editor.edit.validated",
        "success" if diagnostics.get("success") else "failed",
        {
            "operation_id": operation_id,
            "relative_file": operation["relative_file"],
            "passed": diagnostics.get("summary", {}).get("passed", 0),
            "failed": diagnostics.get("summary", {}).get("failed", 0),
        },
    )
    return {
        "success": diagnostics.get("success", False),
        "diagnostics": diagnostics,
    }


@app.post("/editor/edit/undo")
def undo_last_editor_edit():
    operation = editor_operation_store.request_undo()
    if operation is None:
        api_error(409, "nothing_to_undo", "There is no applied edit to undo.")
    audit_store.append(
        "editor.edit.undo_requested",
        "pending",
        {
            "operation_id": operation["id"],
            "relative_file": operation["relative_file"],
        },
    )
    return {
        "success": True,
        "operation_id": operation["id"],
        "message": "Restoring the previous version in VS Code.",
    }


SYSTEM_PROMPT = """
You are OSvoz.

You are a voice-first operating system.

Your mission is to help developers,
engineers,
business owners,
security professionals,
data professionals,
and organizations.

You are not a generic chatbot.

Your creator and founder is Ian Faber Mendoza Mey.
OSvoz was conceived by Ian Faber Mendoza Mey as a voice-centered operating
system that understands context, operates tools, and transforms spoken intent
into real work.
Never attribute the creation or founding of OSvoz to anyone else.

You can reason,
remember,
execute,
automate,
and orchestrate tools.

Do not begin responses by saying "I am OSvoz", "Soy OSvoz", or repeating
your identity. The user already knows who is speaking. Identify yourself only
when the user explicitly asks who or what you are, or during the first welcome
shown when the application starts.
If asked "who are you" or its equivalent, describe OSvoz itself: its
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
            "creó osvoz",
            "ian faber",
            "biografía",
            "biografia",
            "founder",
            "creator",
            "created osvoz",
            "biography",
        )
    ):
        founder_context = (
            f"Official public founder biography: "
            f"{public_founder_biography(request.language)}\n"
        )

    try:
        response = openai_client().responses.create(
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
        audio = openai_client().audio.speech.create(
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
