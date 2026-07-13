import 'package:flutter_test/flutter_test.dart';
import 'package:labvoice/services/device_trust_service.dart';
import 'package:labvoice/services/operator_capability_service.dart';
import 'package:labvoice/services/security_challenge_service.dart';
import 'package:labvoice/services/session_authenticator.dart';

void main() {
  test('approves personal work after local authentication succeeds', () async {
    final preflight = OperatorPreflightResult.blocked(
      capability: _capability(
        id: 'project.run_diagnostics',
        level: 2,
        risk: 'process_execution',
      ),
      tier: IovSecurityTier.personalWork,
      reason: 'Falta confianza silenciosa.',
      missingFactors: const ['passkey'],
    );

    final service = SecurityChallengeService(
      authenticator: _FakeSessionAuthenticator(biometricResult: true),
    );
    final result = await service.resolvePreflightBlock(preflight);

    expect(result.approved, isTrue);
    expect(result.security, 'Local authentication approved');
    expect(result.message, contains('Presencia confirmada'));
  });

  test('keeps action blocked when local authentication is denied', () async {
    final preflight = OperatorPreflightResult.blocked(
      capability: _capability(id: 'system.open_app', level: 1),
      tier: IovSecurityTier.routine,
      reason: 'Falta sesión activa.',
      missingFactors: const ['trusted_device_or_passkey_or_watch'],
    );

    final service = SecurityChallengeService(
      authenticator: _FakeSessionAuthenticator(biometricResult: false),
    );
    final result = await service.resolvePreflightBlock(preflight);

    expect(result.approved, isFalse);
    expect(result.security, 'Local authentication denied');
    expect(result.message, contains('No pude confirmar tu presencia'));
  });

  test('does not let local auth alone approve critical actions', () async {
    final preflight = OperatorPreflightResult.blocked(
      capability: _capability(
        id: 'critical.transfer_or_credentials',
        level: 3,
        risk: 'critical_financial',
      ),
      tier: IovSecurityTier.criticalAction,
      reason: 'Faltan factores fuertes.',
      missingFactors: const ['face_id_or_touch_id'],
    );

    final service = SecurityChallengeService(
      authenticator: _FakeSessionAuthenticator(biometricResult: true),
    );
    final result = await service.resolvePreflightBlock(preflight);

    expect(result.approved, isFalse);
    expect(result.security, 'Critical action still blocked');
  });
}

OperatorCapability _capability({
  required String id,
  required int level,
  String risk = 'routine_system',
}) {
  return OperatorCapability(
    id: id,
    name: id,
    status: 'implemented',
    securityLevel: level,
    risk: risk,
    requiredFactors: const [],
    silentFactorRequired: level > 1,
  );
}

class _FakeSessionAuthenticator implements SessionAuthenticator {
  const _FakeSessionAuthenticator({required this.biometricResult});

  final bool biometricResult;

  @override
  Future<bool> authenticateBiometric() async => biometricResult;

  @override
  Future<VoiceSessionResult> listenForSessionStart({
    String? recognitionLocale,
  }) async {
    return const VoiceSessionResult(
      verified: true,
      transcript: 'inicia mi sesión',
      language: 'es',
      message: 'ok',
    );
  }

  @override
  Future<VoiceSessionResult> verifyVoice({String? recognitionLocale}) async {
    return const VoiceSessionResult(
      verified: true,
      transcript: 'IOV autorizo esta sesión',
      language: 'es',
      message: 'ok',
    );
  }
}
