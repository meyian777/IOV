import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:labvoice/services/labvoice_api.dart';
import 'package:labvoice/services/local_whisper_recorder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('WavEnergyInspector detects silence', () {
    final wav = _wavPcm16(List<int>.filled(1600, 0));

    final energy = WavEnergyInspector.inspect(wav);

    expect(energy.rms, 0);
    expect(energy.peak, 0);
  });

  test('WavEnergyInspector detects audible signal', () {
    final samples = List<int>.generate(1600, (index) {
      return (sin(index / 8) * 9000).round();
    });
    final wav = _wavPcm16(samples);

    final energy = WavEnergyInspector.inspect(wav);

    expect(energy.rms, greaterThan(LocalWhisperRecorder.minimumRms));
    expect(energy.peak, greaterThan(LocalWhisperRecorder.minimumPeak));
  });

  test(
    'transcribes audible wav through the configured local Whisper backend',
    () async {
      final samples = List<int>.generate(1600, (index) {
        return (sin(index / 8) * 9000).round();
      });
      final wav = _wavPcm16(samples);
      var calls = 0;
      late Uint8List sentBytes;
      late String sentLanguage;
      final recorder = LocalWhisperRecorder(
        transcriber: (audioBytes, {required language}) async {
          calls++;
          sentBytes = audioBytes;
          sentLanguage = language;
          return const VoiceTranscriptionResult(
            transcript: ' OSvoz abre el proyecto ',
            language: 'es',
            engine: 'whisper.cpp',
            execution: 'local_offline',
            audioDurationSeconds: 0.1,
          );
        },
      );

      final result = await recorder.transcribeBytesForTest(wav, language: 'es');

      expect(calls, 1);
      expect(sentBytes, wav);
      expect(sentLanguage, 'es');
      expect(result.transcript, 'OSvoz abre el proyecto');
      expect(result.language, 'es');
      expect(result.backendAudioSeconds, 0.1);
      expect(result.localRms, greaterThan(LocalWhisperRecorder.minimumRms));
      expect(result.localPeak, greaterThan(LocalWhisperRecorder.minimumPeak));
    },
  );

  test('rejects silent wav before calling the backend', () async {
    final wav = _wavPcm16(List<int>.filled(1600, 0));
    var calls = 0;
    final recorder = LocalWhisperRecorder(
      transcriber: (audioBytes, {required language}) async {
        calls++;
        return const VoiceTranscriptionResult(
          transcript: 'should not happen',
          language: 'es',
          engine: 'whisper.cpp',
          execution: 'local_offline',
          audioDurationSeconds: 0.1,
        );
      },
    );

    expect(
      () => recorder.transcribeBytesForTest(wav, language: 'es'),
      throwsA(
        isA<OSvozApiException>().having(
          (error) => error.code,
          'code',
          'silent_audio',
        ),
      ),
    );
    expect(calls, 0);
  });
}

Uint8List _wavPcm16(List<int> samples) {
  const sampleRate = 16000;
  const channels = 1;
  const bitsPerSample = 16;
  final dataSize = samples.length * 2;
  final bytes = BytesBuilder();

  void asciiChunk(String value) => bytes.add(ascii.encode(value));
  void u16(int value) {
    final data = ByteData(2)..setUint16(0, value, Endian.little);
    bytes.add(data.buffer.asUint8List());
  }

  void u32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    bytes.add(data.buffer.asUint8List());
  }

  asciiChunk("RIFF");
  u32(36 + dataSize);
  asciiChunk("WAVE");
  asciiChunk("fmt ");
  u32(16);
  u16(1);
  u16(channels);
  u32(sampleRate);
  u32(sampleRate * channels * bitsPerSample ~/ 8);
  u16(channels * bitsPerSample ~/ 8);
  u16(bitsPerSample);
  asciiChunk("data");
  u32(dataSize);

  for (final sample in samples) {
    final data = ByteData(2)..setInt16(0, sample, Endian.little);
    bytes.add(data.buffer.asUint8List());
  }

  return bytes.toBytes();
}
