class WakeWordDecision {
  final bool accepted;
  final bool activated;
  final String command;

  const WakeWordDecision({
    required this.accepted,
    required this.activated,
    required this.command,
  });
}

class WakeWordGate {
  WakeWordGate({
    this.sessionDuration = const Duration(seconds: 35),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration sessionDuration;
  final DateTime Function() _clock;
  DateTime? _activeUntil;

  bool get conversationActive {
    final activeUntil = _activeUntil;
    return activeUntil != null && _clock().isBefore(activeUntil);
  }

  WakeWordDecision evaluate(String transcript) {
    final normalized = transcript.trim();
    if (normalized.isEmpty) {
      return const WakeWordDecision(
        accepted: false,
        activated: false,
        command: "",
      );
    }

    final wakeMatch = RegExp(
      r'\b(?:lab\s*voice|labvoice|la\s*voz)\b',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (wakeMatch != null) {
      _extendSession();
      final before = normalized.substring(0, wakeMatch.start).trim();
      final after = normalized.substring(wakeMatch.end).trim();
      final command = after.replaceFirst(RegExp(r'^[\s,.:;!?-]+'), "").trim();
      return WakeWordDecision(
        accepted: command.isNotEmpty,
        activated: true,
        command: command.isEmpty ? before : command,
      );
    }

    if (conversationActive) {
      _extendSession();
      return WakeWordDecision(
        accepted: true,
        activated: false,
        command: normalized,
      );
    }

    return const WakeWordDecision(
      accepted: false,
      activated: false,
      command: "",
    );
  }

  void closeSession() {
    _activeUntil = null;
  }

  void _extendSession() {
    _activeUntil = _clock().add(sessionDuration);
  }
}
