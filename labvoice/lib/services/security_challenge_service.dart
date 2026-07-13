import 'device_trust_service.dart';
import 'language_manager.dart';
import 'operator_capability_service.dart';
import 'session_authenticator.dart';

class SecurityChallengeResult {
  const SecurityChallengeResult({
    required this.approved,
    required this.message,
    required this.security,
  });

  final bool approved;
  final String message;
  final String security;
}

class SecurityChallengeService {
  SecurityChallengeService({SessionAuthenticator? authenticator})
    : _authenticator = authenticator ?? MethodChannelSessionAuthenticator();

  final SessionAuthenticator _authenticator;

  Future<SecurityChallengeResult> resolvePreflightBlock(
    OperatorPreflightResult preflight,
  ) async {
    final capability = preflight.capability;
    if (capability == null) {
      return SecurityChallengeResult(
        approved: false,
        message: preflight.reason,
        security: "Unknown capability",
      );
    }

    if (!_canChallenge(preflight)) {
      return SecurityChallengeResult(
        approved: false,
        message: _blockedMessage(preflight),
        security: "Blocked by capability policy",
      );
    }

    try {
      final verified = await _authenticator.authenticateBiometric();
      if (!verified) {
        return SecurityChallengeResult(
          approved: false,
          message: LanguageManager.text(
            "No pude confirmar tu presencia. No ejecuté ${capability.name}.",
            "I could not confirm your presence. I did not run ${capability.name}.",
          ),
          security: "Local authentication denied",
        );
      }
    } catch (_) {
      return SecurityChallengeResult(
        approved: false,
        message: LanguageManager.text(
          "No pude abrir la autenticación local. La acción queda protegida.",
          "I could not open local authentication. The action stays protected.",
        ),
        security: "Local authentication unavailable",
      );
    }

    if (preflight.tier == IovSecurityTier.criticalAction) {
      return SecurityChallengeResult(
        approved: false,
        message: LanguageManager.text(
          "Confirmé tu presencia, pero esta acción requiere seguridad fuerte adicional antes de ejecutarse.",
          "I confirmed your presence, but this action requires stronger security before it can run.",
        ),
        security: "Critical action still blocked",
      );
    }

    return SecurityChallengeResult(
      approved: true,
      message: _approvedMessage(preflight),
      security: "Local authentication approved",
    );
  }

  bool _canChallenge(OperatorPreflightResult preflight) {
    final capability = preflight.capability;
    if (capability == null) return false;
    if (capability.status == "planned") return false;
    if (capability.status != "implemented" && capability.status != "partial") {
      return false;
    }
    return preflight.tier != IovSecurityTier.criticalAction ||
        preflight.missingFactors.contains("face_id_or_touch_id");
  }

  String _approvedMessage(OperatorPreflightResult preflight) {
    final name = preflight.capability?.name ?? "esta acción";
    return switch (preflight.tier) {
      IovSecurityTier.routine => LanguageManager.text(
        "Presencia confirmada. Continúo con $name.",
        "Presence confirmed. I will continue with $name.",
      ),
      IovSecurityTier.personalWork => LanguageManager.text(
        "Presencia confirmada. Ejecuto esta acción protegida.",
        "Presence confirmed. I will run this protected action.",
      ),
      IovSecurityTier.criticalAction => LanguageManager.text(
        "Presencia confirmada, pero esta acción sigue requiriendo seguridad fuerte.",
        "Presence confirmed, but this action still requires stronger security.",
      ),
    };
  }

  String _blockedMessage(OperatorPreflightResult preflight) {
    final missing = preflight.missingFactors.isEmpty
        ? ""
        : " ${LanguageManager.text("Falta", "Missing")}: ${preflight.missingFactors.join(", ")}.";
    return "${preflight.reason}$missing";
  }
}
