import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'labvoice_api.dart';
import 'language_manager.dart';
import 'voice_latency_metrics.dart';

class VoiceEngine {
  static const int maxSpeechCharacters = 3900;
  static final AudioPlayer _player = AudioPlayer();
  static final ValueNotifier<bool> speaking = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> paused = ValueNotifier<bool>(false);
  static int _speechGeneration = 0;
  static File? _activeAudioFile;
  static Process? _systemSpeechProcess;
  static StreamSubscription<void>? _completionSubscription;
  static bool _ducked = false;
  static bool _systemSpeechDucked = false;

  static Future<String?> speak(String text) async {
    if (text.trim().isEmpty) return null;

    final generation = ++_speechGeneration;
    await _player.stop();
    _systemSpeechProcess?.kill();
    _systemSpeechProcess = null;
    _ducked = false;
    _systemSpeechDucked = false;
    await _deleteActiveAudioFile();
    speaking.value = true;
    paused.value = false;

    try {
      final ttsStopwatch = Stopwatch()..start();
      final audio = await _naturalVoiceAudio(text);
      if (generation != _speechGeneration) {
        speaking.value = false;
        return null;
      }

      final temporaryDirectory = Directory.systemTemp;
      final audioFile = File("${temporaryDirectory.path}/iov-$generation.mp3");
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
      ttsStopwatch.stop();
      VoiceLatencyMetrics.record("tts_ms", ttsStopwatch.elapsed);
      return null;
    } catch (error) {
      final fallbackStopwatch = Stopwatch()..start();
      final fallbackError = await _speakWithSystemVoice(text, generation);
      fallbackStopwatch.stop();
      VoiceLatencyMetrics.record("tts_ms", fallbackStopwatch.elapsed);
      if (fallbackError == null) return null;
      speaking.value = false;
      return "${error.toString()} · $fallbackError";
    }
  }

  static Future<void> stop() async {
    _speechGeneration++;
    await _completionSubscription?.cancel();
    _completionSubscription = null;
    await _player.stop();
    _systemSpeechProcess?.kill();
    _systemSpeechProcess = null;
    _ducked = false;
    _systemSpeechDucked = false;
    speaking.value = false;
    paused.value = false;
    await _deleteActiveAudioFile();
  }

  static Future<void> pause() async {
    if (!speaking.value) return;
    await restoreVolume();
    final systemSpeech = _systemSpeechProcess;
    if (systemSpeech != null) {
      systemSpeech.kill(ProcessSignal.sigstop);
    } else {
      await _player.pause();
    }
    paused.value = true;
    speaking.value = false;
  }

  static Future<void> resume() async {
    if (!paused.value) return;
    final systemSpeech = _systemSpeechProcess;
    if (systemSpeech != null) {
      systemSpeech.kill(ProcessSignal.sigcont);
    } else {
      await _player.resume();
    }
    paused.value = false;
    speaking.value = true;
  }

  static Future<void> duck() async {
    if (!speaking.value || _ducked) return;
    _ducked = true;
    final systemSpeech = _systemSpeechProcess;
    if (systemSpeech != null) {
      systemSpeech.kill(ProcessSignal.sigstop);
      _systemSpeechDucked = true;
      return;
    }
    await _player.setVolume(0.16);
  }

  static Future<void> restoreVolume() async {
    if (!_ducked) return;
    _ducked = false;
    if (_systemSpeechDucked) {
      _systemSpeechDucked = false;
      if (!paused.value) {
        _systemSpeechProcess?.kill(ProcessSignal.sigcont);
      }
      return;
    }
    await _player.setVolume(1.0);
  }

  static Future<void> setLanguage(String locale) async {
    // The cloud voice receives the active response language per request.
  }

  static Future<List<int>> _naturalVoiceAudio(String text) {
    return OSvozApi.speech(
      textForSpeech(text),
      language: LanguageManager.effectiveLanguage,
    ).timeout(const Duration(seconds: 12));
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

  static Future<String?> _speakWithSystemVoice(
    String text,
    int generation,
  ) async {
    if (!Platform.isMacOS) {
      return "System voice fallback is unavailable on this platform.";
    }
    try {
      final process = await Process.start("/usr/bin/say", [
        "-v",
        LanguageManager.activeSystemVoice,
        "-r",
        "152",
        textForSpeech(text),
      ]);
      if (generation != _speechGeneration) {
        process.kill();
        return null;
      }
      _systemSpeechProcess = process;
      unawaited(
        process.exitCode.then((_) {
          if (generation == _speechGeneration) {
            _systemSpeechProcess = null;
            speaking.value = false;
          }
        }),
      );
      return null;
    } catch (error) {
      return "System voice fallback failed: $error";
    }
  }
}
