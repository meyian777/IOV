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
  static const Map<String, List<String>> _languageMarkers = {
    "es": [
      " el ",
      " la ",
      " que ",
      " por ",
      " para ",
      "hola",
      "proyecto",
      "abre",
      "abrir",
      "navegador",
      "reproduce",
      "canción",
      "cancion",
      "música",
      "musica",
      "dame",
      "estado",
      "sistema",
      "detalle",
      "detallado",
      "resumen",
      "continuemos",
      "trabajando",
      "llevamos",
      "ayer",
      "terminal",
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
      "browser",
      "play ",
      "song",
      "music",
      "summary",
      "status",
      "system",
      "detail",
      "detailed",
      "working",
      "yesterday",
      "terminal",
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
  static String get activeSystemVoice =>
      systemVoiceForLanguage(effectiveLanguage);

  static void setLanguage(String recognitionLocale) {
    _current = profiles[recognitionLocale] ?? profiles["auto"]!;
    _effectiveLanguage = _current.languageTag == "auto"
        ? "es"
        : _current.languageTag;
  }

  static String detectLanguage(String text) {
    final normalized = text.toLowerCase();
    final explicit = explicitLanguageRequest(text);
    if (explicit != null) return explicit;

    if (RegExp(r'[\u3040-\u30ff]').hasMatch(text)) return "ja";
    if (RegExp(r'[\uac00-\ud7af]').hasMatch(text)) return "ko";
    if (RegExp(r'[\u4e00-\u9fff]').hasMatch(text)) return "zh";
    if (RegExp(r'[\u0400-\u04ff]').hasMatch(text)) return "ru";

    final padded = " $normalized ";
    var bestLanguage = _effectiveLanguage;
    var bestScore = 0;
    for (final entry in _languageMarkers.entries) {
      final score = _scoreMarkers(padded, entry.value);
      if (score > bestScore) {
        bestScore = score;
        bestLanguage = entry.key;
      }
    }
    return bestLanguage;
  }

  static String alignToText(String text) {
    final explicit = explicitLanguageRequest(text);
    final detected = detectLanguage(text);
    if (explicit != null ||
        _current.languageTag == "auto" ||
        _hasStrongSignal(text, detected) ||
        _hasScriptSignal(text, detected)) {
      _current = profileForLanguage(detected);
      _effectiveLanguage = detected;
    }
    return effectiveLanguage;
  }

  static String? explicitLanguageRequest(String text) {
    final normalized = " ${text.toLowerCase()} "
        .replaceAll("á", "a")
        .replaceAll("é", "e")
        .replaceAll("í", "i")
        .replaceAll("ó", "o")
        .replaceAll("ú", "u")
        .replaceAll("ñ", "n")
        .replaceAll(RegExp(r'\s+'), " ");
    if (normalized.contains(" habla en espanol ") ||
        normalized.contains(" hablame en espanol ") ||
        normalized.contains(" responde en espanol ") ||
        normalized.contains(" cambia a espanol ") ||
        normalized.contains(" idioma espanol ")) {
      return "es";
    }
    if (normalized.contains(" speak english ") ||
        normalized.contains(" talk to me in english ") ||
        normalized.contains(" respond in english ") ||
        normalized.contains(" switch to english ") ||
        normalized.contains(" english language ")) {
      return "en";
    }
    return null;
  }

  static int _scoreMarkers(String paddedText, List<String> markers) =>
      markers.where(paddedText.contains).length;

  static bool _hasStrongSignal(String text, String languageTag) {
    final normalized = " ${text.toLowerCase()} ";
    if (languageTag == "es" &&
        (normalized.contains(" habla en español ") ||
            normalized.contains(" responde en español ") ||
            normalized.contains(" en español ") ||
            normalized.contains(" en espanol "))) {
      return true;
    }
    if (languageTag == "en" &&
        (normalized.contains(" speak english ") ||
            normalized.contains(" respond in english ") ||
            normalized.contains(" in english "))) {
      return true;
    }
    final markers = _languageMarkers[languageTag];
    if (markers == null) return false;
    return _scoreMarkers(normalized, markers) >= 2;
  }

  static bool _hasScriptSignal(String text, String languageTag) {
    return switch (languageTag) {
      "ja" => RegExp(r'[\u3040-\u30ff]').hasMatch(text),
      "ko" => RegExp(r'[\uac00-\ud7af]').hasMatch(text),
      "zh" => RegExp(r'[\u4e00-\u9fff]').hasMatch(text),
      "ru" => RegExp(r'[\u0400-\u04ff]').hasMatch(text),
      _ => false,
    };
  }

  static LanguageProfile profileForLanguage(String languageTag) =>
      profiles.values.firstWhere(
        (profile) => profile.languageTag == languageTag,
        orElse: () => profiles["en_US"]!,
      );

  static String systemVoiceForLanguage(String languageTag) {
    switch (languageTag) {
      case "es":
        return "Reed (Spanish (Mexico))";
      case "en":
        return "Samantha";
      case "pt":
        return "Luciana";
      case "fr":
        return "Jacques";
      case "de":
        return "Anna";
      case "it":
        return "Alice";
      case "ja":
        return "Kyoko";
      case "ko":
        return "Yuna";
      case "zh":
        return "Ting-Ting";
      case "ru":
        return "Milena";
      default:
        return "Samantha";
    }
  }

  static bool get isSpanish => effectiveLanguage == "es";

  static String languageUpdated() => _current.languageTag == "auto"
      ? "Modo automático activado. Responderé en el idioma que detecte."
      : isSpanish
      ? "Idioma actualizado a ${_current.name}. Estoy listo."
      : "Language updated to ${_current.name}. I'm ready.";

  static String backendError() => isSpanish
      ? "No pude comunicarme con el núcleo de OSvoz."
      : "I could not communicate with the OSvoz core.";

  static String noClearCommand() => isSpanish
      ? "No escuché el comando con claridad. Inténtalo otra vez."
      : "I did not hear the command clearly. Please try again.";

  static String listening() => isSpanish ? "Te escucho..." : "Listening...";

  static String creatorIdentity() => isSpanish
      ? "Mi creador es Ian Faber Mendoza Mey, fundador de OSvoz. Él concibió "
            "este sistema como un sistema operativo centrado en la voz: capaz "
            "de comprender contexto, ejecutar herramientas y convertir una "
            "intención hablada en trabajo real. No nací solo para responder "
            "preguntas; nací para colaborar, construir y ampliar lo que una "
            "persona puede lograr con su voz."
      : "My creator is Ian Faber Mendoza Mey, founder of OSvoz. He envisioned "
            "this system as a voice-centered operating system: capable of "
            "understanding context, operating tools, and turning spoken intent "
            "into real work. I was not created merely to answer questions; I "
            "was created to collaborate, build, and expand what a person can "
            "accomplish with their voice.";

  static String labVoiceIdentity() => isSpanish
      ? "Soy OSvoz, un sistema operativo centrado en la voz. Comprendo "
            "contexto, colaboro contigo y convierto instrucciones habladas en "
            "acciones reales mediante herramientas seguras."
      : "I am OSvoz, a voice-centered operating system. I understand "
            "context, collaborate with you, and turn spoken instructions into "
            "real actions through secure tools.";

  static String founderBiography() => isSpanish
      ? "Ian Faber Mendoza Mey es el fundador y creador de OSvoz. Nacido en "
            "Sincelejo, Colombia, construyó su trayectoria entre la disciplina, "
            "el aprendizaje continuo, los viajes y la migración a Estados "
            "Unidos. Creó OSvoz como un sistema operativo centrado en la voz, "
            "diseñado para transformar intención hablada en acciones reales y "
            "hacer la tecnología más accesible, especialmente para personas "
            "con discapacidad visual."
      : "Ian Faber Mendoza Mey is the founder and creator of OSvoz. Born in "
            "Sincelejo, Colombia, he built his path through discipline, "
            "continuous learning, travel, and migration to the United States. "
            "He created OSvoz as a voice-centered operating system designed "
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
        ? "Permiso para ${label.$1}. Confirma: sí o no."
        : "Permission to ${label.$2}. Confirm: yes or no.";
  }

  static String actionCompleted(String action) =>
      isSpanish ? "Acción completada: $action." : "Action completed: $action.";
}
