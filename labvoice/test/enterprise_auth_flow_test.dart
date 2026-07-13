import 'package:flutter_test/flutter_test.dart';
import 'package:labvoice/services/enterprise_auth_flow.dart';
import 'package:labvoice/services/labvoice_api.dart';

class FakeEnterpriseAuthClient implements EnterpriseAuthClient {
  FakeEnterpriseAuthClient({
    required this.role,
    this.environment = "standard",
    this.correctCode = "123456",
    this.failStart = false,
    this.failBiometric = false,
    this.failVoice = false,
  });

  final String role;
  final String environment;
  final String correctCode;
  final bool failStart;
  final bool failBiometric;
  final bool failVoice;
  final String sessionId = "session-1";
  late List<String> requiredFactors;
  final Set<String> completedFactors = {};
  String activeCode = "";

  @override
  Future<Map<String, dynamic>> registerUser({
    required String organizationId,
    required String email,
    required String fullName,
    required String phone,
    required String role,
  }) async {
    return {
      "success": true,
      "user": {
        "id": "user-1",
        "organization_id": organizationId,
        "email": email,
        "full_name": fullName,
        "phone": phone,
        "role": this.role,
        "status": "active",
      },
      "message": "Usuario listo para iniciar una sesión segura.",
    };
  }

  @override
  Future<Map<String, dynamic>> startSession({
    required String email,
    required String provider,
    required String environment,
    required String deviceId,
  }) async {
    if (failStart) {
      throw const OSvozApiException(
        "OSvoz backend is unavailable.",
        code: "backend_unavailable",
      );
    }
    activeCode = correctCode;
    requiredFactors = switch (environment) {
      "bank" ||
      "hospital" ||
      "regulated" => ["email_code", "biometric", "voice"],
      _ => role == "admin" ? ["email_code", "biometric"] : ["email_code"],
    };
    return _sessionResult(
      stage: requiredFactors.first,
      message: "Código enviado. Revisa tu correo para continuar.",
    );
  }

  @override
  Future<Map<String, dynamic>> verifyFactor({
    required String sessionId,
    required String factor,
    String? code,
  }) async {
    if (factor == "email_code" && code != activeCode) {
      throw const OSvozApiException(
        "El código no coincide. Revisa tu correo o solicita uno nuevo.",
        statusCode: 409,
        code: "enterprise_factor_blocked",
      );
    }
    if (factor == "biometric" && failBiometric) {
      throw const OSvozApiException(
        "No pude confirmar la biometría. Intenta Face ID, Touch ID o código local.",
        statusCode: 409,
        code: "biometric_unavailable",
      );
    }
    if (factor == "voice" && failVoice) {
      throw const OSvozApiException(
        "La voz no coincide. Repite la frase de autorización.",
        statusCode: 409,
        code: "voice_mismatch",
      );
    }
    completedFactors.add(factor);
    final stage = requiredFactors.firstWhere(
      (factor) => !completedFactors.contains(factor),
      orElse: () => "ready",
    );
    return _sessionResult(
      stage: stage,
      message: switch (stage) {
        "biometric" =>
          "Código validado. Confirma ahora con Face ID o Touch ID.",
        "voice" => "Biometría validada. Confirma tu voz para activar OSvoz.",
        "ready" => "Acceso autorizado. OSvoz está listo.",
        _ => "Continúa la autorización.",
      },
    );
  }

  @override
  Future<Map<String, dynamic>> resendCode({required String sessionId}) async {
    activeCode = "654321";
    completedFactors.remove("email_code");
    return _sessionResult(
      stage: "email_code",
      message: "Código reenviado. Usa el código más reciente para continuar.",
    );
  }

  @override
  Future<Map<String, dynamic>> authorizeAction({
    required String sessionId,
    required String action,
    required String environment,
  }) async {
    if (role == "reader" && action == "apply_edit") {
      throw const OSvozApiException(
        "Tu rol reader no permite editor:apply.",
        statusCode: 403,
        code: "enterprise_action_blocked",
      );
    }
    if (action == "apply_edit" && !completedFactors.contains("biometric")) {
      return {
        "success": false,
        "authorized": false,
        "status": "pending_mfa",
        "stage": "biometric",
        "required_factors": ["email_code", "biometric"],
        "completed_factors": completedFactors.toList()..sort(),
        "missing_factors": ["biometric"],
        "message": "Código validado. Confirma ahora con Face ID o Touch ID.",
      };
    }
    return {
      "success": true,
      "authorized": true,
      "permission": action == "apply_edit" ? "editor:apply" : action,
      "message": "Acción autorizada. Puedes continuar.",
    };
  }

  Map<String, dynamic> _sessionResult({
    required String stage,
    required String message,
  }) {
    final authorized = stage == "ready";
    return {
      "success": true,
      "session": {
        "id": sessionId,
        "status": authorized ? "authorized" : "pending",
        "stage": stage,
        "required_factors": requiredFactors,
        "completed_factors": completedFactors.toList()..sort(),
        "provider": "email_code",
        "user": {
          "id": "user-1",
          "organization_id": "acme",
          "email": "dev@acme.test",
          "full_name": "Dev User",
          "role": role,
          "permissions": const [],
        },
      },
      "message": message,
      if (stage == "email_code") "verification_code": activeCode,
    };
  }
}

void main() {
  test(
    'frontend completes bank session with email, biometric and voice',
    () async {
      final flow = EnterpriseAuthFlow(
        client: FakeEnterpriseAuthClient(role: "editor", environment: "bank"),
      );

      await flow.registerUser(
        organizationId: "acme",
        email: "dev@acme.test",
        fullName: "Dev User",
        phone: "+15550000001",
        role: "editor",
      );
      expect(flow.state.stage, "registered");
      expect(flow.state.role, "editor");

      await flow.startSession(
        email: "dev@acme.test",
        provider: "email_code",
        environment: "bank",
        deviceId: "macbook-dev",
      );
      expect(flow.state.stage, "email_code");
      expect(flow.state.requiredFactors, ["email_code", "biometric", "voice"]);
      expect(flow.state.debugVerificationCode, "123456");

      await flow.verifyEmailCode("123456");
      expect(flow.state.stage, "biometric");
      expect(flow.state.completedFactors, ["email_code"]);

      await flow.verifyBiometric();
      expect(flow.state.stage, "voice");
      expect(flow.state.completedFactors, ["biometric", "email_code"]);

      await flow.verifyVoice();
      expect(flow.state.stage, "ready");
      expect(flow.state.authorized, isTrue);
      expect(flow.state.message, contains("Acceso autorizado"));
    },
  );

  test('frontend keeps session visible when email code is wrong', () async {
    final flow = EnterpriseAuthFlow(
      client: FakeEnterpriseAuthClient(role: "editor"),
    );
    await flow.startSession(
      email: "dev@acme.test",
      provider: "email_code",
      environment: "standard",
      deviceId: "macbook-dev",
    );

    await flow.verifyEmailCode("000000");

    expect(flow.state.blocked, isTrue);
    expect(flow.state.stage, "email_code");
    expect(flow.state.message, contains("código no coincide"));
    expect(flow.state.sessionId, "session-1");
  });

  test('frontend can resend code and continue with the newest code', () async {
    final flow = EnterpriseAuthFlow(
      client: FakeEnterpriseAuthClient(role: "editor"),
    );
    await flow.startSession(
      email: "dev@acme.test",
      provider: "email_code",
      environment: "standard",
      deviceId: "macbook-dev",
    );
    await flow.verifyEmailCode("000000");
    expect(flow.state.blocked, isTrue);

    await flow.resendEmailCode();
    expect(flow.state.blocked, isFalse);
    expect(flow.state.message, contains("Código reenviado"));
    expect(flow.state.debugVerificationCode, "654321");

    await flow.verifyEmailCode("654321");
    expect(flow.state.authorized, isTrue);
  });

  test('frontend shows backend unavailable during session start', () async {
    final flow = EnterpriseAuthFlow(
      client: FakeEnterpriseAuthClient(role: "editor", failStart: true),
    );

    await flow.startSession(
      email: "dev@acme.test",
      provider: "email_code",
      environment: "standard",
      deviceId: "macbook-dev",
    );

    expect(flow.state.blocked, isTrue);
    expect(flow.state.stage, "session_blocked");
    expect(flow.state.message, contains("backend"));
  });

  test('frontend blocks clearly when biometric is unavailable', () async {
    final flow = EnterpriseAuthFlow(
      client: FakeEnterpriseAuthClient(
        role: "editor",
        environment: "regulated",
        failBiometric: true,
      ),
    );
    await flow.startSession(
      email: "dev@acme.test",
      provider: "email_code",
      environment: "regulated",
      deviceId: "macbook-dev",
    );
    await flow.verifyEmailCode("123456");
    await flow.verifyBiometric();

    expect(flow.state.blocked, isTrue);
    expect(flow.state.stage, "biometric");
    expect(flow.state.message, contains("biometría"));
  });

  test('frontend blocks clearly when voice does not match', () async {
    final flow = EnterpriseAuthFlow(
      client: FakeEnterpriseAuthClient(
        role: "editor",
        environment: "regulated",
        failVoice: true,
      ),
    );
    await flow.startSession(
      email: "dev@acme.test",
      provider: "email_code",
      environment: "regulated",
      deviceId: "macbook-dev",
    );
    await flow.verifyEmailCode("123456");
    await flow.verifyBiometric();
    await flow.verifyVoice();

    expect(flow.state.blocked, isTrue);
    expect(flow.state.stage, "voice");
    expect(flow.state.message, contains("voz no coincide"));
  });

  test(
    'frontend asks for extra biometric factor before sensitive edit',
    () async {
      final flow = EnterpriseAuthFlow(
        client: FakeEnterpriseAuthClient(role: "editor"),
      );
      await flow.startSession(
        email: "dev@acme.test",
        provider: "email_code",
        environment: "standard",
        deviceId: "macbook-dev",
      );
      await flow.verifyEmailCode("123456");

      await flow.authorizeSensitiveAction(
        action: "apply_edit",
        environment: "standard",
      );

      expect(flow.state.status, "pending_mfa");
      expect(flow.state.stage, "biometric");
      expect(flow.state.missingFactors, ["biometric"]);

      await flow.verifyBiometric();
      await flow.authorizeSensitiveAction(
        action: "apply_edit",
        environment: "standard",
      );

      expect(flow.state.authorized, isTrue);
      expect(flow.state.message, "Acción autorizada. Puedes continuar.");
    },
  );

  test('frontend blocks reader role from applying edits', () async {
    final flow = EnterpriseAuthFlow(
      client: FakeEnterpriseAuthClient(role: "reader"),
    );
    await flow.startSession(
      email: "reader@acme.test",
      provider: "email_code",
      environment: "standard",
      deviceId: "macbook-reader",
    );
    await flow.verifyEmailCode("123456");

    await flow.authorizeSensitiveAction(
      action: "apply_edit",
      environment: "standard",
    );

    expect(flow.state.blocked, isTrue);
    expect(flow.state.stage, "action_blocked");
    expect(flow.state.message, contains("reader no permite"));
  });

  test('frontend keeps parallel enterprise sessions isolated', () async {
    final scenarios = List.generate(24, (index) {
      return (
        role: index % 4 == 0
            ? "reader"
            : index % 3 == 0
            ? "admin"
            : "editor",
        environment: index.isEven ? "bank" : "standard",
        email: "user$index@acme.test",
      );
    });

    final results = await Future.wait(
      scenarios.map((scenario) async {
        final flow = EnterpriseAuthFlow(
          client: FakeEnterpriseAuthClient(
            role: scenario.role,
            environment: scenario.environment,
          ),
        );
        await flow.registerUser(
          organizationId: "acme",
          email: scenario.email,
          fullName: "User ${scenario.email}",
          phone: "+15550000000",
          role: scenario.role,
        );
        await flow.startSession(
          email: scenario.email,
          provider: "email_code",
          environment: scenario.environment,
          deviceId: "device-${scenario.email}",
        );
        await flow.verifyEmailCode("123456");
        if (flow.state.stage == "biometric") {
          await flow.verifyBiometric();
        }
        if (flow.state.stage == "voice") {
          await flow.verifyVoice();
        }
        await flow.authorizeSensitiveAction(
          action: "apply_edit",
          environment: scenario.environment,
        );
        if (flow.state.stage == "biometric") {
          await flow.verifyBiometric();
          await flow.authorizeSensitiveAction(
            action: "apply_edit",
            environment: scenario.environment,
          );
        }
        return flow.state;
      }),
    );

    final blockedReaders = results
        .where((state) => state.blocked && state.role == "reader")
        .length;
    final authorizedEditorsAndAdmins = results
        .where((state) => state.authorized && state.role != "reader")
        .length;

    expect(results, hasLength(24));
    expect(blockedReaders, 6);
    expect(authorizedEditorsAndAdmins, 18);
    expect(results.every((state) => state.sessionId == "session-1"), isTrue);
  });
}
