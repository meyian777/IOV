class VoiceEchoGuardDecision {
  final bool blocked;
  final String reason;

  const VoiceEchoGuardDecision.accepted() : blocked = false, reason = "";

  const VoiceEchoGuardDecision.blocked(this.reason) : blocked = true;
}

class VoiceEchoGuard {
  VoiceEchoGuard({
    this.cooldown = const Duration(milliseconds: 1400),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration cooldown;
  final DateTime Function() _clock;
  DateTime? _blockedUntil;
  String _lastSpoken = "";

  void markSpeechStarted(String text) {
    _lastSpoken = _normalize(text);
    _blockedUntil = _clock().add(const Duration(days: 365));
  }

  void markSpeechEnded() {
    _blockedUntil = _clock().add(cooldown);
  }

  VoiceEchoGuardDecision evaluate(String transcript) {
    final now = _clock();
    final blockedUntil = _blockedUntil;
    if (blockedUntil != null && now.isBefore(blockedUntil)) {
      return const VoiceEchoGuardDecision.blocked("osvoz_speaking_or_cooldown");
    }

    final normalized = _normalize(transcript);
    if (normalized.isEmpty || _lastSpoken.isEmpty) {
      return const VoiceEchoGuardDecision.accepted();
    }
    if (_isEcho(normalized, _lastSpoken)) {
      return const VoiceEchoGuardDecision.blocked(
        "matched_last_osvoz_response",
      );
    }
    return const VoiceEchoGuardDecision.accepted();
  }

  static bool _isEcho(String transcript, String spoken) {
    if (spoken.contains(transcript) && transcript.length >= 18) return true;
    if (transcript.contains(spoken) && spoken.length >= 18) return true;

    final transcriptTokens = _tokens(transcript);
    final spokenTokens = _tokens(spoken);
    if (transcriptTokens.length < 4 || spokenTokens.length < 4) return false;
    final overlap = transcriptTokens.intersection(spokenTokens).length;
    final ratio = overlap / transcriptTokens.length;
    return ratio >= 0.72;
  }

  static Set<String> _tokens(String text) =>
      _normalize(text).split(" ").where((token) => token.length > 2).toSet();

  static String _normalize(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-záéíóúüñ0-9 ]', unicode: true), " ")
      .replaceAll(RegExp(r'\s+'), " ")
      .trim();
}
