import 'labvoice_api.dart';
import 'language_manager.dart';

class OperatorStatusSnapshot {
  final String status;
  final String summaryMode;
  final String spokenSummary;
  final int implementedCount;
  final int partialCount;
  final bool auditValid;

  const OperatorStatusSnapshot({
    required this.status,
    required this.summaryMode,
    required this.spokenSummary,
    required this.implementedCount,
    required this.partialCount,
    required this.auditValid,
  });

  bool get ready => status == "ready";
}

class OperatorStatusService {
  static Future<OperatorStatusSnapshot> fetch({
    String summaryMode = "quick",
  }) async {
    return fromPayload(
      await OSvozApi.operatorStatus(summaryMode: summaryMode),
      language: LanguageManager.isSpanish ? "es" : "en",
    );
  }

  static OperatorStatusSnapshot fromPayload(
    Map<String, dynamic> payload, {
    required String language,
  }) {
    final spoken = payload["spoken_summary"] as Map<String, dynamic>?;
    final capabilities = payload["capabilities"] as Map<String, dynamic>?;
    final security = payload["security"] as Map<String, dynamic>?;
    final implemented = capabilities?["implemented"] as List?;
    final partial = capabilities?["partial"] as List?;
    return OperatorStatusSnapshot(
      status: payload["status"]?.toString() ?? "degraded",
      summaryMode: payload["summary_mode"]?.toString() ?? "quick",
      spokenSummary:
          spoken?[language]?.toString() ??
          spoken?["es"]?.toString() ??
          "Estado operativo recibido.",
      implementedCount: implemented?.length ?? 0,
      partialCount: partial?.length ?? 0,
      auditValid: security?["audit_valid"] == true,
    );
  }
}
