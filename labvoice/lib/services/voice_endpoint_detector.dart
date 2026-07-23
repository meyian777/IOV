import 'dart:math' as math;

enum VoiceEndpointDecision {
  none,
  initialSilence,
  speechEnded,
  maximumDuration,
}

class VoiceEndpointDetector {
  VoiceEndpointDetector({
    this.calibrationWindow = const Duration(milliseconds: 360),
    this.initialSilenceTimeout = const Duration(seconds: 3),
    this.silenceAfterSpeech = const Duration(milliseconds: 600),
    this.maximumCaptureWindow = const Duration(seconds: 8),
    this.minimumCaptureWindow = const Duration(milliseconds: 650),
    this.signalMarginDb = 8,
    this.minimumVoiceThresholdDb = -38,
    this.maximumVoiceThresholdDb = -12,
  });

  final Duration calibrationWindow;
  final Duration initialSilenceTimeout;
  final Duration silenceAfterSpeech;
  final Duration maximumCaptureWindow;
  final Duration minimumCaptureWindow;
  final double signalMarginDb;
  final double minimumVoiceThresholdDb;
  final double maximumVoiceThresholdDb;

  DateTime? _startedAt;
  DateTime? _lastVoiceAt;
  double? _noiseFloorDb;
  bool _speechDetected = false;
  int _consecutiveVoiceSamples = 0;

  bool get speechDetected => _speechDetected;
  double get noiseFloorDb => _noiseFloorDb ?? -60;
  double get voiceThresholdDb => math.min(
    maximumVoiceThresholdDb,
    math.max(minimumVoiceThresholdDb, noiseFloorDb + signalMarginDb),
  );

  void start(DateTime now) {
    _startedAt = now;
    _lastVoiceAt = null;
    _noiseFloorDb = null;
    _speechDetected = false;
    _consecutiveVoiceSamples = 0;
  }

  void reset() {
    _startedAt = null;
    _lastVoiceAt = null;
    _noiseFloorDb = null;
    _speechDetected = false;
    _consecutiveVoiceSamples = 0;
  }

  VoiceEndpointDecision observe(double currentDb, DateTime now) {
    final startedAt = _startedAt;
    if (startedAt == null) return VoiceEndpointDecision.none;
    final elapsed = now.difference(startedAt);

    if (elapsed <= calibrationWindow) {
      _learnNoiseFloor(currentDb, weight: 0.28);
      return evaluate(now);
    }

    if (currentDb >= voiceThresholdDb) {
      _consecutiveVoiceSamples += 1;
      if (_consecutiveVoiceSamples >= 2) {
        _speechDetected = true;
        _lastVoiceAt = now;
      }
    } else {
      _consecutiveVoiceSamples = 0;
      if (!_speechDetected) {
        _learnNoiseFloor(currentDb, weight: 0.08);
      }
    }
    return evaluate(now);
  }

  VoiceEndpointDecision evaluate(DateTime now) {
    final startedAt = _startedAt;
    if (startedAt == null) return VoiceEndpointDecision.none;
    final elapsed = now.difference(startedAt);
    if (elapsed >= maximumCaptureWindow) {
      return VoiceEndpointDecision.maximumDuration;
    }
    if (!_speechDetected && elapsed >= initialSilenceTimeout) {
      return VoiceEndpointDecision.initialSilence;
    }
    final lastVoiceAt = _lastVoiceAt;
    if (_speechDetected &&
        lastVoiceAt != null &&
        elapsed >= minimumCaptureWindow &&
        now.difference(lastVoiceAt) >= silenceAfterSpeech) {
      return VoiceEndpointDecision.speechEnded;
    }
    return VoiceEndpointDecision.none;
  }

  void _learnNoiseFloor(double sample, {required double weight}) {
    final previous = _noiseFloorDb;
    _noiseFloorDb = previous == null
        ? sample
        : (previous * (1 - weight)) + (sample * weight);
  }
}
