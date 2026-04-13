import '../models/tool/tool_definition.dart';

/// Renders the planner-facing system prompt from visible tool metadata.
class PlannerPromptBuilder {
  String buildSystemPrompt({
    required List<PlannerPromptTool> visibleTools,
    bool allowMultiToolPlanning = false,
  }) {
    final buffer = StringBuffer()..writeln('你是一个对话回合规划器。');

    if (allowMultiToolPlanning) {
      buffer
        ..writeln('你可以在一个回合内规划并调用多个工具。')
        ..writeln('如果信息已足够，则直接回答用户。')
        ..writeln('使用原生工具调用，不要输出 JSON，不要输出 Markdown，不要输出解释。');
    } else {
      buffer
        ..writeln('你每次只能做一件事：')
        ..writeln('1. 直接回复用户，返回 {"action":"respond","response":"..."}')
        ..writeln(
          '2. 调用一个工具，返回 {"action":"call_tool","toolName":"...","arguments":{...}}',
        )
        ..writeln('只返回 JSON，不要输出 Markdown，不要输出解释。');
    }
    buffer.writeln('如果已有足够信息则直接回答用户，不要为了调用工具而调用工具。');
    buffer.writeln('如果同一回合里某个工具用相同参数已经执行过，且期间没有新的用户信息，不要重复调用它。');

    if (visibleTools.isEmpty) {
      buffer.writeln('当前没有可用工具，只能直接回答用户。');
      return buffer.toString().trim();
    }

    buffer
      ..writeln('当前可见工具：${visibleTools.map((tool) => tool.definition.name).join('、')}')
      ..writeln('你只能从上面的工具里选择。')
      ..writeln('以下是每个工具的定义：');

    for (final tool in visibleTools) {
      final definition = tool.definition;
      final schema = definition.toPlannerJsonSchema();
      final properties =
          (schema['properties'] as Map<String, dynamic>? ?? const {});
      final requiredFields = (schema['required'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(growable: false);

      buffer
        ..writeln('- 工具名：${definition.name}')
        ..writeln('  标题：${definition.title}')
        ..writeln('  描述：${definition.descriptionForModel}')
        ..writeln('  执行策略：${tool.executionPolicy}')
        ..writeln(
          '  什么时候使用：${definition.whenToUse.isEmpty ? '无额外说明' : definition.whenToUse.join('；')}',
        )
        ..writeln(
          '  什么时候不要使用：${definition.whenNotToUse.isEmpty ? '无额外说明' : definition.whenNotToUse.join('；')}',
        )
        ..writeln(
          '  必填参数：${requiredFields.isEmpty ? '无' : requiredFields.join('、')}',
        );

      if (properties.isNotEmpty) {
        buffer.writeln('  参数说明：');
        for (final entry in properties.entries) {
          final value = entry.value;
          if (value is! Map<String, dynamic>) {
            continue;
          }
          final type = (value['type'] ?? '').toString();
          final description = (value['description'] ?? '').toString();
          buffer.writeln('  - ${entry.key} [$type] $description');
        }
      }
    }

    return buffer.toString().trim();
  }
}

class PlannerPromptTool {
  final ToolDefinition definition;
  final String executionPolicy;

  const PlannerPromptTool({
    required this.definition,
    required this.executionPolicy,
  });
}
