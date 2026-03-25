/// A lightweight placeholder for structured card payloads returned by LLMs.
class StructuredCard {
  final String? title;
  final String? subtitle;
  final Map<String, dynamic>? metadata;

  const StructuredCard({
    this.title,
    this.subtitle,
    this.metadata,
  });
}
