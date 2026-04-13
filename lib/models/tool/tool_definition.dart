import 'tool_argument_property.dart';
import 'tool_argument_schema.dart';

/// High-level grouping used for planner-side tool exposure and routing.
enum ToolCategory {
  retrieval,
  productivity,
  outputAction,
}

/// Stable capability tags used by planner/tool-policy layers to reason about
/// a tool without hard-coding concrete tool names.
enum ToolCapability {
  webSearch,
  webUrlReader,
  fileDiscovery,
  fileRead,
  fileWrite,
  fileEdit,
  noteWrite,
  reminderCreate,
  calendarCreate,
  shareResult,
}

class ToolDefinition {
  final String name;
  final String title;
  final String description;
  final Map<String, String> parameters;
  final ToolCategory category;
  final List<ToolCapability> capabilities;
  final String descriptionForModel;
  final List<String> whenToUse;
  final List<String> whenNotToUse;
  final ToolArgumentSchema? argumentSchema;
  final Map<String, dynamic> argumentExamples;
  final bool requiresConfirmation;
  final String riskLevel;
  final List<String> supportedPlatforms;

  const ToolDefinition({
    required this.name,
    String? title,
    required this.description,
    this.parameters = const {},
    this.category = ToolCategory.retrieval,
    this.capabilities = const [],
    String? descriptionForModel,
    this.whenToUse = const [],
    this.whenNotToUse = const [],
    this.argumentSchema,
    this.argumentExamples = const {},
    this.requiresConfirmation = false,
    this.riskLevel = 'low',
    this.supportedPlatforms = const ['android', 'ios', 'web'],
  })  : title = title ?? name,
        descriptionForModel = descriptionForModel ?? description;

  /// Returns the planner-facing input schema, falling back to legacy
  /// `parameters` when handlers have not been migrated yet.
  ToolArgumentSchema get resolvedArgumentSchema {
    return argumentSchema ?? _buildSchemaFromLegacyParameters(parameters);
  }

  Map<String, dynamic> toPlannerJsonSchema() {
    return resolvedArgumentSchema.toJsonSchema();
  }

  Map<String, dynamic> toPlannerDescriptor() {
    return {
      'name': name,
      'title': title,
      'category': category.name,
      'capabilities': capabilities.map((item) => item.name).toList(),
      'description': descriptionForModel,
      'whenToUse': whenToUse,
      'whenNotToUse': whenNotToUse,
      'inputSchema': toPlannerJsonSchema(),
      if (argumentExamples.isNotEmpty) 'argumentExamples': argumentExamples,
      'requiresConfirmation': requiresConfirmation,
      'riskLevel': riskLevel,
      'supportedPlatforms': supportedPlatforms,
    };
  }

  static ToolArgumentSchema _buildSchemaFromLegacyParameters(
    Map<String, String> parameters,
  ) {
    final properties = <String, ToolArgumentProperty>{};
    final required = <String>[];

    for (final entry in parameters.entries) {
      final rawType = entry.value.trim();
      final isOptional = rawType.endsWith('?');
      final normalizedType =
          isOptional ? rawType.substring(0, rawType.length - 1) : rawType;
      properties[entry.key] = ToolArgumentProperty(
        type: _mapLegacyTypeToJsonType(normalizedType),
        description: '${entry.key} parameter',
      );
      if (!isOptional) {
        required.add(entry.key);
      }
    }

    return ToolArgumentSchema(
      properties: properties,
      required: required,
    );
  }

  static String _mapLegacyTypeToJsonType(String value) {
    switch (value) {
      case 'int':
        return 'integer';
      case 'double':
      case 'num':
        return 'number';
      case 'bool':
        return 'boolean';
      case 'map':
      case 'object':
        return 'object';
      case 'list':
      case 'array':
        return 'array';
      case 'string':
      default:
        return 'string';
    }
  }
}
