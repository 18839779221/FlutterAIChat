/// Structured guideline payload returned before explanatory artifact creation.
class ArtifactGuidelineContract {
  /// Brief instruction telling the model how to consume this contract.
  final String usage;

  /// Optional raw guideline markdown preserved verbatim for model consumption.
  final String? rawGuidelineMarkdown;

  /// Host-provided wrapper markup and token contract shown as a code snippet.
  final String hostMarkupContract;

  /// Layout constraints that keep the artifact native-feeling inside chat.
  final List<String> layoutConstraints;

  /// Rendering rules the generated artifact should follow.
  final List<String> renderingRules;

  const ArtifactGuidelineContract({
    required this.usage,
    this.rawGuidelineMarkdown,
    required this.hostMarkupContract,
    required this.layoutConstraints,
    required this.renderingRules,
  });

  Map<String, dynamic> toJson() {
    return {
      'usage': usage,
      if ((rawGuidelineMarkdown ?? '').isNotEmpty)
        'raw_guideline_markdown': rawGuidelineMarkdown,
      'host_markup_contract': hostMarkupContract,
      'layout_constraints': layoutConstraints,
      'rendering_rules': renderingRules,
    };
  }
}
