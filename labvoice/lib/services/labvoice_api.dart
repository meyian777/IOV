import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class LabVoiceApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? code;

  const LabVoiceApiException(this.message, {this.statusCode, this.code});

  @override
  String toString() => message;
}

class LabVoiceApi {
  static const String baseUrl = "http://127.0.0.1:8000";
  static const Duration _defaultTimeout = Duration(seconds: 10);

  static Future<Map<String, dynamic>> getSession() async {
    return _request("GET", "/session");
  }

  static Future<Map<String, dynamic>> inspectProject() async {
    return _request("GET", "/project/inspect");
  }

  static Future<Map<String, dynamic>> runDiagnostics() async {
    return _request(
      "POST",
      "/project/diagnostics",
      timeout: const Duration(minutes: 5),
    );
  }

  static Future<Map<String, dynamic>> executeAction(String action) async {
    return _request("POST", "/execute", body: {"action": action});
  }

  static Future<Map<String, dynamic>> confirmAction(String token) async {
    return _request(
      "POST",
      "/execute/confirm",
      body: {"confirmation_token": token},
      timeout: const Duration(seconds: 30),
    );
  }

  static Future<Map<String, dynamic>> cancelAction(String token) async {
    return _request(
      "POST",
      "/execute/cancel",
      body: {"confirmation_token": token},
    );
  }

  static Future<Map<String, dynamic>> chat(
    String message, {
    required String language,
  }) async {
    return _request(
      "POST",
      "/chat",
      body: {"message": message, "language": language},
      timeout: const Duration(seconds: 60),
    );
  }

  static Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Duration timeout = _defaultTimeout,
  }) async {
    final uri = Uri.parse("$baseUrl$path");

    try {
      final response = switch (method) {
        "GET" => await http.get(uri).timeout(timeout),
        "POST" =>
          await http
              .post(
                uri,
                headers: {"Content-Type": "application/json"},
                body: body == null ? null : jsonEncode(body),
              )
              .timeout(timeout),
        _ => throw const LabVoiceApiException("Unsupported HTTP method."),
      };

      return _decodeResponse(response);
    } on TimeoutException {
      throw const LabVoiceApiException(
        "LabVoice backend did not respond in time.",
        code: "timeout",
      );
    } on http.ClientException {
      throw const LabVoiceApiException(
        "LabVoice backend is unavailable.",
        code: "backend_unavailable",
      );
    } on FormatException {
      throw const LabVoiceApiException(
        "LabVoice backend returned an invalid response.",
        code: "invalid_response",
      );
    }
  }

  static Map<String, dynamic> _decodeResponse(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException("Expected a JSON object.");
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded["detail"];
      final message = detail is Map
          ? detail["message"]?.toString()
          : detail?.toString();
      final code = detail is Map ? detail["code"]?.toString() : null;

      throw LabVoiceApiException(
        message ?? "LabVoice request failed.",
        statusCode: response.statusCode,
        code: code,
      );
    }

    return decoded;
  }
}
