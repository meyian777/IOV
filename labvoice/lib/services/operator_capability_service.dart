import 'device_trust_service.dart';
import 'labvoice_api.dart';

class OperatorCapability {
  const OperatorCapability({
    required this.id,
    required this.name,
    required this.status,
    required this.securityLevel,
    required this.risk,
    required this.requiredFactors,
    required this.silentFactorRequired,
  });

  final String id;
  final String name;
  final String status;
  final int securityLevel;
  final String risk;
  final List<String> requiredFactors;
  final bool silentFactorRequired;

  factory OperatorCapability.fromJson(Map<String, dynamic> json) {
    final voiceAccess = json["voice_access"] is Map
        ? Map<String, dynamic>.from(json["voice_access"] as Map)
        : const <String, dynamic>{};
    return OperatorCapability(
      id: json["id"]?.toString() ?? "",
      name: json["name"]?.toString() ?? "",
      status: json["status"]?.toString() ?? "unknown",
      securityLevel: int.tryParse(json["security_level"].toString()) ?? 3,
      risk: json["risk"]?.toString() ?? "unknown",
      requiredFactors: ((json["required_factors"] as List?) ?? const [])
          .map((factor) => factor.toString())
          .toList(growable: false),
      silentFactorRequired: voiceAccess["silent_factor_required"] == true,
    );
  }
}

class OperatorPreflightResult {
  const OperatorPreflightResult.approved({
    required this.capability,
    required this.tier,
  }) : approved = true,
       reason = "Approved",
       missingFactors = const [];

  const OperatorPreflightResult.blocked({
    required this.capability,
    required this.tier,
    required this.reason,
    this.missingFactors = const [],
  }) : approved = false;

  final bool approved;
  final OperatorCapability? capability;
  final IovSecurityTier tier;
  final String reason;
  final List<String> missingFactors;
}

class OperatorCapabilityService {
  static const Duration _cacheWindow = Duration(seconds: 15);
  static DateTime? _lastLoadedAt;
  static Map<String, OperatorCapability> _capabilities = {};

  static Future<OperatorPreflightResult> preflightAction(
    String action, {
    DeviceTrustSnapshot? trust,
  }) async {
    final capabilityId = capabilityIdForAction(action);
    final capability = await capabilityById(capabilityId);
    final tier = tierForSecurityLevel(capability?.securityLevel ?? 3);

    if (capability == null) {
      return OperatorPreflightResult.blocked(
        capability: null,
        tier: tier,
        reason: "IOV no reconoce la capacidad necesaria para $action.",
      );
    }
    if (capability.status == "planned") {
      return OperatorPreflightResult.blocked(
        capability: capability,
        tier: tier,
        reason: "${capability.name} todavía está planeada, no activa.",
      );
    }
    if (capability.status != "implemented" && capability.status != "partial") {
      return OperatorPreflightResult.blocked(
        capability: capability,
        tier: tier,
        reason: "${capability.name} no está lista para ejecutarse.",
      );
    }

    if (trust != null && !trust.allows(tier)) {
      return OperatorPreflightResult.blocked(
        capability: capability,
        tier: tier,
        reason: "Falta confianza silenciosa para ${capability.name}.",
        missingFactors: trust.missingFactorsFor(tier),
      );
    }

    return OperatorPreflightResult.approved(capability: capability, tier: tier);
  }

  static Future<Map<String, OperatorCapability>> loadCapabilities({
    bool force = false,
  }) async {
    final loadedAt = _lastLoadedAt;
    if (!force &&
        loadedAt != null &&
        DateTime.now().difference(loadedAt) < _cacheWindow &&
        _capabilities.isNotEmpty) {
      return Map.unmodifiable(_capabilities);
    }

    final response = await OSvozApi.operatorCapabilities();
    final capabilities = ((response["capabilities"] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (json) =>
              OperatorCapability.fromJson(Map<String, dynamic>.from(json)),
        )
        .where((capability) => capability.id.isNotEmpty);
    _capabilities = {
      for (final capability in capabilities) capability.id: capability,
    };
    _lastLoadedAt = DateTime.now();
    return Map.unmodifiable(_capabilities);
  }

  static Future<OperatorCapability?> capabilityById(String id) async {
    final capabilities = await loadCapabilities();
    return capabilities[id];
  }

  static void seedForTesting(List<OperatorCapability> capabilities) {
    _capabilities = {
      for (final capability in capabilities) capability.id: capability,
    };
    _lastLoadedAt = DateTime.now();
  }

  static String capabilityIdForAction(String action) {
    switch (action) {
      case "OPEN_TERMINAL":
      case "OPEN_VSCODE":
      case "OPEN_PROJECT":
        return "system.open_app";
      case "LIST_FILES":
        return "project.read";
      case "RUN_FLUTTER":
      case "RUN_DIAGNOSTICS":
        return "project.run_diagnostics";
      default:
        return action.startsWith("EDITOR_")
            ? "code.apply_edit"
            : "system.open_app";
    }
  }

  static IovSecurityTier tierForSecurityLevel(int level) {
    if (level <= 1) return IovSecurityTier.routine;
    if (level == 2) return IovSecurityTier.personalWork;
    return IovSecurityTier.criticalAction;
  }
}
