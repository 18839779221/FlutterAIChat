import '../../services/prompt/prompt_locale.dart';
import 'localized_tool_text.dart';

/// Describes one tool input field exposed to the planner layer.
class ToolArgumentProperty {
  /// Primitive JSON schema type such as `string` or `integer`.
  final String type;

  /// Human-readable field meaning shown to the model.
  final String description;

  /// Optional localized description overrides; English remains the default.
  final LocalizedToolText? localizedDescription;

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
    this.localizedDescription,
    this.enumValues,
    this.format,
    this.properties,
    this.required,
    this.items,
    this.additionalProperties,
  });

  const ToolArgumentProperty.string({
    required String description,
    LocalizedToolText? localizedDescription,
    List<String>? enumValues,
    String? format,
  }) : this(
          type: 'string',
          description: description,
          localizedDescription: localizedDescription,
          enumValues: enumValues,
          format: format,
        );

  const ToolArgumentProperty.integer({
    required String description,
    LocalizedToolText? localizedDescription,
  }) : this(
          type: 'integer',
          description: description,
          localizedDescription: localizedDescription,
        );

  String resolveDescription(PromptLocale locale) {
    return localizedDescription?.resolve(locale) ?? description;
  }

  Map<String, dynamic> toJsonSchema({
    PromptLocale locale = PromptLocale.english,
  }) {
    return {
      'type': type,
      'description': resolveDescription(locale),
      if (enumValues != null && enumValues!.isNotEmpty) 'enum': enumValues,
      if (format != null && format!.trim().isNotEmpty) 'format': format,
      if (properties != null && properties!.isNotEmpty)
        'properties': {
          for (final entry in properties!.entries)
            entry.key: entry.value.toJsonSchema(locale: locale),
        },
      if (required != null && required!.isNotEmpty) 'required': required,
      if (items != null) 'items': items!.toJsonSchema(locale: locale),
      if (additionalProperties != null)
        'additionalProperties': additionalProperties,
    };
  }
}
