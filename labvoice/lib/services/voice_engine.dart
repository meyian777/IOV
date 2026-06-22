import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'labvoice_api.dart';
import 'language_manager.dart';

class VoiceEngine {
  static final FlutterTts _tts = FlutterTts();
  static final AudioPlayer _player = AudioPlayer();
  static bool _initialized = false;
  static String _activeLocale = "es-ES";
  static int _speechGeneration = 0;
  static const Map<String, List<String>> _preferredVoices = {
    "es": ["Mónica", "Paulina", "Flo", "Sandy", "Reed"],
    "en": ["Samantha", "Ava", "Flo", "Sandy", "Reed"],
  };
  static const List<String> _effectVoices = [
    "albert",
    "bad news",
    "bahh",
    "bells",
    "boing",
    "bubbles",
    "cellos",
    "good news",
    "jester",
    "organ",
    "superstar",
    "trinoids",
    "whisper",
    "wobble",
    "zarvox",
  ];

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
    final generation = ++_speechGeneration;
    await _player.stop();
    await _tts.stop();

    try {
      final audio = await LabVoiceApi.speech(
        text,
        language: LanguageManager.effectiveLanguage,
      );
      if (generation != _speechGeneration) return;
      await _player.play(BytesSource(audio));
    } catch (_) {
      // Never fall back to the robotic system voice. Silence is safer and
      // more consistent with the LabVoice experience.
      return;
    }
  }

  static Future<void> stop() async {
    _speechGeneration++;
    await _player.stop();
    await _tts.stop();
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
          final name = (voice["name"] ?? "").toLowerCase();
          final isEffect = _effectVoices.any(
            (effect) => name == effect || name.startsWith("$effect "),
          );
          return !isEffect &&
              (voiceLocale == locale.toLowerCase() ||
                  voiceLocale.startsWith("$language-") ||
                  voiceLocale.startsWith("${language}_"));
        })
        .toList();

    if (candidates.isEmpty) return;
    candidates.sort(
      (a, b) => _voiceScore(b, language).compareTo(_voiceScore(a, language)),
    );
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

  static int _voiceScore(Map<String, String> voice, String language) {
    final description = voice.values.join(" ").toLowerCase();
    final name = (voice["name"] ?? "").toLowerCase();
    var score = 0;

    final preferences = _preferredVoices[language] ?? const [];
    for (var index = 0; index < preferences.length; index++) {
      if (name.startsWith(preferences[index].toLowerCase())) {
        score += 100 - index;
        break;
      }
    }
    for (final quality in ["premium", "enhanced", "neural", "natural"]) {
      if (description.contains(quality)) score += 20;
    }
    for (final lowQuality in ["compact", "espeak"]) {
      if (description.contains(lowQuality)) score -= 20;
    }

    return score;
  }
}
