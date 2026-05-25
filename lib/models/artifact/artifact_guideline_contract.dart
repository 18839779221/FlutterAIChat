/// Structured guideline payload returned before explanatory artifact creation.
class ArtifactGuidelineContract {
  /// Brief instruction telling the model how to consume this contract.
  final String usage;

  /// Host-provided wrapper markup and token contract shown as a code snippet.
  final String hostMarkupContract;

  /// Layout constraints that keep the artifact native-feeling inside chat.
  final List<String> layoutConstraints;

  /// Rendering rules the generated artifact should follow.
  final List<String> renderingRules;

  const ArtifactGuidelineContract({
    required this.usage,
    required this.hostMarkupContract,
    required this.layoutConstraints,
    required this.renderingRules,
  });

  Map<String, dynamic> toJson() {
    return {
      'usage': usage,
      'host_markup_contract': hostMarkupContract,
      'layout_constraints': layoutConstraints,
      'rendering_rules': renderingRules,
    };
  }
}
