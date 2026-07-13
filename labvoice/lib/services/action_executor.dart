import 'device_trust_service.dart';
import 'labvoice_api.dart';
import 'local_session_trust.dart';
import 'operator_capability_service.dart';
import 'security_challenge_service.dart';
import 'silent_trust_signals.dart';

class ActionExecutor {
  static final DeviceTrustService _defaultTrustService =
      LocalDeviceTrustService(
        sessionTrustStore: FileLocalSessionTrustStore(),
        passkeyAvailable: const SilentTrustSignals().passkeyAvailable,
        biometricAvailable: const SilentTrustSignals().biometricAvailable,
        watchNearby: const SilentTrustSignals().watchNearby,
        watchUnlocked: const SilentTrustSignals().watchUnlocked,
        watchConfirmed: const SilentTrustSignals().watchConfirmed,
      );

  static Future<Map<String, dynamic>> request(
    String action, {
    DeviceTrustService? trustService,
    SecurityChallengeService? securityChallengeService,
  }) async {
    final trust = await (trustService ?? _defaultTrustService).snapshot();
    final preflight = await OperatorCapabilityService.preflightAction(
      action,
      trust: trust,
    );
    if (!preflight.approved) {
      final challenge =
          await (securityChallengeService ?? SecurityChallengeService())
              .resolvePreflightBlock(preflight);
      if (!challenge.approved) {
        throw OSvozApiException(
          challenge.message,
          code: "operator_preflight_blocked",
        );
      }
      return await executeApproved(action);
    }
    return await executeApproved(action);
  }

  static Future<Map<String, dynamic>> executeApproved(String action) async {
    return await OSvozApi.executeAction(action);
  }

  static Future<OperatorPreflightResult> preflight(
    String action, {
    DeviceTrustService? trustService,
  }) async {
    final trust = await (trustService ?? _defaultTrustService).snapshot();
    return await OperatorCapabilityService.preflightAction(
      action,
      trust: trust,
    );
  }

  static Future<SecurityChallengeResult> challengeBlockedPreflight(
    OperatorPreflightResult preflight, {
    SecurityChallengeService? securityChallengeService,
  }) async {
    return await (securityChallengeService ?? SecurityChallengeService())
        .resolvePreflightBlock(preflight);
  }

  static Future<Map<String, dynamic>> confirm(String token) async {
    return await OSvozApi.confirmAction(token);
  }

  static Future<Map<String, dynamic>> cancel(String token) async {
    return await OSvozApi.cancelAction(token);
  }

  static Future<Map<String, dynamic>> inspectProject({
    bool runDiagnostics = false,
  }) async {
    return await OSvozApi.inspectProject(runDiagnostics: runDiagnostics);
  }

  static Future<Map<String, dynamic>> runDiagnostics() async {
    return await OSvozApi.runDiagnostics();
  }

  static Future<Map<String, dynamic>> openVSCode() async {
    return await request("OPEN_VSCODE");
  }

  static Future<Map<String, dynamic>> openProject() async {
    return await request("OPEN_PROJECT");
  }

  static Future<Map<String, dynamic>> runFlutter() async {
    return await request("RUN_FLUTTER");
  }

  static Future<Map<String, dynamic>> openTerminal() async {
    return await request("OPEN_TERMINAL");
  }
}
