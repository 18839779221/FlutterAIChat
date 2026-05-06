/// Expandable raw-json section rendered in the debug inspector context tab.
class DebugTurnInspectorContextSection {
  final String id;
  final String title;
  final String summary;
  final bool defaultExpanded;
  final Object? rawJson;

  const DebugTurnInspectorContextSection({
    required this.id,
    required this.title,
    required this.summary,
    required this.defaultExpanded,
    required this.rawJson,
  });

  String? get rawText {
    final value = rawJson;
    return value is String ? value : null;
  }
}
