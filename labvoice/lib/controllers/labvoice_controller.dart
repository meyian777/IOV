import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/action_executor.dart';
import '../services/intent_engine.dart';
import '../services/labvoice_api.dart';
import '../services/language_manager.dart';
import '../services/project_memory.dart';
import '../services/session_memory.dart';
import '../services/voice_engine.dart';

class LabVoiceController extends ChangeNotifier {
  bool isListening = false;
  String selectedLanguageCode = "auto";
  String selectedLanguageName = "Automático";
  String heardCommand = "Todavía no he recibido ningún comando.";
  String response = "Ian, ¿qué vamos a construir hoy?";
  String detectedIntent = "Esperando un comando";
  String technicalAction = "Sin acciones pendientes";
  String securityLevel = "Seguro";

  String? _pendingConfirmationToken;
  String? _pendingActionName;

  String get activeLanguageName {
    if (selectedLanguageCode != "auto") return selectedLanguageName;
    return LanguageManager.profileForLanguage(
      LanguageManager.effectiveLanguage,
    ).name;
  }

  Map<String, String> get languages => {
    for (final entry in LanguageManager.profiles.entries)
      entry.value.name: entry.key,
  };

  Future<void> initialize() async {
    await VoiceEngine.setLanguage(LanguageManager.activeVoiceLocale);
    try {
      final project = await ProjectMemory.loadProjectState();
      final session = await SessionMemory.loadSessionState();
      response =
          "Buenos días, ${project.owner}. "
          "Proyecto activo: ${project.project}. "
          "Tarea actual: ${session.currentTask}. "
          "Última acción: ${session.lastAction}. "
          "Siguiente paso: ${session.nextAction}. "
          "¿Qué vamos a construir hoy?";
    } catch (error) {
      response = LanguageManager.text(
        "No pude recuperar la memoria: $error",
        "I could not recover memory: $error",
      );
    }
    notifyListeners();
  }

  Future<void> selectLanguage(String code) async {
    LanguageManager.setLanguage(code);
    await VoiceEngine.setLanguage(LanguageManager.activeVoiceLocale);
    selectedLanguageCode = code;
    selectedLanguageName = LanguageManager.current.name;
    response = LanguageManager.languageUpdated();
    notifyListeners();
    unawaited(VoiceEngine.speak(response));
  }

  void setListening(bool value) {
    isListening = value;
    if (value) {
      response = LanguageManager.listening();
      heardCommand = LanguageManager.text(
        "Escuchando el micrófono...",
        "Listening to the microphone...",
      );
      detectedIntent = "listening";
      technicalAction = "Speech recognition is active.";
    }
    notifyListeners();
  }

  Future<void> speechRecognitionError(String error) async {
    isListening = false;
    heardCommand = LanguageManager.text(
      "No se recibió ningún comando.",
      "No command was received.",
    );
    response = LanguageManager.text(
      "El reconocimiento de voz falló: $error",
      "Speech recognition failed: $error",
    );
    detectedIntent = "speech_recognition_error";
    technicalAction = error;
    securityLevel = "Blocked";
    notifyListeners();
  }

  void updatePartialTranscript(String text) {
    heardCommand = text;
    notifyListeners();
  }

  Future<void> microphoneUnavailable() async {
    await _update(
      heard: "Microphone unavailable.",
      response: LanguageManager.text(
        "No pude activar el micrófono, Ian.",
        "I could not activate the microphone, Ian.",
      ),
      intent: "microphone_error",
      action: "Check browser or system permissions.",
      security: "Secure",
    );
  }

  Future<void> processCommand(String rawCommand) async {
    if (LanguageManager.current.languageTag == "auto") {
      LanguageManager.alignToText(rawCommand);
      await VoiceEngine.setLanguage(LanguageManager.activeVoiceLocale);
    }

    final command = rawCommand.toLowerCase().trim();
    final intent = IntentEngine.detectIntent(command);

    if (intent == "stop_speaking") {
      await _stopSpeaking(rawCommand);
      return;
    }
    if (intent == "summarize_response") {
      await _summarizeResponse(rawCommand);
      return;
    }
    if (intent == "confirm_action") {
      await _confirmPendingAction(rawCommand);
      return;
    }
    if (intent == "cancel_action") {
      await _cancelPendingAction(rawCommand);
      return;
    }
    if (command.isEmpty) {
      await _update(
        heard: "No clear command detected.",
        response: LanguageManager.noClearCommand(),
        intent: "empty_command",
        action: "Waiting for a valid command.",
        security: "Secure",
      );
      return;
    }
    if (command.startsWith("chat ")) {
      await _runChat(rawCommand, command.replaceFirst("chat ", ""));
      return;
    }

    switch (intent) {
      case "labvoice_identity":
        await _labVoiceIdentity(rawCommand);
        return;
      case "creator_identity":
        await _creatorIdentity(rawCommand);
        return;
      case "founder_biography":
        await _founderBiography(rawCommand);
        return;
      case "inspect_project":
        await _inspectProject(rawCommand);
        return;
      case "run_diagnostics":
        await _runDiagnostics(rawCommand);
        return;
      case "open_vscode":
        await _requestAction(rawCommand, intent, "OPEN_VSCODE");
        return;
      case "open_project":
        await _requestAction(rawCommand, intent, "OPEN_PROJECT");
        return;
      case "continue_work":
        await _continueWork(rawCommand);
        return;
      case "run_flutter":
        await _requestAction(rawCommand, intent, "RUN_FLUTTER");
        return;
      case "open_terminal":
        await _requestAction(rawCommand, intent, "OPEN_TERMINAL");
        return;
      case "list_files":
        await _requestAction(rawCommand, intent, "LIST_FILES");
        return;
      default:
        await _runChat(rawCommand, rawCommand);
        return;
    }
  }

  Future<void> _creatorIdentity(String rawCommand) async {
    await _update(
      heard: rawCommand,
      response: LanguageManager.creatorIdentity(),
      intent: "creator_identity",
      action: "Presented official LabVoice founder identity.",
      security: "Public identity",
    );
  }

  Future<void> _labVoiceIdentity(String rawCommand) async {
    await _update(
      heard: rawCommand,
      response: LanguageManager.labVoiceIdentity(),
      intent: "labvoice_identity",
      action: "Presented LabVoice system identity.",
      security: "Public identity",
    );
  }

  Future<void> _founderBiography(String rawCommand) async {
    await _update(
      heard: rawCommand,
      response: LanguageManager.founderBiography(),
      intent: "founder_biography",
      action: "Presented approved public founder biography.",
      security: "Public identity",
    );
  }

  Future<void> _stopSpeaking(String rawCommand) async {
    await VoiceEngine.stop();
    heardCommand = rawCommand;
    response = LanguageManager.text("Voz detenida.", "Voice stopped.");
    detectedIntent = "stop_speaking";
    technicalAction = "Audio playback stopped.";
    securityLevel = "Secure";
    notifyListeners();
  }

  Future<void> _summarizeResponse(String rawCommand) async {
    final previousResponse = response;
    try {
      final instruction = LanguageManager.isSpanish
          ? "Resume en máximo dos frases esta respuesta, conservando solo lo "
                "esencial:\n\n$previousResponse"
          : "Summarize this response in at most two sentences, preserving only "
                "the essential information:\n\n$previousResponse";
      final result = await LabVoiceApi.chat(
        instruction,
        language: LanguageManager.effectiveLanguage,
      );
      await _update(
        heard: rawCommand,
        response: result["response"] ?? previousResponse,
        intent: "summarize_response",
        action: "Previous response summarized.",
        security: "Secure",
      );
    } on LabVoiceApiException catch (error) {
      await _update(
        heard: rawCommand,
        response: error.message,
        intent: "backend_error",
        action: error.code ?? "summary_failed",
        security: "Blocked",
      );
    }
  }

  Future<void> _inspectProject(String rawCommand) async {
    await _update(
      heard: rawCommand,
      response: LanguageManager.text(
        "Estoy inspeccionando el proyecto activo.",
        "Inspecting the active project.",
      ),
      intent: "inspect_project",
      action: "Reading project metadata and Git status.",
      security: "Read only",
    );
    try {
      final result = await ActionExecutor.inspectProject();
      final project = result["project"] as Map<String, dynamic>?;
      final technologies = (project?["technologies"] as List?) ?? [];
      await _update(
        heard: rawCommand,
        response: LanguageManager.text(
          "Inspección completada. Encontré ${project?["file_count"] ?? 0} archivos y las tecnologías ${technologies.join(", ")}.",
          result["message"] ?? "Project inspection completed.",
        ),
        intent: "inspect_project",
        action: "PROJECT_INSPECT completed.",
        security: "Read only",
      );
    } catch (error) {
      await _failure(
        rawCommand,
        LanguageManager.text(
          "No pude inspeccionar el proyecto.",
          "I could not inspect the project.",
        ),
        error,
        "Read only",
      );
    }
  }

  Future<void> _runDiagnostics(String rawCommand) async {
    await _update(
      heard: rawCommand,
      response: LanguageManager.text(
        "Estoy ejecutando el análisis y las pruebas del proyecto.",
        "Running project analysis and tests.",
      ),
      intent: "run_diagnostics",
      action: "Executing approved diagnostic tools.",
      security: "Controlled execution",
    );
    try {
      final result = await ActionExecutor.runDiagnostics();
      final summary = result["summary"] as Map<String, dynamic>?;
      final failed = summary?["failed"] ?? 0;
      await _update(
        heard: rawCommand,
        response: LanguageManager.text(
          "Diagnóstico completado: ${summary?["passed"] ?? 0} comprobaciones correctas y $failed con errores.",
          result["message"] ?? "Project diagnostics completed.",
        ),
        intent: "run_diagnostics",
        action: failed == 0
            ? "All diagnostic checks passed."
            : "$failed diagnostic checks require attention.",
        security: "Controlled execution",
      );
    } catch (error) {
      await _failure(
        rawCommand,
        LanguageManager.text(
          "No pude completar el diagnóstico del proyecto.",
          "I could not complete the project diagnostics.",
        ),
        error,
        "Controlled execution",
      );
    }
  }

  Future<void> _continueWork(String rawCommand) async {
    try {
      final session = await SessionMemory.loadSessionState();
      await _update(
        heard: rawCommand,
        response: LanguageManager.text(
          "Proyecto activo: ${session.activeProject}. Tarea actual: ${session.currentTask}. Última acción: ${session.lastAction}. Siguiente paso: ${session.nextAction}.",
          "Active project: ${session.activeProject}. Current task: ${session.currentTask}. Last action: ${session.lastAction}. Next action: ${session.nextAction}.",
        ),
        intent: "continue_work",
        action: "Recovered persistent session from the backend.",
        security: "Read only",
      );
    } catch (error) {
      await _failure(
        rawCommand,
        LanguageManager.text(
          "No pude recuperar la sesión guardada.",
          "I could not recover the saved session.",
        ),
        error,
        "Read only",
      );
    }
  }

  Future<void> _runChat(String rawCommand, String message) async {
    try {
      final result = await LabVoiceApi.chat(
        message,
        language: LanguageManager.effectiveLanguage,
      );
      await _update(
        heard: rawCommand,
        response: result["response"] ?? "I could not produce a response.",
        intent: "chat",
        action: "AI conversation",
        security: "Secure",
      );
    } on LabVoiceApiException catch (error) {
      await _update(
        heard: rawCommand,
        response: error.message,
        intent: "backend_error",
        action: error.code ?? "chat_failed",
        security: "Blocked",
      );
    }
  }

  Future<void> _requestAction(
    String rawCommand,
    String intent,
    String actionName,
  ) async {
    try {
      final result = await ActionExecutor.request(actionName);
      if (result["requires_confirmation"] == true) {
        _pendingConfirmationToken = result["confirmation_token"];
        _pendingActionName = actionName;
        await _update(
          heard: rawCommand,
          response: LanguageManager.confirmationRequired(actionName),
          intent: intent,
          action: "$actionName is waiting for confirmation.",
          security: result["policy"]?["risk"] ?? "Confirmation required",
        );
        return;
      }
      await _update(
        heard: rawCommand,
        response: LanguageManager.text(
          LanguageManager.actionCompleted(actionName),
          result["message"] ?? "$actionName completed.",
        ),
        intent: intent,
        action: "$actionName executed.",
        security: result["policy"]?["risk"] ?? "Controlled",
      );
    } catch (error) {
      await _failure(
        rawCommand,
        LanguageManager.backendError(),
        error,
        "Blocked",
      );
    }
  }

  Future<void> _confirmPendingAction(String rawCommand) async {
    final token = _pendingConfirmationToken;
    final actionName = _pendingActionName;
    if (token == null || actionName == null) {
      await _update(
        heard: rawCommand,
        response: LanguageManager.text(
          "No hay ninguna acción pendiente para confirmar.",
          "There is no pending action to confirm.",
        ),
        intent: "confirm_action",
        action: "No pending confirmation.",
        security: "Secure",
      );
      return;
    }
    try {
      final result = await ActionExecutor.confirm(token);
      _clearPendingAction();
      await _update(
        heard: rawCommand,
        response: LanguageManager.text(
          LanguageManager.actionCompleted(actionName),
          result["message"] ?? "$actionName completed.",
        ),
        intent: "confirm_action",
        action: "$actionName confirmed and executed.",
        security: "Confirmed",
      );
    } on LabVoiceApiException catch (error) {
      _clearPendingAction();
      await _update(
        heard: rawCommand,
        response: error.message,
        intent: "confirm_action",
        action: error.code ?? "confirmation_failed",
        security: "Blocked",
      );
    }
  }

  Future<void> _cancelPendingAction(String rawCommand) async {
    final token = _pendingConfirmationToken;
    if (token == null) {
      await _update(
        heard: rawCommand,
        response: LanguageManager.text(
          "No hay ninguna acción pendiente para cancelar.",
          "There is no pending action to cancel.",
        ),
        intent: "cancel_action",
        action: "No pending confirmation.",
        security: "Secure",
      );
      return;
    }
    try {
      final result = await ActionExecutor.cancel(token);
      _clearPendingAction();
      await _update(
        heard: rawCommand,
        response: LanguageManager.text(
          "Acción pendiente cancelada.",
          result["message"] ?? "Pending action canceled.",
        ),
        intent: "cancel_action",
        action: "Pending action canceled.",
        security: "Secure",
      );
    } on LabVoiceApiException catch (error) {
      _clearPendingAction();
      await _update(
        heard: rawCommand,
        response: error.message,
        intent: "cancel_action",
        action: error.code ?? "cancel_failed",
        security: "Blocked",
      );
    }
  }

  void _clearPendingAction() {
    _pendingConfirmationToken = null;
    _pendingActionName = null;
  }

  Future<void> _failure(
    String heard,
    String message,
    Object error,
    String security,
  ) => _update(
    heard: heard,
    response: message,
    intent: "backend_error",
    action: error.toString(),
    security: security,
  );

  Future<void> _update({
    required String heard,
    required String response,
    required String intent,
    required String action,
    required String security,
  }) async {
    heardCommand = heard;
    this.response = response;
    detectedIntent = intent;
    technicalAction = action;
    securityLevel = security;
    notifyListeners();
    unawaited(_speakResponse(response));
  }

  Future<void> _speakResponse(String text) async {
    final error = await VoiceEngine.speak(text);
    if (error == null) return;
    technicalAction = "Voice playback failed: $error";
    notifyListeners();
  }
}
