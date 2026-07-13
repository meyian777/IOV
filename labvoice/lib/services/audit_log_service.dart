import 'dart:async';

import 'labvoice_api.dart';

class AuditLogService {
  static const _sensitiveKeys = {
    'token',
    'confirmation_token',
    'password',
    'secret',
    'api_key',
    'authorization',
  };

  static Future<void> record(
    String eventType,
    String outcome, {
    Map<String, dynamic> metadata = const {},
  }) async {
    try {
      await OSvozApi.appendAuditEvent(
        eventType: eventType,
        outcome: outcome,
        metadata: sanitize(metadata),
      );
    } catch (_) {
      // Audit transport must never block the operator flow. Backend health
      // still exposes whether the tamper-evident audit chain is available.
    }
  }

  static void recordLater(
    String eventType,
    String outcome, {
    Map<String, dynamic> metadata = const {},
  }) {
    unawaited(record(eventType, outcome, metadata: metadata));
  }

  static Map<String, dynamic> sanitize(Map<String, dynamic> metadata) {
    final sanitized = <String, dynamic>{};
    for (final entry in metadata.entries) {
      final key = entry.key.toLowerCase();
      if (_sensitiveKeys.any(key.contains)) continue;
      sanitized[entry.key] = _safeValue(entry.value);
    }
    return sanitized;
  }

  static Object? _safeValue(Object? value) {
    if (value is String && value.length > 240) {
      return '${value.substring(0, 240)}...';
    }
    if (value is Map) {
      return sanitize(Map<String, dynamic>.from(value));
    }
    if (value is Iterable) {
      return value.take(20).map(_safeValue).toList(growable: false);
    }
    return value;
  }
}
