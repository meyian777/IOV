class VoiceNoiseDecision {
  final bool accepted;
  final String reason;
  final String cleanedTranscript;

  const VoiceNoiseDecision({
    required this.accepted,
    required this.reason,
    required this.cleanedTranscript,
  });
}

class VoiceNoiseGate {
  VoiceNoiseGate({
    this.duplicateWindow = const Duration(seconds: 8),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration duplicateWindow;
  final DateTime Function() _clock;
  String? _lastAcceptedTranscript;
  DateTime? _lastAcceptedAt;

  VoiceNoiseDecision evaluate(String transcript) {
    final cleaned = _clean(transcript);
    if (cleaned.isEmpty) {
      return const VoiceNoiseDecision(
        accepted: false,
        reason: "empty_transcript",
        cleanedTranscript: "",
      );
    }

    if (cleaned.length < 3) {
      return VoiceNoiseDecision(
        accepted: false,
        reason: "too_short",
        cleanedTranscript: cleaned,
      );
    }

    if (_looksLikeWhisperNoise(cleaned)) {
      return VoiceNoiseDecision(
        accepted: false,
        reason: "likely_background_or_hallucination",
        cleanedTranscript: cleaned,
      );
    }

    final now = _clock();
    final lastTranscript = _lastAcceptedTranscript;
    final lastAt = _lastAcceptedAt;
    if (lastTranscript != null &&
        lastAt != null &&
        cleaned == lastTranscript &&
        now.difference(lastAt) < duplicateWindow) {
      return VoiceNoiseDecision(
        accepted: false,
        reason: "duplicate_transcript",
        cleanedTranscript: cleaned,
      );
    }

    _lastAcceptedTranscript = cleaned;
    _lastAcceptedAt = now;
    return VoiceNoiseDecision(
      accepted: true,
      reason: "accepted",
      cleanedTranscript: cleaned,
    );
  }

  String _clean(String transcript) => transcript
      .trim()
      .replaceAll(RegExp(r'\s+'), " ")
      .replaceAll(RegExp(r'^[\s,.:;!?-]+|[\s,.:;!?-]+$'), "");

  bool _looksLikeWhisperNoise(String transcript) {
    final text = transcript.toLowerCase();
    const noisePhrases = [
      "subtítulos realizados por la comunidad",
      "subtitulos realizados por la comunidad",
      "gracias por ver",
      "thank you for watching",
      "thanks for watching",
      "suscríbete",
      "suscribete",
      "subscribe",
      "amara.org",
      "記者",
      "請問",
    ];
    if (noisePhrases.any(text.contains)) return true;
    if (RegExp(r'[\u3040-\u30ff\u3400-\u9fff]').hasMatch(transcript)) {
      return true;
    }

    final letters = text.replaceAll(RegExp(r'[^a-záéíóúñü]'), "");
    if (letters.isEmpty) return true;
    final uniqueLetters = letters.split("").toSet().length;
    return letters.length >= 8 && uniqueLetters <= 2;
  }
}
