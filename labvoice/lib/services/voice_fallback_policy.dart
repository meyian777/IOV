import 'labvoice_api.dart';

class VoiceFallbackPolicy {
  static bool isNoSpeech(OSvozApiException error) {
    return error.code == "transcription_failed" &&
        error.message.toLowerCase().contains("no speech");
  }

  static bool shouldUseNativeSpeechFallback(OSvozApiException error) {
    return error.code == "backend_unavailable" ||
        error.code == "invalid_response" ||
        error.code == "timeout" ||
        (error.code == "transcription_failed" &&
            isLocalWhisperInfrastructureFailure(error.message));
  }

  static String safeVoiceErrorMessage(String error) {
    final normalized = error.replaceAll(RegExp(r"\s+"), " ").trim();
    if (normalized.isEmpty) return "No detecté voz. Intenta de nuevo.";
    final lower = normalized.toLowerCase();
    if (isLocalWhisperInfrastructureFailure(lower)) {
      return "Whisper local no pudo iniciar. Intenta de nuevo; usaré reconocimiento nativo como respaldo.";
    }
    if (lower.contains("no speech")) {
      return "No detecté voz. Intenta de nuevo.";
    }
    if (normalized.length <= 180) return normalized;
    return "${normalized.substring(0, 177)}...";
  }

  static bool isLocalWhisperInfrastructureFailure(String error) {
    final lower = error.toLowerCase();
    return lower.contains("ggml_") ||
        lower.contains("_rsets_init") ||
        lower.contains("libggml") ||
        lower.contains("load_backend") ||
        lower.contains("/opt/homebrew") ||
        lower.contains("metal_device") ||
        lower.contains("failed to initialize whisper context") ||
        lower.contains("local whisper could not initialize");
  }
}
