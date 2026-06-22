class LanguageProfile {
  final String name;
  final String? recognitionLocale;
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
    "auto": LanguageProfile(
      name: "Automático",
      recognitionLocale: null,
      voiceLocale: "en-US",
      languageTag: "auto",
    ),
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

  static LanguageProfile _current = profiles["auto"]!;
  static String _effectiveLanguage = "es";

  static LanguageProfile get current => _current;
  static String get effectiveLanguage => _current.languageTag == "auto"
      ? _effectiveLanguage
      : _current.languageTag;
  static String? get activeRecognitionLocale => _current.languageTag == "auto"
      ? profileForLanguage(_effectiveLanguage).recognitionLocale
      : _current.recognitionLocale;
  static String get activeVoiceLocale =>
      profileForLanguage(effectiveLanguage).voiceLocale;

  static void setLanguage(String recognitionLocale) {
    _current = profiles[recognitionLocale] ?? profiles["auto"]!;
    _effectiveLanguage = _current.languageTag == "auto"
        ? "es"
        : _current.languageTag;
  }

  static String detectLanguage(String text) {
    final normalized = text.toLowerCase();

    if (RegExp(r'[\u3040-\u30ff]').hasMatch(text)) return "ja";
    if (RegExp(r'[\uac00-\ud7af]').hasMatch(text)) return "ko";
    if (RegExp(r'[\u4e00-\u9fff]').hasMatch(text)) return "zh";
    if (RegExp(r'[\u0400-\u04ff]').hasMatch(text)) return "ru";

    const markers = {
      "es": [
        " el ",
        " la ",
        " que ",
        " por ",
        " para ",
        "hola",
        "proyecto",
        "abre",
        "ejecuta",
        "quiero",
        "puedes",
        "siguiente",
      ],
      "en": [
        " the ",
        " and ",
        " what ",
        " for ",
        "hello",
        "project",
        "open ",
        "while",
        "run ",
        "please",
        "next",
        "can you",
        "i want",
      ],
      "pt": [" você ", " para ", " projeto", "olá", " abrir "],
      "fr": [" le ", " la ", " pour ", "bonjour", " projet"],
      "de": [" der ", " die ", " und ", "hallo", " projekt"],
      "it": [" il ", " la ", " per ", "ciao", " progetto"],
    };

    final padded = " $normalized ";
    var bestLanguage = _effectiveLanguage;
    var bestScore = 0;
    for (final entry in markers.entries) {
      final score = entry.value.where(padded.contains).length;
      if (score > bestScore) {
        bestScore = score;
        bestLanguage = entry.key;
      }
    }
    return bestLanguage;
  }

  static String alignToText(String text) {
    if (_current.languageTag == "auto") {
      _effectiveLanguage = detectLanguage(text);
    }
    return effectiveLanguage;
  }

  static LanguageProfile profileForLanguage(String languageTag) =>
      profiles.values.firstWhere(
        (profile) => profile.languageTag == languageTag,
        orElse: () => profiles["en_US"]!,
      );

  static bool get isSpanish => effectiveLanguage == "es";

  static String languageUpdated() => _current.languageTag == "auto"
      ? "Modo automático activado. Responderé en el idioma que detecte."
      : isSpanish
      ? "Idioma actualizado a ${_current.name}. Estoy listo."
      : "Language updated to ${_current.name}. I'm ready.";

  static String backendError() => isSpanish
      ? "No pude comunicarme con el núcleo de LabVoice."
      : "I could not communicate with the LabVoice core.";

  static String noClearCommand() => isSpanish
      ? "No escuché el comando con claridad. Inténtalo otra vez."
      : "I did not hear the command clearly. Please try again.";

  static String listening() => isSpanish ? "Te escucho..." : "Listening...";

  static String creatorIdentity() => isSpanish
      ? "Mi creador es Ian Faber Mendoza Mey, fundador de LabVoice. Él concibió "
            "este sistema como un sistema operativo centrado en la voz: capaz "
            "de comprender contexto, ejecutar herramientas y convertir una "
            "intención hablada en trabajo real. No nací solo para responder "
            "preguntas; nací para colaborar, construir y ampliar lo que una "
            "persona puede lograr con su voz."
      : "My creator is Ian Faber Mendoza Mey, founder of LabVoice. He envisioned "
            "this system as a voice-centered operating system: capable of "
            "understanding context, operating tools, and turning spoken intent "
            "into real work. I was not created merely to answer questions; I "
            "was created to collaborate, build, and expand what a person can "
            "accomplish with their voice.";

  static String founderBiography() => isSpanish
      ? "Ian Faber Mendoza Mey es el fundador y creador de LabVoice. Nacido en "
            "Sincelejo, Colombia, construyó su trayectoria entre la disciplina, "
            "el aprendizaje continuo, los viajes y la migración a Estados "
            "Unidos. Creó LabVoice como un sistema operativo centrado en la voz, "
            "diseñado para transformar intención hablada en acciones reales y "
            "hacer la tecnología más accesible, especialmente para personas "
            "con discapacidad visual."
      : "Ian Faber Mendoza Mey is the founder and creator of LabVoice. Born in "
            "Sincelejo, Colombia, he built his path through discipline, "
            "continuous learning, travel, and migration to the United States. "
            "He created LabVoice as a voice-centered operating system designed "
            "to transform spoken intent into real action and make technology "
            "more accessible, especially for people with visual disabilities.";

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
