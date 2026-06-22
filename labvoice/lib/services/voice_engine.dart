import 'dart:io';

import 'package:audioplayers/audioplayers.dart';

import 'labvoice_api.dart';
import 'language_manager.dart';

class VoiceEngine {
  static final AudioPlayer _player = AudioPlayer();
  static int _speechGeneration = 0;
  static File? _activeAudioFile;

  static Future<String?> speak(String text) async {
    if (text.trim().isEmpty) return null;

    final generation = ++_speechGeneration;
    await _player.stop();
    await _deleteActiveAudioFile();

    try {
      final audio = await LabVoiceApi.speech(
        text,
        language: LanguageManager.effectiveLanguage,
      );
      if (generation != _speechGeneration) return null;

      final temporaryDirectory = Directory.systemTemp;
      final audioFile = File(
        "${temporaryDirectory.path}/labvoice-$generation.mp3",
      );
      await audioFile.writeAsBytes(audio, flush: true);
      if (generation != _speechGeneration) {
        await audioFile.delete();
        return null;
      }

      _activeAudioFile = audioFile;
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setVolume(1.0);
      await _player.play(
        DeviceFileSource(audioFile.path, mimeType: "audio/mpeg"),
      );
      return null;
    } catch (error) {
      // LabVoice never falls back to a robotic system voice.
      return error.toString();
    }
  }

  static Future<void> stop() async {
    _speechGeneration++;
    await _player.stop();
    await _deleteActiveAudioFile();
  }

  static Future<void> setLanguage(String locale) async {
    // The cloud voice receives the active response language per request.
  }

  static Future<void> _deleteActiveAudioFile() async {
    final file = _activeAudioFile;
    _activeAudioFile = null;
    if (file != null && await file.exists()) {
      await file.delete();
    }
  }
}
