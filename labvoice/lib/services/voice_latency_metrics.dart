class VoiceLatencyMetrics {
  static const Map<String, int> targetsMs = {
    "feedback_ms": 300,
    "capture_ms": 1200,
    "transcription_ms": 1500,
    "language_detection_ms": 80,
    "intent_ms": 100,
    "orchestration_ms": 150,
    "backend_intent_ms": 250,
    "execution_ms": 1200,
    "command_response_ms": 1500,
    "tts_ms": 1200,
    "total_ms": 2500,
  };

  static final Map<String, int> _latest = {};

  static Map<String, int> get latest => Map.unmodifiable(_latest);

  static void record(String key, Duration duration) {
    _latest[key] = duration.inMilliseconds;
    if (_latest.length <= 24) return;
    _latest.remove(_latest.keys.first);
  }

  static String compactSummary() {
    if (_latest.isEmpty) return "Sin métricas todavía.";
    return _latest.entries
        .map((entry) {
          final target = targetsMs[entry.key];
          final label = _label(entry.key);
          final status = target != null && entry.value > target
              ? "lento"
              : "ok";
          return target == null
              ? "$label ${entry.value} ms"
              : "$label ${entry.value} ms/$target $status";
        })
        .join(" · ");
  }

  static String _label(String key) => switch (key) {
    "feedback_ms" => "feedback",
    "capture_ms" => "captura",
    "transcription_ms" => "transcripción",
    "language_detection_ms" => "idioma",
    "intent_ms" => "intención",
    "orchestration_ms" => "orquestador",
    "backend_intent_ms" => "backend",
    "execution_ms" => "ejecución",
    "command_response_ms" => "respuesta",
    "tts_ms" => "voz",
    "total_ms" => "total",
    _ => key,
  };
}
