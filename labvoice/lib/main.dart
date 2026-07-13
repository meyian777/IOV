import 'package:flutter/material.dart';

import 'screens/labvoice_command_center.dart';
import 'screens/enterprise_session_gate.dart';
import 'screens/session_gate.dart';
import 'services/device_trust_service.dart';
import 'services/enterprise_auth_flow.dart';
import 'services/local_session_trust.dart';
import 'services/session_authenticator.dart';
import 'services/silent_trust_signals.dart';

void main() {
  runApp(const OSvozApp());
}

class OSvozApp extends StatelessWidget {
  const OSvozApp({
    super.key,
    this.authenticator,
    this.enterpriseClient,
    this.deviceTrustService,
    this.localSessionTrustStore,
    this.showEnterpriseGate = false,
  });

  final SessionAuthenticator? authenticator;
  final EnterpriseAuthClient? enterpriseClient;
  final DeviceTrustService? deviceTrustService;
  final LocalSessionTrustStore? localSessionTrustStore;
  final bool showEnterpriseGate;

  @override
  Widget build(BuildContext context) {
    final sessionTrustStore =
        localSessionTrustStore ?? FileLocalSessionTrustStore();
    const silentTrustSignals = SilentTrustSignals();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'IOV',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0C0E16),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7568FF),
          brightness: Brightness.dark,
        ),
        fontFamily: "SF Pro Display",
        useMaterial3: true,
      ),
      home: _SessionBootstrap(
        authenticator: authenticator ?? MethodChannelSessionAuthenticator(),
        enterpriseClient: enterpriseClient ?? const OSvozEnterpriseAuthClient(),
        deviceTrustService:
            deviceTrustService ??
            LocalDeviceTrustService(
              sessionTrustStore: sessionTrustStore,
              biometricAvailable: silentTrustSignals.biometricAvailable,
              passkeyAvailable: silentTrustSignals.passkeyAvailable,
              watchNearby: silentTrustSignals.watchNearby,
              watchUnlocked: silentTrustSignals.watchUnlocked,
              watchConfirmed: silentTrustSignals.watchConfirmed,
            ),
        localSessionTrustStore: sessionTrustStore,
        showEnterpriseGate: showEnterpriseGate,
      ),
    );
  }
}

class _SessionBootstrap extends StatelessWidget {
  const _SessionBootstrap({
    required this.authenticator,
    required this.enterpriseClient,
    required this.deviceTrustService,
    required this.localSessionTrustStore,
    required this.showEnterpriseGate,
  });

  static const _trustedSessionDuration = Duration(hours: 24);

  final SessionAuthenticator authenticator;
  final EnterpriseAuthClient enterpriseClient;
  final DeviceTrustService deviceTrustService;
  final LocalSessionTrustStore localSessionTrustStore;
  final bool showEnterpriseGate;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DeviceTrustSnapshot>(
      future: deviceTrustService.snapshot(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data!.allowsRoutineSession) {
          return const OSvozCommandCenter();
        }
        return _authFlow();
      },
    );
  }

  Widget _authFlow() {
    final sessionGate = SessionGate(
      authenticator: authenticator,
      onSessionReady: () =>
          localSessionTrustStore.trustFor(_trustedSessionDuration),
    );
    if (!showEnterpriseGate) return sessionGate;
    return EnterpriseSessionGate(
      client: enterpriseClient,
      onAuthorized: (_) => sessionGate,
    );
  }
}
