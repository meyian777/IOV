import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../controllers/labvoice_controller.dart';
import '../services/iov_interaction_state_machine.dart';
import '../services/labvoice_api.dart';
import '../services/language_manager.dart';
import '../services/local_whisper_recorder.dart';
import '../services/native_control_speech.dart';
import '../services/voice_engine.dart';
import '../services/voice_control_router.dart';
import '../services/voice_echo_guard.dart';
import '../services/voice_endpoint_detector.dart';
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
  final NativeControlSpeech _controlSpeech = NativeControlSpeech();
  final WakeWordGate _wakeWordGate = WakeWordGate();
  final VoiceEchoGuard _echoGuard = VoiceEchoGuard();
  final VoiceEndpointDetector _endpointDetector = VoiceEndpointDetector();
  final VoiceNoiseGate _voiceNoiseGate = VoiceNoiseGate();
  final VoiceControlRouter _controlRouter = VoiceControlRouter();
  final IOVInteractionStateMachine _interactionState =
      IOVInteractionStateMachine();
  late final AnimationController _pulse;
  final bool _continuousListening = false;
  final bool _preferFastNativeSpeech = false;
  bool _startingListener = false;
  bool _usingNativeSpeech = false;
  bool _forceNativeSpeechOnce = false;
  bool _autoStoppingWhisper = false;
  bool _manualWhisperCapture = false;
  bool _controlSpeechStarting = false;
  bool _controlSpeechListening = false;
  bool _handlingControlEvent = false;
  Timer? _rearmTimer;
  Timer? _captureMonitorTimer;
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  StreamSubscription<NativeControlSpeechEvent>? _controlSpeechSubscription;
  Timer? _bargeInRestoreTimer;
  DateTime? _captureStartedAt;
  String _nativeTranscript = "";
  String _voiceDebugStatus = "Esperando prueba manual.";
  String _voiceDebugLanguage = "auto";
  String _voiceDebugAudio = "Sin audio capturado.";
  String _voiceDebugLatency = "Sin transcripción.";
  String _voiceDebugError = "Sin errores.";
  String _backendInterpretation = "Sin interpretación.";
  String _codeRoute = "Sin ruta de código.";
  double _liveAmplitude = 0;

  static const Duration _amplitudeInterval = Duration(milliseconds: 120);

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.92,
      upperBound: 1.06,
    );
    _controller.addListener(_refresh);
    VoiceEngine.speaking.addListener(_voiceStateChanged);
    _controlSpeechSubscription = _controlSpeech.events.listen(
      _controlSpeechEvent,
      onError: (_) => _controlSpeechEnded(),
    );
    unawaited(_initializeContinuousVoice());
  }

  Future<void> _initializeContinuousVoice() async {
    await _controller.initialize();
    _scheduleRearm();
  }

  void _refresh() {
    _syncVoiceAnimation();
    if (mounted) setState(() {});
  }

  void _syncVoiceAnimation() {
    final active = _controller.isListening || VoiceEngine.speaking.value;
    if (active && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!active && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    VoiceEngine.speaking.removeListener(_voiceStateChanged);
    _controller.dispose();
    _pulse.dispose();
    _rearmTimer?.cancel();
    _cancelCaptureMonitor();
    _bargeInRestoreTimer?.cancel();
    unawaited(_controlSpeechSubscription?.cancel());
    unawaited(_whisperRecorder.dispose());
    unawaited(_nativeSpeech.cancel());
    unawaited(_controlSpeech.stop());
    super.dispose();
  }

  void _voiceStateChanged() {
    _syncVoiceAnimation();
    if (mounted) setState(() {});
    if (VoiceEngine.speaking.value) {
      if (_interactionState.state != IOVInteractionState.speaking) {
        _interactionState.dispatch(IOVInteractionEvent.speak);
      }
      _rearmTimer?.cancel();
      _cancelCaptureMonitor();
      unawaited(_whisperRecorder.stop());
      unawaited(_nativeSpeech.cancel());
      _usingNativeSpeech = false;
      _controller.setListening(false);
      _echoGuard.markSpeechStarted(_controller.response);
      unawaited(_startControlRouter());
      return;
    }
    if (VoiceEngine.paused.value ||
        _interactionState.state == IOVInteractionState.paused) {
      unawaited(_startControlRouter());
      return;
    }
    _interactionState.dispatch(IOVInteractionEvent.finish);
    unawaited(_stopControlRouter());
    _echoGuard.markSpeechEnded();
    _scheduleRearm();
  }

  Future<void> _startControlRouter() async {
    final state = _interactionState.state;
    if (state != IOVInteractionState.speaking &&
        state != IOVInteractionState.paused) {
      return;
    }
    if (_controlSpeechStarting || _controlSpeechListening) return;
    _controlSpeechStarting = true;
    try {
      _controlSpeechListening = await _controlSpeech.start(
        locale: LanguageManager.activeVoiceLocale.replaceAll('-', '_'),
      );
    } catch (_) {
      _controlSpeechListening = false;
      _scheduleControlRouterRestart();
    } finally {
      _controlSpeechStarting = false;
    }
  }

  Future<void> _stopControlRouter() async {
    _controlSpeechListening = false;
    _bargeInRestoreTimer?.cancel();
    await VoiceEngine.restoreVolume();
    await _controlSpeech.stop();
  }

  void _controlSpeechEvent(NativeControlSpeechEvent event) {
    if (event.type == 'status') {
      _setControlDebug('Control manos libres activo.');
      return;
    }
    if (event.type == 'error') {
      _setControlDebug(
        'Canal de control no disponible: ${event.message ?? "error desconocido"}',
      );
      _controlSpeechEnded();
      return;
    }
    if (event.type != 'transcript') return;
    final transcript = event.transcript.trim();
    _setControlDebug('Control oyó: $transcript');
    if (_controlRouter.containsWakeWord(transcript)) {
      unawaited(VoiceEngine.duck());
      _bargeInRestoreTimer?.cancel();
      _bargeInRestoreTimer = Timer(const Duration(milliseconds: 950), () {
        unawaited(VoiceEngine.restoreVolume());
      });
    }
    if (_handlingControlEvent) return;
    final decision = _controlRouter.evaluate(
      transcript,
      confidence: event.confidence,
    );
    if (decision.accepted) {
      _bargeInRestoreTimer?.cancel();
      unawaited(_applyControlEvent(decision.event!, transcript));
      return;
    }
    if (event.isFinal) {
      unawaited(VoiceEngine.restoreVolume());
      _controlSpeechEnded();
    }
  }

  void _setControlDebug(String message) {
    _voiceDebugStatus = message;
    if (mounted) setState(() {});
  }

  void _controlSpeechEnded() {
    _controlSpeechListening = false;
    unawaited(VoiceEngine.restoreVolume());
    _scheduleControlRouterRestart();
  }

  void _scheduleControlRouterRestart() {
    if (!mounted ||
        (_interactionState.state != IOVInteractionState.speaking &&
            _interactionState.state != IOVInteractionState.paused)) {
      return;
    }
    Future<void>.delayed(const Duration(milliseconds: 220), () {
      if (mounted) unawaited(_startControlRouter());
    });
  }

  Future<void> _applyControlEvent(
    VoiceControlEvent event,
    String transcript,
  ) async {
    if (_handlingControlEvent) return;
    _handlingControlEvent = true;
    await _stopControlRouter();
    switch (event) {
      case VoiceControlEvent.pause:
        if (_interactionState.dispatch(IOVInteractionEvent.pause)) {
          await VoiceEngine.pause();
          _controller.narrationControlFeedback(
            heard: transcript,
            message: LanguageManager.text("En pausa.", "Paused."),
            control: "pause",
          );
        }
      case VoiceControlEvent.resume:
        if (_interactionState.dispatch(IOVInteractionEvent.resume)) {
          _controller.narrationControlFeedback(
            heard: transcript,
            message: LanguageManager.text("Continuando.", "Continuing."),
            control: "resume",
          );
          await VoiceEngine.resume();
        }
      case VoiceControlEvent.stop:
        _interactionState.dispatch(IOVInteractionEvent.stop);
        await VoiceEngine.stop();
        _controller.narrationControlFeedback(
          heard: transcript,
          message: LanguageManager.text("Me detuve.", "Stopped."),
          control: "stop",
        );
    }
    _handlingControlEvent = false;
    if (mounted &&
        (_interactionState.state == IOVInteractionState.speaking ||
            _interactionState.state == IOVInteractionState.paused)) {
      unawaited(_startControlRouter());
    }
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
    _interactionState.dispatch(IOVInteractionEvent.listen);
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
    _interactionState.dispatch(IOVInteractionEvent.listen);
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
    _interactionState.dispatch(IOVInteractionEvent.process);
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
    _endpointDetector.start(now);
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
    _liveAmplitude = ((current + 60) / 48).clamp(0.0, 1.0);
    final decision = _endpointDetector.observe(current, now);
    _setVoiceDebug(
      audio:
          "Nivel ${current.toStringAsFixed(1)} dB · ruido ${_endpointDetector.noiseFloorDb.toStringAsFixed(1)} dB · umbral ${_endpointDetector.voiceThresholdDb.toStringAsFixed(1)} dB",
    );
    _applyEndpointDecision(decision);
  }

  void _evaluateAutoStop([DateTime? observedAt]) {
    if (!_controller.isListening ||
        _usingNativeSpeech ||
        _startingListener ||
        _autoStoppingWhisper) {
      return;
    }
    final now = observedAt ?? DateTime.now();
    _applyEndpointDecision(_endpointDetector.evaluate(now));
  }

  void _applyEndpointDecision(VoiceEndpointDecision decision) {
    final reason = switch (decision) {
      VoiceEndpointDecision.initialSilence => "No detecté voz inicial.",
      VoiceEndpointDecision.speechEnded => "Silencio detectado. Procesando.",
      VoiceEndpointDecision.maximumDuration => "Límite máximo alcanzado.",
      VoiceEndpointDecision.none => null,
    };
    if (reason != null) unawaited(_autoStopWhisper(reason));
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
    _endpointDetector.reset();
    _liveAmplitude = 0;
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

  String _ui(String spanish, String english) =>
      LanguageManager.text(spanish, english);

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
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) => Transform.scale(
            scale: listening ? _pulse.value : 1,
            child: child,
          ),
          child: AnimatedContainer(
            key: const Key("voice-core"),
            duration: const Duration(milliseconds: 350),
            width: 176,
            height: 176,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: listening
                    ? [const Color(0xFF1BD8FF), const Color(0xFF0868FF)]
                    : [const Color(0xFF102D45), const Color(0xFF07121F)],
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
              size: 62,
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
      color: const Color(0xFF0B1722).withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFF1B3C55)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _ui("RESPUESTA", "RESPONSE"),
          style: theme.textTheme.labelMedium?.copyWith(
            color: const Color(0xFF29C8FF),
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
        _ui("Detalles del sistema", "System details"),
        style: theme.textTheme.labelLarge?.copyWith(color: Colors.white54),
      ),
      children: [
        _detailRow(_ui("Idioma", "Language"), _controller.activeLanguageName),
        _detailRow(_ui("Voz", "Voice"), _voiceDebugStatus),
        _detailRow("Whisper", "$_voiceDebugLanguage · $_voiceDebugLatency"),
        _detailRow("Audio", _voiceDebugAudio),
        _detailRow(
          _ui("Latencia", "Latency"),
          VoiceLatencyMetrics.compactSummary(),
        ),
        _detailRow(_ui("Error de voz", "Voice error"), _voiceDebugError),
        _detailRow("Backend", _backendInterpretation),
        _detailRow(_ui("Código", "Code"), _codeRoute),
        _detailRow(_ui("Operador", "Operator"), _controller.operatorStatus),
        _detailRow(_ui("Intención", "Intent"), _controller.detectedIntent),
        _detailRow(_ui("Acción", "Action"), _controller.technicalAction),
        _detailRow(_ui("Seguridad", "Security"), _controller.securityLevel),
      ],
    ),
  );

  int get _primaryLatencyMs {
    final metrics = VoiceLatencyMetrics.latest;
    return metrics["total_ms"] ??
        metrics["transcription_ms"] ??
        metrics["backend_intent_ms"] ??
        0;
  }

  String get _interactionLabel {
    if (_controller.isListening) return "LISTENING";
    if (VoiceEngine.paused.value) return "PAUSED";
    if (VoiceEngine.speaking.value) return "RESPONDING";
    if (_controller.detectedIntent == "voice_processing") return "PROCESSING";
    return "READY";
  }

  Widget _panel({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(18),
  }) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: const Color(0xFF08131D).withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFF18364B)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x44000000),
          blurRadius: 20,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: child,
  );

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      color: Color(0xFF7894A8),
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
    ),
  );

  Widget _statusPanel() => _panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(_ui("ESTADO DEL SISTEMA", "SYSTEM STATUS")),
        const SizedBox(height: 14),
        _statusRow(
          Icons.memory_rounded,
          _ui("Inteligencia local", "Local intelligence"),
          _ui("Activa", "Running"),
          const Color(0xFF4FE39B),
        ),
        _statusRow(
          Icons.language_rounded,
          _ui("Idioma", "Language"),
          _controller.activeLanguageName,
          const Color(0xFF29C8FF),
        ),
        _statusRow(
          Icons.shield_outlined,
          _ui("Seguridad", "Security"),
          _controller.securityLevel,
          const Color(0xFF4FE39B),
        ),
        _statusRow(
          Icons.account_tree_outlined,
          _ui("Intención", "Intent"),
          _controller.detectedIntent,
          const Color(0xFF29C8FF),
        ),
      ],
    ),
  );

  Widget _statusRow(IconData icon, String label, String value, Color color) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(color: Color(0xFF9BB0BE), fontSize: 12),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(color: color, fontSize: 11),
              ),
            ),
          ],
        ),
      );

  Widget _voiceStage(ThemeData theme, ColorScheme colors) => Column(
    children: [
      Text(
        _ui("MOTOR DE VOZ", "VOICE RUNTIME"),
        style: const TextStyle(
          color: Color(0xFF6F899B),
          fontSize: 11,
          letterSpacing: 2.4,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 18),
      AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) => CustomPaint(
          painter: _IOVWavePainter(
            phase: _pulse.value,
            active: _controller.isListening || VoiceEngine.speaking.value,
            signal: _controller.isListening
                ? _liveAmplitude
                : VoiceEngine.speaking.value
                ? 0.72
                : 0.08,
          ),
          child: Center(child: _voiceCore(colors)),
        ),
      ),
      const SizedBox(height: 22),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF0E2636),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFF1D638A)),
        ),
        child: Text(
          _interactionLabel,
          style: const TextStyle(
            color: Color(0xFF45D6FF),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
      ),
      const SizedBox(height: 18),
      _heardText(theme),
    ],
  );

  Widget _codePanel() => _panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionLabel(_ui("CÓDIGO ACTIVO", "ACTIVE CODE")),
            const Spacer(),
            const Icon(Icons.circle, color: Color(0xFF4FE39B), size: 8),
            const SizedBox(width: 6),
            const Text(
              "CONNECTED",
              style: TextStyle(
                color: Color(0xFF4FE39B),
                fontSize: 9,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: _controller.hasActiveCodePreview
              ? Column(
                  key: ValueKey(_controller.activeCodePath),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.description_outlined,
                          color: Color(0xFF29C8FF),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _controller.activeCodePath,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFD7E7F1),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          _controller.activeCodeLanguage.toUpperCase(),
                          style: const TextStyle(
                            color: Color(0xFF4FE39B),
                            fontSize: 9,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 430),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF050C12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF142B3B)),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          _controller.activeCodePreview,
                          style: const TextStyle(
                            color: Color(0xFF9EDFFF),
                            fontFamily: "monospace",
                            fontSize: 11,
                            height: 1.55,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : Container(
                  key: const ValueKey("code-waiting"),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 34,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF061019),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.code_rounded,
                        color: Color(0xFF24516D),
                        size: 34,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _ui(
                          "Pide explicar el archivo activo",
                          "Ask to explain the active file",
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF6F899B),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    ),
  );

  Widget _metricCard(IconData icon, String label, String value, Color color) =>
      Expanded(
        child: Container(
          constraints: const BoxConstraints(minHeight: 82),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1823),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF17364B)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Color(0xFF748B9A),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _bottomMetrics() => Row(
    children: [
      _metricCard(
        Icons.mic_rounded,
        _ui("MICRÓFONO", "MICROPHONE"),
        _controller.isListening
            ? _ui("Activo", "Active")
            : _ui("Listo", "Ready"),
        const Color(0xFF4FE39B),
      ),
      const SizedBox(width: 12),
      _metricCard(
        Icons.shield_outlined,
        _ui("SEGURIDAD", "SECURITY"),
        _controller.securityLevel,
        const Color(0xFF4FE39B),
      ),
      const SizedBox(width: 12),
      _metricCard(
        Icons.speed_rounded,
        _ui("LATENCIA", "LATENCY"),
        _primaryLatencyMs == 0
            ? _ui("Esperando datos", "Awaiting data")
            : "$_primaryLatencyMs ms",
        const Color(0xFF29C8FF),
      ),
      const SizedBox(width: 12),
      _metricCard(
        Icons.code_rounded,
        "VS CODE",
        _codeRoute == "Sin ruta de código."
            ? _ui("En espera", "Standby")
            : _ui("Conectado", "Connected"),
        const Color(0xFF29C8FF),
      ),
    ],
  );

  Widget _voiceControls() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      _controlButton(
        Icons.mic_rounded,
        _controller.isListening
            ? _ui("Detener captura", "Stop capture")
            : _ui("Hablar", "Speak"),
        () => _listen(manual: true),
        primary: true,
      ),
      const SizedBox(width: 12),
      _controlButton(
        VoiceEngine.paused.value
            ? Icons.play_arrow_rounded
            : Icons.pause_rounded,
        VoiceEngine.paused.value
            ? _ui("Continuar", "Resume")
            : _ui("Pausa", "Pause"),
        () {
          final event = VoiceEngine.paused.value
              ? VoiceControlEvent.resume
              : VoiceControlEvent.pause;
          unawaited(_applyControlEvent(event, "UI control"));
        },
      ),
      const SizedBox(width: 12),
      _controlButton(
        Icons.stop_rounded,
        _ui("Detener", "Stop"),
        () =>
            unawaited(_applyControlEvent(VoiceControlEvent.stop, "UI control")),
      ),
    ],
  );

  Widget _controlButton(
    IconData icon,
    String label,
    VoidCallback onPressed, {
    bool primary = false,
  }) => FilledButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    label: Text(label),
    style: FilledButton.styleFrom(
      backgroundColor: primary
          ? const Color(0xFF087DC1)
          : const Color(0xFF102637),
      foregroundColor: primary ? Colors.white : const Color(0xFF9EDFFF),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF1C5574)),
      ),
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
      backgroundColor: const Color(0xFF030A10),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.2),
            radius: 1.1,
            colors: [Color(0xFF0B2535), Color(0xFF030A10)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 1050;
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 26),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1480),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: _statusColor(colors),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: _statusColor(
                                      colors,
                                    ).withValues(alpha: 0.55),
                                    blurRadius: 12,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 9),
                            Text(
                              _interactionLabel,
                              style: const TextStyle(
                                color: Color(0xFF8DA5B5),
                                fontSize: 11,
                                letterSpacing: 1.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              _controller.activeLanguageName,
                              style: const TextStyle(
                                color: Color(0xFF607887),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (compact) ...[
                          _voiceStage(theme, colors),
                          const SizedBox(height: 18),
                          _responseCard(theme),
                          const SizedBox(height: 18),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _statusPanel()),
                              const SizedBox(width: 14),
                              Expanded(child: _codePanel()),
                            ],
                          ),
                        ] else
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 235, child: _statusPanel()),
                              const SizedBox(width: 24),
                              Expanded(
                                flex: 4,
                                child: Column(
                                  children: [
                                    _voiceStage(theme, colors),
                                    const SizedBox(height: 18),
                                    _responseCard(theme),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 24),
                              SizedBox(width: 430, child: _codePanel()),
                            ],
                          ),
                        const SizedBox(height: 18),
                        _voiceControls(),
                        const SizedBox(height: 16),
                        if (!compact) _bottomMetrics(),
                        const SizedBox(height: 8),
                        _details(theme),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _IOVWavePainter extends CustomPainter {
  const _IOVWavePainter({
    required this.phase,
    required this.active,
    required this.signal,
  });

  final double phase;
  final bool active;
  final double signal;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final glow = Paint()
      ..color = Color.fromRGBO(21, 190, 255, active ? 0.18 : 0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24);
    canvas.drawCircle(center, 105, glow);

    for (var line = 0; line < 3; line++) {
      final path = Path();
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = line == 0 ? 2 : 1
        ..color = Color.fromRGBO(
          37,
          205,
          255,
          active ? 0.72 - line * 0.16 : 0.24,
        );
      for (double x = 0; x <= size.width; x += 4) {
        final distance = (x - center.dx).abs() / center.dx;
        final envelope = (1 - distance).clamp(0.0, 1.0);
        final baseAmplitude = 7 + (signal.clamp(0.0, 1.0) * 44);
        final amplitude = baseAmplitude * envelope * (1 - line * 0.2);
        final y =
            center.dy + math.sin((x * 0.045) + (phase * 8) + line) * amplitude;
        if (x == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _IOVWavePainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.active != active ||
      oldDelegate.signal != signal;
}
