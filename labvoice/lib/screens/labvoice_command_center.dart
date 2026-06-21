import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../controllers/labvoice_controller.dart';
import '../services/language_manager.dart';

class LabVoiceCommandCenter extends StatefulWidget {
  const LabVoiceCommandCenter({super.key});

  @override
  State<LabVoiceCommandCenter> createState() => _LabVoiceCommandCenterState();
}

class _LabVoiceCommandCenterState extends State<LabVoiceCommandCenter> {
  final LabVoiceController _controller = LabVoiceController();
  final TextEditingController _commandController = TextEditingController();
  final stt.SpeechToText _speech = stt.SpeechToText();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_refresh);
    _controller.initialize();
    _speech.initialize();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    _controller.dispose();
    _commandController.dispose();
    _speech.cancel();
    super.dispose();
  }

  Future<void> _listen() async {
    if (_controller.isListening) return;
    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == "done") _controller.setListening(false);
      },
      onError: (_) => _controller.setListening(false),
    );
    if (!available) {
      await _controller.microphoneUnavailable();
      return;
    }

    _controller.setListening(true);
    await _speech.listen(
      listenOptions: stt.SpeechListenOptions(
        localeId: LanguageManager.activeRecognitionLocale,
        listenFor: const Duration(minutes: 10),
        pauseFor: const Duration(seconds: 2),
      ),
      onResult: (result) async {
        if (!result.finalResult) {
          _controller.updatePartialTranscript(result.recognizedWords);
          return;
        }
        final command = result.recognizedWords.trim();
        await _speech.stop();
        _controller.setListening(false);
        if (command.isNotEmpty) await _controller.processCommand(command);
      },
    );
  }

  void _sendTypedCommand() {
    final command = _commandController.text;
    _commandController.clear();
    _controller.processCommand(command);
  }

  Widget _card(String title, String value, IconData icon) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(value),
    ),
  );

  Widget _languageSelector() => DropdownButtonFormField<String>(
    initialValue: _controller.selectedLanguageCode,
    decoration: const InputDecoration(
      border: OutlineInputBorder(),
      labelText: "Recognition Language",
    ),
    items: _controller.languages.entries
        .map(
          (entry) => DropdownMenuItem<String>(
            value: entry.value,
            child: Text(entry.key),
          ),
        )
        .toList(),
    onChanged: (value) {
      if (value != null) _controller.selectLanguage(value);
    },
  );

  Widget _commandInput() => Row(
    children: [
      Expanded(
        child: TextField(
          controller: _commandController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: "Command for LabVoice",
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

  Widget _quickCommands() {
    const commands = [
      "Inspect Project",
      "Run Diagnostics",
      "Confirm",
      "Cancel",
      "Open VS Code",
      "Open LabVoice Project",
      "Run Flutter",
      "Continue Work",
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: commands
          .map(
            (command) => ActionChip(
              label: Text(command),
              onPressed: () => _controller.processCommand(command),
            ),
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("LABVOICE DEV COMMAND CENTER")),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            _card("LabVoice Response", _controller.response, Icons.assistant),
            _languageSelector(),
            const SizedBox(height: 12),
            _card(
              "Active Language",
              _controller.activeLanguageName,
              Icons.language,
            ),
            _card("Heard Command", _controller.heardCommand, Icons.hearing),
            _card(
              "Detected Intent",
              _controller.detectedIntent,
              Icons.psychology,
            ),
            _card(
              "Technical Action",
              _controller.technicalAction,
              Icons.terminal,
            ),
            _card("Security Level", _controller.securityLevel, Icons.security),
            const SizedBox(height: 12),
            _commandInput(),
            const SizedBox(height: 18),
            _quickCommands(),
            const SizedBox(height: 90),
          ],
        ),
      ),
    ),
    floatingActionButton: FloatingActionButton.large(
      onPressed: _listen,
      child: Icon(_controller.isListening ? Icons.mic : Icons.mic_none),
    ),
  );
}
