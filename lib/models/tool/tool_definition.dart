class ToolDefinition {
  final String name;
  final String title;
  final String description;
  final Map<String, String> parameters;
  final bool requiresConfirmation;
  final String riskLevel;
  final List<String> supportedPlatforms;

  const ToolDefinition({
    required this.name,
    String? title,
    required this.description,
    required this.parameters,
    this.requiresConfirmation = false,
    this.riskLevel = 'low',
    this.supportedPlatforms = const ['android', 'ios', 'web'],
  }) : title = title ?? name;
}
