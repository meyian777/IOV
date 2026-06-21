import 'dart:convert';
import 'package:http/http.dart' as http;

class LabVoiceApi {
  static const String baseUrl = "http://127.0.0.1:8000";

  static Future<Map<String, dynamic>> executeAction(
    String action,
  ) async {
    final response = await http.post(
      Uri.parse("$baseUrl/execute"),
      headers: {
        "Content-Type": "application/json",
      },
      body: jsonEncode({
        "action": action,
      }),
    );

    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> chat(
    String message,
  ) async {
    final response = await http.post(
      Uri.parse("$baseUrl/chat"),
      headers: {
        "Content-Type": "application/json",
      },
      body: jsonEncode({
        "message": message,
      }),
    );

    return jsonDecode(response.body);
  }
}