import 'package:flutter_tts/flutter_tts.dart';

class VoiceEngine {
  static final FlutterTts _tts = FlutterTts();

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;

    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.75);

    await _tts.setVolume(1.0);

    await _tts.setPitch(1.10);

    _initialized = true;
  }

  static Future<void> speak(String text) async {
    await initialize();

    await _tts.stop();

    await _tts.speak(text);
  }

  static Future<void> setSpanish() async {
    await initialize();

    await _tts.setLanguage("es-ES");
  }

  static Future<void> setEnglish() async {
    await initialize();

    await _tts.setLanguage("en-US");
  }
}
