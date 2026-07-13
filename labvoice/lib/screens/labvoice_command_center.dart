import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../controllers/labvoice_controller.dart';
import '../services/labvoice_api.dart';
import '../services/language_manager.dart';
import '../services/local_whisper_recorder.dart';
import '../services/voice_engine.dart';
import '../services/voice_echo_guard.dart';
import '../services/voice_fallback_policy.dart';
import '../services/voice_latency_metrics.dart';
import '../services/voice_noise_gate.dart';
import '../services/wake_word_gate.dart';

class OSvozCommandCenter extends StatefulWidget {
  const OSvozCommandCenter({super.key});

  @override
  State<OSvozCommandCenter> createState() => _OSvozCommandCenterState();
}

class _OSvozCommandCenterState extends State<OSvozCommandCenter>
    with SingleTickerProviderStateMixin {
  final OSvozController _controller = OSvozController();
  final LocalWhisperRecorder _whisperRecorder = LocalWhisperRecorder();
  final SpeechToText _nativeSpeech = SpeechToText();
  final WakeWordGate _wakeWordGate = WakeWordGate();
  final VoiceEchoGuard _echoGuard = VoiceEchoGuard();
  final VoiceNoiseGate _voiceNoiseGate = VoiceNoiseGate();
  late final AnimationController _pulse;
  final bool _continuousListening = false;
  final bool _preferFastNativeSpeech = false;
  bool _startingListener = false;
  bool _usingNativeSpeech = false;
  bool _forceNativeSpeechOnce = false;
  bool _autoStoppingWhisper = false;
  bool _manualWhisperCapture = false;
  Timer? _rearmTimer;
  Timer? _captureMonitorTimer;
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  DateTime? _captureStartedAt;
  DateTime? _lastVoiceAt;
  bool _voiceDetectedInCapture = false;
  String _nativeTranscript = "";
  String _voiceDebugStatus = "Esperando prueba manual.";
  String _voiceDebugLanguage = "auto";
  String _voiceDebugAudio = "Sin audio capturado.";
  String _voiceDebugLatency = "Sin transcripción.";
  String _voiceDebugError = "Sin errores.";
  String _backendInterpretation = "Sin interpretación.";
  String _codeRoute = "Sin ruta de código.";

  static const Duration _amplitudeInterval = Duration(milliseconds: 120);
  static const Duration _minimumCaptureWindow = Duration(milliseconds: 650);
  static const Duration _initialSilenceTimeout = Duration(seconds: 3);
  static const Duration _silenceAfterSpeech = Duration(milliseconds: 950);
  static const Duration _maximumCaptureWindow = Duration(seconds: 12);
  static const double _voiceThresholdDb = -43;

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
    VoiceEngine.speaking.addListener(_voiceStateChanged);
    unawaited(_initializeContinuousVoice());
  }

  Future<void> _initializeContinuousVoice() async {
    await _controller.initialize();
    _scheduleRearm();
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
    VoiceEngine.speaking.removeListener(_voiceStateChanged);
    _controller.dispose();
    _pulse.dispose();
    _rearmTimer?.cancel();
    _cancelCaptureMonitor();
    unawaited(_whisperRecorder.dispose());
    unawaited(_nativeSpeech.cancel());
    super.dispose();
  }

  void _voiceStateChanged() {
    if (VoiceEngine.speaking.value) {
      _rearmTimer?.cancel();
      _cancelCaptureMonitor();
      unawaited(_whisperRecorder.stop());
      unawaited(_nativeSpeech.cancel());
      _usingNativeSpeech = false;
      _controller.setListening(false);
      _echoGuard.markSpeechStarted(_controller.response);
      return;
    }
    _echoGuard.markSpeechEnded();
    _scheduleRearm();
  }

  void _scheduleRearm([Duration delay = const Duration(milliseconds: 450)]) {
    if (!_continuousListening || !mounted) return;
    _rearmTimer?.cancel();
    _rearmTimer = Timer(delay, () {
      if (mounted && !VoiceEngine.speaking.value) {
        unawaited(_listen());
      }
    });
  }

  Future<void> _listen({bool manual = false}) async {
    if (_controller.isListening && manual) {
      if (_usingNativeSpeech) {
        await _stopNativeSpeech(manual: manual);
      } else {
        await _stopListeningAndProcess(manual: manual);
      }
      return;
    }
    if (_controller.isListening || _startingListener) return;
    if (VoiceEngine.speaking.value) {
      if (!manual) {
        _scheduleRearm();
        return;
      }
      await VoiceEngine.stop();
    }
    _startingListener = true;
    _setVoiceDebug(
      status: "Preparando micrófono...",
      language: _whisperLanguage(),
      error: "Sin errores.",
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    if (_forceNativeSpeechOnce) {
      _forceNativeSpeechOnce = false;
      await _startNativeSpeech(
        manual: manual,
        reason: "Usando reconocimiento nativo rápido.",
      );
      return;
    }

    if (_preferFastNativeSpeech) {
      await _startNativeSpeech(
        manual: manual,
        reason: "Modo rápido: reconocimiento nativo.",
      );
      return;
    }

    final backendAvailability = OSvozApi.isBackendAvailable();
    final microphonePermission = _whisperRecorder.hasPermission().catchError(
      (_) => false,
    );
    final backendAvailable = await backendAvailability;
    if (!backendAvailable) {
      await _startNativeSpeech(
        manual: manual,
        reason: "Backend apagado. Usando reconocimiento nativo.",
      );
      return;
    }

    final available = await microphonePermission;
    if (!available) {
      _startingListener = false;
      _setVoiceDebug(
        status: "Permiso de micrófono no disponible.",
        error:
            "Activa OSvoz en Ajustes del Sistema > Privacidad y seguridad > Micrófono y reinicia la app.",
      );
      await _controller.microphoneUnavailable();
      return;
    }

    _controller.setListening(true);
    _manualWhisperCapture = manual;
    _setVoiceDebug(
      status: "Micrófono activo. Habla y procesaré al detectar silencio.",
      language: _whisperLanguage(),
    );
    try {
      _startingListener = false;
      await _whisperRecorder.startRecording();
      _beginCaptureMonitor();
    } on OSvozApiException catch (error) {
      _manualWhisperCapture = false;
      _startingListener = false;
      _controller.setListening(false);
      _setVoiceDebug(
        status: "No pude iniciar el micrófono.",
        error: "${error.code ?? "error"}: ${error.message}",
      );
      await _controller.speechRecognitionError(error.message);
    } catch (error) {
      _manualWhisperCapture = false;
      _startingListener = false;
      _controller.setListening(false);
      _setVoiceDebug(
        status: "Error inesperado en voz.",
        latency: "Falló antes de completar.",
        error: error.toString(),
      );
      await _controller.speechRecognitionError(error.toString());
      _scheduleRearm(const Duration(seconds: 1));
    }
  }

  Future<void> _startNativeSpeech({
    bool manual = false,
    String reason = "Usando reconocimiento nativo.",
  }) async {
    _nativeTranscript = "";
    _usingNativeSpeech = true;
    _setVoiceDebug(
      status: reason,
      language: LanguageManager.effectiveLanguage,
      error: "Sin errores.",
    );
    final available = await _nativeSpeech.initialize(
      onStatus: _nativeSpeechStatus,
      onError: _nativeSpeechError,
    );
    if (!available) {
      _startingListener = false;
      _usingNativeSpeech = false;
      await _controller.microphoneUnavailable();
      return;
    }
    _controller.setListening(true);
    _startingListener = false;
    await _nativeSpeech.listen(
      onResult: _nativeSpeechResult,
      listenOptions: SpeechListenOptions(
        localeId: LanguageManager.current.languageTag == "auto"
            ? "es_ES"
            : LanguageManager.activeVoiceLocale,
        listenMode: ListenMode.dictation,
        partialResults: true,
      ),
    );
  }

  void _nativeSpeechResult(SpeechRecognitionResult result) {
    _nativeTranscript = result.recognizedWords.trim();
    if (_nativeTranscript.isNotEmpty) {
      _controller.updatePartialTranscript(_nativeTranscript);
    }
    if (result.finalResult) {
      unawaited(_stopNativeSpeech(manual: true));
    }
  }

  void _nativeSpeechStatus(String status) {
    _setVoiceDebug(status: "Reconocimiento nativo: $status");
  }

  void _nativeSpeechError(SpeechRecognitionError error) {
    _setVoiceDebug(
      status: "Falló reconocimiento nativo.",
      error: "${error.errorMsg} · permanent=${error.permanent}",
    );
  }

  Future<void> _stopNativeSpeech({bool manual = false}) async {
    if (_startingListener) return;
    _startingListener = true;
    await _nativeSpeech.stop();
    _controller.setListening(false);
    final command = _nativeTranscript.trim();
    _usingNativeSpeech = false;
    _startingListener = false;
    if (command.isEmpty) {
      await _controller.speechRecognitionError(
        "No se detectó texto con el reconocimiento nativo.",
      );
      return;
    }
    _setVoiceDebug(
      status: "Texto nativo recibido.",
      audio: "Reconocimiento del sistema",
      latency: "Sin Whisper/backend",
      error: "Sin errores.",
    );
    if (_blockEcho(command)) return;
    await _controller.processCommand(command);
  }

  Future<void> _stopListeningAndProcess({bool manual = false}) async {
    if (_startingListener) return;
    _startingListener = true;
    final captureStartedAt = _captureStartedAt;
    _cancelCaptureMonitor();
    _controller.setListening(false);
    _controller.processingCapturedVoice();
    if (captureStartedAt != null) {
      VoiceLatencyMetrics.record(
        "capture_ms",
        DateTime.now().difference(captureStartedAt),
      );
    }
    _setVoiceDebug(
      status: "Procesando audio...",
      language: _whisperLanguage(),
      error: "Sin errores.",
    );
    try {
      final result = await _whisperRecorder.stopAndTranscribe(
        language: _whisperLanguage(),
      );
      VoiceLatencyMetrics.record(
        "transcription_ms",
        result.transcriptionElapsed,
      );
      final command = result.transcript;
      _startingListener = false;
      _autoStoppingWhisper = false;
      _manualWhisperCapture = false;
      _setVoiceDebug(
        status: command.isEmpty
            ? "Whisper no devolvió texto."
            : "Transcripción recibida.",
        language: result.language,
        audio:
            "${_formatBytes(result.audioBytes)} · ${(result.backendAudioSeconds ?? result.recordingWindow.inMilliseconds / 1000).toStringAsFixed(2)}s",
        latency:
            "${result.transcriptionElapsed.inMilliseconds} ms · rms=${result.localRms.toStringAsFixed(4)} peak=${result.localPeak.toStringAsFixed(4)}",
        error: "Sin errores.",
      );
      if (command.isNotEmpty) {
        final noiseDecision = _voiceNoiseGate.evaluate(command);
        _controller.updatePartialTranscript(noiseDecision.cleanedTranscript);
        if (!noiseDecision.accepted) {
          _setVoiceDebug(
            status: "Audio ignorado por compuerta de voz.",
            error: "Filtro: ${noiseDecision.reason}",
          );
          _scheduleRearm();
          return;
        }
        if (_blockEcho(noiseDecision.cleanedTranscript)) {
          _scheduleRearm();
          return;
        }
        unawaited(
          _interpretTranscript(
            noiseDecision.cleanedTranscript,
            result.language,
          ),
        );
        if (_isVoiceEnrollmentCommand(noiseDecision.cleanedTranscript)) {
          await _enrollSpeakerFromAudio(
            noiseDecision.cleanedTranscript,
            result.rawAudioBytes,
          );
          _scheduleRearm();
          return;
        }
        if (_isVoiceVerificationCommand(noiseDecision.cleanedTranscript)) {
          await _verifySpeakerFromAudio(
            noiseDecision.cleanedTranscript,
            result.rawAudioBytes,
          );
          _scheduleRearm();
          return;
        }
        final decision = _wakeWordGate.evaluate(
          noiseDecision.cleanedTranscript,
        );
        if (manual && !decision.accepted) {
          await _controller.processCommand(noiseDecision.cleanedTranscript);
        } else if (decision.accepted) {
          await _controller.processCommand(decision.command);
        } else {
          _controller.ambientSpeechIgnored(noiseDecision.cleanedTranscript);
        }
      }
      _scheduleRearm();
    } on OSvozApiException catch (error) {
      _startingListener = false;
      _autoStoppingWhisper = false;
      _manualWhisperCapture = false;
      _controller.setListening(false);
      final safeError = VoiceFallbackPolicy.safeVoiceErrorMessage(
        error.message,
      );
      _setVoiceDebug(
        status: "Falló la transcripción.",
        latency: "Falló antes de completar.",
        error: "${error.code ?? "error"}: $safeError",
      );
      if (VoiceFallbackPolicy.shouldUseNativeSpeechFallback(error)) {
        await _controller.speechRecognitionError(
          "Whisper local no pudo iniciar. Cambio a reconocimiento nativo.",
        );
        _setVoiceDebug(
          status: "Cambiando a reconocimiento nativo...",
          latency: "Fallback activo",
          error: safeError,
        );
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (mounted && !VoiceEngine.speaking.value) {
          await _startNativeSpeech(
            manual: true,
            reason: "Whisper falló. Usando reconocimiento nativo.",
          );
        } else {
          _forceNativeSpeechOnce = true;
        }
        return;
      }
      if (VoiceFallbackPolicy.isNoSpeech(error)) {
        _scheduleRearm(const Duration(milliseconds: 250));
        return;
      }
      await _controller.speechRecognitionError(safeError);
      _scheduleRearm(const Duration(seconds: 1));
    } catch (error) {
      _startingListener = false;
      _autoStoppingWhisper = false;
      _manualWhisperCapture = false;
      _controller.setListening(false);
      final safeError = VoiceFallbackPolicy.safeVoiceErrorMessage(
        error.toString(),
      );
      _setVoiceDebug(
        status: "Error inesperado en voz.",
        latency: "Falló antes de completar.",
        error: safeError,
      );
      await _controller.speechRecognitionError(safeError);
      _scheduleRearm(const Duration(seconds: 1));
    }
  }

  void _beginCaptureMonitor() {
    _cancelCaptureMonitor();
    final now = DateTime.now();
    _captureStartedAt = now;
    _lastVoiceAt = null;
    _voiceDetectedInCapture = false;
    _autoStoppingWhisper = false;
    _setVoiceDebug(
      status: "Habla ahora. Cortaré automáticamente al terminar.",
      latency: "Auto-corte activo",
    );
    _amplitudeSubscription = _whisperRecorder
        .onAmplitudeChanged(_amplitudeInterval)
        .listen(_handleAmplitudeChanged, onError: (_) {});
    _captureMonitorTimer = Timer.periodic(
      _amplitudeInterval,
      (_) => _evaluateAutoStop(),
    );
  }

  void _handleAmplitudeChanged(Amplitude amplitude) {
    final now = DateTime.now();
    final current = amplitude.current;
    if (current >= _voiceThresholdDb) {
      _voiceDetectedInCapture = true;
      _lastVoiceAt = now;
    }
    _setVoiceDebug(
      audio:
          "Nivel ${current.toStringAsFixed(1)} dB · max ${amplitude.max.toStringAsFixed(1)} dB",
    );
    _evaluateAutoStop(now);
  }

  void _evaluateAutoStop([DateTime? observedAt]) {
    if (!_controller.isListening ||
        _usingNativeSpeech ||
        _startingListener ||
        _autoStoppingWhisper) {
      return;
    }
    final startedAt = _captureStartedAt;
    if (startedAt == null) return;
    final now = observedAt ?? DateTime.now();
    final elapsed = now.difference(startedAt);
    if (elapsed >= _maximumCaptureWindow) {
      unawaited(_autoStopWhisper("Límite máximo alcanzado."));
      return;
    }
    if (!_voiceDetectedInCapture && elapsed >= _initialSilenceTimeout) {
      unawaited(_autoStopWhisper("No detecté voz inicial."));
      return;
    }
    final lastVoiceAt = _lastVoiceAt;
    if (_voiceDetectedInCapture &&
        lastVoiceAt != null &&
        elapsed >= _minimumCaptureWindow &&
        now.difference(lastVoiceAt) >= _silenceAfterSpeech) {
      unawaited(_autoStopWhisper("Silencio detectado. Procesando."));
    }
  }

  Future<void> _autoStopWhisper(String reason) async {
    if (_autoStoppingWhisper) return;
    _autoStoppingWhisper = true;
    _setVoiceDebug(status: reason);
    await _stopListeningAndProcess(manual: _manualWhisperCapture);
  }

  void _cancelCaptureMonitor() {
    _captureMonitorTimer?.cancel();
    _captureMonitorTimer = null;
    unawaited(_amplitudeSubscription?.cancel());
    _amplitudeSubscription = null;
    _captureStartedAt = null;
    _lastVoiceAt = null;
    _voiceDetectedInCapture = false;
  }

  bool _blockEcho(String transcript) {
    final decision = _echoGuard.evaluate(transcript);
    if (!decision.blocked) return false;
    _controller.ambientSpeechIgnored(transcript);
    _setVoiceDebug(
      status: "Eco de OSvoz bloqueado.",
      error: "Filtro anti-eco: ${decision.reason}",
    );
    return true;
  }

  Future<void> _interpretTranscript(String transcript, String language) async {
    _setVoiceDebug(status: "Interpretando comando...");
    final stopwatch = Stopwatch()..start();
    try {
      final result = await OSvozApi.interpretVoice(
        transcript,
        language: language,
      );
      stopwatch.stop();
      VoiceLatencyMetrics.record("backend_intent_ms", stopwatch.elapsed);
      final interpretation = result["interpretation"];
      final codeRoute = result["code_route"];
      final intent = interpretation is Map
          ? interpretation["intent"]?.toString() ?? "unknown"
          : "unknown";
      final action = interpretation is Map
          ? interpretation["action"]?.toString() ?? "none"
          : "none";
      final executable = interpretation is Map
          ? interpretation["executable"]?.toString() ?? "false"
          : "false";
      final domain = codeRoute is Map
          ? codeRoute["domain"]?.toString() ?? "unknown"
          : "unknown";
      final capability = codeRoute is Map
          ? codeRoute["capability"]?.toString() ?? "unknown"
          : "unknown";
      final routeLanguage = codeRoute is Map
          ? codeRoute["language"]?.toString() ?? "unknown"
          : "unknown";
      if (!mounted) return;
      setState(() {
        _backendInterpretation =
            "intent=$intent · action=$action · executable=$executable";
        _codeRoute = "$domain/$capability · $routeLanguage";
      });
    } on OSvozApiException catch (error) {
      stopwatch.stop();
      VoiceLatencyMetrics.record("backend_intent_ms", stopwatch.elapsed);
      if (!mounted) return;
      setState(() {
        _backendInterpretation =
            "Falló interpretación: ${error.code ?? "error"}";
        _codeRoute = error.message;
      });
    }
  }

  String _whisperLanguage() {
    final language = LanguageManager.current.languageTag == "auto"
        ? "auto"
        : LanguageManager.effectiveLanguage;
    return {"auto", "es", "en"}.contains(language) ? language : "auto";
  }

  bool _isVoiceEnrollmentCommand(String transcript) {
    final normalized = transcript.toLowerCase();
    return normalized.contains("entrena mi voz") ||
        normalized.contains("registrar mi voz") ||
        normalized.contains("registra mi voz") ||
        normalized.contains("graba mi voz") ||
        normalized.contains("enroll my voice") ||
        normalized.contains("register my voice");
  }

  bool _isVoiceVerificationCommand(String transcript) {
    final normalized = transcript.toLowerCase();
    return normalized.contains("verifica mi voz") ||
        normalized.contains("verificar mi voz") ||
        normalized.contains("confirma mi voz") ||
        normalized.contains("confirmar mi voz") ||
        normalized.contains("verify my voice") ||
        normalized.contains("confirm my voice");
  }

  Future<void> _enrollSpeakerFromAudio(
    String transcript,
    List<int> audioBytes,
  ) async {
    _setVoiceDebug(status: "Guardando muestra de identidad de voz...");
    try {
      final result = await OSvozApi.enrollSpeaker(
        Uint8List.fromList(audioBytes),
        phrase: transcript,
      );
      final sampleCount = result["sample_count"]?.toString() ?? "0";
      final recommended = result["recommended_samples"]?.toString() ?? "12";
      final enrolled = result["enrolled"] == true;
      await _controller.voiceEnrollmentResult(
        heard: transcript,
        response: enrolled
            ? "Listo, Ian. Ya tengo una base local de tu voz. Seguiremos reforzándola con más muestras."
            : "Guardé esta muestra de tu voz. Llevamos $sampleCount de $recommended recomendadas.",
        action: enrolled
            ? "Local speaker profile enrolled."
            : "Local speaker sample saved.",
      );
      _setVoiceDebug(
        status: enrolled
            ? "Identidad de voz inicial activa."
            : "Muestra de voz $sampleCount/$recommended guardada.",
        error: "Sin errores.",
      );
    } on OSvozApiException catch (error) {
      await _controller.voiceEnrollmentResult(
        heard: transcript,
        response: "No pude guardar esta muestra de voz: ${error.message}",
        action: error.code ?? "speaker_enrollment_failed",
        security: "Blocked",
      );
      _setVoiceDebug(
        status: "Falló identidad de voz.",
        error: "${error.code ?? "error"}: ${error.message}",
      );
    }
  }

  Future<void> _verifySpeakerFromAudio(
    String transcript,
    List<int> audioBytes,
  ) async {
    _setVoiceDebug(status: "Verificando identidad de voz...");
    try {
      final result = await OSvozApi.verifySpeaker(
        Uint8List.fromList(audioBytes),
      );
      final verified = result["verified"] == true;
      final error = result["error"]?.toString();
      final distance = result["distance"]?.toString();
      await _controller.voiceVerificationResult(
        heard: transcript,
        verified: verified,
        response: verified
            ? "Voz confirmada localmente. Tu identidad de voz coincide."
            : error == "speaker_not_enrolled"
            ? "Todavía necesito al menos tres muestras. Di: IOV, registra mi voz."
            : "La voz no coincide con el perfil local. No autoricé ninguna acción.",
        action: verified
            ? "Local speaker identity verified."
            : error ?? "speaker_voice_mismatch",
      );
      _setVoiceDebug(
        status: verified
            ? "Identidad de voz confirmada."
            : "Identidad de voz no confirmada.",
        error: verified
            ? "Sin errores${distance == null ? "." : " · distancia=$distance"}"
            : error ?? "voice_mismatch",
      );
    } on OSvozApiException catch (error) {
      await _controller.voiceVerificationResult(
        heard: transcript,
        verified: false,
        response: "No pude verificar tu voz: ${error.message}",
        action: error.code ?? "speaker_verification_failed",
      );
      _setVoiceDebug(
        status: "Falló la verificación de voz.",
        error: "${error.code ?? "error"}: ${error.message}",
      );
    }
  }

  void _setVoiceDebug({
    String? status,
    String? language,
    String? audio,
    String? latency,
    String? error,
  }) {
    if (!mounted) return;
    setState(() {
      if (status != null) _voiceDebugStatus = status;
      if (language != null) _voiceDebugLanguage = language;
      if (audio != null) _voiceDebugAudio = audio;
      if (latency != null) _voiceDebugLatency = latency;
      if (error != null) _voiceDebugError = error;
    });
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    return "${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB";
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
      label: listening ? "OSvoz está escuchando" : "Activar micrófono de OSvoz",
      hint: listening
          ? "Toca otra vez para detener manualmente"
          : "Toca para activar el micrófono",
      child: GestureDetector(
        onTap: () => _listen(manual: true),
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
          "OSvoz",
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
        _detailRow("Voz", _voiceDebugStatus),
        _detailRow("Whisper", "$_voiceDebugLanguage · $_voiceDebugLatency"),
        _detailRow("Audio", _voiceDebugAudio),
        _detailRow("Latencia", VoiceLatencyMetrics.compactSummary()),
        _detailRow("Error voz", _voiceDebugError),
        _detailRow("Backend", _backendInterpretation),
        _detailRow("Código", _codeRoute),
        _detailRow("Operador", _controller.operatorStatus),
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
                              : VoiceEngine.speaking.value
                              ? "RESPONDIENDO"
                              : _continuousListening
                              ? "REARMANDO ESCUCHA"
                              : "TOCA PARA ACTIVAR",
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
                      VoiceEngine.speaking.value
                          ? "La escucha volverá al terminar"
                          : !_continuousListening
                          ? _controller.isListening
                                ? "Habla normal. Procesaré al detectar silencio."
                                : "Toca para activar el micrófono. No necesitas decir “OSvoz”."
                          : _wakeWordGate.conversationActive
                          ? "Conversación activa"
                          : "Di “OSvoz” para comenzar",
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
