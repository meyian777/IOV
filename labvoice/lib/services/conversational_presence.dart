enum ConversationalPresenceStage {
  received,
  securityCheck,
  working,
  almostThere,
}

class ConversationalPresence {
  static String cue({
    required ConversationalPresenceStage stage,
    required String actionName,
    required String language,
    int turn = 0,
  }) {
    final spanish = language == "es";
    final options = spanish
        ? _spanishOptions(stage, actionName)
        : _englishOptions(stage, actionName);
    return options[turn % options.length];
  }

  static List<String> progressMessages({
    required String actionName,
    required String language,
  }) {
    final spanish = language == "es";
    if (_isDiagnostics(actionName)) {
      return spanish
          ? const [
              "Sigo revisando las pruebas. Te aviso con lo importante.",
              "Ya casi tengo el resultado limpio.",
            ]
          : const [
              "I am still checking the tests. I will keep only what matters.",
              "Almost there. I am cleaning up the result.",
            ];
    }
    if (_isEditorAction(actionName)) {
      return spanish
          ? const [
              "Estoy revisando el cambio antes de tocar el proyecto.",
              "Sigo validando el contexto para no mover nada a ciegas.",
            ]
          : const [
              "I am checking the change before touching the project.",
              "Still validating the context so I do not move blindly.",
            ];
    }
    return spanish
        ? const ["Sigo en ello.", "Ya casi."]
        : const ["Still on it.", "Almost there."];
  }

  static List<String> _spanishOptions(
    ConversationalPresenceStage stage,
    String actionName,
  ) {
    switch (stage) {
      case ConversationalPresenceStage.received:
        if (_isDiagnostics(actionName)) {
          return const [
            "Recibido. Voy a ejecutar las pruebas y te diré solo lo esencial.",
            "Entendido. Reviso las pruebas y te resumo el resultado.",
          ];
        }
        if (_isOpenAction(actionName)) {
          return const ["Listo, lo abro.", "Voy con eso."];
        }
        return const ["Recibido. Lo preparo.", "Entendido, voy con eso."];
      case ConversationalPresenceStage.securityCheck:
        return const [
          "Antes de seguir, confirmo que eres tú.",
          "Voy a validar tu presencia antes de ejecutar.",
        ];
      case ConversationalPresenceStage.working:
        return const ["Estoy en ello.", "Sigo trabajando."];
      case ConversationalPresenceStage.almostThere:
        return const ["Ya casi.", "Estoy cerrando el resultado."];
    }
  }

  static List<String> _englishOptions(
    ConversationalPresenceStage stage,
    String actionName,
  ) {
    switch (stage) {
      case ConversationalPresenceStage.received:
        if (_isDiagnostics(actionName)) {
          return const [
            "Got it. I will run the tests and keep the summary short.",
            "Understood. I am checking the tests and will give you the essentials.",
          ];
        }
        if (_isOpenAction(actionName)) {
          return const ["Done, opening it.", "On it."];
        }
        return const [
          "Got it. I am preparing that.",
          "Understood, I am on it.",
        ];
      case ConversationalPresenceStage.securityCheck:
        return const [
          "Before I continue, I am confirming it is you.",
          "I am checking your presence before running this.",
        ];
      case ConversationalPresenceStage.working:
        return const ["I am on it.", "Still working."];
      case ConversationalPresenceStage.almostThere:
        return const ["Almost there.", "I am wrapping up the result."];
    }
  }

  static bool _isDiagnostics(String actionName) =>
      actionName == "RUN_DIAGNOSTICS";

  static bool _isOpenAction(String actionName) =>
      actionName == "OPEN_TERMINAL" ||
      actionName == "OPEN_VSCODE" ||
      actionName == "OPEN_BROWSER";

  static bool _isEditorAction(String actionName) =>
      actionName.contains("EDIT") || actionName.contains("FILE");
}
