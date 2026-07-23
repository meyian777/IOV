import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:labvoice/main.dart';
import 'package:labvoice/services/device_trust_service.dart';
import 'package:labvoice/services/local_session_trust.dart';
import 'package:labvoice/services/session_authenticator.dart';

class FakeSessionAuthenticator implements SessionAuthenticator {
  FakeSessionAuthenticator({
    this.biometricResults = const [true],
    this.sessionStartResults = const [
      VoiceSessionResult(
        verified: true,
        transcript: 'inicia mi sesión',
        language: 'es',
        message: 'Iniciando tu sesión.',
      ),
    ],
    this.voiceResults = const [
      VoiceSessionResult(
        verified: true,
        transcript: 'OSvoz soy Ian y autorizo esta sesión',
        language: 'es',
        message: 'Voz verificada.',
      ),
    ],
  });

  final List<bool> biometricResults;
  final List<VoiceSessionResult> sessionStartResults;
  final List<VoiceSessionResult> voiceResults;
  int biometricCalls = 0;
  int sessionStartCalls = 0;
  int voiceCalls = 0;
  final List<String?> voiceLocales = [];

  @override
  Future<bool> authenticateBiometric() async {
    final index = biometricCalls.clamp(0, biometricResults.length - 1);
    biometricCalls += 1;
    return biometricResults[index];
  }

  @override
  Future<VoiceSessionResult> listenForSessionStart({
    String? recognitionLocale,
  }) async {
    final index = sessionStartCalls.clamp(0, sessionStartResults.length - 1);
    sessionStartCalls += 1;
    return sessionStartResults[index];
  }

  @override
  Future<VoiceSessionResult> verifyVoice({String? recognitionLocale}) async {
    voiceLocales.add(recognitionLocale);
    final index = voiceCalls.clamp(0, voiceResults.length - 1);
    voiceCalls += 1;
    return voiceResults[index];
  }
}

class MemorySessionTrustStore implements LocalSessionTrustStore {
  MemorySessionTrustStore({this.trusted = false});

  bool trusted;
  int trustCalls = 0;

  @override
  Future<void> clear() async {
    trusted = false;
  }

  @override
  Future<bool> isTrusted() async => trusted;

  @override
  Future<void> trustFor(Duration duration) async {
    trustCalls += 1;
    trusted = true;
  }
}

class FakeDeviceTrustService implements DeviceTrustService {
  FakeDeviceTrustService({this.routineAllowed = false});

  final bool routineAllowed;

  @override
  Future<DeviceTrustSnapshot> snapshot() async {
    return DeviceTrustSnapshot(
      localSessionTrusted: routineAllowed,
      passkeyAvailable: false,
      biometricAvailable: true,
      watchNearby: false,
      watchUnlocked: false,
      watchConfirmed: false,
    );
  }
}

void main() {
  testWidgets('OSvoz abre el command center tras el session gate', (
    WidgetTester tester,
  ) async {
    final authenticator = FakeSessionAuthenticator();
    await tester.pumpWidget(
      OSvozApp(
        authenticator: authenticator,
        deviceTrustService: FakeDeviceTrustService(),
        localSessionTrustStore: MemorySessionTrustStore(),
        showEnterpriseGate: false,
      ),
    );
    await tester.pump();

    expect(find.text('IOV'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('voice-core')), findsOneWidget);
    expect(authenticator.sessionStartCalls, 1);
    expect(authenticator.biometricCalls, 1);
    expect(authenticator.voiceCalls, 0);
    expect(find.text('Voz'), findsNothing);
    expect(find.text('Confirmación'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(ActionChip), findsNothing);
  });

  testWidgets('OSvoz no exige confirmación de voz después de la biometría', (
    WidgetTester tester,
  ) async {
    final authenticator = FakeSessionAuthenticator(
      voiceResults: const [
        VoiceSessionResult(
          verified: false,
          transcript: 'hola sistema',
          language: 'es',
          message: 'Esta confirmación no debe ejecutarse.',
        ),
      ],
    );

    await tester.pumpWidget(
      OSvozApp(
        authenticator: authenticator,
        deviceTrustService: FakeDeviceTrustService(),
        localSessionTrustStore: MemorySessionTrustStore(),
        showEnterpriseGate: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('voice-core')), findsOneWidget);
    expect(authenticator.biometricCalls, 1);
    expect(authenticator.voiceCalls, 0);
    expect(find.text('Voz no confirmada'), findsNothing);
    expect(find.text('Reintentar voz'), findsNothing);
  });

  testWidgets('OSvoz mantiene el gate si la identidad local falla', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      OSvozApp(
        authenticator: FakeSessionAuthenticator(
          biometricResults: const [false],
        ),
        deviceTrustService: FakeDeviceTrustService(),
        localSessionTrustStore: MemorySessionTrustStore(),
        showEnterpriseGate: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('No pude verificarte'), findsOneWidget);
    expect(find.text('Reintentar identidad'), findsOneWidget);
    expect(find.byKey(const Key('voice-core')), findsNothing);
  });

  testWidgets('OSvoz conserva el idioma detectado al autenticar en inglés', (
    WidgetTester tester,
  ) async {
    final authenticator = FakeSessionAuthenticator(
      sessionStartResults: const [
        VoiceSessionResult(
          verified: true,
          transcript: 'start my session',
          language: 'en',
          message: 'Starting your session.',
        ),
      ],
      voiceResults: const [
        VoiceSessionResult(
          verified: true,
          transcript: 'OSvoz I authorize this session',
          language: 'en',
          message: 'Voice verified.',
        ),
      ],
    );
    await tester.pumpWidget(
      OSvozApp(
        authenticator: authenticator,
        deviceTrustService: FakeDeviceTrustService(),
        localSessionTrustStore: MemorySessionTrustStore(),
        showEnterpriseGate: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('voice-core')), findsOneWidget);
    expect(authenticator.voiceCalls, 0);
  });

  testWidgets('OSvoz guarda confianza local al completar la biometría', (
    WidgetTester tester,
  ) async {
    final trustStore = MemorySessionTrustStore();
    await tester.pumpWidget(
      OSvozApp(
        authenticator: FakeSessionAuthenticator(),
        deviceTrustService: FakeDeviceTrustService(),
        localSessionTrustStore: trustStore,
        showEnterpriseGate: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('voice-core')), findsOneWidget);
    expect(trustStore.trusted, isTrue);
    expect(trustStore.trustCalls, 1);
  });

  testWidgets('OSvoz omite login si la sesión local sigue vigente', (
    WidgetTester tester,
  ) async {
    final authenticator = FakeSessionAuthenticator();
    await tester.pumpWidget(
      OSvozApp(
        authenticator: authenticator,
        deviceTrustService: FakeDeviceTrustService(routineAllowed: true),
        localSessionTrustStore: MemorySessionTrustStore(trusted: true),
        showEnterpriseGate: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('voice-core')), findsOneWidget);
    expect(find.text('Elige tu idioma'), findsNothing);
    expect(authenticator.biometricCalls, 0);
    expect(authenticator.voiceCalls, 0);
  });
}
