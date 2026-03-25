class StructuredSummaryCard {
  final String title;
  final String summary;
  final List<String> keyPoints;
  final List<String> actionItems;
  final List<String> risks;

  const StructuredSummaryCard({
    required this.title,
    required this.summary,
    required this.keyPoints,
    required this.actionItems,
    required this.risks,
  });

  factory StructuredSummaryCard.fromJson(Map<String, dynamic> json) {
    return StructuredSummaryCard(
      title: _requireString(json, 'title'),
      summary: _requireString(json, 'summary'),
      keyPoints: _requireStringList(json, 'keyPoints'),
      actionItems: _requireStringList(json, 'actionItems'),
      risks: _requireStringList(json, 'risks'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'summary': summary,
      'keyPoints': keyPoints,
      'actionItems': actionItems,
      'risks': risks,
    };
  }

  static String _requireString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      throw const FormatException('Invalid structured summary string field.');
    }
    return value;
  }

  static List<String> _requireStringList(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! List) {
      throw const FormatException('Invalid structured summary list field.');
    }

    final list = value.map((item) {
      if (item is! String) {
        throw const FormatException('Invalid structured summary list item.');
      }
      return item;
    }).toList();

    return List<String>.unmodifiable(list);
  }
}
