import 'package:flutter/services.dart';

class NativeControlSpeechEvent {
  const NativeControlSpeechEvent({
    required this.type,
    this.transcript = '',
    this.confidence,
    this.isFinal = false,
    this.status,
    this.message,
  });

  factory NativeControlSpeechEvent.fromMap(Map<dynamic, dynamic> map) {
    final rawConfidence = map['confidence'];
    return NativeControlSpeechEvent(
      type: map['type'] as String? ?? 'unknown',
      transcript: map['transcript'] as String? ?? '',
      confidence: rawConfidence is num ? rawConfidence.toDouble() : null,
      isFinal: map['final'] as bool? ?? false,
      status: map['status'] as String?,
      message: map['message'] as String?,
    );
  }

  final String type;
  final String transcript;
  final double? confidence;
  final bool isFinal;
  final String? status;
  final String? message;
}

class NativeControlSpeech {
  static const MethodChannel _methods = MethodChannel('osvoz/control_speech');
  static const EventChannel _events = EventChannel(
    'osvoz/control_speech/events',
  );

  Stream<NativeControlSpeechEvent>? _eventStream;

  Stream<NativeControlSpeechEvent> get events =>
      _eventStream ??= _events.receiveBroadcastStream().map((dynamic value) {
        if (value is Map<dynamic, dynamic>) {
          return NativeControlSpeechEvent.fromMap(value);
        }
        return const NativeControlSpeechEvent(type: 'unknown');
      });

  Future<bool> start({required String locale}) async {
    return await _methods.invokeMethod<bool>('start', {'locale': locale}) ??
        false;
  }

  Future<void> stop() async {
    await _methods.invokeMethod<bool>('stop');
  }
}
