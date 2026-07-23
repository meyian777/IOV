enum VoiceControlEvent { pause, resume, stop }

class VoiceControlDecision {
  const VoiceControlDecision._({this.event, required this.reason});

  const VoiceControlDecision.ignored(String reason) : this._(reason: reason);

  const VoiceControlDecision.accepted(VoiceControlEvent event, String reason)
    : this._(event: event, reason: reason);

  final VoiceControlEvent? event;
  final String reason;

  bool get accepted => event != null;
}

class VoiceControlRouter {
  static const double _bareCommandConfidence = 0.82;
  static const double _addressedCommandConfidence = 0.45;

  VoiceControlDecision evaluate(String transcript, {double? confidence}) {
    final normalized = _normalize(transcript);
    if (normalized.isEmpty) {
      return const VoiceControlDecision.ignored('empty_transcript');
    }

    final addressed = _addressedCommands[normalized];
    if (addressed != null) {
      if (_hasUsableConfidence(confidence) &&
          confidence! < _addressedCommandConfidence) {
        return const VoiceControlDecision.ignored('low_confidence');
      }
      return VoiceControlDecision.accepted(addressed, 'addressed_control');
    }

    final bare = _bareCommands[normalized];
    if (bare == null) {
      return const VoiceControlDecision.ignored('not_a_control_phrase');
    }
    if (!_hasUsableConfidence(confidence) ||
        confidence! < _bareCommandConfidence) {
      return const VoiceControlDecision.ignored(
        'bare_command_requires_high_confidence',
      );
    }
    return VoiceControlDecision.accepted(bare, 'high_confidence_control');
  }

  bool containsWakeWord(String transcript) {
    final normalized = _normalize(transcript);
    if (normalized.isEmpty) return false;
    return normalized.split(' ').contains('iov');
  }

  static bool _hasUsableConfidence(double? confidence) =>
      confidence != null && confidence >= 0 && confidence <= 1;

  static String _normalize(String value) {
    var normalized = value.toLowerCase().trim();
    const accents = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
    };
    for (final entry in accents.entries) {
      normalized = normalized.replaceAll(entry.key, entry.value);
    }
    normalized = normalized
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return normalized
        .replaceAll(RegExp(r'\b(i o v|yo vi|eye oh vee|iob|os voz)\b'), 'iov')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static const Map<String, VoiceControlEvent> _addressedCommands = {
    'iov pausa': VoiceControlEvent.pause,
    'ok pausa': VoiceControlEvent.pause,
    'pausa iov': VoiceControlEvent.pause,
    'iov pause': VoiceControlEvent.pause,
    'pause iov': VoiceControlEvent.pause,
    'ok pause': VoiceControlEvent.pause,
    'iov continua': VoiceControlEvent.resume,
    'ok continua': VoiceControlEvent.resume,
    'continua iov': VoiceControlEvent.resume,
    'iov continue': VoiceControlEvent.resume,
    'continue iov': VoiceControlEvent.resume,
    'iov resume': VoiceControlEvent.resume,
    'resume iov': VoiceControlEvent.resume,
    'ok continue': VoiceControlEvent.resume,
    'iov detente': VoiceControlEvent.stop,
    'ok detente': VoiceControlEvent.stop,
    'detente iov': VoiceControlEvent.stop,
    'iov stop': VoiceControlEvent.stop,
    'stop iov': VoiceControlEvent.stop,
    'ok stop': VoiceControlEvent.stop,
  };

  static const Map<String, VoiceControlEvent> _bareCommands = {
    'pausa': VoiceControlEvent.pause,
    'pause': VoiceControlEvent.pause,
    'continua': VoiceControlEvent.resume,
    'continue': VoiceControlEvent.resume,
    'resume': VoiceControlEvent.resume,
    'detente': VoiceControlEvent.stop,
    'stop': VoiceControlEvent.stop,
    'stop speaking': VoiceControlEvent.stop,
  };
}
