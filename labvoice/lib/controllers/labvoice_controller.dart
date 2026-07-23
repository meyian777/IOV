import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/action_executor.dart';
import '../services/audit_log_service.dart';
import '../services/conversational_presence.dart';
import '../services/device_trust_service.dart';
import '../services/intent_engine.dart';
import '../services/intent_orchestrator.dart';
import '../services/labvoice_api.dart';
import '../services/language_manager.dart';
import '../services/operator_capability_service.dart';
import '../services/operator_status_service.dart';
import '../services/project_memory.dart';
import '../services/semantic_code_narrator.dart';
import '../services/session_memory.dart';
import '../services/voice_engine.dart';
import '../services/voice_latency_metrics.dart';

class _OrchestratedTaskResult {
  final String label;
  final bool success;
  final String message;

  const _OrchestratedTaskResult({
    required this.label,
    required this.success,
    required this.message,
  });
}

class OSvozController extends ChangeNotifier {
  bool isListening = false;
  String selectedLanguageCode = "auto";
  String selectedLanguageName = "Automático";
  String heardCommand = "Todavía no he recibido ningún comando.";
  String response = "Ian, ¿qué vamos a construir hoy?";
  String detectedIntent = "Esperando un comando";
  String technicalAction = "Sin acciones pendientes";
  String securityLevel = "Seguro";
  String operatorStatus = "Operador listo";
  String activeCodePath = "";
  String activeCodeLanguage = "";
  String activeCodePreview = "";

  bool get hasActiveCodePreview =>
      activeCodePath.isNotEmpty && activeCodePreview.isNotEmpty;

  String? _pendingConfirmationToken;
  String? _pendingActionName;
  String? _pendingEditOperationId;
  Timer? _progressTimer;
  int _progressGeneration = 0;
  int _presenceTurn = 0;
  DateTime? _commandStartedAt;
  final SemanticCodeNarrator _semanticNarrator = SemanticCodeNarrator();

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

  void ambientSpeechIgnored(String transcript) {
    isListening = false;
    heardCommand = transcript;
    detectedIntent = "ambient_speech_ignored";
    technicalAction =
        "Speech was not addressed to OSvoz and was safely ignored.";
    securityLevel = "Wake word required";
    notifyListeners();
  }

  Future<void> speechRecognitionError(String error) async {
    final safeError = _safeSpeechRecognitionError(error);
    isListening = false;
    heardCommand = LanguageManager.text(
      "No se recibió ningún comando.",
      "No command was received.",
    );
    response = LanguageManager.text(
      "El reconocimiento de voz falló: $safeError",
      "Speech recognition failed: $safeError",
    );
    detectedIntent = "speech_recognition_error";
    technicalAction = safeError;
    securityLevel = "Blocked";
    notifyListeners();
    unawaited(_speakResponse(response));
  }

  static String _safeSpeechRecognitionError(String error) {
    final normalized = error.replaceAll(RegExp(r"\s+"), " ").trim();
    if (normalized.isEmpty) {
      return LanguageManager.text(
        "No detecté voz. Intenta de nuevo.",
        "I did not detect speech. Try again.",
      );
    }
    final lower = normalized.toLowerCase();
    if (lower.contains("ggml_") ||
        lower.contains("_rsets_init") ||
        lower.contains("libggml") ||
        lower.contains("load_backend") ||
        lower.contains("/opt/homebrew") ||
        lower.contains("metal_device") ||
        lower.contains("gpu name") ||
        lower.contains("failed to initialize whisper context") ||
        lower.contains("local whisper could not initialize")) {
      return LanguageManager.text(
        "Whisper local no pudo iniciar. Intenta de nuevo; usaré reconocimiento nativo como respaldo.",
        "Local Whisper could not start. Try again; I will use native recognition as backup.",
      );
    }
    if (lower.contains("no speech")) {
      return LanguageManager.text(
        "No detecté voz. Intenta de nuevo.",
        "I did not detect speech. Try again.",
      );
    }
    if (normalized.length <= 180) return normalized;
    return "${normalized.substring(0, 177)}...";
  }

  void updatePartialTranscript(String text) {
    heardCommand = text;
    notifyListeners();
  }

  void processingCapturedVoice() {
    final feedbackStopwatch = Stopwatch()..start();
    isListening = false;
    response = LanguageManager.text(
      "Procesando tu voz...",
      "Processing your voice...",
    );
    detectedIntent = "voice_processing";
    technicalAction = "Audio captured; transcription is running.";
    securityLevel = "Secure";
    notifyListeners();
    feedbackStopwatch.stop();
    VoiceLatencyMetrics.record("feedback_ms", feedbackStopwatch.elapsed);
    // Do not synthesize speech here. Speaking while Whisper is transcribing marks
    // the user's captured command as app echo and prevents interpretation.
  }

  void narrationControlFeedback({
    required String heard,
    required String message,
    required String control,
  }) {
    heardCommand = heard;
    response = message;
    detectedIntent = "narration_control_$control";
    technicalAction = "Local narration control event: $control.";
    securityLevel = "Local control";
    notifyListeners();
  }

  Future<void> microphoneUnavailable() async {
    await _update(
      heard: "Microphone unavailable.",
      response: LanguageManager.text(
        "No pude activar el micrófono, Ian. Revisa Ajustes del Sistema > Privacidad y seguridad > Micrófono, habilita OSvoz y reinicia la app.",
        "I could not activate the microphone, Ian. Check System Settings > Privacy & Security > Microphone, enable OSvoz and restart the app.",
      ),
      intent: "microphone_error",
      action: "Check macOS microphone permission and restart OSvoz.",
      security: "Secure",
    );
  }

  Future<void> processCommand(String rawCommand) async {
    _commandStartedAt = DateTime.now();
    final languageStopwatch = Stopwatch()..start();
    LanguageManager.alignToText(rawCommand);
    languageStopwatch.stop();
    VoiceLatencyMetrics.record(
      "language_detection_ms",
      languageStopwatch.elapsed,
    );
    await VoiceEngine.setLanguage(LanguageManager.activeVoiceLocale);
    selectedLanguageCode = LanguageManager.current.recognitionLocale ?? "auto";
    selectedLanguageName = LanguageManager.current.name;

    final command = rawCommand.toLowerCase().trim();
    final intentStopwatch = Stopwatch()..start();
    final intent = IntentEngine.detectIntent(command);
    intentStopwatch.stop();
    VoiceLatencyMetrics.record("intent_ms", intentStopwatch.elapsed);

    if (intent == "stop_speaking") {
      await _stopSpeaking(rawCommand);
      return;
    }
    if (intent == "summarize_response") {
      await _summarizeResponse(rawCommand);
      return;
    }
    if (intent == "confirm_action") {
      if (_pendingEditOperationId != null) {
        await _confirmPendingEdit(rawCommand);
        return;
      }
      await _confirmPendingAction(rawCommand);
      return;
    }
    if (intent == "cancel_action") {
      if (_pendingEditOperationId != null) {
        await _cancelPendingEdit(rawCommand);
        return;
      }
      await _cancelPendingAction(rawCommand);
      return;
    }
    if (_requestsPendingExecution(command)) {
      if (_pendingEditOperationId != null) {
        await _confirmPendingEdit(rawCommand);
        return;
      }
      if (_pendingConfirmationToken != null) {
        await _confirmPendingAction(rawCommand);
        return;
      }
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

    final orchestrationStopwatch = Stopwatch()..start();
    final plan = IntentOrchestrator.plan(rawCommand);
    orchestrationStopwatch.stop();
    VoiceLatencyMetrics.record(
      "orchestration_ms",
      orchestrationStopwatch.elapsed,
    );
    if (plan.tasks.isNotEmpty) {
      await _runOrchestratedPlan(rawCommand, plan);
      return;
    }
    if (intent == "operator_status" ||
        IntentEngine.looksLikeOperatorStatus(rawCommand)) {
      await _operatorStatus(rawCommand);
      return;
    }

    switch (intent) {
      case "osvoz_identity":
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
      case "read_project_file":
        await _readProjectFile(rawCommand);
        return;
      case "explain_active_file":
        await _explainActiveFile(rawCommand);
        return;
      case "continue_semantic_narration":
        await _continueSemanticNarration(rawCommand);
        return;
      case "summarize_semantic_narration":
        await _summarizeSemanticNarration(rawCommand);
        return;
      case "run_diagnostics":
        await _runDiagnostics(rawCommand);
        return;
      case "edit_active_file":
        await _prepareEdit(rawCommand);
        return;
      case "undo_edit":
        await _undoLastEdit(rawCommand);
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
      case "open_browser":
        await _openBrowser(rawCommand);
        return;
      case "youtube_music":
        await _openYouTubeMusic(rawCommand);
        return;
      case "skip_ad":
        await _skipAdGuidance(rawCommand);
        return;
      case "open_terminal":
        await _requestAction(rawCommand, intent, "OPEN_TERMINAL");
        return;
      case "list_files":
        await _listProjectFiles(rawCommand);
        return;
      default:
        if (IntentEngine.looksLikeOperatorStatus(rawCommand)) {
          await _operatorStatus(rawCommand);
          return;
        }
        if (IntentOrchestrator.looksLikeMusicRequest(rawCommand)) {
          await _musicNeedsClarification(rawCommand);
          return;
        }
        await _runChat(rawCommand, rawCommand);
        return;
    }
  }

  Future<void> _creatorIdentity(String rawCommand) async {
    await _update(
      heard: rawCommand,
      response: LanguageManager.creatorIdentity(),
      intent: "creator_identity",
      action: "Presented official OSvoz founder identity.",
      security: "Public identity",
    );
  }

  bool _requestsPendingExecution(String command) =>
      command == "ejecutalo" ||
      command == "ejecútalo" ||
      command == "hazlo" ||
      command == "dale" ||
      command == "aplicalo" ||
      command == "aplícalo" ||
      command == "execute it" ||
      command == "do it" ||
      command == "go ahead";

  Future<void> _labVoiceIdentity(String rawCommand) async {
    await _update(
      heard: rawCommand,
      response: LanguageManager.labVoiceIdentity(),
      intent: "osvoz_identity",
      action: "Presented OSvoz system identity.",
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

  Future<void> _operatorStatus(String rawCommand) async {
    _showStatus(
      heard: rawCommand,
      response: LanguageManager.text(
        "Revisando estado operativo.",
        "Checking operator status.",
      ),
      intent: "operator_status_pending",
      action: "Fetching /core/operator-status.",
      security: "Read only audit event",
      operatorStatus: "Revisando operador",
    );
    try {
      final summaryMode = IntentEngine.summaryMode(rawCommand);
      final status = await OperatorStatusService.fetch(
        summaryMode: summaryMode,
      );
      await _update(
        heard: rawCommand,
        response: status.spokenSummary,
        intent: "operator_status",
        action:
            "Operator status checked in ${status.summaryMode} mode: ${status.implementedCount} ready, ${status.partialCount} partial.",
        security: status.auditValid ? "Audited read only" : "Audit degraded",
        operatorStatus: status.ready ? "Operador listo" : "Operador parcial",
      );
    } on OSvozApiException catch (error) {
      await _update(
        heard: rawCommand,
        response: _friendlyApiError(error),
        intent: "operator_status_failed",
        action: error.code ?? "operator_status_failed",
        security: "Blocked",
        operatorStatus: "No pude revisar el operador",
      );
    }
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
      final result = await OSvozApi.chat(
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
    } on OSvozApiException catch (error) {
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
        "Estoy revisando el proyecto activo.",
        "Checking the active project.",
      ),
      intent: "inspect_project",
      action: "Reading project metadata.",
      security: "Read only",
    );
    try {
      final result = await ActionExecutor.inspectProject();
      final project = result["project"] as Map<String, dynamic>?;
      final technologies = (project?["technologies"] as List?) ?? [];
      final explanation = result["explanation"] as Map<String, dynamic>?;
      await _update(
        heard: rawCommand,
        response: LanguageManager.text(
          "Proyecto activo: ${project?["name"] ?? "ian_labvoice"}. "
          "Archivos visibles: ${project?["file_count"] ?? 0}. "
          "Tecnologías: ${technologies.isEmpty ? "pendiente" : technologies.join(", ")}. "
          "Siguiente paso sugerido: ${explanation?["next_action"] ?? "probar comandos básicos"}.",
          result["message"] ?? "Project inspection completed.",
        ),
        intent: "inspect_project",
        action: "PROJECT_INSPECT completed without diagnostics.",
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

  Future<void> _listProjectFiles(String rawCommand) async {
    await _update(
      heard: rawCommand,
      response: "Estoy listando archivos seguros del proyecto.",
      intent: "list_files",
      action: "Reading project file index through File Access Layer.",
      security: "Read only",
    );
    try {
      final result = await OSvozApi.listProjectFiles(limit: 18);
      final directories = (result["directories"] as List?) ?? [];
      final files = (result["files"] as List?) ?? [];
      final directoryText = directories.take(5).join(", ");
      final fileText = files
          .take(8)
          .map(
            (file) => file is Map ? file["path"].toString() : file.toString(),
          )
          .join(", ");
      final parts = [
        if (directoryText.isNotEmpty) "Carpetas: $directoryText.",
        if (fileText.isNotEmpty) "Archivos: $fileText.",
      ];
      await _update(
        heard: rawCommand,
        response: parts.isEmpty
            ? "No encontré archivos visibles en el proyecto."
            : parts.join(" "),
        intent: "list_files",
        action: "Listed read-only project files.",
        security: result["permission"]?.toString() ?? "Read only",
      );
    } on OSvozApiException catch (error) {
      await _update(
        heard: rawCommand,
        response: error.message,
        intent: "list_files_failed",
        action: error.code ?? "file_list_failed",
        security: "Blocked",
      );
    }
  }

  Future<void> _readProjectFile(String rawCommand) async {
    final path = IntentEngine.extractProjectFilePath(rawCommand);
    if (path == null) {
      await _update(
        heard: rawCommand,
        response: "Dime qué archivo quieres leer, por ejemplo: lee README.",
        intent: "read_project_file",
        action: "Missing project-relative file path.",
        security: "Read only",
      );
      return;
    }
    await _update(
      heard: rawCommand,
      response: "Estoy leyendo $path en modo seguro.",
      intent: "read_project_file",
      action: "Reading project file through File Access Layer.",
      security: "Read only",
    );
    try {
      final result = await OSvozApi.readProjectFile(path);
      final content = result["content"]?.toString() ?? "";
      final preview = _compactFilePreview(content);
      await _update(
        heard: rawCommand,
        response: "Leí ${result["path"]}. Resumen rápido: $preview",
        intent: "read_project_file",
        action: "Read safe project text file.",
        security: result["permission"]?.toString() ?? "Read only",
      );
    } on OSvozApiException catch (error) {
      await _update(
        heard: rawCommand,
        response: error.message,
        intent: "read_project_file_failed",
        action: error.code ?? "file_read_failed",
        security: "Blocked",
      );
    }
  }

  Future<void> _explainActiveFile(String rawCommand) async {
    try {
      final result = await OSvozApi.getEditorContext();
      final context = result["context"] as Map<String, dynamic>?;
      final connected = context?["connected"] == true;
      final source = context?["document_text"]?.toString() ?? "";
      final path =
          context?["relative_file"]?.toString() ??
          context?["active_file"]?.toString() ??
          "archivo activo";
      final language = context?["language_id"]?.toString() ?? "código";
      if (!connected || source.trim().isEmpty) {
        throw const OSvozApiException(
          "VS Code no compartió un archivo activo con contenido.",
          code: "editor_context_unavailable",
        );
      }
      final tree = SemanticCodeAnalyzer.analyze(
        path: path,
        language: language,
        source: source,
      );
      activeCodePath = path;
      activeCodeLanguage = language;
      activeCodePreview = source.split(RegExp(r'\r?\n')).take(42).join('\n');
      await _update(
        heard: rawCommand,
        response: _semanticNarrator.start(tree),
        intent: "semantic_narration",
        action:
            "Semantic tree created with ${tree.nodes.length} critical nodes; cursor=${_semanticNarrator.cursor}.",
        security: "Read only",
      );
    } on OSvozApiException catch (error) {
      await _update(
        heard: rawCommand,
        response: _friendlyApiError(error),
        intent: "semantic_narration_failed",
        action: error.code ?? "semantic_narration_failed",
        security: "Blocked",
      );
    }
  }

  Future<void> _continueSemanticNarration(String rawCommand) async {
    await _update(
      heard: rawCommand,
      response: _semanticNarrator.next(),
      intent: "semantic_narration_continue",
      action:
          "Semantic narration continued at cursor=${_semanticNarrator.cursor}.",
      security: "Read only",
    );
  }

  Future<void> _summarizeSemanticNarration(String rawCommand) async {
    await _update(
      heard: rawCommand,
      response: _semanticNarrator.summary(),
      intent: "semantic_narration_summary",
      action:
          "Semantic narration summarized at cursor=${_semanticNarrator.cursor}.",
      security: "Read only",
    );
  }

  String _compactFilePreview(String content) {
    final cleaned = content
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .take(6)
        .join(" ");
    if (cleaned.length <= 420) return cleaned;
    return "${cleaned.substring(0, 420)}...";
  }

  Future<void> _runDiagnostics(String rawCommand) async {
    try {
      final result = await _executeActionWithVisibleSecurity(
        actionName: "RUN_DIAGNOSTICS",
        rawCommand: rawCommand,
        intent: "run_diagnostics",
        execute: ActionExecutor.runDiagnostics,
      );
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

  Future<void> _openBrowser(String rawCommand) async {
    await _openBrowserUrl(
      rawCommand,
      "https://www.google.com",
      LanguageManager.text("Abrí el navegador.", "I opened the browser."),
    );
  }

  Future<void> _openYouTubeMusic(String rawCommand) async {
    final query = IntentEngine.extractYouTubeQuery(rawCommand);
    final wantsSummary = IntentEngine.requestsProjectContinuation(rawCommand);
    await _update(
      heard: rawCommand,
      response: LanguageManager.text(
        "Abriendo YouTube e intentando reproducir $query.",
        "Opening YouTube and trying to play $query.",
      ),
      intent: "youtube_music",
      action: "Opening YouTube playback attempt.",
      security: "Routine browser action",
    );
    try {
      final result = await OSvozApi.playYouTube(query);
      final playAttempted = result["play_attempted"] == true;
      String response = playAttempted
          ? LanguageManager.text(
              "Abrí YouTube e intenté reproducir el primer resultado de $query.",
              "I opened YouTube and tried to play the first result for $query.",
            )
          : LanguageManager.text(
              "Abrí YouTube con la búsqueda de $query. El navegador no permitió reproducción automática todavía.",
              "I opened YouTube search for $query. The browser did not allow autoplay yet.",
            );
      if (wantsSummary) {
        response = "$response ${await _localProjectSummary()}";
      }
      await _update(
        heard: rawCommand,
        response: response,
        intent: "youtube_music",
        action: result["message"]?.toString() ?? "YouTube playback requested.",
        security: "Routine browser action",
      );
    } on OSvozApiException catch (error) {
      await _update(
        heard: rawCommand,
        response: _friendlyApiError(error),
        intent: "youtube_music_failed",
        action: error.code ?? "youtube_music_failed",
        security: "Blocked",
      );
    }
  }

  Future<void> _runOrchestratedPlan(
    String rawCommand,
    OSvozIntentPlan plan,
  ) async {
    final hasMedia = plan.tasks.any(
      (task) => task.type == OSvozTaskType.playMedia,
    );
    if (hasMedia) {
      final mediaTask = plan.tasks.firstWhere(
        (task) => task.type == OSvozTaskType.playMedia,
      );
      final query = mediaTask.parameters["query"] ?? "la música";
      await _speakResponse(
        LanguageManager.text(
          "Listo, pongo $query. Dejo los detalles en pantalla.",
          "Done, playing $query. I will leave the details on screen.",
        ),
      );
    }

    _showStatus(
      heard: rawCommand,
      response: LanguageManager.text(
        "Entendido. Estoy ejecutando ${plan.tasks.length} tareas.",
        "Understood. I am running ${plan.tasks.length} tasks.",
      ),
      intent: plan.intent,
      action: plan.toJson().toString(),
      security: "Routine orchestrated action",
    );

    final parallelTasks = plan.tasks
        .where((task) => task.canRunInParallel)
        .toList(growable: false);
    final sequentialTasks = plan.tasks
        .where((task) => !task.canRunInParallel)
        .toList(growable: false);
    final results = <_OrchestratedTaskResult>[];
    final executionStopwatch = Stopwatch()..start();

    if (parallelTasks.isNotEmpty) {
      _showStatus(
        heard: rawCommand,
        response: LanguageManager.text(
          "Voy con ${parallelTasks.length} tarea${parallelTasks.length == 1 ? "" : "s"} rápida${parallelTasks.length == 1 ? "" : "s"}.",
          "Running ${parallelTasks.length} quick task${parallelTasks.length == 1 ? "" : "s"}.",
        ),
        intent: "compound_task_progress",
        action: parallelTasks.map(_taskProgressLabel).join(", "),
        security: "Routine orchestrated action",
      );
      results.addAll(
        await Future.wait(
          parallelTasks.map((task) => _runOrchestratedTask(task)),
        ),
      );
    }
    for (var index = 0; index < sequentialTasks.length; index++) {
      final task = sequentialTasks[index];
      _showStatus(
        heard: rawCommand,
        response: LanguageManager.text(
          "Paso ${index + 1} de ${sequentialTasks.length}: ${_taskProgressLabel(task)}.",
          "Step ${index + 1} of ${sequentialTasks.length}: ${_taskProgressLabel(task)}.",
        ),
        intent: "compound_task_progress",
        action: task.toJson().toString(),
        security: "Routine orchestrated action",
      );
      results.add(await _runOrchestratedTask(task));
    }
    executionStopwatch.stop();
    VoiceLatencyMetrics.record("execution_ms", executionStopwatch.elapsed);

    final response = plan.executiveSummary
        ? _executiveOrchestratedResponse(results)
        : _orchestratedResponse(results);
    await _update(
      heard: rawCommand,
      response: response,
      intent: plan.intent,
      action: results
          .map((result) => "${result.label}: ${result.message}")
          .join(" | "),
      security: results.any((result) => !result.success)
          ? "Partial completion"
          : "Routine orchestrated action",
      speak: !hasMedia,
    );
  }

  Future<_OrchestratedTaskResult> _runOrchestratedTask(OSvozTask task) async {
    switch (task.type) {
      case OSvozTaskType.openApp:
        final action = task.target == "terminal"
            ? "OPEN_TERMINAL"
            : "OPEN_VSCODE";
        final result = await _safeAction(action);
        return _OrchestratedTaskResult(
          label: task.target == "terminal" ? "Terminal" : "VS Code",
          success: result["success"] == true,
          message: result["message"]?.toString() ?? action,
        );
      case OSvozTaskType.openBrowser:
        try {
          final result = await OSvozApi.openBrowserUrl(
            "https://www.google.com",
          );
          return _OrchestratedTaskResult(
            label: "Navegador",
            success: result["success"] == true,
            message: result["message"]?.toString() ?? "Browser opened.",
          );
        } catch (error) {
          return _OrchestratedTaskResult(
            label: "Navegador",
            success: false,
            message: error.toString(),
          );
        }
      case OSvozTaskType.playMedia:
        final query = task.parameters["query"] ?? "music";
        final platform = task.parameters["platform"] ?? task.target;
        final autoSkipAds = task.parameters["auto_skip_ads"] == "true";
        final result = await _safePlayMusic(
          query,
          platform,
          autoSkipAds: autoSkipAds,
        );
        final playAttempted = result["play_attempted"] == true;
        return _OrchestratedTaskResult(
          label: _musicPlatformLabel(platform),
          success: result["success"] == true,
          message: platform == "youtube"
              ? (playAttempted
                    ? "intenté reproducir $query${autoSkipAds ? " y activar omisión automática de anuncios" : ""}"
                    : "abrí la búsqueda de $query")
              : "abrí $platform con $query",
        );
      case OSvozTaskType.operatorStatus:
        try {
          final status = await OperatorStatusService.fetch(
            summaryMode: task.parameters["summary_mode"] ?? "quick",
          );
          return _OrchestratedTaskResult(
            label: "Estado",
            success: true,
            message: status.spokenSummary,
          );
        } catch (error) {
          return _OrchestratedTaskResult(
            label: "Estado",
            success: false,
            message: error.toString(),
          );
        }
      case OSvozTaskType.summarizeProject:
        return _OrchestratedTaskResult(
          label: "Resumen",
          success: true,
          message: await _localProjectSummary(),
        );
      case OSvozTaskType.listFiles:
        try {
          final result = await OSvozApi.listProjectFiles(limit: 12);
          final files = ((result["files"] as List?) ?? [])
              .take(6)
              .map(
                (file) =>
                    file is Map ? file["path"].toString() : file.toString(),
              )
              .join(", ");
          return _OrchestratedTaskResult(
            label: "Archivos",
            success: true,
            message: files.isEmpty ? "no encontré archivos visibles" : files,
          );
        } catch (error) {
          return _OrchestratedTaskResult(
            label: "Archivos",
            success: false,
            message: error.toString(),
          );
        }
      case OSvozTaskType.readFile:
        final path = task.parameters["path"];
        if (path == null) {
          return const _OrchestratedTaskResult(
            label: "Archivo",
            success: false,
            message: "falta la ruta del archivo",
          );
        }
        try {
          final result = await OSvozApi.readProjectFile(path);
          return _OrchestratedTaskResult(
            label: "Archivo",
            success: true,
            message:
                "leí ${result["path"]}: ${_compactFilePreview(result["content"]?.toString() ?? "")}",
          );
        } catch (error) {
          return _OrchestratedTaskResult(
            label: "Archivo",
            success: false,
            message: error.toString(),
          );
        }
      case OSvozTaskType.runDiagnostics:
        try {
          final result = await _executeActionWithVisibleSecurity(
            actionName: "RUN_DIAGNOSTICS",
            rawCommand: "run diagnostics",
            intent: "run_diagnostics",
            execute: ActionExecutor.runDiagnostics,
          );
          final summary = result["summary"] as Map<String, dynamic>?;
          final passed = summary?["passed"] ?? 0;
          final failed = summary?["failed"] ?? 0;
          return _OrchestratedTaskResult(
            label: "Pruebas",
            success: failed == 0,
            message: failed == 0
                ? "pasaron $passed comprobaciones"
                : "pasaron $passed comprobaciones y fallaron $failed",
          );
        } catch (error) {
          return _OrchestratedTaskResult(
            label: "Pruebas",
            success: false,
            message: error.toString(),
          );
        }
    }
  }

  String _taskProgressLabel(OSvozTask task) {
    return switch (task.type) {
      OSvozTaskType.openApp =>
        task.target == "terminal" ? "abriendo Terminal" : "abriendo VS Code",
      OSvozTaskType.openBrowser => "abriendo navegador",
      OSvozTaskType.playMedia => "preparando música",
      OSvozTaskType.operatorStatus => "revisando estado",
      OSvozTaskType.summarizeProject => "preparando resumen",
      OSvozTaskType.listFiles => "listando archivos",
      OSvozTaskType.readFile => "leyendo archivo",
      OSvozTaskType.runDiagnostics => "ejecutando diagnóstico",
    };
  }

  Future<Map<String, dynamic>> _safeAction(String actionName) async {
    try {
      return await _executeActionWithVisibleSecurity(
        actionName: actionName,
        rawCommand: actionName,
        intent: "orchestrated_action",
      );
    } catch (error) {
      return {"success": false, "message": error.toString()};
    }
  }

  Future<Map<String, dynamic>> _executeActionWithVisibleSecurity({
    required String actionName,
    required String rawCommand,
    required String intent,
    Future<Map<String, dynamic>> Function()? execute,
    bool announceRoutine = false,
  }) async {
    final receivedCue = ConversationalPresence.cue(
      stage: ConversationalPresenceStage.received,
      actionName: actionName,
      language: LanguageManager.effectiveLanguage,
      turn: _presenceTurn++,
    );
    _showStatus(
      heard: rawCommand,
      response: receivedCue,
      intent: "${intent}_received",
      action: "$actionName received.",
      security: "Preparing",
      operatorStatus: "Preparando acción",
    );
    unawaited(_speakResponse(receivedCue));

    final preflight = await ActionExecutor.preflight(actionName);
    _auditOperatorEvent(
      "operator.preflight",
      preflight.approved ? "approved" : "blocked",
      actionName: actionName,
      intent: intent,
      preflight: preflight,
    );
    if (!preflight.approved) {
      final pendingMessage = ConversationalPresence.cue(
        stage: ConversationalPresenceStage.securityCheck,
        actionName: actionName,
        language: LanguageManager.effectiveLanguage,
        turn: _presenceTurn++,
      );
      _showStatus(
        heard: rawCommand,
        response: pendingMessage,
        intent: "security_challenge_pending",
        action: "$actionName waiting for local authentication.",
        security: _securityChallengeLabel(preflight),
        operatorStatus: "Confirmando presencia antes de ejecutar",
      );
      await _speakResponse(pendingMessage);

      final challenge = await ActionExecutor.challengeBlockedPreflight(
        preflight,
      );
      _auditOperatorEvent(
        "operator.challenge",
        challenge.approved ? "approved" : "blocked",
        actionName: actionName,
        intent: intent,
        preflight: preflight,
        extra: {"challenge_security": challenge.security},
      );
      if (!challenge.approved) {
        final blockedIntent =
            challenge.security == "Critical action still blocked"
            ? "critical_action_blocked"
            : "security_challenge_failed";
        await _update(
          heard: rawCommand,
          response: challenge.message,
          intent: blockedIntent,
          action: "$actionName blocked by security challenge.",
          security: challenge.security,
          operatorStatus: blockedIntent == "critical_action_blocked"
              ? "Acción crítica bloqueada"
              : "No se confirmó presencia",
        );
        throw OSvozApiException(challenge.message, code: blockedIntent);
      }

      _showStatus(
        heard: rawCommand,
        response: challenge.message,
        intent: "security_challenge_approved",
        action: "$actionName approved by local authentication.",
        security: challenge.security,
        operatorStatus: "Presencia confirmada",
      );
      await _speakResponse(challenge.message);
    } else if (announceRoutine) {
      await _update(
        heard: rawCommand,
        response: "Ejecutando ${_actionLabel(actionName)}.",
        intent: intent,
        action: "$actionName requested.",
        security: "Routine action",
        operatorStatus: "Ejecutando acción rutinaria",
      );
    }

    _auditOperatorEvent(
      "operator.execution",
      "requested",
      actionName: actionName,
      intent: intent,
      preflight: preflight,
    );
    final run = execute ?? () => ActionExecutor.executeApproved(actionName);
    final progress = _beginProgress(
      rawCommand,
      ConversationalPresence.progressMessages(
        actionName: actionName,
        language: LanguageManager.effectiveLanguage,
      ),
    );
    late final Map<String, dynamic> result;
    try {
      final executionStopwatch = Stopwatch()..start();
      result = await run();
      executionStopwatch.stop();
      VoiceLatencyMetrics.record("execution_ms", executionStopwatch.elapsed);
    } finally {
      _finishProgress(progress);
    }
    _auditOperatorEvent(
      "operator.execution",
      result["success"] == true ? "success" : "failed",
      actionName: actionName,
      intent: intent,
      preflight: preflight,
      extra: {"requires_confirmation": result["requires_confirmation"] == true},
    );
    return result;
  }

  void _auditOperatorEvent(
    String eventType,
    String outcome, {
    required String actionName,
    required String intent,
    required OperatorPreflightResult preflight,
    Map<String, dynamic> extra = const {},
  }) {
    AuditLogService.recordLater(
      eventType,
      outcome,
      metadata: {
        "action": actionName,
        "intent": intent,
        "capability_id": preflight.capability?.id,
        "security_tier": preflight.tier.name,
        "security_level": preflight.capability?.securityLevel,
        "risk": preflight.capability?.risk,
        "missing_factors": preflight.missingFactors,
        ...extra,
      },
    );
  }

  String _securityChallengeLabel(OperatorPreflightResult preflight) {
    return switch (preflight.tier) {
      IovSecurityTier.routine => "security_challenge_pending",
      IovSecurityTier.personalWork => "security_challenge_pending_personal",
      IovSecurityTier.criticalAction => "security_challenge_pending_critical",
    };
  }

  String _orchestratedResponse(List<_OrchestratedTaskResult> results) {
    final successes = results.where((result) => result.success).toList();
    final failures = results.where((result) => !result.success).toList();
    final opened = successes
        .where((result) => result.label != "Resumen")
        .map((result) => "${result.label}: ${result.message}")
        .join(". ");
    final summary = successes
        .where((result) => result.label == "Resumen")
        .map((result) => result.message)
        .join(" ");
    final failureText = failures.isEmpty
        ? ""
        : " Pendiente: ${failures.map((result) => "${result.label}: ${result.message}").join(". ")}";
    final parts = [
      if (opened.isNotEmpty) opened,
      if (summary.isNotEmpty) summary,
    ];
    final body = parts.isEmpty
        ? "No pude completar las tareas."
        : parts.join(". ");
    return "$body$failureText";
  }

  String _executiveOrchestratedResponse(List<_OrchestratedTaskResult> results) {
    final successes = results.where((result) => result.success).toList();
    final failures = results.where((result) => !result.success).toList();
    final status = failures.isEmpty
        ? "Listo: completé la misión."
        : successes.isEmpty
        ? "No pude completar la misión."
        : "Completé parte de la misión.";
    final resultText = results
        .take(4)
        .map((result) => "${result.label}: ${result.message}")
        .join(". ");
    final nextStep = failures.isEmpty
        ? "Siguiente paso: podemos seguir con una edición o una prueba más específica."
        : "Siguiente paso: revisamos primero ${failures.first.label.toLowerCase()} y lo corregimos.";
    return "$status Resultado: $resultText. $nextStep";
  }

  Future<Map<String, dynamic>> _safePlayMusic(
    String query,
    String platform, {
    bool autoSkipAds = false,
  }) async {
    try {
      return await OSvozApi.playMusic(
        query,
        platform: platform,
        autoSkipAds: autoSkipAds,
      );
    } catch (error) {
      return {
        "success": false,
        "play_attempted": false,
        "message": error.toString(),
      };
    }
  }

  String _musicPlatformLabel(String platform) {
    switch (platform) {
      case "spotify":
        return "Spotify";
      case "apple_music":
        return "Apple Music";
      default:
        return "YouTube";
    }
  }

  Future<void> _openBrowserUrl(
    String rawCommand,
    String url,
    String successResponse,
  ) async {
    await _update(
      heard: rawCommand,
      response: LanguageManager.text("Abriendo navegador.", "Opening browser."),
      intent: "browser_open",
      action: "Opening validated browser URL.",
      security: "Routine browser action",
    );
    try {
      await OSvozApi.openBrowserUrl(url);
      await _update(
        heard: rawCommand,
        response: successResponse,
        intent: "browser_open",
        action: "Opened $url",
        security: "Routine browser action",
      );
    } on OSvozApiException catch (error) {
      await _update(
        heard: rawCommand,
        response: _friendlyApiError(error),
        intent: "browser_open_failed",
        action: error.code ?? "browser_open_failed",
        security: "Blocked",
      );
    }
  }

  Future<String> _localProjectSummary() async {
    try {
      final session = await SessionMemory.loadSessionState();
      return LanguageManager.text(
        "Resumen rápido: proyecto activo ${session.activeProject}. "
            "Tarea actual: ${session.currentTask}. "
            "Último avance: ${session.lastAction}. "
            "Siguiente paso: ${session.nextAction}.",
        "Quick summary: active project ${session.activeProject}. "
            "Current task: ${session.currentTask}. "
            "Last progress: ${session.lastAction}. "
            "Next step: ${session.nextAction}.",
      );
    } catch (_) {
      return LanguageManager.text(
        "No pude cargar la memoria local del proyecto.",
        "I could not load the local project memory.",
      );
    }
  }

  Future<void> _skipAdGuidance(String rawCommand) async {
    await _update(
      heard: rawCommand,
      response: LanguageManager.text("Revisando YouTube.", "Checking YouTube."),
      intent: "skip_ad",
      action: "Looking for the official YouTube skip ad button.",
      security: "Platform rules respected",
    );
    try {
      final result = await OSvozApi.skipYouTubeAd();
      final skipped = result["skipped"] == true;
      final state = result["state"]?.toString();
      await _update(
        heard: rawCommand,
        response: skipped
            ? LanguageManager.text("Anuncio omitido.", "Ad skipped.")
            : _skipAdStatusMessage(state),
        intent: "skip_ad",
        action: result["message"]?.toString() ?? "YouTube ad skip checked.",
        security: "Platform rules respected",
      );
    } on OSvozApiException catch (error) {
      await _update(
        heard: rawCommand,
        response: _friendlyApiError(error),
        intent: "skip_ad_failed",
        action: error.code ?? "youtube_ad_skip_failed",
        security: "Blocked",
      );
    }
  }

  String _skipAdStatusMessage(String? state) {
    if (state == "chrome_javascript_events_disabled") {
      return LanguageManager.text(
        "Chrome bloquea el control. Activa View, Developer, Allow JavaScript from Apple Events.",
        "Chrome is blocking control. Enable View, Developer, Allow JavaScript from Apple Events.",
      );
    }
    if (state == "accessibility_unavailable") {
      return LanguageManager.text(
        "Falta permiso de Accesibilidad para controlar Chrome.",
        "Accessibility permission is required to control Chrome.",
      );
    }
    if (state == "control_unavailable") {
      return LanguageManager.text(
        "No pude controlar la pestaña actual de Chrome todavía.",
        "I could not control the current Chrome tab yet.",
      );
    }
    return LanguageManager.text(
      "Todavía no aparece el botón oficial de omitir.",
      "The official skip button is not visible yet.",
    );
  }

  Future<void> _musicNeedsClarification(String rawCommand) async {
    await _update(
      heard: rawCommand,
      response: LanguageManager.text(
        "Escuché una petición de música, pero no pude separar bien el artista o la plataforma. Dime: reproduce seguido del artista y luego la plataforma.",
        "I heard a music request, but I could not separate the artist or platform clearly. Say: play, then the artist, then the platform.",
      ),
      intent: "music_clarification_needed",
      action:
          "Music-like command did not produce a safe structured media task.",
      security: "No external action executed",
    );
  }

  Future<void> _runChat(String rawCommand, String message) async {
    final progress = _beginProgress(rawCommand, const [
      "Sigo revisando el contexto. Ya casi tengo una respuesta útil.",
      "Continúo analizando; no necesitas repetir la pregunta.",
    ]);
    _showStatus(
      heard: rawCommand,
      response: LanguageManager.text("Estoy pensando...", "Thinking..."),
      intent: "chat_pending",
      action: "Waiting for OSvoz response.",
      security: "Secure",
    );
    try {
      final result = await OSvozApi.chat(
        message,
        language: LanguageManager.effectiveLanguage,
      );
      final routing = result["routing"] as Map<String, dynamic>?;
      final domain = routing?["domain"]?.toString();
      final capability = routing?["capability"]?.toString();
      final codeLanguage = routing?["language"]?.toString();
      final action = domain == "software_engineering"
          ? "Code agent · $capability · $codeLanguage"
          : "AI conversation";
      _finishProgress(progress);
      await _update(
        heard: rawCommand,
        response: result["response"] ?? "I could not produce a response.",
        intent: "chat",
        action: action,
        security: "Secure",
      );
    } on OSvozApiException catch (error) {
      _finishProgress(progress);
      await _update(
        heard: rawCommand,
        response: _friendlyApiError(error),
        intent: "backend_error",
        action: error.code ?? "chat_failed",
        security: "Blocked",
      );
    }
  }

  String _friendlyApiError(OSvozApiException error) {
    final message = error.message.trim();
    final lower = message.toLowerCase();
    if (lower.contains("ai service") ||
        lower.contains("temporarily unavailable")) {
      return LanguageManager.text(
        "La IA conversacional no está disponible ahora. Los comandos locales como abrir Terminal, VS Code y leer archivos deben seguir funcionando.",
        "The conversational AI is unavailable right now. Local commands like opening Terminal, VS Code and reading files should still work.",
      );
    }
    return message.isEmpty ? LanguageManager.backendError() : message;
  }

  Future<void> _prepareEdit(String rawCommand) async {
    final progress = _beginProgress(rawCommand, const [
      "Sigo preparando el cambio y comprobando que no afecte código ajeno.",
      "La vista previa todavía se está construyendo. El archivo original permanece intacto.",
    ]);
    await _update(
      heard: rawCommand,
      response: "Estoy preparando una vista previa exacta del cambio.",
      intent: "edit_active_file",
      action: "Preparing a reversible editor operation.",
      security: "Preview only",
    );
    try {
      final result = await OSvozApi.prepareEdit(
        rawCommand,
        language: LanguageManager.effectiveLanguage,
      );
      _pendingEditOperationId = result["operation_id"]?.toString();
      _finishProgress(progress);
      await _update(
        heard: rawCommand,
        response:
            "Preparé el cambio en ${result["relative_file"]}. "
            "${result["summary"]}. Revisa la comparación en Visual Studio "
            "Code y di “Sí, aplicar” o “Cancelar”.",
        intent: "edit_preview",
        action: "Exact diff sent to VS Code for review.",
        security: "Awaiting explicit confirmation",
      );
    } on OSvozApiException catch (error) {
      _finishProgress(progress);
      await _update(
        heard: rawCommand,
        response: error.message,
        intent: "edit_failed",
        action: error.code ?? "edit_prepare_failed",
        security: "Blocked",
      );
    }
  }

  Future<void> _confirmPendingEdit(String rawCommand) async {
    final operationId = _pendingEditOperationId;
    if (operationId == null) return;
    try {
      final result = await OSvozApi.confirmEdit(operationId);
      _pendingEditOperationId = null;
      await _update(
        heard: rawCommand,
        response:
            result["message"] ??
            "Cambio aprobado. Lo aplicaré, ejecutaré las pruebas y restauraré "
                "el original automáticamente si algo falla.",
        intent: "edit_confirmed",
        action: "Edit approved for transactional application.",
        security: "Confirmed",
      );
      unawaited(_monitorEdit(operationId));
    } on OSvozApiException catch (error) {
      await _update(
        heard: rawCommand,
        response: error.message,
        intent: "edit_confirmation_failed",
        action: error.code ?? "edit_confirmation_failed",
        security: "Blocked",
      );
    }
  }

  Future<void> _monitorEdit(String operationId) async {
    const terminalStates = {"applied", "failed", "canceled", "undone"};
    for (var attempt = 0; attempt < 300; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      try {
        final result = await OSvozApi.getEdit(operationId);
        final operation = result["operation"] as Map<String, dynamic>?;
        final status = operation?["status"]?.toString();
        if (status == null || !terminalStates.contains(status)) continue;

        if (status == "applied") {
          final diagnostics =
              operation?["diagnostics"] as Map<String, dynamic>?;
          final summary = diagnostics?["summary"] as Map<String, dynamic>?;
          await _update(
            heard: heardCommand,
            response:
                "Cambio aplicado y guardado. "
                "${summary?["passed"] ?? "Todas las"} pruebas pasaron. "
                "Puedes decir “Deshacer último cambio”.",
            intent: "edit_applied",
            action: "Edit saved after successful validation.",
            security: "Validated and reversible",
          );
        } else if (status == "failed") {
          await _update(
            heard: heardCommand,
            response:
                "Las pruebas fallaron o la validación no pudo completarse. "
                "No modifiqué el archivo original.",
            intent: "edit_rolled_back",
            action: operation?["error"]?.toString() ?? "Edit rolled back.",
            security: "Automatically restored",
          );
        } else if (status == "undone") {
          await _update(
            heard: heardCommand,
            response: "Listo. Restauré la copia anterior del archivo.",
            intent: "edit_undone",
            action: "Previous editor backup restored.",
            security: "Restored",
          );
        }
        return;
      } on OSvozApiException {
        return;
      }
    }
  }

  int _beginProgress(String heard, List<String> messages) {
    final generation = ++_progressGeneration;
    var index = 0;
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (generation != _progressGeneration || messages.isEmpty) return;
      if (VoiceEngine.speaking.value) return;
      final message = messages[index % messages.length];
      index++;
      heardCommand = heard;
      response = message;
      detectedIntent = "task_progress";
      technicalAction = "Long-running task remains active.";
      securityLevel = "In progress";
      notifyListeners();
      unawaited(_speakResponse(message));
    });
    return generation;
  }

  void _finishProgress(int generation) {
    if (generation != _progressGeneration) return;
    _progressTimer?.cancel();
    _progressTimer = null;
    _progressGeneration++;
  }

  Future<void> _cancelPendingEdit(String rawCommand) async {
    final operationId = _pendingEditOperationId;
    if (operationId == null) return;
    try {
      final result = await OSvozApi.cancelEdit(operationId);
      _pendingEditOperationId = null;
      await _update(
        heard: rawCommand,
        response: result["message"] ?? "Cambio cancelado.",
        intent: "edit_canceled",
        action: "Proposed editor operation canceled.",
        security: "Secure",
      );
    } on OSvozApiException catch (error) {
      await _update(
        heard: rawCommand,
        response: error.message,
        intent: "edit_cancel_failed",
        action: error.code ?? "edit_cancel_failed",
        security: "Blocked",
      );
    }
  }

  Future<void> _undoLastEdit(String rawCommand) async {
    try {
      final result = await OSvozApi.undoLastEdit();
      await _update(
        heard: rawCommand,
        response:
            result["message"] ??
            "Estoy restaurando la copia anterior del archivo.",
        intent: "undo_edit",
        action: "Persistent editor backup restoration requested.",
        security: "Reversible change",
      );
      final operationId = result["operation_id"]?.toString();
      if (operationId != null) {
        unawaited(_monitorEdit(operationId));
      }
    } on OSvozApiException catch (error) {
      await _update(
        heard: rawCommand,
        response: error.message,
        intent: "undo_edit_failed",
        action: error.code ?? "undo_edit_failed",
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
      final result = await _executeActionWithVisibleSecurity(
        actionName: actionName,
        rawCommand: rawCommand,
        intent: intent,
        announceRoutine: _routineAction(actionName),
      );
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
        response: _actionSuccessMessage(actionName, result),
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

  bool _routineAction(String action) =>
      action == "OPEN_TERMINAL" ||
      action == "OPEN_VSCODE" ||
      action == "OPEN_PROJECT";

  String _actionLabel(String action) {
    switch (action) {
      case "OPEN_TERMINAL":
        return LanguageManager.text("Terminal", "Terminal");
      case "OPEN_VSCODE":
        return LanguageManager.text("Visual Studio Code", "Visual Studio Code");
      case "OPEN_PROJECT":
        return LanguageManager.text("el proyecto", "the project");
      case "RUN_DIAGNOSTICS":
        return LanguageManager.text(
          "las pruebas del proyecto",
          "the project tests",
        );
      default:
        return action;
    }
  }

  String _actionSuccessMessage(String action, Map<String, dynamic> result) {
    if (action == "OPEN_TERMINAL") {
      return LanguageManager.text(
        "Terminal abierta en el proyecto OSvoz.",
        result["message"]?.toString() ?? "Terminal opened.",
      );
    }
    if (action == "OPEN_VSCODE") {
      return LanguageManager.text(
        "Visual Studio Code abierto con el proyecto OSvoz.",
        result["message"]?.toString() ?? "Visual Studio Code opened.",
      );
    }
    if (action == "OPEN_PROJECT") {
      return LanguageManager.text(
        "Proyecto OSvoz abierto.",
        result["message"]?.toString() ?? "Project opened.",
      );
    }
    return LanguageManager.text(
      LanguageManager.actionCompleted(action),
      result["message"]?.toString() ?? "$action completed.",
    );
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
    } on OSvozApiException catch (error) {
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
    } on OSvozApiException catch (error) {
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

  Future<void> voiceEnrollmentResult({
    required String heard,
    required String response,
    required String action,
    String security = "Voice identity",
  }) => _update(
    heard: heard,
    response: response,
    intent: "speaker_enrollment",
    action: action,
    security: security,
    operatorStatus: "Identidad de voz actualizada",
  );

  Future<void> voiceVerificationResult({
    required String heard,
    required bool verified,
    required String response,
    required String action,
  }) => _update(
    heard: heard,
    response: response,
    intent: "speaker_verification",
    action: action,
    security: verified ? "Voice identity verified" : "Blocked",
    operatorStatus: verified
        ? "Identidad de voz confirmada"
        : "Identidad de voz no confirmada",
  );

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
    operatorStatus: "Operación bloqueada",
  );

  Future<void> _update({
    required String heard,
    required String response,
    required String intent,
    required String action,
    required String security,
    String? operatorStatus,
    bool speak = true,
  }) async {
    heardCommand = heard;
    this.response = response;
    detectedIntent = intent;
    technicalAction = action;
    securityLevel = security;
    if (operatorStatus != null) this.operatorStatus = operatorStatus;
    final startedAt = _commandStartedAt;
    if (startedAt != null &&
        !intent.endsWith("_pending") &&
        intent != "task_progress") {
      final totalElapsed = DateTime.now().difference(startedAt);
      VoiceLatencyMetrics.record("command_response_ms", totalElapsed);
      VoiceLatencyMetrics.record("total_ms", totalElapsed);
    }
    notifyListeners();
    if (speak) {
      unawaited(_speakResponse(response));
    }
  }

  void _showStatus({
    required String heard,
    required String response,
    required String intent,
    required String action,
    required String security,
    String? operatorStatus,
  }) {
    heardCommand = heard;
    this.response = response;
    detectedIntent = intent;
    technicalAction = action;
    securityLevel = security;
    if (operatorStatus != null) this.operatorStatus = operatorStatus;
    notifyListeners();
  }

  Future<void> _speakResponse(String text) async {
    try {
      final error = await VoiceEngine.speak(text);
      if (error == null) return;
      technicalAction = "Voice playback failed: $error";
      notifyListeners();
    } catch (error) {
      technicalAction = "Voice playback failed: $error";
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }
}
