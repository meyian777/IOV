import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class OSvozApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? code;

  const OSvozApiException(this.message, {this.statusCode, this.code});

  @override
  String toString() => message;
}

class VoiceTranscriptionResult {
  final String transcript;
  final String language;
  final String engine;
  final String execution;
  final double? audioDurationSeconds;

  const VoiceTranscriptionResult({
    required this.transcript,
    required this.language,
    required this.engine,
    required this.execution,
    required this.audioDurationSeconds,
  });
}

class OSvozApi {
  static const String baseUrl = "http://127.0.0.1:8000";
  static const Duration _defaultTimeout = Duration(seconds: 10);
  static const Duration _availabilityCacheWindow = Duration(seconds: 3);
  static final http.Client _client = http.Client();
  static final Map<String, Duration> _recentLatencies = {};
  static DateTime? _lastAvailabilityCheckAt;
  static bool? _lastAvailabilityResult;

  static Map<String, Duration> get recentLatencies =>
      Map.unmodifiable(_recentLatencies);

  static Future<Map<String, dynamic>> getSession() async {
    return _request("GET", "/session");
  }

  static Future<Map<String, dynamic>> getEditorContext() async {
    return _request("GET", "/editor/context");
  }

  static Future<bool> isBackendAvailable({
    Duration timeout = const Duration(milliseconds: 350),
  }) async {
    final lastCheck = _lastAvailabilityCheckAt;
    final lastResult = _lastAvailabilityResult;
    if (lastCheck != null &&
        lastResult != null &&
        DateTime.now().difference(lastCheck) < _availabilityCacheWindow) {
      return lastResult;
    }
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _client
          .get(Uri.parse("$baseUrl/"))
          .timeout(timeout);
      _recordLatency("GET /", stopwatch.elapsed);
      final available = response.statusCode >= 200 && response.statusCode < 300;
      _lastAvailabilityCheckAt = DateTime.now();
      _lastAvailabilityResult = available;
      return available;
    } catch (_) {
      _recordLatency("GET /", stopwatch.elapsed);
      _lastAvailabilityCheckAt = DateTime.now();
      _lastAvailabilityResult = false;
      return false;
    }
  }

  static Future<Map<String, dynamic>> inspectProject({
    bool runDiagnostics = false,
  }) async {
    final query = Uri(
      queryParameters: {if (runDiagnostics) "run_diagnostics": "true"},
    ).query;
    final path = query.isEmpty ? "/project/inspect" : "/project/inspect?$query";
    return _request(
      "GET",
      path,
      timeout: runDiagnostics ? const Duration(minutes: 5) : _defaultTimeout,
    );
  }

  static Future<Map<String, dynamic>> listProjectFiles({
    String directory = "",
    int limit = 25,
  }) async {
    final query = Uri(
      queryParameters: {
        if (directory.isNotEmpty) "directory": directory,
        "limit": limit.toString(),
      },
    ).query;
    return _request("GET", "/project/files?$query");
  }

  static Future<Map<String, dynamic>> readProjectFile(String path) async {
    final query = Uri(queryParameters: {"path": path}).query;
    return _request("GET", "/project/file?$query");
  }

  static Future<Map<String, dynamic>> runDiagnostics() async {
    return _request(
      "POST",
      "/project/diagnostics",
      timeout: const Duration(minutes: 5),
    );
  }

  static Future<Map<String, dynamic>> getMlFrameworks() async {
    return _request("GET", "/ml/frameworks");
  }

  static Future<Map<String, dynamic>> getMlProvider() async {
    return _request("GET", "/ml/provider");
  }

  static Future<Map<String, dynamic>> operatorCapabilities() async {
    return _request("GET", "/core/operator-capabilities");
  }

  static Future<Map<String, dynamic>> operatorStatus({
    String summaryMode = "quick",
  }) async {
    final query = Uri(queryParameters: {"summary_mode": summaryMode}).query;
    return _request("GET", "/core/operator-status?$query");
  }

  static Future<Map<String, dynamic>> appendAuditEvent({
    required String eventType,
    required String outcome,
    Map<String, dynamic> metadata = const {},
  }) async {
    return _request(
      "POST",
      "/core/audit/events",
      body: {"event_type": eventType, "outcome": outcome, "metadata": metadata},
    );
  }

  static Future<Map<String, dynamic>> createAudioEmbedding(
    List<double> features,
  ) async {
    return _request(
      "POST",
      "/ml/audio/embedding",
      body: {"features": features},
    );
  }

  static Future<Map<String, dynamic>> executePythonScript(
    String scriptPath, {
    List<String> arguments = const [],
    int timeoutSeconds = 30,
  }) async {
    return _request(
      "POST",
      "/python/execute",
      body: {
        "script_path": scriptPath,
        "arguments": arguments,
        "timeout_seconds": timeoutSeconds,
      },
      timeout: Duration(seconds: timeoutSeconds + 5),
    );
  }

  static Future<Map<String, dynamic>> executeAction(String action) async {
    return _request("POST", "/execute", body: {"action": action});
  }

  static Future<Map<String, dynamic>> openBrowserUrl(String url) async {
    return _request("POST", "/browser/open", body: {"url": url});
  }

  static Future<Map<String, dynamic>> playYouTube(
    String query, {
    bool autoSkipAds = false,
  }) async {
    return _request(
      "POST",
      "/browser/youtube/play",
      body: {"query": query, "auto_skip_ads": autoSkipAds},
    );
  }

  static Future<Map<String, dynamic>> skipYouTubeAd() async {
    return _request("POST", "/browser/youtube/skip-ad");
  }

  static Future<Map<String, dynamic>> playMusic(
    String query, {
    required String platform,
    bool autoSkipAds = false,
  }) async {
    return _request(
      "POST",
      "/music/play",
      body: {
        "query": query,
        "platform": platform,
        "auto_skip_ads": autoSkipAds,
      },
    );
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

  static Future<Map<String, dynamic>> prepareEdit(
    String instruction, {
    required String language,
  }) async {
    return _request(
      "POST",
      "/editor/edit/prepare",
      body: {"instruction": instruction, "language": language},
      timeout: const Duration(minutes: 2),
    );
  }

  static Future<Map<String, dynamic>> confirmEdit(String operationId) async {
    return _request(
      "POST",
      "/editor/edit/$operationId/confirm",
      timeout: const Duration(seconds: 30),
    );
  }

  static Future<Map<String, dynamic>> getEdit(String operationId) async {
    return _request("GET", "/editor/edit/$operationId");
  }

  static Future<Map<String, dynamic>> cancelEdit(String operationId) async {
    return _request("POST", "/editor/edit/$operationId/cancel");
  }

  static Future<Map<String, dynamic>> undoLastEdit() async {
    return _request("POST", "/editor/edit/undo");
  }

  static Future<Uint8List> speech(
    String text, {
    required String language,
  }) async {
    final uri = Uri.parse("$baseUrl/speech");
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _client
          .post(
            uri,
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"text": text, "language": language}),
          )
          .timeout(const Duration(seconds: 60));
      _recordLatency("POST /speech", stopwatch.elapsed);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _decodeResponse(response);
      }
      return response.bodyBytes;
    } on TimeoutException {
      _recordLatency("POST /speech", stopwatch.elapsed);
      throw const OSvozApiException(
        "Natural voice generation timed out.",
        code: "timeout",
      );
    } on http.ClientException {
      _recordLatency("POST /speech", stopwatch.elapsed);
      throw const OSvozApiException(
        "OSvoz backend is unavailable.",
        code: "backend_unavailable",
      );
    }
  }

  static Future<String> transcribeWav(
    Uint8List audioBytes, {
    required String language,
  }) async {
    final result = await transcribeWavDetails(audioBytes, language: language);
    return result.transcript;
  }

  static Future<VoiceTranscriptionResult> transcribeWavDetails(
    Uint8List audioBytes, {
    required String language,
  }) async {
    final uri = Uri.parse(
      "$baseUrl/voice/transcribe?language=${Uri.encodeQueryComponent(language)}",
    );
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _client
          .post(uri, headers: {"Content-Type": "audio/wav"}, body: audioBytes)
          .timeout(const Duration(minutes: 2));
      _recordLatency("POST /voice/transcribe", stopwatch.elapsed);
      final decoded = _decodeResponse(response);
      final audio = decoded["audio"];
      final duration = audio is Map
          ? double.tryParse(audio["duration_seconds"]?.toString() ?? "")
          : null;
      return VoiceTranscriptionResult(
        transcript: decoded["transcript"]?.toString() ?? "",
        language: decoded["language"]?.toString() ?? language,
        engine: decoded["engine"]?.toString() ?? "unknown",
        execution: decoded["execution"]?.toString() ?? "unknown",
        audioDurationSeconds: duration,
      );
    } on TimeoutException {
      _recordLatency("POST /voice/transcribe", stopwatch.elapsed);
      throw const OSvozApiException(
        "Local voice recognition timed out.",
        code: "timeout",
      );
    } on http.ClientException {
      _recordLatency("POST /voice/transcribe", stopwatch.elapsed);
      throw const OSvozApiException(
        "OSvoz backend is unavailable.",
        code: "backend_unavailable",
      );
    } on FormatException catch (error) {
      _recordLatency("POST /voice/transcribe", stopwatch.elapsed);
      throw OSvozApiException(
        "OSvoz backend returned an invalid transcription response: ${error.message}",
        code: "invalid_response",
      );
    }
  }

  static Future<Map<String, dynamic>> interpretVoice(
    String transcript, {
    required String language,
  }) async {
    return _request(
      "POST",
      "/voice/interpret",
      body: {"transcript": transcript, "language": language},
    );
  }

  static Future<Map<String, dynamic>> enrollSpeaker(
    Uint8List audioBytes, {
    required String phrase,
  }) async {
    final uri = Uri.parse(
      "$baseUrl/speaker/enroll?phrase=${Uri.encodeQueryComponent(phrase)}",
    );
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _client
          .post(uri, headers: {"Content-Type": "audio/wav"}, body: audioBytes)
          .timeout(const Duration(seconds: 30));
      _recordLatency("POST /speaker/enroll", stopwatch.elapsed);
      return _decodeResponse(response);
    } on TimeoutException {
      _recordLatency("POST /speaker/enroll", stopwatch.elapsed);
      throw const OSvozApiException(
        "Voice enrollment timed out.",
        code: "timeout",
      );
    } on http.ClientException {
      _recordLatency("POST /speaker/enroll", stopwatch.elapsed);
      throw const OSvozApiException(
        "OSvoz backend is unavailable.",
        code: "backend_unavailable",
      );
    } on FormatException {
      _recordLatency("POST /speaker/enroll", stopwatch.elapsed);
      throw const OSvozApiException(
        "OSvoz backend returned an invalid enrollment response.",
        code: "invalid_response",
      );
    }
  }

  static Future<Map<String, dynamic>> speakerStatus() async {
    return _request("GET", "/speaker/status");
  }

  static Future<Map<String, dynamic>> verifySpeaker(
    Uint8List audioBytes,
  ) async {
    final uri = Uri.parse("$baseUrl/speaker/verify");
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _client
          .post(uri, headers: {"Content-Type": "audio/wav"}, body: audioBytes)
          .timeout(const Duration(seconds: 30));
      _recordLatency("POST /speaker/verify", stopwatch.elapsed);
      return _decodeResponse(response);
    } on TimeoutException {
      _recordLatency("POST /speaker/verify", stopwatch.elapsed);
      throw const OSvozApiException(
        "Voice verification timed out.",
        code: "timeout",
      );
    } on http.ClientException {
      _recordLatency("POST /speaker/verify", stopwatch.elapsed);
      throw const OSvozApiException(
        "OSvoz backend is unavailable.",
        code: "backend_unavailable",
      );
    } on FormatException {
      _recordLatency("POST /speaker/verify", stopwatch.elapsed);
      throw const OSvozApiException(
        "OSvoz backend returned an invalid voice verification response.",
        code: "invalid_response",
      );
    }
  }

  static Future<Map<String, dynamic>> enterpriseCapabilities() async {
    return _request("GET", "/auth/enterprise/capabilities");
  }

  static Future<Map<String, dynamic>> registerEnterpriseUser({
    required String organizationId,
    required String email,
    required String fullName,
    required String phone,
    required String role,
  }) async {
    return _request(
      "POST",
      "/auth/enterprise/users",
      body: {
        "organization_id": organizationId,
        "email": email,
        "full_name": fullName,
        "phone": phone,
        "role": role,
      },
    );
  }

  static Future<Map<String, dynamic>> startEnterpriseSession({
    required String email,
    required String provider,
    required String environment,
    required String deviceId,
  }) async {
    return _request(
      "POST",
      "/auth/enterprise/session/start",
      body: {
        "email": email,
        "provider": provider,
        "environment": environment,
        "device_id": deviceId,
      },
    );
  }

  static Future<Map<String, dynamic>> verifyEnterpriseFactor({
    required String sessionId,
    required String factor,
    String? code,
  }) async {
    return _request(
      "POST",
      "/auth/enterprise/session/verify",
      body: {"session_id": sessionId, "factor": factor, "code": ?code},
    );
  }

  static Future<Map<String, dynamic>> resendEnterpriseCode({
    required String sessionId,
  }) async {
    return _request(
      "POST",
      "/auth/enterprise/session/resend-code",
      body: {"session_id": sessionId},
    );
  }

  static Future<Map<String, dynamic>> authorizeEnterpriseAction({
    required String sessionId,
    required String action,
    required String environment,
  }) async {
    return _request(
      "POST",
      "/auth/enterprise/action/authorize",
      body: {
        "session_id": sessionId,
        "action": action,
        "environment": environment,
      },
    );
  }

  static Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Duration timeout = _defaultTimeout,
  }) async {
    final uri = Uri.parse("$baseUrl$path");
    final latencyKey = "$method ${uri.path}";
    final stopwatch = Stopwatch()..start();

    try {
      final response = switch (method) {
        "GET" => await _client.get(uri).timeout(timeout),
        "POST" =>
          await _client
              .post(
                uri,
                headers: {"Content-Type": "application/json"},
                body: body == null ? null : jsonEncode(body),
              )
              .timeout(timeout),
        _ => throw const OSvozApiException("Unsupported HTTP method."),
      };

      _recordLatency(latencyKey, stopwatch.elapsed);
      return _decodeResponse(response);
    } on TimeoutException {
      _recordLatency(latencyKey, stopwatch.elapsed);
      throw const OSvozApiException(
        "OSvoz backend did not respond in time.",
        code: "timeout",
      );
    } on http.ClientException {
      _recordLatency(latencyKey, stopwatch.elapsed);
      throw const OSvozApiException(
        "OSvoz backend is unavailable.",
        code: "backend_unavailable",
      );
    } on FormatException catch (error) {
      _recordLatency(latencyKey, stopwatch.elapsed);
      throw OSvozApiException(
        "OSvoz backend returned an invalid response: ${error.message}",
        code: "invalid_response",
      );
    }
  }

  static Map<String, dynamic> _decodeResponse(http.Response response) {
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (error) {
      final preview = response.body.trim();
      throw FormatException(
        "status=${response.statusCode}, body=${preview.isEmpty ? "<empty>" : preview.substring(0, preview.length > 500 ? 500 : preview.length)}",
        error.source,
        error.offset,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException("Expected a JSON object.");
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded["detail"];
      final message = detail is Map
          ? detail["message"]?.toString()
          : detail?.toString();
      final code = detail is Map ? detail["code"]?.toString() : null;

      throw OSvozApiException(
        message ?? "OSvoz request failed.",
        statusCode: response.statusCode,
        code: code,
      );
    }

    return decoded;
  }

  static void _recordLatency(String key, Duration elapsed) {
    _recentLatencies[key] = elapsed;
    if (_recentLatencies.length <= 24) return;
    _recentLatencies.remove(_recentLatencies.keys.first);
  }
}
