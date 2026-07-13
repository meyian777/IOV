import 'intent_engine.dart';
import 'music_intent_parser.dart';

enum OSvozTaskType {
  openApp,
  openBrowser,
  playMedia,
  operatorStatus,
  summarizeProject,
  listFiles,
  readFile,
  runDiagnostics,
}

class OSvozTask {
  final OSvozTaskType type;
  final String target;
  final Map<String, String> parameters;
  final bool canRunInParallel;

  const OSvozTask({
    required this.type,
    required this.target,
    this.parameters = const {},
    this.canRunInParallel = true,
  });

  Map<String, dynamic> toJson() => {
    "type": type.name,
    "target": target,
    "parameters": parameters,
    "can_run_in_parallel": canRunInParallel,
  };
}

class OSvozIntentPlan {
  final String intent;
  final double confidence;
  final List<OSvozTask> tasks;
  final String route;
  final bool executiveSummary;

  const OSvozIntentPlan({
    required this.intent,
    required this.confidence,
    required this.tasks,
    required this.route,
    this.executiveSummary = false,
  });

  bool get isCompound => tasks.length > 1;

  Map<String, dynamic> toJson() => {
    "intent": intent,
    "confidence": confidence,
    "route": route,
    "executive_summary": executiveSummary,
    "tasks": tasks.map((task) => task.toJson()).toList(),
  };
}

class IntentOrchestrator {
  static OSvozIntentPlan plan(String command) {
    final text = command.toLowerCase().trim();
    final fuzzyText = _fuzzyNormalize(text);
    final tasks = <OSvozTask>[];

    if (_requestsVSCode(fuzzyText)) {
      tasks.add(const OSvozTask(type: OSvozTaskType.openApp, target: "vscode"));
    }

    if (_requestsTerminal(fuzzyText)) {
      tasks.add(
        const OSvozTask(type: OSvozTaskType.openApp, target: "terminal"),
      );
    }

    if (_requestsBrowser(fuzzyText) && !_requestsMedia(fuzzyText)) {
      tasks.add(
        const OSvozTask(type: OSvozTaskType.openBrowser, target: "default"),
      );
    }

    final musicIntent = MusicIntentParser.parse(command);
    if (musicIntent != null) {
      tasks.add(
        OSvozTask(
          type: OSvozTaskType.playMedia,
          target: musicIntent.platform,
          parameters: musicIntent.toParameters(),
        ),
      );
    }

    if (_requestsExplicitSummary(fuzzyText)) {
      tasks.add(
        const OSvozTask(
          type: OSvozTaskType.summarizeProject,
          target: "local_session",
          canRunInParallel: false,
        ),
      );
    }

    if (_requestsOperatorStatus(fuzzyText)) {
      tasks.add(
        OSvozTask(
          type: OSvozTaskType.operatorStatus,
          target: "core",
          parameters: {"summary_mode": IntentEngine.summaryMode(fuzzyText)},
          canRunInParallel: false,
        ),
      );
    }

    if (_requestsDiagnostics(fuzzyText)) {
      tasks.add(
        const OSvozTask(
          type: OSvozTaskType.runDiagnostics,
          target: "project",
          canRunInParallel: false,
        ),
      );
    }

    if (_requestsFileList(fuzzyText)) {
      tasks.add(
        const OSvozTask(
          type: OSvozTaskType.listFiles,
          target: "project",
          canRunInParallel: false,
        ),
      );
    }

    final filePath = IntentEngine.extractProjectFilePath(command);
    if (_requestsFileRead(fuzzyText) && filePath != null) {
      tasks.add(
        OSvozTask(
          type: OSvozTaskType.readFile,
          target: "project_file",
          parameters: {"path": filePath},
          canRunInParallel: false,
        ),
      );
    }

    final uniqueTasks = _dedupe(tasks);
    return OSvozIntentPlan(
      intent: uniqueTasks.length > 1 ? "compound_task" : "single_task",
      confidence: uniqueTasks.isEmpty
          ? 0
          : (uniqueTasks.length > 1 ? 0.86 : 0.72),
      tasks: uniqueTasks,
      route: "local_structured_orchestrator",
      executiveSummary: _requestsExecutiveSummary(fuzzyText),
    );
  }

  static String _fuzzyNormalize(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-záéíóúüñ0-9 ]', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\babre\s*visual\b'), 'abre visual')
      .replaceAll('abrevisual', 'abre visual')
      .replaceAll('abreviso', 'abre visual')
      .replaceAll('abrevizo', 'abre visual')
      .replaceAll('visual estudio', 'visual studio')
      .replaceAll('estudio code', 'studio code')
      .replaceAll('esta ols sistema', 'estado del sistema')
      .replaceAll('esta los sistema', 'estado del sistema')
      .replaceAll('esta el sistema', 'estado del sistema')
      .replaceAll('ols sistema', 'del sistema')
      .replaceAll('listarchos', 'lista archivos')
      .replaceAll('listar chos', 'lista archivos')
      .replaceAll('listar archivos', 'lista archivos')
      .replaceAll('mostrame', 'muéstrame')
      .replaceAll('muestrame', 'muéstrame')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool _requestsVSCode(String text) {
    return IntentEngine.requestsVSCode(text) ||
        text.contains("visual studio") ||
        text.contains("vs code") ||
        text.contains("vscode") ||
        text.contains("studio code");
  }

  static bool _requestsOperatorStatus(String text) =>
      IntentEngine.looksLikeOperatorStatus(text) ||
      text.contains("estado del sistema") ||
      text.contains("estado sistema") ||
      text.contains("sistema estado");

  static bool _requestsTerminal(String text) =>
      text.contains("abre terminal") ||
      text.contains("abre la terminal") ||
      text.contains("open terminal") ||
      text.contains("launch terminal");

  static bool _requestsBrowser(String text) =>
      text.contains("abre navegador") ||
      text.contains("abre el navegador") ||
      text.contains("abre chrome") ||
      text.contains("abre safari") ||
      text.contains("open browser");

  static bool _requestsMedia(String text) =>
      MusicIntentParser.parse(text) != null ||
      IntentEngine.requestsYouTubeMusic(text);

  static bool _requestsFileList(String text) =>
      text.contains("lista archivos") ||
      text.contains("lista los archivos") ||
      text.contains("archivos principales") ||
      text.contains("show files") ||
      text.contains("list files");

  static bool _requestsFileRead(String text) =>
      text.contains("lee ") ||
      text.contains("leer ") ||
      text.contains("read file") ||
      text.contains("show file") ||
      text.contains("archivo principal de flutter");

  static bool _requestsExplicitSummary(String text) =>
      text.contains("dame un resumen") ||
      text.contains("dame resumen") ||
      text.contains("resumen de lo que llevamos") ||
      text.contains("resumeme") ||
      text.contains("resúmeme") ||
      text.contains("dime en que vamos") ||
      text.contains("dime en qué vamos") ||
      text.contains("en que vamos") ||
      text.contains("en qué vamos") ||
      text.contains("give me a summary") ||
      text.contains("summarize") ||
      text.contains("where are we");

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

  static bool _requestsExecutiveSummary(String text) =>
      text.contains("explicame el resultado") ||
      text.contains("explícame el resultado") ||
      text.contains("resume el resultado") ||
      text.contains("resumen del resultado") ||
      text.contains("en un resumen") ||
      text.contains("solo lo basico") ||
      text.contains("solo lo básico") ||
      text.contains("lo logico y basico") ||
      text.contains("lo lógico y básico") ||
      text.contains("executive summary") ||
      text.contains("explain the result") ||
      text.contains("summarize the result");

  static bool looksLikeMusicRequest(String command) =>
      MusicIntentParser.looksLikeMusicRequest(command);

  static List<OSvozTask> _dedupe(List<OSvozTask> tasks) {
    final seen = <String>{};
    final unique = <OSvozTask>[];
    for (final task in tasks) {
      final key = "${task.type.name}:${task.target}:${task.parameters}";
      if (seen.add(key)) unique.add(task);
    }
    return unique;
  }
}
