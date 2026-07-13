import 'labvoice_api.dart';

abstract class EnterpriseAuthClient {
  Future<Map<String, dynamic>> registerUser({
    required String organizationId,
    required String email,
    required String fullName,
    required String phone,
    required String role,
  });

  Future<Map<String, dynamic>> startSession({
    required String email,
    required String provider,
    required String environment,
    required String deviceId,
  });

  Future<Map<String, dynamic>> verifyFactor({
    required String sessionId,
    required String factor,
    String? code,
  });

  Future<Map<String, dynamic>> resendCode({required String sessionId});

  Future<Map<String, dynamic>> authorizeAction({
    required String sessionId,
    required String action,
    required String environment,
  });
}

class OSvozEnterpriseAuthClient implements EnterpriseAuthClient {
  const OSvozEnterpriseAuthClient();

  @override
  Future<Map<String, dynamic>> registerUser({
    required String organizationId,
    required String email,
    required String fullName,
    required String phone,
    required String role,
  }) {
    return OSvozApi.registerEnterpriseUser(
      organizationId: organizationId,
      email: email,
      fullName: fullName,
      phone: phone,
      role: role,
    );
  }

  @override
  Future<Map<String, dynamic>> startSession({
    required String email,
    required String provider,
    required String environment,
    required String deviceId,
  }) {
    return OSvozApi.startEnterpriseSession(
      email: email,
      provider: provider,
      environment: environment,
      deviceId: deviceId,
    );
  }

  @override
  Future<Map<String, dynamic>> verifyFactor({
    required String sessionId,
    required String factor,
    String? code,
  }) {
    return OSvozApi.verifyEnterpriseFactor(
      sessionId: sessionId,
      factor: factor,
      code: code,
    );
  }

  @override
  Future<Map<String, dynamic>> resendCode({required String sessionId}) {
    return OSvozApi.resendEnterpriseCode(sessionId: sessionId);
  }

  @override
  Future<Map<String, dynamic>> authorizeAction({
    required String sessionId,
    required String action,
    required String environment,
  }) {
    return OSvozApi.authorizeEnterpriseAction(
      sessionId: sessionId,
      action: action,
      environment: environment,
    );
  }
}

class EnterpriseAuthState {
  final String status;
  final String stage;
  final String message;
  final String? sessionId;
  final String? role;
  final List<String> requiredFactors;
  final List<String> completedFactors;
  final List<String> missingFactors;
  final String? debugVerificationCode;
  final bool authorized;
  final bool blocked;

  const EnterpriseAuthState({
    required this.status,
    required this.stage,
    required this.message,
    this.sessionId,
    this.role,
    this.requiredFactors = const [],
    this.completedFactors = const [],
    this.missingFactors = const [],
    this.debugVerificationCode,
    this.authorized = false,
    this.blocked = false,
  });

  factory EnterpriseAuthState.idle() => const EnterpriseAuthState(
    status: "idle",
    stage: "start",
    message: "Listo para iniciar sesión.",
  );

  EnterpriseAuthState copyWith({
    String? status,
    String? stage,
    String? message,
    String? sessionId,
    String? role,
    List<String>? requiredFactors,
    List<String>? completedFactors,
    List<String>? missingFactors,
    Object? debugVerificationCode = _unchanged,
    bool? authorized,
    bool? blocked,
  }) {
    return EnterpriseAuthState(
      status: status ?? this.status,
      stage: stage ?? this.stage,
      message: message ?? this.message,
      sessionId: sessionId ?? this.sessionId,
      role: role ?? this.role,
      requiredFactors: requiredFactors ?? this.requiredFactors,
      completedFactors: completedFactors ?? this.completedFactors,
      missingFactors: missingFactors ?? this.missingFactors,
      debugVerificationCode: debugVerificationCode == _unchanged
          ? this.debugVerificationCode
          : debugVerificationCode as String?,
      authorized: authorized ?? this.authorized,
      blocked: blocked ?? this.blocked,
    );
  }
}

const Object _unchanged = Object();

class EnterpriseAuthFlow {
  EnterpriseAuthFlow({required this.client});

  final EnterpriseAuthClient client;
  EnterpriseAuthState state = EnterpriseAuthState.idle();

  Future<EnterpriseAuthState> registerUser({
    required String organizationId,
    required String email,
    required String fullName,
    required String phone,
    required String role,
  }) async {
    state = state.copyWith(
      status: "working",
      stage: "register",
      message: "Preparando tu acceso.",
      blocked: false,
      authorized: false,
    );
    try {
      final result = await client.registerUser(
        organizationId: organizationId,
        email: email,
        fullName: fullName,
        phone: phone,
        role: role,
      );
      final user = _map(result["user"]);
      state = state.copyWith(
        status: "registered",
        stage: "registered",
        message:
            result["message"]?.toString() ??
            "Usuario listo para iniciar una sesión segura.",
        role: user["role"]?.toString(),
      );
    } on OSvozApiException catch (error) {
      state = _blocked("register_blocked", error.message);
    }
    return state;
  }

  Future<EnterpriseAuthState> startSession({
    required String email,
    required String provider,
    required String environment,
    required String deviceId,
  }) async {
    state = state.copyWith(
      status: "working",
      stage: "session_start",
      message: "Validando tu cuenta.",
      blocked: false,
      authorized: false,
    );
    try {
      final result = await client.startSession(
        email: email,
        provider: provider,
        environment: environment,
        deviceId: deviceId,
      );
      state = _fromSessionResult(result);
    } on OSvozApiException catch (error) {
      state = _blocked("session_blocked", error.message);
    }
    return state;
  }

  Future<EnterpriseAuthState> verifyEmailCode(String code) {
    return verifyFactor(factor: "email_code", code: code);
  }

  Future<EnterpriseAuthState> verifyBiometric() {
    return verifyFactor(factor: "biometric");
  }

  Future<EnterpriseAuthState> verifyVoice() {
    return verifyFactor(factor: "voice");
  }

  Future<EnterpriseAuthState> verifyFactor({
    required String factor,
    String? code,
  }) async {
    final sessionId = state.sessionId;
    if (sessionId == null) {
      state = _blocked("missing_session", "Inicia sesión nuevamente.");
      return state;
    }
    state = state.copyWith(
      status: "working",
      stage: factor,
      message: _workingMessage(factor),
      blocked: false,
    );
    try {
      final result = await client.verifyFactor(
        sessionId: sessionId,
        factor: factor,
        code: code,
      );
      state = _fromSessionResult(result);
    } on OSvozApiException catch (error) {
      state = state.copyWith(
        status: "blocked",
        stage: factor,
        message: error.message,
        blocked: true,
        authorized: false,
      );
    }
    return state;
  }

  Future<EnterpriseAuthState> resendEmailCode() async {
    final sessionId = state.sessionId;
    if (sessionId == null) {
      state = _blocked("missing_session", "Inicia sesión nuevamente.");
      return state;
    }
    state = state.copyWith(
      status: "working",
      stage: "email_code",
      message: "Solicitando un nuevo código.",
      blocked: false,
    );
    try {
      final result = await client.resendCode(sessionId: sessionId);
      state = _fromSessionResult(result);
    } on OSvozApiException catch (error) {
      state = state.copyWith(
        status: "blocked",
        stage: "email_code",
        message: error.message,
        blocked: true,
        authorized: false,
      );
    }
    return state;
  }

  Future<EnterpriseAuthState> authorizeSensitiveAction({
    required String action,
    required String environment,
  }) async {
    final sessionId = state.sessionId;
    if (sessionId == null) {
      state = _blocked("missing_session", "Inicia sesión nuevamente.");
      return state;
    }
    state = state.copyWith(
      status: "working",
      stage: "authorize_action",
      message: "Verificando permisos para la acción solicitada.",
      blocked: false,
      authorized: false,
    );
    try {
      final result = await client.authorizeAction(
        sessionId: sessionId,
        action: action,
        environment: environment,
      );
      state = _fromActionResult(result);
    } on OSvozApiException catch (error) {
      state = _blocked("action_blocked", error.message);
    }
    return state;
  }

  EnterpriseAuthState _fromSessionResult(Map<String, dynamic> result) {
    final session = _map(result["session"]);
    final user = _map(session["user"]);
    final status = session["status"]?.toString() ?? "pending";
    final stage = session["stage"]?.toString() ?? "unknown";
    return EnterpriseAuthState(
      status: status,
      stage: stage,
      message: result["message"]?.toString() ?? "Continúa la autorización.",
      sessionId: session["id"]?.toString(),
      role: user["role"]?.toString() ?? state.role,
      requiredFactors: _strings(session["required_factors"]),
      completedFactors: _strings(session["completed_factors"]),
      debugVerificationCode: result["verification_code"]?.toString(),
      authorized: status == "authorized" || stage == "ready",
      blocked: false,
    );
  }

  EnterpriseAuthState _fromActionResult(Map<String, dynamic> result) {
    final authorized = result["authorized"] == true;
    return state.copyWith(
      status: authorized ? "authorized" : result["status"]?.toString(),
      stage: result["stage"]?.toString() ?? (authorized ? "ready" : "mfa"),
      message: result["message"]?.toString() ?? "Acción evaluada.",
      missingFactors: _strings(result["missing_factors"]),
      requiredFactors: _strings(result["required_factors"]).isEmpty
          ? state.requiredFactors
          : _strings(result["required_factors"]),
      completedFactors: _strings(result["completed_factors"]).isEmpty
          ? state.completedFactors
          : _strings(result["completed_factors"]),
      authorized: authorized,
      blocked: false,
    );
  }

  EnterpriseAuthState _blocked(String stage, String message) {
    return state.copyWith(
      status: "blocked",
      stage: stage,
      message: message,
      blocked: true,
      authorized: false,
    );
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return {};
  }

  static List<String> _strings(Object? value) {
    if (value is List) return value.map((item) => item.toString()).toList();
    return const [];
  }

  static String _workingMessage(String factor) {
    return switch (factor) {
      "email_code" => "Verificando código.",
      "biometric" => "Esperando confirmación biométrica.",
      "voice" => "Esperando confirmación de voz.",
      "oauth" => "Esperando autorización OAuth.",
      "sso" => "Esperando autorización SSO.",
      _ => "Verificando factor de seguridad.",
    };
  }
}
