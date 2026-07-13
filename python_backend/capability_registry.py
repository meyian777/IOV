from dataclasses import asdict, dataclass


@dataclass(frozen=True)
class VoiceAccessPolicy:
    initiate_by_voice: bool
    confirm_by_voice: bool
    silent_factor_required: bool
    reason: str

    def to_dict(self) -> dict:
        return asdict(self)


@dataclass(frozen=True)
class OperatorCapability:
    id: str
    name: str
    adapter: str
    status: str
    security_level: int
    risk: str
    required_factors: tuple[str, ...]
    voice_access: VoiceAccessPolicy
    examples: tuple[str, ...]

    def to_dict(self) -> dict:
        data = asdict(self)
        data["required_factors"] = list(self.required_factors)
        data["examples"] = list(self.examples)
        data["voice_access"] = self.voice_access.to_dict()
        return data


class CapabilityRegistry:
    CAPABILITIES = (
        OperatorCapability(
            id="system.open_app",
            name="Open trusted local applications",
            adapter="native_action_engine",
            status="implemented",
            security_level=1,
            risk="routine_system",
            required_factors=("wake_word", "active_session"),
            voice_access=VoiceAccessPolicy(
                initiate_by_voice=True,
                confirm_by_voice=False,
                silent_factor_required=False,
                reason="Routine app launch is reversible and low risk.",
            ),
            examples=("abre VS Code", "abre terminal", "open browser"),
        ),
        OperatorCapability(
            id="project.read",
            name="Read project files and active context",
            adapter="file_access_layer",
            status="implemented",
            security_level=1,
            risk="read_only",
            required_factors=("wake_word", "active_session"),
            voice_access=VoiceAccessPolicy(
                initiate_by_voice=True,
                confirm_by_voice=False,
                silent_factor_required=False,
                reason="Read-only project context can be spoken on request.",
            ),
            examples=("lee el archivo principal", "que proyecto esta activo"),
        ),
        OperatorCapability(
            id="code.preview_edit",
            name="Prepare code edits with preview",
            adapter="editor_bridge",
            status="implemented",
            security_level=2,
            risk="personal_data",
            required_factors=(
                "trusted_device",
                "voice_id",
                "preview_confirmation",
            ),
            voice_access=VoiceAccessPolicy(
                initiate_by_voice=True,
                confirm_by_voice=True,
                silent_factor_required=True,
                reason="IOV may prepare edits by voice, but applying them needs a trusted user signal.",
            ),
            examples=("cambia esta funcion", "prepara la edicion"),
        ),
        OperatorCapability(
            id="code.apply_edit",
            name="Apply confirmed code edits",
            adapter="editor_bridge",
            status="implemented",
            security_level=2,
            risk="process_execution",
            required_factors=(
                "trusted_device",
                "voice_id",
                "preview_confirmation",
            ),
            voice_access=VoiceAccessPolicy(
                initiate_by_voice=True,
                confirm_by_voice=True,
                silent_factor_required=True,
                reason="Edits alter source code, so the preview must be accepted before writing.",
            ),
            examples=("ejecutalo", "aplica el cambio", "deshaz la ultima edicion"),
        ),
        OperatorCapability(
            id="project.run_diagnostics",
            name="Run tests and explain the result",
            adapter="diagnostics_runner",
            status="implemented",
            security_level=2,
            risk="process_execution",
            required_factors=(
                "trusted_device",
                "voice_id",
                "preview_confirmation",
            ),
            voice_access=VoiceAccessPolicy(
                initiate_by_voice=True,
                confirm_by_voice=True,
                silent_factor_required=True,
                reason="Running project processes can execute local code.",
            ),
            examples=("ejecuta las pruebas y resume", "run tests"),
        ),
        OperatorCapability(
            id="browser.control",
            name="Control browser tabs and permitted page actions",
            adapter="browser_automation",
            status="partial",
            security_level=2,
            risk="personal_data",
            required_factors=("trusted_device", "voice_id"),
            voice_access=VoiceAccessPolicy(
                initiate_by_voice=True,
                confirm_by_voice=False,
                silent_factor_required=True,
                reason="Browser control can expose personal sessions, so it requires trusted presence.",
            ),
            examples=("abre youtube", "reproduce musica", "omite anuncio si aparece"),
        ),
        OperatorCapability(
            id="api.connect_external",
            name="Connect external service APIs",
            adapter="oauth_api_connector",
            status="planned",
            security_level=2,
            risk="personal_data",
            required_factors=("trusted_device", "voice_id", "oauth_consent"),
            voice_access=VoiceAccessPolicy(
                initiate_by_voice=True,
                confirm_by_voice=False,
                silent_factor_required=True,
                reason="The user can ask by voice, but OAuth consent must happen through the provider.",
            ),
            examples=("conecta mi calendario", "abre spotify autorizado"),
        ),
        OperatorCapability(
            id="critical.transfer_or_credentials",
            name="Money movement, credentials, and irreversible actions",
            adapter="critical_action_guard",
            status="planned",
            security_level=3,
            risk="critical_financial",
            required_factors=(
                "trusted_device",
                "face_id_or_touch_id",
                "apple_watch_presence",
                "passkey",
                "explicit_preview_confirmation",
            ),
            voice_access=VoiceAccessPolicy(
                initiate_by_voice=True,
                confirm_by_voice=False,
                silent_factor_required=True,
                reason="Voice can request the action, but cannot be the final secret for critical operations.",
            ),
            examples=("envia dinero", "cambia mi contrasena"),
        ),
    )

    @classmethod
    def all(cls) -> list[dict]:
        return [capability.to_dict() for capability in cls.CAPABILITIES]

    @classmethod
    def by_level(cls) -> dict[str, list[dict]]:
        grouped: dict[str, list[dict]] = {}
        for capability in cls.CAPABILITIES:
            grouped.setdefault(str(capability.security_level), []).append(
                capability.to_dict()
            )
        return grouped

    @classmethod
    def status(cls) -> dict:
        capabilities = cls.all()
        return {
            "success": True,
            "model": "voice_authorized_operator_capabilities",
            "principle": (
                "Voice may initiate work; risky execution requires trusted "
                "presence, preview, audit, and silent factors."
            ),
            "capabilities": capabilities,
            "by_security_level": cls.by_level(),
        }
