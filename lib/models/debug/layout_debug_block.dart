/// Supported block kinds for the layout debug page.
enum LayoutDebugBlockType {
  /// A full assistant document block with optional label and reasoning.
  assistantDoc,
}

/// Fixed preview block used by the document layout debug page.
class LayoutDebugBlock {
  /// The concrete block renderer to use on the preview page.
  final LayoutDebugBlockType type;

  /// The Markdown body rendered inside the real assistant doc component.
  final String markdownText;

  /// Optional small label shown above the assistant document content.
  final String? label;

  /// Optional reasoning text rendered before the Markdown body.
  final String? reasoningText;

  /// Optional stable cache key override for Markdown subtree reuse.
  final String? markdownCacheKey;

  const LayoutDebugBlock({
    required this.type,
    required this.markdownText,
    this.label,
    this.reasoningText,
    this.markdownCacheKey,
  });
}
