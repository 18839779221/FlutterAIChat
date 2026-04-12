import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/tool/tool_definition.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/tools/core/tool_argument_resolution.dart';
import 'package:ai_chat/tools/core/tool_execution_context.dart';
import 'package:ai_chat/tools/core/tool_handler.dart';
import 'package:ai_chat/tools/core/tool_runtime_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolRuntimeRegistry', () {
    test('returns registered handler by tool name', () {
      final registry = ToolRuntimeRegistry(
        handlers: [
          _FakeToolHandler(toolName: 'web_search'),
        ],
      );

      expect(registry.findHandler('web_search'), isNotNull);
      expect(registry.findHandler('missing_tool'), isNull);
    });

    test('does not resolve unknown tool names that are not explicitly registered', () {
      final registry = ToolRuntimeRegistry(
        handlers: [
          _FakeToolHandler(toolName: 'web_search'),
        ],
      );

      expect(registry.findHandler('search_news'), isNull);
    });

    test('exposes all tool definitions for decision service', () {
      final registry = ToolRuntimeRegistry(
        handlers: [
          _FakeToolHandler(toolName: 'web_search'),
          _FakeToolHandler(toolName: 'create_reminder'),
        ],
      );

      expect(
        registry.getAllDefinitions().map((item) => item.name).toList(),
        ['web_search', 'create_reminder'],
      );
    });
  });
}

class _FakeToolHandler implements ToolHandler {
  _FakeToolHandler({required this.toolName});

  final String toolName;

  @override
  ToolDefinition get definition => ToolDefinition(
        name: toolName,
        description: '$toolName description',
        parameters: const {
          'query': 'string',
        },
      );

  @override
  List<ChatMessage> buildContextMessages({
    required ToolResult result,
    required ToolExecutionContext context,
  }) {
    return const [];
  }

  @override
  Future<ToolResult> execute(ToolExecutionContext context) async {
    return ToolResult(
      toolName: toolName,
      status: ToolExecutionStatus.success,
      summary: 'ok',
    );
  }

  @override
  Future<ToolArgumentResolution> normalizeArguments({
    required Map<String, dynamic> rawArguments,
    required String userMessage,
    required List<ChatMessage> history,
    required DateTime now,
  }) async {
    return ToolArgumentResolution.valid(rawArguments);
  }
}
