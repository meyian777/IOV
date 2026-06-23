import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'labvoice_api.dart';
import 'language_manager.dart';

class VoiceEngine {
  static const int maxSpeechCharacters = 3900;
  static final AudioPlayer _player = AudioPlayer();
  static final ValueNotifier<bool> speaking = ValueNotifier<bool>(false);
  static int _speechGeneration = 0;
  static File? _activeAudioFile;
  static StreamSubscription<void>? _completionSubscription;

  static Future<String?> speak(String text) async {
    if (text.trim().isEmpty) return null;

    final generation = ++_speechGeneration;
    await _player.stop();
    await _deleteActiveAudioFile();
    speaking.value = true;

    try {
      final audio = await LabVoiceApi.speech(
        textForSpeech(text),
        language: LanguageManager.effectiveLanguage,
      );
      if (generation != _speechGeneration) {
        speaking.value = false;
        return null;
      }

      final temporaryDirectory = Directory.systemTemp;
      final audioFile = File(
        "${temporaryDirectory.path}/labvoice-$generation.mp3",
      );
      await audioFile.writeAsBytes(audio, flush: true);
      if (generation != _speechGeneration) {
        await audioFile.delete();
        speaking.value = false;
        return null;
      }

      _activeAudioFile = audioFile;
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setVolume(1.0);
      await _completionSubscription?.cancel();
      _completionSubscription = _player.onPlayerComplete.listen((_) {
        if (generation == _speechGeneration) {
          speaking.value = false;
          unawaited(_deleteActiveAudioFile());
        }
      });
      await _player.play(
        DeviceFileSource(audioFile.path, mimeType: "audio/mpeg"),
      );
      return null;
    } catch (error) {
      speaking.value = false;
      // LabVoice never falls back to a robotic system voice.
      return error.toString();
    }
  }

  static Future<void> stop() async {
    _speechGeneration++;
    await _completionSubscription?.cancel();
    _completionSubscription = null;
    await _player.stop();
    speaking.value = false;
    await _deleteActiveAudioFile();
  }

  static Future<void> setLanguage(String locale) async {
    // The cloud voice receives the active response language per request.
  }

  static String textForSpeech(String text) {
    final normalized = text.trim();
    if (normalized.length <= maxSpeechCharacters) return normalized;

    final shortened = normalized.substring(0, maxSpeechCharacters);
    final sentenceBoundary = shortened.lastIndexOf(RegExp(r'[.!?]\s'));
    final safeEnd = sentenceBoundary > 2500
        ? sentenceBoundary + 1
        : maxSpeechCharacters;
    return "${shortened.substring(0, safeEnd).trim()} "
        "La respuesta completa permanece visible en pantalla.";
  }

  static Future<void> _deleteActiveAudioFile() async {
    final file = _activeAudioFile;
    _activeAudioFile = null;
    if (file != null && await file.exists()) {
      await file.delete();
    }
  }
}
