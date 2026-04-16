import 'tool_card_presentation_variant.dart';

/// Compact UI model derived from workflow steps or tool results.
class ToolCardPresentationModel {
  /// Semantic variant that determines the card family and emphasis level.
  final ToolCardPresentationVariant variant;

  /// Primary title shown in the rendered card.
  final String title;

  /// Short supporting summary shown under the title.
  final String summary;

  /// Structured fields surfaced in richer variants like outcome cards.
  final Map<String, String> primaryFields;

  /// Optional status label shown in compact rows or headers.
  final String? statusLabel;

  const ToolCardPresentationModel({
    required this.variant,
    required this.title,
    required this.summary,
    this.primaryFields = const {},
    this.statusLabel,
  });
}
