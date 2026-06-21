import 'labvoice_api.dart';

class ActionExecutor {
  static Future<Map<String, dynamic>> inspectProject() async {
    return await LabVoiceApi.inspectProject();
  }

  static Future<Map<String, dynamic>> runDiagnostics() async {
    return await LabVoiceApi.runDiagnostics();
  }

  static Future<Map<String, dynamic>> openVSCode() async {
    return await LabVoiceApi.executeAction("OPEN_VSCODE");
  }

  static Future<Map<String, dynamic>> openProject() async {
    return await LabVoiceApi.executeAction("OPEN_PROJECT");
  }

  static Future<Map<String, dynamic>> runFlutter() async {
    return await LabVoiceApi.executeAction("RUN_FLUTTER");
  }

  static Future<Map<String, dynamic>> openTerminal() async {
    return await LabVoiceApi.executeAction("OPEN_TERMINAL");
  }
}
