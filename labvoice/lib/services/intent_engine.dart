class IntentEngine {
  static String detectIntent(String command) {
    final text = _normalizeCommand(command);

    if (text == "detente" ||
        text == "deténte" ||
        text == "para" ||
        text == "párate" ||
        text == "silencio" ||
        text == "cállate" ||
        text == "callate" ||
        text == "stop" ||
        text == "stop speaking" ||
        text == "be quiet") {
      return "stop_speaking";
    }

    if (text.contains("resúmelo") ||
        text.contains("resumelo") ||
        text.contains("resume eso") ||
        text.contains("respuesta corta") ||
        text.contains("hazlo más corto") ||
        text.contains("hazlo mas corto") ||
        text.contains("summarize") ||
        text.contains("shorter answer") ||
        text.contains("make it shorter")) {
      return "summarize_response";
    }

    if (text.contains("quién eres") ||
        text.contains("quien eres") ||
        text.contains("qué eres") ||
        text.contains("que eres") ||
        text.contains("háblame de ti") ||
        text.contains("hablame de ti") ||
        text.contains("who are you") ||
        text.contains("what are you") ||
        text.contains("tell me about yourself")) {
      return "osvoz_identity";
    }

    if (text.contains("quién te creó") ||
        text.contains("quien te creo") ||
        text.contains("quién es tu creador") ||
        text.contains("quien es tu creador") ||
        text.contains("quién es tu fundador") ||
        text.contains("quien es tu fundador") ||
        text.contains("quién creó osvoz") ||
        text.contains("quien creo osvoz") ||
        text.contains("who created you") ||
        text.contains("who made you") ||
        text.contains("who is your creator") ||
        text.contains("who is your founder") ||
        text.contains("who founded osvoz")) {
      return "creator_identity";
    }

    if (text.contains("biografía de ian") ||
        text.contains("biografia de ian") ||
        text.contains("biografía del fundador") ||
        text.contains("biografia del fundador") ||
        text.contains("quién es ian faber") ||
        text.contains("quien es ian faber") ||
        text.contains("ian faber mendoza mey") ||
        text.contains("biography of ian") ||
        text.contains("founder biography") ||
        text.contains("who is ian faber")) {
      return "founder_biography";
    }

    if (text == "sí, aplicar" ||
        text == "si, aplicar" ||
        text == "sí aplicar" ||
        text == "si aplicar" ||
        text == "aplicar cambio" ||
        text == "aplica el cambio" ||
        text == "confirmar" ||
        text == "confirmo" ||
        text == "sí" ||
        text == "si" ||
        text == "yes" ||
        text == "sí confirmar" ||
        text == "si confirmar" ||
        text == "confirm" ||
        text == "yes confirm") {
      return "confirm_action";
    }

    if (text == "cancelar" ||
        text == "cancela" ||
        text == "cancel" ||
        text == "no" ||
        text == "no cancelar") {
      return "cancel_action";
    }

    if (text.contains("deshacer último cambio") ||
        text.contains("deshacer ultimo cambio") ||
        text.contains("revierte el último cambio") ||
        text.contains("revierte el ultimo cambio") ||
        text.contains("restaura el archivo anterior") ||
        text.contains("undo last change")) {
      return "undo_edit";
    }

    if (text.startsWith("modifica ") ||
        text.startsWith("cambia ") ||
        text.startsWith("reemplaza ") ||
        text.startsWith("agrega ") ||
        text.startsWith("añade ") ||
        text.startsWith("corrige ") ||
        text.startsWith("edita ")) {
      return "edit_active_file";
    }

    if (_requestsDiagnostics(text)) {
      return "run_diagnostics";
    }

    if (_requestsOperatorStatus(text)) {
      return "operator_status";
    }

    if (text.contains("analiza el proyecto") ||
        text.contains("inspecciona el proyecto") ||
        text.contains("estado del proyecto") ||
        text.contains("qué proyecto está activo") ||
        text.contains("que proyecto esta activo") ||
        text.contains("qué proyecto es activo") ||
        text.contains("que proyecto es activo") ||
        text.contains("cuál proyecto está activo") ||
        text.contains("cual proyecto esta activo") ||
        text.contains("proyecto activo") ||
        text.contains("analyze project") ||
        text.contains("inspect project") ||
        text.contains("project status") ||
        text.contains("active project")) {
      return "inspect_project";
    }

    if (text.contains("lee ") ||
        text.contains("leer ") ||
        text.contains("abre el archivo") ||
        text.contains("muéstrame ") ||
        text.contains("muestrame ") ||
        text.contains("read file") ||
        text.contains("show file")) {
      return "read_project_file";
    }

    if (text.contains("abre visual studio") ||
        text.contains("abre vs code") ||
        text.contains("open vs code") ||
        text.contains("open visual studio code") ||
        text.contains("open vscode")) {
      return "open_vscode";
    }

    if (text.contains("abre mi proyecto") ||
        text.contains("abre osvoz") ||
        text.contains("open project")) {
      return "open_project";
    }

    if (text.contains("continúa donde me quedé") ||
        text.contains("continua donde me quede") ||
        text.contains("continua donde quede") ||
        text.contains("continuar proyecto") ||
        text.contains("retoma el proyecto") ||
        text.contains("seguir proyecto") ||
        text.contains("lo más importante") ||
        text.contains("lo mas importante") ||
        text.contains("muéstrame lo importante") ||
        text.contains("muestrame lo importante") ||
        text.contains("show me the most important") ||
        text.contains("continue project")) {
      return "continue_work";
    }

    if (text.contains("ejecuta flutter") ||
        text.contains("flutter run") ||
        text.contains("run flutter")) {
      return "run_flutter";
    }

    if (text.contains("omite el anuncio") ||
        text.contains("omitir anuncio") ||
        text.contains("quita el anuncio") ||
        text.contains("skip ad") ||
        text.contains("skip the ad")) {
      return "skip_ad";
    }

    if (text.contains("youtube") &&
        (text.contains("reproduce") ||
            text.contains("pon ") ||
            text.contains("ponme ") ||
            text.contains("play ") ||
            text.contains("canción") ||
            text.contains("cancion") ||
            text.contains("song") ||
            text.contains("música") ||
            text.contains("musica"))) {
      return "youtube_music";
    }

    if (text.contains("abre navegador") ||
        text.contains("abre el navegador") ||
        text.contains("abre safari") ||
        text.contains("abre chrome") ||
        text.contains("open browser")) {
      return "open_browser";
    }

    if (text.contains("open terminal") ||
        text.contains("open terminal app") ||
        text.contains("launch terminal") ||
        text.contains("abre terminal") ||
        text.contains("abre la terminal") ||
        text.contains("abre el terminal") ||
        text.contains("abrir terminal") ||
        text.contains("abrir la terminal") ||
        text.contains("abrir el terminal")) {
      return "open_terminal";
    }

    if (text.contains("list files") ||
        text.contains("show files") ||
        text.contains("project files") ||
        text.contains("lista archivos") ||
        text.contains("lista los archivos") ||
        text.contains("listar archivos") ||
        text.contains("muestra los archivos") ||
        text.contains("archivos principales") ||
        text.contains("archivos del proyecto")) {
      return "list_files";
    }

    return "unknown";
  }

  static String? extractProjectFilePath(String command) {
    var text = _normalizeCommand(command);
    final replacements = [
      "lee el archivo",
      "lee archivo",
      "lee",
      "leer el archivo",
      "leer archivo",
      "leer",
      "abre el archivo",
      "muestrame el archivo",
      "muéstrame el archivo",
      "muestrame",
      "muéstrame",
      "read file",
      "show file",
    ];
    for (final prefix in replacements) {
      if (text.startsWith(prefix)) {
        text = text.replaceFirst(prefix, "").trim();
        break;
      }
    }
    text = text
        .replaceAll(" punto ", ".")
        .replaceAll(" slash ", "/")
        .replaceAll(" barra ", "/")
        .replaceAll(RegExp(r'^[\s,.:;!?-]+|[\s,.:;!?-]+$'), "");
    if (text.isEmpty) return null;
    if (text == "readme") return "README.md";
    if (text == "pubspec") return "labvoice/pubspec.yaml";
    if (text == "main dart" ||
        text == "archivo principal de flutter" ||
        text == "principal de flutter" ||
        text == "main de flutter" ||
        text == "flutter main" ||
        text == "main flutter") {
      return "labvoice/lib/main.dart";
    }
    return text;
  }

  static bool _requestsDiagnostics(String text) {
    final asksForChecks = text.contains(
      RegExp(
        r'\b(prueba|pruebas|test|tests|diagnostico|diagnosticos|diagnóstico|diagnósticos)\b',
      ),
    );
    final asksToRun = text.contains(
      RegExp(
        r'\b(ejecuta|ejecutar|corre|correr|haz|hacer|lanza|lanzar|analiza|analizar|prueba|probar|run|execute|diagnose)\b',
      ),
    );
    return (asksForChecks && asksToRun) ||
        text.contains("run diagnostics") ||
        text.contains("run the tests") ||
        text.contains("run tests") ||
        text.contains("analiza y prueba");
  }

  static String summaryMode(String command) {
    final text = _normalizeCommand(command);
    if (text.contains("en detalle") ||
        text.contains("con detalle") ||
        text.contains("detallado") ||
        text.contains("diagnostico completo") ||
        text.contains("diagnóstico completo") ||
        text.contains("detalles tecnicos") ||
        text.contains("detalles técnicos") ||
        text.contains("para desarrollador") ||
        text.contains("in detail") ||
        text.contains("detailed") ||
        text.contains("full diagnostic") ||
        text.contains("technical details") ||
        text.contains("developer")) {
      return "detailed";
    }
    return "quick";
  }

  static bool looksLikeOperatorStatus(String command) =>
      _requestsOperatorStatus(_normalizeCommand(command));

  static bool _requestsOperatorStatus(String text) {
    final asksStatus =
        text.contains("estado") ||
        text.contains("estatus") ||
        text.contains("status") ||
        text.contains("state") ||
        text.contains("salud") ||
        text.contains("health") ||
        text.contains("operativo") ||
        text.contains("operational");
    final asksOperator =
        text.contains("operador") ||
        text.contains("operator") ||
        text.contains("iov") ||
        text.contains("osvoz") ||
        text.contains("sistema") ||
        text.contains("system") ||
        text.contains("core");
    return (asksStatus && asksOperator) ||
        text == "status" ||
        text == "estado" ||
        text == "estatus" ||
        text == "operador" ||
        text == "operator" ||
        text == "operativo" ||
        text == "operational" ||
        text.contains("como estas operador") ||
        text.contains("como estas sistema") ||
        text.contains("how are you operator") ||
        text.contains("operator status") ||
        text.contains("system status") ||
        text.contains("core status") ||
        text.contains("estado operativo");
  }

  static String _normalizeCommand(String command) {
    var text = command.toLowerCase().trim();
    const accents = {
      "á": "a",
      "é": "e",
      "í": "i",
      "ó": "o",
      "ú": "u",
      "ü": "u",
      "ñ": "n",
    };
    for (final entry in accents.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }
    text = text.replaceFirst(
      RegExp(
        r'^(?:ok(?:ay)?|oye|hey)?[\s,.:;!?-]*(?:iov|io\s*v|osvoz|os\s*voz)?[\s,.:;!?-]*',
      ),
      "",
    );
    return text.trim();
  }

  static bool requestsProjectContinuation(String command) {
    final text = _normalizeCommand(command);
    return text.contains("continuemos") ||
        text.contains("continúa") ||
        text.contains("continua") ||
        text.contains("proyecto de ayer") ||
        text.contains("resumen de lo que llevamos") ||
        text.contains("dame un resumen") ||
        text.contains("continue working") ||
        text.contains("summary");
  }

  static bool requestsVSCode(String command) {
    final text = _normalizeCommand(command);
    return text.contains("abre visual studio") ||
        text.contains("abre vs code") ||
        text.contains("open vs code") ||
        text.contains("open visual studio code") ||
        text.contains("open vscode");
  }

  static bool requestsYouTubeMusic(String command) {
    final text = _normalizeCommand(command);
    return text.contains("youtube") &&
        (text.contains("reproduce") ||
            text.contains("pon ") ||
            text.contains("ponme ") ||
            text.contains("play ") ||
            text.contains("canción") ||
            text.contains("cancion") ||
            text.contains("song") ||
            text.contains("música") ||
            text.contains("musica"));
  }

  static String extractYouTubeQuery(String command) {
    var text = _normalizeCommand(command);
    text = text
        .replaceAll("abre el navegador y", "")
        .replaceAll("abre navegador y", "")
        .replaceAll("abre vs code y", "")
        .replaceAll("abre vs code,", "")
        .replaceAll("abre vs code", "")
        .replaceAll("abre visual studio code y", "")
        .replaceAll("abre visual studio code,", "")
        .replaceAll("abre visual studio code", "")
        .replaceAll("open vs code and", "")
        .replaceAll("open vs code,", "")
        .replaceAll("open vs code", "")
        .replaceAll("open visual studio code and", "")
        .replaceAll("open visual studio code,", "")
        .replaceAll("open visual studio code", "")
        .replaceAll("abre youtube y", "")
        .replaceAll("en youtube", "")
        .replaceAll("youtube", "")
        .replaceAll("reproduce", "")
        .replaceAll("ponme", "")
        .replaceAll("pon", "")
        .replaceAll("play", "")
        .replaceAll("una canción de", "")
        .replaceAll("una cancion de", "")
        .replaceAll("canción de", "")
        .replaceAll("cancion de", "")
        .replaceAll("música de", "")
        .replaceAll("musica de", "")
        .replaceAll("song by", "")
        .replaceAll("music by", "");
    final stopMarkers = [
      " y que",
      " y continuemos",
      " continuemos",
      " y dame un resumen",
      " dame un resumen",
      " y dime en qué vamos",
      " y dime en que vamos",
      " dime en qué vamos",
      " dime en que vamos",
      " en qué vamos",
      " en que vamos",
      " and give me a summary",
      " give me a summary",
      " mientras",
      " while",
    ];
    for (final marker in stopMarkers) {
      final index = text.indexOf(marker);
      if (index >= 0) text = text.substring(0, index);
    }
    text = text
        .replaceAll(RegExp(r'\s+'), " ")
        .replaceAll(RegExp(r'^[\s,.:;!?-]+|[\s,.:;!?-]+$'), "")
        .trim();
    return text.isEmpty ? "music" : text;
  }
}
