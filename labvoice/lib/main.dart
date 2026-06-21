import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'services/project_memory.dart';
import 'services/session_memory.dart';
import 'services/action_executor.dart';
import 'services/intent_engine.dart';
import 'services/voice_engine.dart';
import 'services/language_manager.dart';
import 'services/labvoice_api.dart';

void main() {
  runApp(const LabVoiceApp());
}

class LabVoiceApp extends StatelessWidget {
  const LabVoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LABVOICE DEV',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const LabVoiceCommandCenter(),
    );
  }
}

class LabVoiceCommandCenter extends StatefulWidget {
  const LabVoiceCommandCenter({super.key});

  @override
  State<LabVoiceCommandCenter> createState() => _LabVoiceCommandCenterState();
}

class _LabVoiceCommandCenterState extends State<LabVoiceCommandCenter> {
  late stt.SpeechToText _speech;
  final TextEditingController _commandController = TextEditingController();

  bool _isListening = false;

  String _selectedLanguageCode = "en_US";
  String _selectedLanguageName = "English";

  String _heardCommand = "No command received yet.";
  String _labVoiceResponse = "Ian, what are we building today?";
  String _detectedIntent = "Waiting for command";
  String _technicalAction = "No pending action";
  String _securityLevel = "Secure";
  String? _pendingConfirmationToken;
  String? _pendingActionName;
  final Map<String, String> _languages = {
    "Español": "es_ES",
    "English": "en_US",
    "Português": "pt_BR",
    "Français": "fr_FR",
    "Deutsch": "de_DE",
    "Italiano": "it_IT",
    "Русский": "ru_RU",
    "中文 Mandarin": "zh_CN",
    "日本語": "ja_JP",
    "한국어": "ko_KR",
  };

  @override
  void initState() {
    super.initState();

    _speech = stt.SpeechToText();

    _initializeSpeech();

    _loadProjectMemory();
  }

  Future<void> _initializeSpeech() async {
    await _speech.initialize();
  }

  Future<void> _loadProjectMemory() async {
    try {
      final project = await ProjectMemory.loadProjectState();
      final session = await SessionMemory.loadSessionState();

      setState(() {
        _labVoiceResponse =
            "Good morning ${project.owner}. "
            "Active project: ${project.project}. "
            "Current task: ${session.currentTask}. "
            "Last action: ${session.lastAction}. "
            "Next action: ${session.nextAction}. "
            "What are we building today?";
      });
    } catch (e) {
      setState(() {
        _labVoiceResponse = "MEMORY ERROR: $e";
      });
    }
  }

  @override
  void dispose() {
    _commandController.dispose();
    super.dispose();
  }

  Future<void> _processCommand(String rawCommand) async {
    final command = rawCommand.toLowerCase().trim();
    final intent = IntentEngine.detectIntent(command);

    if (intent == "confirm_action") {
      await _confirmPendingAction(rawCommand);
      return;
    }

    if (intent == "cancel_action") {
      await _cancelPendingAction(rawCommand);
      return;
    }

    if (command.startsWith("chat ")) {
      final result = await LabVoiceApi.chat(command.replaceFirst("chat ", ""));

      _updateState(
        heard: rawCommand,
        response: result["response"],
        intent: "chat",
        action: "AI conversation",
        security: "Secure",
      );

      return;
    }

    if (command.isEmpty) {
      _updateState(
        heard: "No clear command detected.",
        response: "Please repeat the command, Ian.",
        intent: "empty_command",
        action: "Waiting for a valid command.",
        security: "Secure",
      );
      return;
    }
    if (_containsAny(command, [
      "what are we doing today",
      "start work",
      "begin work",
      "start project",
    ])) {
      _updateState(
        heard: rawCommand,
        response:
            "I'm on it, Ian. Today we can continue building the LabVoice core.",
        intent: "daily_start",
        action:
            "Priorities: open project, run app, analyze errors, automate tasks, and improve the Python backend.",
        security: "Secure",
      );
      return;
    }

    if (intent == "inspect_project") {
      _updateState(
        heard: rawCommand,
        response: "Inspecting the active project.",
        intent: "inspect_project",
        action: "Reading project metadata and Git status.",
        security: "Read only",
      );

      try {
        final result = await ActionExecutor.inspectProject();

        await _updateState(
          heard: rawCommand,
          response: result["message"] ?? "Project inspection completed.",
          intent: "inspect_project",
          action: "PROJECT_INSPECT completed.",
          security: "Read only",
        );
      } catch (e) {
        await _updateState(
          heard: rawCommand,
          response: "I could not inspect the project.",
          intent: "backend_error",
          action: e.toString(),
          security: "Read only",
        );
      }

      return;
    }

    if (intent == "run_diagnostics") {
      await _updateState(
        heard: rawCommand,
        response: "Running project analysis and tests.",
        intent: "run_diagnostics",
        action: "Executing approved diagnostic tools.",
        security: "Controlled execution",
      );

      try {
        final result = await ActionExecutor.runDiagnostics();
        final summary = result["summary"] as Map<String, dynamic>?;
        final failed = summary?["failed"] ?? 0;

        await _updateState(
          heard: rawCommand,
          response: result["message"] ?? "Project diagnostics completed.",
          intent: "run_diagnostics",
          action: failed == 0
              ? "All diagnostic checks passed."
              : "$failed diagnostic checks require attention.",
          security: "Controlled execution",
        );
      } catch (e) {
        await _updateState(
          heard: rawCommand,
          response: "I could not complete the project diagnostics.",
          intent: "backend_error",
          action: e.toString(),
          security: "Controlled execution",
        );
      }

      return;
    }

    if (intent == "open_vscode") {
      LanguageManager.setLanguage("en");
      await VoiceEngine.setEnglish();

      await _requestAction(
        rawCommand: rawCommand,
        intent: "open_vscode",
        actionName: "OPEN_VSCODE",
      );
      return;
    }

    if (intent == "open_project") {
      await _requestAction(
        rawCommand: rawCommand,
        intent: "open_project",
        actionName: "OPEN_PROJECT",
      );
      return;
    }

    if (intent == "continue_work") {
      try {
        final session = await SessionMemory.loadSessionState();

        await _updateState(
          heard: rawCommand,
          response:
              "Active project: ${session.activeProject}. "
              "Current task: ${session.currentTask}. "
              "Last action: ${session.lastAction}. "
              "Next action: ${session.nextAction}. "
              "I am ready to continue.",
          intent: "continue_work",
          action: "Recovered persistent session from the backend.",
          security: "Read only",
        );
      } catch (e) {
        await _updateState(
          heard: rawCommand,
          response: "I could not recover the saved session.",
          intent: "backend_error",
          action: e.toString(),
          security: "Read only",
        );
      }

      return;
    }

    if (intent == "run_flutter") {
      await _requestAction(
        rawCommand: rawCommand,
        intent: "run_flutter",
        actionName: "RUN_FLUTTER",
      );
      return;
    }
    if (intent == "open_terminal") {
      await _requestAction(
        rawCommand: rawCommand,
        intent: "open_terminal",
        actionName: "OPEN_TERMINAL",
      );
      return;
    }
    if (intent == "list_files") {
      await _requestAction(
        rawCommand: rawCommand,
        intent: "list_files",
        actionName: "LIST_FILES",
      );
      return;
    }

    if (_containsAny(command, [
      "backup project",
      "create backup",
      "project backup",
    ])) {
      _updateState(
        heard: rawCommand,
        response: "I'm on it, Ian. Preparing project backup.",
        intent: "backup_project",
        action:
            "Python will execute: cd ~/Desktop && zip -r LABVOICE_BACKUP.zip ian_labvoice",
        security: "Secure",
      );
      return;
    }

    if (_containsAny(command, [
      "fix error",
      "solve error",
      "debug this",
      "debug error",
    ])) {
      _updateState(
        heard: rawCommand,
        response:
            "I'm on it, Ian. I will analyze the error and propose an exact solution.",
        intent: "debug_error",
        action:
            "LabVoice will read terminal output, classify the error, and prepare a fix.",
        security: "Confirmation required before modifying files",
      );
      return;
    }

    if (_containsAny(command, [
      "automate this task",
      "create automation",
      "automate task",
    ])) {
      _updateState(
        heard: rawCommand,
        response:
            "I'm on it, Ian. I will convert that task into executable steps.",
        intent: "automate_task",
        action:
            "LabVoice will break the request into file operations, commands, testing, and validation.",
        security: "Confirmation required",
      );
      return;
    }

    if (_containsAny(command, ["create file", "new file"])) {
      _updateState(
        heard: rawCommand,
        response: "I'm on it, Ian. Preparing file creation.",
        intent: "create_file",
        action:
            "Python will request path, filename, and content before writing to the project.",
        security: "Confirmation required",
      );
      return;
    }

    if (_containsAny(command, ["paste code", "copy code"])) {
      _updateState(
        heard: rawCommand,
        response:
            "I'm on it, Ian. Preparing code insertion into the correct file.",
        intent: "copy_paste_code",
        action:
            "LabVoice will identify the destination file, replace content, and save changes.",
        security: "Confirmation required",
      );
      return;
    }

    if (_containsAny(command, [
      "continue where i left off",
      "continue project",
    ])) {
      _updateState(
        heard: rawCommand,
        response: "I'm on it, Ian. Restoring the project state.",
        intent: "continue_work",
        action: "Reading saved state, modified files, and next pending task.",
        security: "Secure",
      );
      return;
    }

    final result = await LabVoiceApi.chat(rawCommand);

    _updateState(
      heard: rawCommand,
      response: result["response"],
      intent: "chat",
      action: "GPT fallback",
      security: "Secure",
    );
  }

  Future<void> _requestAction({
    required String rawCommand,
    required String intent,
    required String actionName,
  }) async {
    try {
      final result = await ActionExecutor.request(actionName);

      if (result["requires_confirmation"] == true) {
        _pendingConfirmationToken = result["confirmation_token"];
        _pendingActionName = actionName;

        await _updateState(
          heard: rawCommand,
          response: result["message"] ?? "Confirmation required.",
          intent: intent,
          action: "$actionName is waiting for confirmation.",
          security: result["policy"]?["risk"] ?? "Confirmation required",
        );
        return;
      }

      await _updateState(
        heard: rawCommand,
        response: result["message"] ?? "$actionName completed.",
        intent: intent,
        action: "$actionName executed.",
        security: result["policy"]?["risk"] ?? "Controlled",
      );
    } catch (e) {
      await _updateState(
        heard: rawCommand,
        response: LanguageManager.backendError(),
        intent: "backend_error",
        action: e.toString(),
        security: "Blocked",
      );
    }
  }

  Future<void> _confirmPendingAction(String rawCommand) async {
    final token = _pendingConfirmationToken;
    final actionName = _pendingActionName;
    if (token == null || actionName == null) {
      await _updateState(
        heard: rawCommand,
        response: "There is no pending action to confirm.",
        intent: "confirm_action",
        action: "No pending confirmation.",
        security: "Secure",
      );
      return;
    }

    final result = await ActionExecutor.confirm(token);
    _pendingConfirmationToken = null;
    _pendingActionName = null;

    await _updateState(
      heard: rawCommand,
      response: result["message"] ?? "$actionName completed.",
      intent: "confirm_action",
      action: result["success"] == true
          ? "$actionName confirmed and executed."
          : "$actionName was blocked.",
      security: result["success"] == true ? "Confirmed" : "Blocked",
    );
  }

  Future<void> _cancelPendingAction(String rawCommand) async {
    final token = _pendingConfirmationToken;
    if (token == null) {
      await _updateState(
        heard: rawCommand,
        response: "There is no pending action to cancel.",
        intent: "cancel_action",
        action: "No pending confirmation.",
        security: "Secure",
      );
      return;
    }

    final result = await ActionExecutor.cancel(token);
    _pendingConfirmationToken = null;
    _pendingActionName = null;

    await _updateState(
      heard: rawCommand,
      response: result["message"] ?? "Pending action canceled.",
      intent: "cancel_action",
      action: "Pending action canceled.",
      security: "Secure",
    );
  }

  bool _containsAny(String text, List<String> patterns) {
    return patterns.any((pattern) => text.contains(pattern));
  }

  Future<void> _updateState({
    required String heard,
    required String response,
    required String intent,
    required String action,
    required String security,
  }) async {
    await VoiceEngine.speak(response);
    setState(() {
      _heardCommand = heard;
      _labVoiceResponse = response;
      _detectedIntent = intent;
      _technicalAction = action;
      _securityLevel = security;
    });
  }

  void _sendTypedCommand() {
    final command = _commandController.text;
    _commandController.clear();
    _processCommand(command);
  }

  Future<void> _listen() async {
    if (_isListening) return;

    final available = await _speech.initialize(
      onStatus: (status) async {
        if (status == "done") {
          setState(() {
            _isListening = false;
          });

          await Future.delayed(const Duration(milliseconds: 800));

          _listen();
        }
      },
      onError: (error) {
        setState(() {
          _isListening = false;
        });
      },
    );

    if (!available) {
      _updateState(
        heard: "Microphone unavailable.",
        response: "I could not activate the microphone, Ian.",
        intent: "microphone_error",
        action: "Check browser or system permissions.",
        security: "Secure",
      );
      return;
    }

    setState(() {
      _isListening = true;
      _labVoiceResponse = "Listening, Ian...";
    });

    _speech.listen(
      listenOptions: stt.SpeechListenOptions(
        localeId: _selectedLanguageCode,
        listenFor: const Duration(minutes: 10),
        pauseFor: const Duration(seconds: 2),
      ),
      onResult: (result) async {
        if (result.finalResult) {
          final command = result.recognizedWords.trim();

          if (command.isEmpty) return;

          await _speech.stop();

          setState(() {
            _isListening = false;
          });

          await _processCommand(command);

          await _speech.stop();

          await Future.delayed(const Duration(milliseconds: 500));

          // _listen();
        } else {
          setState(() {
            _heardCommand = result.recognizedWords;
          });
        }
      },
    );
  }

  Widget _buildCard(String title, String value, IconData icon) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(value),
      ),
    );
  }

  Widget _buildLanguageSelector() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedLanguageCode,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        labelText: "Recognition Language",
      ),
      items: _languages.entries.map((entry) {
        return DropdownMenuItem<String>(
          value: entry.value,
          child: Text(entry.key),
        );
      }).toList(),
      onChanged: (value) {
        if (value == null) return;

        final selectedName = _languages.entries
            .firstWhere((entry) => entry.value == value)
            .key;

        setState(() {
          _selectedLanguageCode = value;
          _selectedLanguageName = selectedName;
          _labVoiceResponse =
              "Language updated to $selectedName. Ready for commands.";
        });
      },
    );
  }

  Widget _buildCommandInput() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _commandController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: "Command for LabVoice",
              hintText: "Example: debug Flutter error",
            ),
            onSubmitted: (_) => _sendTypedCommand(),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filled(
          onPressed: _sendTypedCommand,
          icon: const Icon(Icons.send),
        ),
      ],
    );
  }

  Widget _buildDeveloperCommands() {
    final commands = [
      "What are we building today?",
      "Inspect Project",
      "Run Diagnostics",
      "Confirm",
      "Cancel",
      "Open VS Code",
      "Open LabVoice Project",
      "Run Flutter",
      "Backup Project",
      "Debug Error",
      "Automate Task",
      "Create File",
      "Copy and Paste Code",
      "Continue Work",
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: commands.map((command) {
        return ActionChip(
          label: Text(command),
          onPressed: () => _processCommand(command),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("LABVOICE DEV COMMAND CENTER")),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              _buildCard(
                "LabVoice Response",
                _labVoiceResponse,
                Icons.assistant,
              ),
              _buildLanguageSelector(),
              const SizedBox(height: 12),
              _buildCard(
                "Active Language",
                _selectedLanguageName,
                Icons.language,
              ),
              _buildCard("Heard Command", _heardCommand, Icons.hearing),
              _buildCard("Detected Intent", _detectedIntent, Icons.psychology),
              _buildCard("Technical Action", _technicalAction, Icons.terminal),
              _buildCard("Security Level", _securityLevel, Icons.security),
              const SizedBox(height: 12),
              _buildCommandInput(),
              const SizedBox(height: 18),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Developer Quick Commands",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              _buildDeveloperCommands(),
              const SizedBox(height: 90),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.large(
        onPressed: _listen,
        child: Icon(_isListening ? Icons.mic : Icons.mic_none),
      ),
    );
  }
}
