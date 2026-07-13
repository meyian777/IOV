import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/enterprise_auth_flow.dart';

class EnterpriseSessionGate extends StatefulWidget {
  const EnterpriseSessionGate({
    super.key,
    required this.client,
    required this.onAuthorized,
  });

  final EnterpriseAuthClient client;
  final WidgetBuilder onAuthorized;

  @override
  State<EnterpriseSessionGate> createState() => _EnterpriseSessionGateState();
}

class _EnterpriseSessionGateState extends State<EnterpriseSessionGate> {
  static const _personalOrganizationId = "osvoz-personal";
  static const _placeholderPhone = "+10000000000";

  late final EnterpriseAuthFlow _flow;
  final _email = TextEditingController();
  final _fullName = TextEditingController();
  final _code = TextEditingController();
  final String _role = "editor";
  final String _environment = "regulated";
  final String _provider = "email_code";
  bool _busy = false;
  EnterpriseAuthState _state = EnterpriseAuthState.idle();

  @override
  void initState() {
    super.initState();
    _flow = EnterpriseAuthFlow(client: widget.client);
  }

  @override
  void dispose() {
    _email.dispose();
    _fullName.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<EnterpriseAuthState> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    final next = await action();
    if (!mounted) return;
    setState(() {
      _state = next;
      _busy = false;
    });
  }

  Future<void> _registerAndStart() async {
    if (!_canSubmitIdentity) return;
    await _run(
      () => _flow.registerUser(
        organizationId: _personalOrganizationId,
        email: _email.text.trim(),
        fullName: _fullName.text.trim(),
        phone: _placeholderPhone,
        role: _role,
      ),
    );
    if (!_flow.state.blocked) {
      await _startSession();
    }
  }

  bool get _canSubmitIdentity =>
      _email.text.trim().contains("@") && _fullName.text.trim().length >= 2;

  Future<void> _startSession() => _run(
    () => _flow.startSession(
      email: _email.text.trim(),
      provider: _provider,
      environment: _environment,
      deviceId: "macos-local",
    ),
  );

  Future<void> _verifyCode() => _run(() => _flow.verifyEmailCode(_code.text));

  Future<void> _resendCode() => _run(_flow.resendEmailCode);

  Future<void> _verifyBiometric() => _run(_flow.verifyBiometric);

  Future<void> _verifyVoice() => _run(_flow.verifyVoice);

  void _continue() {
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute<void>(builder: widget.onAuthorized));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xFF0B0D14)),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    color: const Color(0xFF121620),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "OSvoz",
                          textAlign: TextAlign.center,
                          style: theme.textTheme.displaySmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _title,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _friendlyMessage,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.68),
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _body(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _title {
    if (_state.authorized) return "Acceso confirmado";
    return switch (_state.stage) {
      "email_code" => "Revisa tu correo",
      "biometric" => "Confirma tu identidad",
      "voice" => "Confirma tu voz",
      _ => "Inicia sesión",
    };
  }

  String get _friendlyMessage {
    if (_state.blocked) return _state.message;
    if (_state.authorized) {
      return "Todo listo. Falta la verificación local de este equipo.";
    }
    return switch (_state.stage) {
      "email_code" => "Ingresa el código que enviamos para continuar.",
      "biometric" => "Usa Face ID, Touch ID o el método seguro disponible.",
      "voice" => "Una última confirmación por voz y seguimos.",
      "working" => "Un momento, estamos verificando tu acceso.",
      _ => "Usa tu correo y tu nombre para crear o abrir tu acceso.",
    };
  }

  Widget _body() {
    if (_busy) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_state.authorized) return _continueAction();
    if (_state.stage == "email_code") return _codeStep();
    if (_state.stage == "biometric") return _biometricStep();
    if (_state.stage == "voice") return _voiceStep();
    return _identityStep();
  }

  Widget _identityStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _field(_email, "Correo electrónico", Icons.alternate_email_rounded),
        _field(_fullName, "Nombre completo", Icons.person_rounded),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _canSubmitIdentity ? _registerAndStart : null,
          icon: const Icon(Icons.login_rounded),
          label: const Text("Continuar"),
        ),
        if (_state.blocked) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _busy ? null : _registerAndStart,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text("Intentar de nuevo"),
          ),
        ],
      ],
    );
  }

  Widget _codeStep() {
    final showDebugCode = !kReleaseMode && _state.debugVerificationCode != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showDebugCode) ...[
          _debugCodeHint(_state.debugVerificationCode!),
          const SizedBox(height: 10),
        ],
        TextField(
          controller: _code,
          decoration: const InputDecoration(
            labelText: "Código de verificación",
            prefixIcon: Icon(Icons.pin_rounded),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _verifyCode,
          icon: const Icon(Icons.verified_rounded),
          label: const Text("Verificar"),
        ),
        TextButton.icon(
          onPressed: _busy ? null : _resendCode,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text("Enviar otro código"),
        ),
      ],
    );
  }

  Widget _biometricStep() {
    return FilledButton.icon(
      onPressed: _busy ? null : _verifyBiometric,
      icon: const Icon(Icons.fingerprint_rounded),
      label: const Text("Confirmar identidad"),
    );
  }

  Widget _voiceStep() {
    return FilledButton.icon(
      onPressed: _busy ? null : _verifyVoice,
      icon: const Icon(Icons.mic_rounded),
      label: const Text("Confirmar voz"),
    );
  }

  Widget _continueAction() {
    return FilledButton.icon(
      key: const Key("enterprise-continue-local"),
      onPressed: _continue,
      icon: const Icon(Icons.arrow_forward_rounded),
      label: const Text("Entrar a OSvoz"),
    );
  }

  Widget _field(TextEditingController controller, String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _debugCodeHint(String code) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: const Color(0xFF54D6B6).withValues(alpha: 0.12),
        border: Border.all(
          color: const Color(0xFF54D6B6).withValues(alpha: 0.34),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.bug_report_rounded, color: Color(0xFF54D6B6)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "Código de prueba local: $code",
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.86),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
