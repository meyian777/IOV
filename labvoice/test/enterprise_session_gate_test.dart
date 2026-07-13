import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:labvoice/main.dart';
import 'package:labvoice/services/device_trust_service.dart';
import 'package:labvoice/services/enterprise_auth_flow.dart';
import 'package:labvoice/services/labvoice_api.dart';
import 'package:labvoice/services/local_session_trust.dart';
import 'package:labvoice/services/session_authenticator.dart';

class VisualEnterpriseClient implements EnterpriseAuthClient {
  VisualEnterpriseClient({
    this.correctCode = "123456",
    this.failStart = false,
    this.failBiometric = false,
    this.failVoice = false,
  });

  final Set<String> completed = {};
  final List<String> required = const ["email_code", "biometric", "voice"];
  final String correctCode;
  final bool failStart;
  final bool failBiometric;
  final bool failVoice;
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
      "user": {"id": "u1", "role": role},
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
    return _session(
      "email_code",
      "Código enviado. Revisa tu correo para continuar.",
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
    completed.add(factor);
    final next = required.firstWhere(
      (factor) => !completed.contains(factor),
      orElse: () => "ready",
    );
    return _session(
      next,
      next == "ready"
          ? "Acceso autorizado. OSvoz está listo."
          : next == "biometric"
          ? "Código validado. Confirma ahora con Face ID o Touch ID."
          : "Biometría validada. Confirma tu voz para activar OSvoz.",
    );
  }

  @override
  Future<Map<String, dynamic>> resendCode({required String sessionId}) async {
    activeCode = "654321";
    completed.remove("email_code");
    return _session(
      "email_code",
      "Código reenviado. Usa el código más reciente para continuar.",
    );
  }

  @override
  Future<Map<String, dynamic>> authorizeAction({
    required String sessionId,
    required String action,
    required String environment,
  }) async {
    return {
      "success": true,
      "authorized": true,
      "message": "Acción autorizada. Puedes continuar.",
    };
  }

  Map<String, dynamic> _session(String stage, String message) {
    return {
      "success": true,
      "session": {
        "id": "s1",
        "status": stage == "ready" ? "authorized" : "pending",
        "stage": stage,
        "required_factors": required,
        "completed_factors": completed.toList()..sort(),
        "user": {
          "id": "u1",
          "organization_id": "acme",
          "email": "dev@acme.test",
          "full_name": "Dev User",
          "role": "editor",
        },
      },
      "message": message,
      if (stage == "email_code") "verification_code": activeCode,
    };
  }
}

class VisualSessionAuthenticator implements SessionAuthenticator {
  @override
  Future<bool> authenticateBiometric() async => true;

  @override
  Future<VoiceSessionResult> listenForSessionStart({
    String? recognitionLocale,
  }) async {
    return const VoiceSessionResult(
      verified: true,
      transcript: "inicia mi sesión",
      language: "es",
      message: "Iniciando tu sesión.",
    );
  }

  @override
  Future<VoiceSessionResult> verifyVoice({String? recognitionLocale}) async {
    return const VoiceSessionResult(
      verified: true,
      transcript: "OSvoz soy Ian y autorizo esta sesión",
      language: "es",
      message: "Voz verificada.",
    );
  }
}

class MemorySessionTrustStore implements LocalSessionTrustStore {
  @override
  Future<void> clear() async {}

  @override
  Future<bool> isTrusted() async => false;

  @override
  Future<void> trustFor(Duration duration) async {}
}

class UntrustedDeviceTrustService implements DeviceTrustService {
  const UntrustedDeviceTrustService();

  @override
  Future<DeviceTrustSnapshot> snapshot() async {
    return const DeviceTrustSnapshot(
      localSessionTrusted: false,
      passkeyAvailable: false,
      biometricAvailable: true,
      watchNearby: false,
      watchUnlocked: false,
      watchConfirmed: false,
    );
  }
}

void main() {
  Future<void> pumpEnterpriseApp(
    WidgetTester tester, {
    required EnterpriseAuthClient enterpriseClient,
    required SessionAuthenticator authenticator,
  }) async {
    await tester.pumpWidget(
      OSvozApp(
        enterpriseClient: enterpriseClient,
        authenticator: authenticator,
        deviceTrustService: const UntrustedDeviceTrustService(),
        localSessionTrustStore: MemorySessionTrustStore(),
        showEnterpriseGate: true,
      ),
    );
    await tester.pump();
  }

  Future<void> fillIdentity(WidgetTester tester) async {
    await tester.enterText(
      find.widgetWithText(TextField, "Correo electrónico"),
      "dev@acme.test",
    );
    await tester.enterText(
      find.widgetWithText(TextField, "Nombre completo"),
      "Dev User",
    );
    await tester.pump();
  }

  Future<void> startVisualSession(WidgetTester tester) async {
    await fillIdentity(tester);
    await tester.ensureVisible(find.widgetWithText(FilledButton, "Continuar"));
    await tester.tap(find.widgetWithText(FilledButton, "Continuar"));
    await tester.pump();
    await tester.pump();
  }

  Future<void> verifyCode(WidgetTester tester, String code) async {
    await tester.enterText(
      find.widgetWithText(TextField, "Código de verificación"),
      code,
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, "Verificar"));
    await tester.tap(find.widgetWithText(FilledButton, "Verificar"));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('OSvoz muestra inicio limpio antes del gate local', (
    tester,
  ) async {
    await pumpEnterpriseApp(
      tester,
      enterpriseClient: VisualEnterpriseClient(),
      authenticator: VisualSessionAuthenticator(),
    );

    expect(find.text("Inicia sesión"), findsOneWidget);
    expect(find.text("Correo electrónico"), findsOneWidget);
    expect(find.text("Nombre completo"), findsOneWidget);
    expect(find.text("Continuar"), findsOneWidget);
    expect(find.textContaining("corporativa"), findsNothing);
    expect(find.textContaining("empresarial"), findsNothing);
    expect(find.textContaining("Organización"), findsNothing);

    await startVisualSession(tester);

    expect(find.text("Verificar"), findsOneWidget);
    expect(find.text("Revisa tu correo"), findsOneWidget);
    expect(find.textContaining("Ingresa el código"), findsOneWidget);
    expect(
      find.textContaining("Código de prueba local: 123456"),
      findsOneWidget,
    );

    await verifyCode(tester, "123456");

    expect(find.text("Confirmar identidad"), findsOneWidget);

    await tester.ensureVisible(find.text("Confirmar identidad"));
    await tester.tap(find.text("Confirmar identidad"));
    await tester.pump();
    await tester.pump();

    expect(find.text("Confirmar voz"), findsOneWidget);

    await tester.ensureVisible(find.text("Confirmar voz"));
    await tester.tap(find.text("Confirmar voz"));
    await tester.pump();
    await tester.pump();

    expect(find.text("Entrar a OSvoz"), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key("enterprise-continue-local")),
    );
    await tester.tap(find.byKey(const Key("enterprise-continue-local")));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text("Inicia sesión"), findsNothing);
    expect(find.byKey(const Key("enterprise-continue-local")), findsNothing);
  });

  testWidgets('OSvoz explica código incorrecto y permite reenviar', (
    tester,
  ) async {
    await pumpEnterpriseApp(
      tester,
      enterpriseClient: VisualEnterpriseClient(),
      authenticator: VisualSessionAuthenticator(),
    );

    await startVisualSession(tester);
    await verifyCode(tester, "000000");

    expect(find.textContaining("código no coincide"), findsOneWidget);
    expect(find.text("Enviar otro código"), findsOneWidget);

    await tester.ensureVisible(find.text("Enviar otro código"));
    await tester.tap(find.text("Enviar otro código"));
    await tester.pump();
    await tester.pump();

    expect(find.text("Revisa tu correo"), findsOneWidget);
    expect(
      find.textContaining("Código de prueba local: 654321"),
      findsOneWidget,
    );

    await verifyCode(tester, "654321");
    expect(find.text("Confirmar identidad"), findsOneWidget);
  });

  testWidgets('OSvoz muestra backend caído sin congelar el inicio', (
    tester,
  ) async {
    await pumpEnterpriseApp(
      tester,
      enterpriseClient: VisualEnterpriseClient(failStart: true),
      authenticator: VisualSessionAuthenticator(),
    );

    await startVisualSession(tester);

    expect(find.textContaining("backend"), findsOneWidget);
    expect(find.text("Intentar de nuevo"), findsOneWidget);
  });

  testWidgets('OSvoz explica fallo biométrico en la etapa correcta', (
    tester,
  ) async {
    await pumpEnterpriseApp(
      tester,
      enterpriseClient: VisualEnterpriseClient(failBiometric: true),
      authenticator: VisualSessionAuthenticator(),
    );

    await startVisualSession(tester);
    await verifyCode(tester, "123456");

    await tester.ensureVisible(find.text("Confirmar identidad"));
    await tester.tap(find.text("Confirmar identidad"));
    await tester.pump();
    await tester.pump();

    expect(
      find.textContaining("No pude confirmar la biometría"),
      findsOneWidget,
    );
    expect(find.text("Confirma tu identidad"), findsOneWidget);
  });

  testWidgets('OSvoz explica voz no coincidente en la etapa correcta', (
    tester,
  ) async {
    await pumpEnterpriseApp(
      tester,
      enterpriseClient: VisualEnterpriseClient(failVoice: true),
      authenticator: VisualSessionAuthenticator(),
    );

    await startVisualSession(tester);
    await verifyCode(tester, "123456");
    await tester.ensureVisible(find.text("Confirmar identidad"));
    await tester.tap(find.text("Confirmar identidad"));
    await tester.pump();
    await tester.pump();

    await tester.ensureVisible(find.text("Confirmar voz"));
    await tester.tap(find.text("Confirmar voz"));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining("voz no coincide"), findsOneWidget);
    expect(find.text("Confirma tu voz"), findsOneWidget);
  });
}
