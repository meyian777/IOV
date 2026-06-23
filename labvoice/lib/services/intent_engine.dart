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
      return "labvoice_identity";
    }

    if (text.contains("quién te creó") ||
        text.contains("quien te creo") ||
        text.contains("quién es tu creador") ||
        text.contains("quien es tu creador") ||
        text.contains("quién es tu fundador") ||
        text.contains("quien es tu fundador") ||
        text.contains("quién creó labvoice") ||
        text.contains("quien creo labvoice") ||
        text.contains("who created you") ||
        text.contains("who made you") ||
        text.contains("who is your creator") ||
        text.contains("who is your founder") ||
        text.contains("who founded labvoice")) {
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

    if (text.contains("ejecuta diagnosticos") ||
        text.contains("ejecuta diagnósticos") ||
        text.contains("ejecuta las pruebas") ||
        text.contains("corre las pruebas") ||
        text.contains("analiza y prueba") ||
        text.contains("run diagnostics") ||
        text.contains("run tests")) {
      return "run_diagnostics";
    }

    if (text.contains("analiza el proyecto") ||
        text.contains("inspecciona el proyecto") ||
        text.contains("estado del proyecto") ||
        text.contains("analyze project") ||
        text.contains("inspect project") ||
        text.contains("project status")) {
      return "inspect_project";
    }

    if (text.contains("abre visual studio") ||
        text.contains("abre vs code") ||
        text.contains("open vs code") ||
        text.contains("open visual studio code") ||
        text.contains("open vscode")) {
      return "open_vscode";
    }

    if (text.contains("abre mi proyecto") ||
        text.contains("abre labvoice") ||
        text.contains("open project")) {
      return "open_project";
    }

    if (text.contains("continúa donde me quedé") ||
        text.contains("continua donde me quede") ||
        text.contains("continua donde quede") ||
        text.contains("continuar proyecto") ||
        text.contains("retoma el proyecto") ||
        text.contains("seguir proyecto") ||
        text.contains("continue project")) {
      return "continue_work";
    }

    if (text.contains("ejecuta flutter") ||
        text.contains("flutter run") ||
        text.contains("run flutter")) {
      return "run_flutter";
    }

    if (text.contains("open terminal") ||
        text.contains("open terminal app") ||
        text.contains("launch terminal") ||
        text.contains("abre terminal")) {
      return "open_terminal";
    }

    if (text.contains("list files") ||
        text.contains("show files") ||
        text.contains("project files")) {
      return "list_files";
    }

    return "unknown";
  }

  static String _normalizeCommand(String command) {
    var text = command.toLowerCase().trim();
    text = text.replaceFirst(
      RegExp(
        r'^(?:ok(?:ay)?|oye|hey)?[\s,.:;!?-]*(?:lab\s*voice|labvoice)?[\s,.:;!?-]*',
      ),
      "",
    );
    return text.trim();
  }
}
