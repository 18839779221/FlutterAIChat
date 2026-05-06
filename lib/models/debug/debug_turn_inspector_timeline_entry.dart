enum DebugTurnTimelineSource {
  persisted,
  runtime,
  trace,
}

enum DebugTimelineSeverity {
  info,
  warning,
  error,
}

/// One normalized row shown in the debug inspector timeline tab.
class DebugTurnTimelineEntry {
  final String id;
  final DateTime timestamp;
  final String kind;
  final String title;
  final String summary;
  final DebugTurnTimelineSource source;
  final DebugTimelineSeverity severity;
  final Map<String, dynamic>? payloadJson;

  const DebugTurnTimelineEntry({
    required this.id,
    required this.timestamp,
    required this.kind,
    required this.title,
    required this.summary,
    required this.source,
    required this.severity,
    this.payloadJson,
  });
}
