import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../controllers/labvoice_controller.dart';
import '../services/language_manager.dart';
import '../services/voice_engine.dart';

class LabVoiceCommandCenter extends StatefulWidget {
  const LabVoiceCommandCenter({super.key});

  @override
  State<LabVoiceCommandCenter> createState() => _LabVoiceCommandCenterState();
}

class _LabVoiceCommandCenterState extends State<LabVoiceCommandCenter>
    with SingleTickerProviderStateMixin {
  final LabVoiceController _controller = LabVoiceController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  late final AnimationController _pulse;
  bool _speechInitialized = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
      lowerBound: 0.92,
      upperBound: 1.06,
    );
    _controller.addListener(_refresh);
    _controller.initialize();
  }

  void _refresh() {
    if (_controller.isListening && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!_controller.isListening && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 1;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    _controller.dispose();
    _pulse.dispose();
    _speech.cancel();
    super.dispose();
  }

  Future<void> _listen() async {
    if (_controller.isListening) return;
    await VoiceEngine.stop();
    await Future<void>.delayed(const Duration(milliseconds: 150));

    final available = _speechInitialized
        ? _speech.isAvailable
        : await _initializeSpeech();
    if (!available) {
      await _controller.microphoneUnavailable();
      return;
    }

    final localeId = await _supportedLocale(
      LanguageManager.activeRecognitionLocale,
    );
    _controller.setListening(true);
    try {
      await _speech.listen(
        listenOptions: stt.SpeechListenOptions(
          localeId: localeId,
          listenFor: const Duration(minutes: 10),
          pauseFor: const Duration(seconds: 3),
          cancelOnError: true,
          partialResults: true,
          listenMode: stt.ListenMode.dictation,
          sampleRate: 44100,
        ),
        onResult: (result) async {
          if (!result.finalResult) {
            _controller.updatePartialTranscript(result.recognizedWords);
            return;
          }
          final command = result.recognizedWords.trim();
          await _speech.stop();
          _controller.setListening(false);
          if (command.isNotEmpty) await _controller.processCommand(command);
        },
      );
      if (!_speech.isListening && !_speech.hasRecognized) {
        final error = _speech.lastError?.errorMsg ?? "listen_not_started";
        await _controller.speechRecognitionError(error);
      }
    } catch (error) {
      await _controller.speechRecognitionError(error.toString());
    }
  }

  Future<bool> _initializeSpeech() async {
    final available = await _speech.initialize(
      debugLogging: true,
      onStatus: (status) {
        if (status == "done" || status == "notListening") {
          _controller.setListening(false);
        }
      },
      onError: (error) {
        _controller.speechRecognitionError(error.errorMsg);
      },
    );
    _speechInitialized = available;
    return available;
  }

  Future<String?> _supportedLocale(String? preferredLocale) async {
    if (preferredLocale == null) return null;
    final locales = await _speech.locales();
    final normalizedPreferred = preferredLocale.replaceAll("-", "_");
    for (final locale in locales) {
      if (locale.localeId.replaceAll("-", "_") == normalizedPreferred) {
        return locale.localeId;
      }
    }
    return null;
  }

  Color _statusColor(ColorScheme colors) {
    if (_controller.isListening) return colors.primary;
    if (_controller.securityLevel.toLowerCase() == "blocked") {
      return colors.error;
    }
    return const Color(0xFF54D6B6);
  }

  Widget _voiceCore(ColorScheme colors) {
    final listening = _controller.isListening;
    final statusColor = _statusColor(colors);
    return Semantics(
      button: true,
      label: listening
          ? "LabVoice está escuchando"
          : "Activar micrófono de LabVoice",
      hint: "Toca para hablar con LabVoice",
      child: GestureDetector(
        onTap: _listen,
        child: ScaleTransition(
          scale: _pulse,
          child: AnimatedContainer(
            key: const Key("voice-core"),
            duration: const Duration(milliseconds: 350),
            width: 142,
            height: 142,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: listening
                    ? [const Color(0xFF8C7CFF), const Color(0xFF4E5BFF)]
                    : [const Color(0xFF252A3A), const Color(0xFF161925)],
              ),
              border: Border.all(
                color: statusColor.withValues(alpha: 0.75),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: statusColor.withValues(alpha: listening ? 0.42 : 0.18),
                  blurRadius: listening ? 42 : 24,
                  spreadRadius: listening ? 6 : 1,
                ),
              ],
            ),
            child: Icon(
              listening ? Icons.graphic_eq_rounded : Icons.mic_rounded,
              size: 54,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _responseCard(ThemeData theme) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
    decoration: BoxDecoration(
      color: const Color(0xFF171A26).withValues(alpha: 0.88),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "LABVOICE",
          style: theme.textTheme.labelMedium?.copyWith(
            color: const Color(0xFF9B91FF),
            letterSpacing: 2.4,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        SelectableText(
          _controller.response,
          style: theme.textTheme.titleLarge?.copyWith(
            height: 1.42,
            color: const Color(0xFFF1F2F8),
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    ),
  );

  Widget _heardText(ThemeData theme) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 250),
    child: Text(
      _controller.heardCommand,
      key: ValueKey(_controller.heardCommand),
      textAlign: TextAlign.center,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyLarge?.copyWith(
        color: Colors.white.withValues(alpha: 0.68),
        height: 1.35,
      ),
    ),
  );

  Widget _details(ThemeData theme) => Theme(
    data: theme.copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 12),
      iconColor: Colors.white54,
      collapsedIconColor: Colors.white38,
      title: Text(
        "Detalles del sistema",
        style: theme.textTheme.labelLarge?.copyWith(color: Colors.white54),
      ),
      children: [
        _detailRow("Idioma", _controller.activeLanguageName),
        _detailRow("Intención", _controller.detectedIntent),
        _detailRow("Acción", _controller.technicalAction),
        _detailRow("Seguridad", _controller.securityLevel),
      ],
    ),
  );

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(label, style: const TextStyle(color: Colors.white38)),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(color: Colors.white70)),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.55),
            radius: 1.15,
            colors: [Color(0xFF24233B), Color(0xFF0C0E16)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 30, 28, 36),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _statusColor(colors),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: _statusColor(
                                  colors,
                                ).withValues(alpha: 0.45),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _controller.isListening
                              ? "ESCUCHANDO"
                              : "LISTO PARA ESCUCHAR",
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: Colors.white60,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _controller.activeLanguageName,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: Colors.white38,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 34),
                    _responseCard(theme),
                    const SizedBox(height: 34),
                    _heardText(theme),
                    const SizedBox(height: 34),
                    _voiceCore(colors),
                    const SizedBox(height: 18),
                    Text(
                      _controller.isListening
                          ? "Habla con naturalidad"
                          : "Toca para hablar",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white38,
                      ),
                    ),
                    const SizedBox(height: 34),
                    _details(theme),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
