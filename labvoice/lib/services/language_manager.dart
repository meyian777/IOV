class LanguageProfile {
  final String name;
  final String recognitionLocale;
  final String voiceLocale;
  final String languageTag;

  const LanguageProfile({
    required this.name,
    required this.recognitionLocale,
    required this.voiceLocale,
    required this.languageTag,
  });
}

class LanguageManager {
  static const Map<String, LanguageProfile> profiles = {
    "es_ES": LanguageProfile(
      name: "Español",
      recognitionLocale: "es_ES",
      voiceLocale: "es-ES",
      languageTag: "es",
    ),
    "en_US": LanguageProfile(
      name: "English",
      recognitionLocale: "en_US",
      voiceLocale: "en-US",
      languageTag: "en",
    ),
    "pt_BR": LanguageProfile(
      name: "Português",
      recognitionLocale: "pt_BR",
      voiceLocale: "pt-BR",
      languageTag: "pt",
    ),
    "fr_FR": LanguageProfile(
      name: "Français",
      recognitionLocale: "fr_FR",
      voiceLocale: "fr-FR",
      languageTag: "fr",
    ),
    "de_DE": LanguageProfile(
      name: "Deutsch",
      recognitionLocale: "de_DE",
      voiceLocale: "de-DE",
      languageTag: "de",
    ),
    "it_IT": LanguageProfile(
      name: "Italiano",
      recognitionLocale: "it_IT",
      voiceLocale: "it-IT",
      languageTag: "it",
    ),
    "ru_RU": LanguageProfile(
      name: "Русский",
      recognitionLocale: "ru_RU",
      voiceLocale: "ru-RU",
      languageTag: "ru",
    ),
    "zh_CN": LanguageProfile(
      name: "中文 Mandarin",
      recognitionLocale: "zh_CN",
      voiceLocale: "zh-CN",
      languageTag: "zh",
    ),
    "ja_JP": LanguageProfile(
      name: "日本語",
      recognitionLocale: "ja_JP",
      voiceLocale: "ja-JP",
      languageTag: "ja",
    ),
    "ko_KR": LanguageProfile(
      name: "한국어",
      recognitionLocale: "ko_KR",
      voiceLocale: "ko-KR",
      languageTag: "ko",
    ),
  };

  static LanguageProfile _current = profiles["es_ES"]!;

  static LanguageProfile get current => _current;

  static void setLanguage(String recognitionLocale) {
    _current = profiles[recognitionLocale] ?? profiles["en_US"]!;
  }

  static bool get isSpanish => _current.languageTag == "es";

  static String languageUpdated() => isSpanish
      ? "Idioma actualizado a ${_current.name}. Estoy listo."
      : "Language updated to ${_current.name}. I'm ready.";

  static String backendError() => isSpanish
      ? "No pude comunicarme con el núcleo de LabVoice."
      : "I could not communicate with the LabVoice core.";

  static String noClearCommand() => isSpanish
      ? "No escuché el comando con claridad. Inténtalo otra vez."
      : "I did not hear the command clearly. Please try again.";

  static String listening() => isSpanish ? "Te escucho..." : "Listening...";

  static String text(String spanish, String english) =>
      isSpanish ? spanish : english;

  static String confirmationRequired(String action) {
    final labels = {
      "OPEN_VSCODE": ("abrir Visual Studio Code", "open Visual Studio Code"),
      "OPEN_PROJECT": ("abrir el proyecto activo", "open the active project"),
      "OPEN_TERMINAL": ("abrir Terminal", "open Terminal"),
      "RUN_FLUTTER": ("iniciar Flutter", "start Flutter"),
    };
    final label = labels[action] ?? (action, action);
    return isSpanish
        ? "Necesito tu permiso para ${label.$1}. Di sí para confirmar o no para cancelar."
        : "I need your permission to ${label.$2}. Say yes to confirm or no to cancel.";
  }

  static String actionCompleted(String action) =>
      isSpanish ? "Acción completada: $action." : "Action completed: $action.";
}
