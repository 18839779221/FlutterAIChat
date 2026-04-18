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

  /// Nested object properties when this field is an object.
  final Map<String, ToolArgumentProperty>? properties;

  /// Required property names for nested object fields.
  final List<String>? required;

  /// Item schema when this field is an array.
  final ToolArgumentProperty? items;

  /// Whether nested object fields may accept unspecified keys.
  final bool? additionalProperties;

  const ToolArgumentProperty({
    required this.type,
    required this.description,
    this.enumValues,
    this.format,
    this.properties,
    this.required,
    this.items,
    this.additionalProperties,
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
      if (properties != null && properties!.isNotEmpty)
        'properties': {
          for (final entry in properties!.entries)
            entry.key: entry.value.toJsonSchema(),
        },
      if (required != null && required!.isNotEmpty) 'required': required,
      if (items != null) 'items': items!.toJsonSchema(),
      if (additionalProperties != null)
        'additionalProperties': additionalProperties,
    };
  }
}
