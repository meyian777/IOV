import 'package:flutter_tts/flutter_tts.dart';

class VoiceEngine {
  static final FlutterTts _tts = FlutterTts();
  static bool _initialized = false;
  static String _activeLocale = "es-ES";

  static Future<void> initialize() async {
    if (_initialized) return;

    await _tts.awaitSpeakCompletion(true);
    await _tts.setVolume(1.0);
    await _tts.setSpeechRate(0.52);
    await _tts.setPitch(1.0);
    _initialized = true;
    await setLanguage(_activeLocale);
  }

  static Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await initialize();
    await _tts.stop();
    await _tts.speak(text);
  }

  static Future<void> setLanguage(String locale) async {
    _activeLocale = locale;
    if (!_initialized) {
      await initialize();
      return;
    }

    await _tts.setLanguage(locale);
    await _selectBestVoice(locale);
  }

  static Future<void> _selectBestVoice(String locale) async {
    final dynamic rawVoices = await _tts.getVoices;
    if (rawVoices is! List) return;

    final language = locale.toLowerCase().split("-").first;
    final candidates = rawVoices
        .whereType<Map>()
        .map(
          (voice) => voice.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          ),
        )
        .where((voice) {
          final voiceLocale = (voice["locale"] ?? "").toLowerCase();
          return voiceLocale == locale.toLowerCase() ||
              voiceLocale.startsWith("$language-") ||
              voiceLocale.startsWith("${language}_");
        })
        .toList();

    if (candidates.isEmpty) return;
    candidates.sort((a, b) => _voiceScore(b).compareTo(_voiceScore(a)));
    final selected = candidates.first;
    final identifier = selected["identifier"];

    if (identifier != null && identifier.isNotEmpty) {
      await _tts.setVoice({"identifier": identifier});
      return;
    }

    final name = selected["name"];
    final voiceLocale = selected["locale"];
    if (name != null && voiceLocale != null) {
      await _tts.setVoice({"name": name, "locale": voiceLocale});
    }
  }

  static int _voiceScore(Map<String, String> voice) {
    final description = voice.values.join(" ").toLowerCase();
    var score = 0;

    for (final quality in ["premium", "enhanced", "neural", "natural"]) {
      if (description.contains(quality)) score += 20;
    }
    for (final lowQuality in ["compact", "espeak"]) {
      if (description.contains(lowQuality)) score -= 20;
    }

    return score;
  }
}
