class IntentEngine {

  static String detectIntent(String command) {

    final text = command.toLowerCase().trim();

    if (
      text.contains("abre visual studio") ||
      text.contains("abre vs code") ||
      text.contains("open vs code") ||
      text.contains("open visual studio code") ||
      text.contains("open vscode")
    ) {
      return "open_vscode";
    }

    if (
      text.contains("abre mi proyecto") ||
      text.contains("abre labvoice") ||
      text.contains("open project")
    ) {
      return "open_project";
    }

    if (
      text.contains("continúa donde me quedé") ||
      text.contains("continua donde me quede") ||
      text.contains("continua donde quede") ||
      text.contains("continuar proyecto") ||
      text.contains("retoma el proyecto") ||
      text.contains("seguir proyecto") ||
      text.contains("continue project")
    ) {
      return "continue_work";
    }

    if (
      text.contains("ejecuta flutter") ||
      text.contains("flutter run") ||
      text.contains("run flutter")
    ) {
      return "run_flutter";
    }

    if (
      text.contains("open terminal") ||
      text.contains("open terminal app") ||
      text.contains("launch terminal") ||
      text.contains("abre terminal")
    ) {
      return "open_terminal";
    }

    if (
      text.contains("list files") ||
      text.contains("show files") ||
      text.contains("project files")
    ) {
      return "list_files";
    }

    return "unknown";
  }
}