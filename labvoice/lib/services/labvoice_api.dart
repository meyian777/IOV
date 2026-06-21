import 'dart:convert';
import 'package:http/http.dart' as http;

class LabVoiceApi {
  static const String baseUrl = "http://127.0.0.1:8000";

  static Future<Map<String, dynamic>> getSession() async {
    final response = await http
        .get(Uri.parse("$baseUrl/session"))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception("Session loading failed: ${response.statusCode}");
    }

    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> inspectProject() async {
    final response = await http
        .get(Uri.parse("$baseUrl/project/inspect"))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception("Project inspection failed: ${response.statusCode}");
    }

    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> executeAction(String action) async {
    final response = await http.post(
      Uri.parse("$baseUrl/execute"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"action": action}),
    );

    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> chat(String message) async {
    final response = await http.post(
      Uri.parse("$baseUrl/chat"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"message": message}),
    );

    return jsonDecode(response.body);
  }
}
