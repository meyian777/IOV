import 'dart:async';

import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'language_manager.dart';

class VoiceSessionResult {
  final bool verified;
  final String transcript;
  final String language;
  final String message;

  const VoiceSessionResult({
    required this.verified,
    required this.transcript,
    required this.language,
    required this.message,
  });
}

abstract class SessionAuthenticator {
  Future<bool> authenticateBiometric();
  Future<VoiceSessionResult> listenForSessionStart({String? recognitionLocale});
  Future<VoiceSessionResult> verifyVoice({String? recognitionLocale});
}

class MethodChannelSessionAuthenticator implements SessionAuthenticator {
  MethodChannelSessionAuthenticator({
    MethodChannel? channel,
    SpeechToText? speech,
  }) : _channel = channel ?? const MethodChannel('osvoz/session_auth'),
       _speech = speech ?? SpeechToText();

  final MethodChannel _channel;
  final SpeechToText _speech;

  @override
  Future<bool> authenticateBiometric() async {
    final result = await _channel.invokeMethod<bool>('authenticate');
    return result == true;
  }

  @override
  Future<VoiceSessionResult> listenForSessionStart({
    String? recognitionLocale,
  }) async {
    final transcript = await _captureSpeech(
      recognitionLocale: recognitionLocale,
      timeout: const Duration(seconds: 7),
    );
    final language = LanguageManager.alignToText(transcript);
    final verified = validatesSessionStart(transcript);
    return VoiceSessionResult(
      verified: verified,
      transcript: transcript,
      language: language,
      message: verified
          ? language == "en"
                ? "Starting your session."
                : "Iniciando tu sesión."
          : language == "en"
          ? "Say: start my session."
          : "Di: inicia mi sesión.",
    );
  }

  @override
  Future<VoiceSessionResult> verifyVoice({String? recognitionLocale}) async {
    final transcript = await _captureSpeech(
      recognitionLocale: recognitionLocale,
      timeout: const Duration(seconds: 8),
    );
    final language =
        _languageForLocale(recognitionLocale) ??
        LanguageManager.alignToText(transcript);
    final verified = validatesVoiceAuthorization(transcript);
    return VoiceSessionResult(
      verified: verified,
      transcript: transcript,
      language: language,
      message: verified
          ? "Voz verificada."
          : language == "en"
          ? "Say: IOV, I authorize this session."
          : "Di: IOV, autorizo esta sesión.",
    );
  }

  Future<String> _captureSpeech({
    required Duration timeout,
    String? recognitionLocale,
  }) async {
    final completer = Completer<String>();
    var transcript = "";
    final available = await _speech.initialize(
      onStatus: (status) {
        if ((status == "done" || status == "notListening") &&
            !completer.isCompleted) {
          completer.complete(transcript);
        }
      },
      onError: (error) {
        if (!completer.isCompleted) {
          completer.completeError(error.errorMsg);
        }
      },
    );
    if (!available) {
      return "";
    }

    await _speech.listen(
      onResult: (SpeechRecognitionResult result) {
        transcript = result.recognizedWords.trim();
        if (result.finalResult && !completer.isCompleted) {
          completer.complete(transcript);
        }
      },
      listenOptions: SpeechListenOptions(
        localeId:
            recognitionLocale ??
            LanguageManager.activeRecognitionLocale ??
            "es_ES",
        listenMode: ListenMode.confirmation,
        partialResults: true,
      ),
    );

    try {
      transcript = await completer.future.timeout(timeout);
    } on TimeoutException {
      transcript = transcript.trim();
    } finally {
      await _speech.stop();
    }

    return transcript;
  }

  static bool validatesSessionStart(String transcript) {
    final normalized = _normalizeTranscript(transcript);
    final spanishStart =
        (normalized.contains("inicia") ||
            normalized.contains("iniciar") ||
            normalized.contains("abre") ||
            normalized.contains("abrir") ||
            normalized.contains("activa") ||
            normalized.contains("entrar")) &&
        (normalized.contains("sesion") ||
            normalized.contains("session") ||
            normalized.contains("osvoz") ||
            normalized.contains("iov"));
    final englishStart =
        (normalized.contains("start") ||
            normalized.contains("open") ||
            normalized.contains("begin") ||
            normalized.contains("sign") ||
            normalized.contains("log")) &&
        (normalized.contains("session") ||
            normalized.contains("osvoz") ||
            normalized.contains("iov") ||
            normalized.contains("me in"));
    return spanishStart || englishStart;
  }

  static bool validatesVoiceAuthorization(String transcript) {
    final normalized = _normalizeTranscript(transcript);
    final mentionsWakeName =
        normalized.contains("iov") ||
        normalized.contains("osvoz") ||
        normalized.contains("os voz") ||
        normalized.startsWith("os ");
    final spanishAuthorization =
        normalized.contains("autorizo") ||
        normalized.contains("autorizar") ||
        normalized.contains("confirmo") ||
        normalized.contains("permiso") ||
        normalized.contains("sesion") ||
        normalized.contains("soy");
    final englishAuthorization =
        normalized.contains("authorize") ||
        normalized.contains("authorise") ||
        normalized.contains("confirm") ||
        normalized.contains("permission") ||
        normalized.contains("session") ||
        normalized.contains("i am");
    final explicitSpanishSessionAuthorization =
        (normalized.contains("autorizo") ||
            normalized.contains("autorizar") ||
            normalized.contains("confirmo")) &&
        normalized.contains("sesion");
    final explicitSpanishShortAuthorization =
        normalized.contains("autorizo") && normalized.contains("esta");
    final explicitEnglishSessionAuthorization =
        (normalized.contains("authorize") ||
            normalized.contains("authorise") ||
            normalized.contains("confirm")) &&
        normalized.contains("session");
    final explicitEnglishShortAuthorization =
        (normalized.contains("i authorize") ||
            normalized.contains("i authorise")) &&
        !normalized.contains("not");
    return (mentionsWakeName &&
            (spanishAuthorization || englishAuthorization)) ||
        explicitSpanishSessionAuthorization ||
        explicitSpanishShortAuthorization ||
        explicitEnglishSessionAuthorization ||
        explicitEnglishShortAuthorization;
  }

  static String _normalizeTranscript(String text) {
    return text
        .toLowerCase()
        .replaceAll("á", "a")
        .replaceAll("é", "e")
        .replaceAll("í", "i")
        .replaceAll("ó", "o")
        .replaceAll("ú", "u")
        .replaceAll("ü", "u")
        .replaceAll("ñ", "n")
        .replaceAll(RegExp(r"[^a-z0-9\s]"), " ")
        .replaceAll(RegExp(r"\s+"), " ")
        .trim();
  }

  String? _languageForLocale(String? locale) {
    if (locale == null) return null;
    final normalized = locale.toLowerCase();
    if (normalized.startsWith("es")) return "es";
    if (normalized.startsWith("en")) return "en";
    return null;
  }
}
