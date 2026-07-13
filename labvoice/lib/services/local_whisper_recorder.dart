import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'labvoice_api.dart';

typedef WhisperTranscriber =
    Future<VoiceTranscriptionResult> Function(
      Uint8List audioBytes, {
      required String language,
    });

class LocalWhisperRecordingResult {
  final String transcript;
  final String language;
  final Uint8List rawAudioBytes;
  final int audioBytes;
  final Duration recordingWindow;
  final Duration transcriptionElapsed;
  final double? backendAudioSeconds;
  final double localRms;
  final double localPeak;

  const LocalWhisperRecordingResult({
    required this.transcript,
    required this.language,
    required this.rawAudioBytes,
    required this.audioBytes,
    required this.recordingWindow,
    required this.transcriptionElapsed,
    required this.backendAudioSeconds,
    required this.localRms,
    required this.localPeak,
  });
}

class LocalWhisperRecorder {
  LocalWhisperRecorder({this._recorder, WhisperTranscriber? transcriber})
    : _transcriber = transcriber ?? OSvozApi.transcribeWavDetails;

  static const Duration defaultWindow = Duration(seconds: 5);
  static const double minimumRms = 0.004;
  static const double minimumPeak = 0.025;

  AudioRecorder? _recorder;
  final WhisperTranscriber _transcriber;
  String? _activePath;
  DateTime? _recordingStartedAt;

  AudioRecorder get _audioRecorder => _recorder ??= AudioRecorder();

  Future<bool> hasPermission() => _audioRecorder.hasPermission();

  Future<bool> isRecording() => _audioRecorder.isRecording();

  Stream<Amplitude> onAmplitudeChanged([
    Duration interval = const Duration(milliseconds: 200),
  ]) => _audioRecorder.onAmplitudeChanged(interval);

  Future<void> startRecording() async {
    final recorder = _audioRecorder;
    if (!await recorder.hasPermission()) {
      throw const OSvozApiException(
        "Microphone permission was not granted.",
        code: "microphone_permission_denied",
      );
    }
    if (await recorder.isRecording()) return;

    final path =
        "${Directory.systemTemp.path}/labvoice-whisper-${DateTime.now().microsecondsSinceEpoch}.wav";
    _activePath = path;
    _recordingStartedAt = DateTime.now();
    await recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );
  }

  Future<LocalWhisperRecordingResult> stopAndTranscribe({
    required String language,
  }) async {
    final startedAt = _recordingStartedAt;
    final expectedPath = _activePath;
    final recordedPath = await _audioRecorder.stop();
    _activePath = null;
    _recordingStartedAt = null;
    final path = recordedPath ?? expectedPath;
    if (path == null) {
      throw const OSvozApiException(
        "No audio was recorded.",
        code: "empty_audio",
      );
    }

    final file = File(path);
    try {
      final bytes = await file.readAsBytes();
      final recordingWindow = startedAt == null
          ? Duration.zero
          : DateTime.now().difference(startedAt);
      return await _transcribeBytes(
        bytes,
        language: language,
        recordingWindow: recordingWindow,
      );
    } finally {
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<LocalWhisperRecordingResult> recordAndTranscribe({
    required String language,
    Duration window = defaultWindow,
  }) async {
    await startRecording();
    await Future<void>.delayed(window);
    return stopAndTranscribe(language: language);
  }

  Future<void> stop() async {
    final recorder = _recorder;
    if (recorder != null && await recorder.isRecording()) {
      await recorder.stop();
    }
    final path = _activePath;
    _activePath = null;
    _recordingStartedAt = null;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<void> dispose() async {
    await _recorder?.dispose();
    _recorder = null;
  }

  @visibleForTesting
  Future<LocalWhisperRecordingResult> transcribeBytesForTest(
    Uint8List bytes, {
    required String language,
  }) {
    return _transcribeBytes(
      bytes,
      language: language,
      recordingWindow: Duration.zero,
    );
  }

  Future<LocalWhisperRecordingResult> _transcribeBytes(
    Uint8List bytes, {
    required String language,
    required Duration recordingWindow,
  }) async {
    final energy = WavEnergyInspector.inspect(bytes);
    if (energy.rms < minimumRms && energy.peak < minimumPeak) {
      throw OSvozApiException(
        "No detecté suficiente voz. RMS=${energy.rms.toStringAsFixed(4)}, peak=${energy.peak.toStringAsFixed(4)}.",
        code: "silent_audio",
      );
    }
    final stopwatch = Stopwatch()..start();
    final result = await _transcriber(bytes, language: language);
    stopwatch.stop();
    return LocalWhisperRecordingResult(
      transcript: result.transcript.trim(),
      language: result.language,
      rawAudioBytes: bytes,
      audioBytes: bytes.length,
      recordingWindow: recordingWindow,
      transcriptionElapsed: stopwatch.elapsed,
      backendAudioSeconds: result.audioDurationSeconds,
      localRms: energy.rms,
      localPeak: energy.peak,
    );
  }
}

class WavEnergy {
  final double rms;
  final double peak;
  final int samples;

  const WavEnergy({
    required this.rms,
    required this.peak,
    required this.samples,
  });
}

class WavEnergyInspector {
  static WavEnergy inspect(Uint8List bytes) {
    if (bytes.length < 44 ||
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) != "RIFF" ||
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) != "WAVE") {
      throw const OSvozApiException(
        "Recorded audio is not a valid WAV file.",
        code: "invalid_local_wav",
      );
    }

    var offset = 12;
    int? dataStart;
    int? dataLength;
    while (offset + 8 <= bytes.length) {
      final chunkId = ascii.decode(
        bytes.sublist(offset, offset + 4),
        allowInvalid: true,
      );
      final chunkSize = ByteData.sublistView(
        bytes,
        offset + 4,
        offset + 8,
      ).getUint32(0, Endian.little);
      final chunkDataStart = offset + 8;
      if (chunkId == "data") {
        dataStart = chunkDataStart;
        dataLength = min(chunkSize, bytes.length - chunkDataStart);
        break;
      }
      offset = chunkDataStart + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }

    if (dataStart == null || dataLength == null || dataLength < 2) {
      throw const OSvozApiException(
        "Recorded WAV did not contain audio samples.",
        code: "empty_audio",
      );
    }

    final data = ByteData.sublistView(bytes, dataStart, dataStart + dataLength);
    final sampleCount = dataLength ~/ 2;
    var sumSquares = 0.0;
    var peak = 0.0;
    for (var index = 0; index < sampleCount; index++) {
      final sample = data.getInt16(index * 2, Endian.little) / 32768.0;
      final absolute = sample.abs();
      if (absolute > peak) peak = absolute;
      sumSquares += sample * sample;
    }

    return WavEnergy(
      rms: sqrt(sumSquares / sampleCount),
      peak: peak,
      samples: sampleCount,
    );
  }
}
