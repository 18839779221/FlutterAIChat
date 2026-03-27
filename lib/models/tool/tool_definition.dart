class ToolDefinition {
  final String name;
  final String description;
  final Map<String, String> parameters;

  const ToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
  });
}
