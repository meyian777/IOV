import 'labvoice_api.dart';

class ActionExecutor {
  static Future<Map<String, dynamic>> request(String action) async {
    return await LabVoiceApi.executeAction(action);
  }

  static Future<Map<String, dynamic>> confirm(String token) async {
    return await LabVoiceApi.confirmAction(token);
  }

  static Future<Map<String, dynamic>> cancel(String token) async {
    return await LabVoiceApi.cancelAction(token);
  }

  static Future<Map<String, dynamic>> inspectProject() async {
    return await LabVoiceApi.inspectProject();
  }

  static Future<Map<String, dynamic>> runDiagnostics() async {
    return await LabVoiceApi.runDiagnostics();
  }

  static Future<Map<String, dynamic>> openVSCode() async {
    return await request("OPEN_VSCODE");
  }

  static Future<Map<String, dynamic>> openProject() async {
    return await request("OPEN_PROJECT");
  }

  static Future<Map<String, dynamic>> runFlutter() async {
    return await request("RUN_FLUTTER");
  }

  static Future<Map<String, dynamic>> openTerminal() async {
    return await request("OPEN_TERMINAL");
  }
}
