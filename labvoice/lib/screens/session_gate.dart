import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/language_manager.dart';
import '../services/session_authenticator.dart';
import 'labvoice_command_center.dart';

enum SessionGatePhase { selectingLanguage, biometric, ready, blocked }

class SessionGate extends StatefulWidget {
  const SessionGate({
    super.key,
    required this.authenticator,
    this.onSessionReady,
  });

  final SessionAuthenticator authenticator;
  final Future<void> Function()? onSessionReady;

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  SessionGatePhase _phase = SessionGatePhase.selectingLanguage;
  String _title = "Escuchando";
  String _detail = "Di: inicia mi sesión.";
  String _language = "Español";
  String _recognitionLocale = "es_ES";
  String _transcript = "";
  bool _busy = false;
  bool _languageReady = false;
  bool _identityVerified = false;

  @override
  void initState() {
    super.initState();
    _prepareDefaultLanguage();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_listenForSessionStart());
    });
  }

  void _prepareDefaultLanguage() {
    final locale = PlatformDispatcher.instance.locale;
    final languageCode = locale.languageCode.toLowerCase();
    final defaultLocale = languageCode == "en" ? "en_US" : "es_ES";
    _selectLanguage(defaultLocale, authenticate: false);
  }

  Future<void> _begin() async {
    await _authenticateBiometric();
  }

  Future<void> _listenForSessionStart() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _phase = SessionGatePhase.selectingLanguage;
      _languageReady = false;
      _identityVerified = false;
      _transcript = "";
      _title = _language == "English" ? "Listening" : "Escuchando";
      _detail = _language == "English"
          ? "Say: start my session."
          : "Di: inicia mi sesión.";
    });
    final result = await widget.authenticator.listenForSessionStart(
      recognitionLocale: _recognitionLocale,
    );
    if (!mounted) return;
    final profile = LanguageManager.profileForLanguage(result.language);
    LanguageManager.setLanguage(profile.recognitionLocale ?? "es_ES");
    setState(() {
      _busy = false;
      _language = profile.name;
      _recognitionLocale = profile.recognitionLocale ?? "es_ES";
      _transcript = result.transcript;
    });
    if (!result.verified) {
      setState(() {
        _phase = SessionGatePhase.blocked;
        _title = _language == "English"
            ? "I did not catch it"
            : "No te escuché";
        _detail = result.message;
      });
      return;
    }
    setState(() {
      _languageReady = true;
      _title = _language == "English"
          ? "Session requested"
          : "Sesión solicitada";
      _detail = _language == "English"
          ? "Confirm your identity to continue."
          : "Confirma tu identidad para continuar.";
    });
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await _begin();
  }

  void _changeLanguage() {
    setState(() {
      _phase = SessionGatePhase.selectingLanguage;
      _languageReady = false;
      _identityVerified = false;
      _transcript = "";
      _title = "Elige tu idioma";
      _detail = "IOV escuchará en el idioma que elijas.";
    });
  }

  void _selectLanguage(String recognitionLocale, {bool authenticate = true}) {
    final profile = LanguageManager.profiles.values.firstWhere(
      (profile) => profile.recognitionLocale == recognitionLocale,
      orElse: () => LanguageManager.profiles["es_ES"]!,
    );
    LanguageManager.setLanguage(profile.recognitionLocale ?? "es_ES");
    setState(() {
      _phase = SessionGatePhase.selectingLanguage;
      _languageReady = false;
      _identityVerified = false;
      _transcript = "";
      _language = profile.name;
      _recognitionLocale = profile.recognitionLocale ?? "es_ES";
      _title = _language == "English" ? "Listening" : "Escuchando";
      _detail = _language == "English"
          ? "Say: start my session."
          : "Di: inicia mi sesión.";
    });
    if (authenticate) unawaited(_listenForSessionStart());
  }

  Future<void> _authenticateBiometric() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _languageReady = true;
      _phase = SessionGatePhase.biometric;
      _title = "Verificando identidad";
      _detail = "Usa Face ID, Touch ID o la autenticación local del sistema.";
    });
    try {
      final verified = await widget.authenticator.authenticateBiometric();
      if (!mounted) return;
      if (!verified) {
        setState(() {
          _busy = false;
          _identityVerified = false;
          _phase = SessionGatePhase.blocked;
          _title = "No pude verificarte";
          _detail = "Reintenta la verificación local para abrir IOV.";
        });
        return;
      }
      setState(() {
        _busy = false;
        _identityVerified = true;
        _phase = SessionGatePhase.ready;
        _title = "Identidad verificada";
        _detail = _language == "English"
            ? "Local authentication completed. Opening IOV."
            : "Autenticación local completada. Entrando a IOV.";
      });
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (!mounted) return;
      await widget.onSessionReady?.call();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const OSvozCommandCenter()),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _identityVerified = false;
        _phase = SessionGatePhase.blocked;
        _title = "Autenticación no disponible";
        _detail = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.45),
            radius: 1.1,
            colors: [Color(0xFF24233B), Color(0xFF0C0E16)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      "IOV",
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.84),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _detail,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.58),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 36),
                    if (_phase == SessionGatePhase.selectingLanguage && !_busy)
                      _languageChooser(theme)
                    else ...[
                      _steps(theme),
                      if (_transcript.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text(
                          _transcript,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: Colors.white70,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                      const SizedBox(height: 36),
                      _actions(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _languageChooser(ThemeData theme) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        ChoiceChip(
          selected: _recognitionLocale == "es_ES",
          avatar: const Icon(Icons.language_rounded),
          label: const Text("Español"),
          onSelected: (_) => _selectLanguage("es_ES"),
        ),
        ChoiceChip(
          selected: _recognitionLocale == "en_US",
          avatar: const Icon(Icons.language_rounded),
          label: const Text("English"),
          onSelected: (_) => _selectLanguage("en_US"),
        ),
      ],
    );
  }

  Widget _steps(ThemeData theme) {
    final steps = [
      ("Idioma", _languageReady, _language),
      ("Identidad", _identityVerified, "Sistema"),
    ];
    return Row(
      children: [
        for (final step in steps)
          Expanded(
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: step.$2
                        ? const Color(0xFF54D6B6)
                        : Colors.white.withValues(alpha: 0.08),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Icon(
                    step.$2 ? Icons.check_rounded : Icons.circle_outlined,
                    color: step.$2 ? const Color(0xFF10141D) : Colors.white38,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  step.$1,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  step.$3,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white38,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _actions() {
    if (_phase == SessionGatePhase.ready) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_busy) {
      return const Center(child: CircularProgressIndicator());
    }
    final retrySessionStart =
        _phase == SessionGatePhase.selectingLanguage ||
        (_phase == SessionGatePhase.blocked &&
            (_title.contains("escuch") || _title.contains("catch")));
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            onPressed: retrySessionStart
                ? _listenForSessionStart
                : _authenticateBiometric,
            icon: Icon(
              retrySessionStart ? Icons.mic_rounded : Icons.lock_open_rounded,
            ),
            label: Text(
              retrySessionStart ? "Escuchar" : "Reintentar identidad",
            ),
          ),
          if (retrySessionStart) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              key: const Key("change-session-language"),
              onPressed: _changeLanguage,
              icon: const Icon(Icons.language_rounded),
              label: const Text("Cambiar idioma"),
            ),
          ],
        ],
      ),
    );
  }
}
