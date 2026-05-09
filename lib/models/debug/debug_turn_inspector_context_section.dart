/// One expandable section inside the debug inspector context tab.
class DebugTurnInspectorContextSection {
  final String id;
  final String title;
  final String summary;
  final Object? rawJson;
  final String? rawText;
  final bool defaultExpanded;

  const DebugTurnInspectorContextSection({
    required this.id,
    required this.title,
    required this.summary,
    required this.defaultExpanded,
    this.rawJson,
    this.rawText,
  });
}
