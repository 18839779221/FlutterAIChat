/// Planner-side tool declaration passed into structured planner requests.
class PlannerToolOption {
  /// Stable runtime tool name.
  final String name;

  /// Model-facing description of when the tool should be used.
  final String description;

  /// JSON schema for the tool input object.
  final Map<String, dynamic> inputSchema;

  const PlannerToolOption({
    required this.name,
    required this.description,
    required this.inputSchema,
  });
}
