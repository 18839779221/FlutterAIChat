import '../../services/prompt/prompt_locale.dart';
import 'localized_tool_text.dart';
import 'tool_argument_property.dart';
import 'tool_argument_schema.dart';

/// Runtime handling mode used by the turn loop before invoking a tool handler.
enum ToolRuntimeKind {
  immediate,
  requiresConfirmation,
  userInteraction,
}

class ToolDefinition {
  final String name;
  final String title;
  final Map<String, String> parameters;
  final String descriptionForModel;
  final LocalizedToolText? localizedTitle;
  final LocalizedToolText? localizedDescriptionForModel;
  final ToolArgumentSchema? argumentSchema;
  final bool requiresConfirmation;
  final ToolRuntimeKind runtimeKind;
  final List<String> supportedPlatforms;

  const ToolDefinition({
    required this.name,
    String? title,
    this.parameters = const {},
    String? descriptionForModel,
    this.localizedTitle,
    this.localizedDescriptionForModel,
    this.argumentSchema,
    this.requiresConfirmation = false,
    this.runtimeKind = ToolRuntimeKind.immediate,
    this.supportedPlatforms = const ['android', 'ios', 'web'],
  })  : title = title ?? name,
        descriptionForModel = descriptionForModel ?? title ?? name;

  /// Returns the planner-facing input schema, falling back to legacy
  /// `parameters` when handlers have not been migrated yet.
  ToolArgumentSchema get resolvedArgumentSchema {
    return argumentSchema ?? _buildSchemaFromLegacyParameters(parameters);
  }

  String resolveTitle(PromptLocale locale) {
    return localizedTitle?.resolve(locale) ?? title;
  }

  String resolveDescriptionForModel(PromptLocale locale) {
    return localizedDescriptionForModel?.resolve(locale) ?? descriptionForModel;
  }

  Map<String, dynamic> toPlannerJsonSchema({
    PromptLocale locale = PromptLocale.english,
  }) {
    return resolvedArgumentSchema.toJsonSchema(locale: locale);
  }

  ToolRuntimeKind get resolvedRuntimeKind {
    if (runtimeKind != ToolRuntimeKind.immediate) {
      return runtimeKind;
    }
    if (requiresConfirmation) {
      return ToolRuntimeKind.requiresConfirmation;
    }
    return ToolRuntimeKind.immediate;
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
