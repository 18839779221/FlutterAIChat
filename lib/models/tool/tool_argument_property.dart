/// Describes one tool input field exposed to the planner layer.
class ToolArgumentProperty {
  /// Primitive JSON schema type such as `string` or `integer`.
  final String type;

  /// Human-readable field meaning shown to the model.
  final String description;

  /// Optional enum candidates for closed-value fields.
  final List<String>? enumValues;

  /// Optional schema format such as `uri` or `date-time`.
  final String? format;

  const ToolArgumentProperty({
    required this.type,
    required this.description,
    this.enumValues,
    this.format,
  });

  const ToolArgumentProperty.string({
    required String description,
    List<String>? enumValues,
    String? format,
  }) : this(
          type: 'string',
          description: description,
          enumValues: enumValues,
          format: format,
        );

  const ToolArgumentProperty.integer({
    required String description,
  }) : this(
          type: 'integer',
          description: description,
        );

  Map<String, dynamic> toJsonSchema() {
    return {
      'type': type,
      'description': description,
      if (enumValues != null && enumValues!.isNotEmpty) 'enum': enumValues,
      if (format != null && format!.trim().isNotEmpty) 'format': format,
    };
  }
}
