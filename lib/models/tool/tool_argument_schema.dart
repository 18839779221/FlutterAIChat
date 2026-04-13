import 'tool_argument_property.dart';

/// Structured input schema exported to the planner layer.
class ToolArgumentSchema {
  /// Tool input fields keyed by argument name.
  final Map<String, ToolArgumentProperty> properties;

  /// Required argument names that must be present for execution.
  final List<String> required;

  const ToolArgumentSchema({
    required this.properties,
    this.required = const [],
  });

  Map<String, dynamic> toJsonSchema() {
    return {
      'type': 'object',
      'properties': {
        for (final entry in properties.entries) entry.key: entry.value.toJsonSchema(),
      },
      'required': required,
    };
  }
}
