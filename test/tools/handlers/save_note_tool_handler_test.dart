import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/tools/core/tool_execution_context.dart';
import 'package:ai_chat/tools/handlers/save_note_tool_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SaveNoteToolHandler', () {
    test('normalizes title content and folder before executing note save', () async {
      final handler = SaveNoteToolHandler(
        noteSaver: ({required title, required content, folder}) async => ToolResult(
          toolName: 'save_note',
          status: ToolExecutionStatus.success,
          summary: '已保存笔记：$title',
          data: {
            'title': title,
            'content': content,
            'folder': folder,
          },
        ),
      );

      final resolution = await handler.normalizeArguments(
        rawArguments: {
          'title': '  Tool Runtime  ',
          'content': '  需要继续重构 tool runtime  ',
          'folder': '  architecture  ',
        },
        userMessage: '帮我记下来',
        history: const [],
        now: DateTime(2026, 4, 12),
      );

      expect(resolution.isValid, isTrue);
      expect(resolution.normalizedArguments['title'], 'Tool Runtime');
      expect(resolution.normalizedArguments['content'], '需要继续重构 tool runtime');
      expect(resolution.normalizedArguments['folder'], 'architecture');

      final result = await handler.execute(
        ToolExecutionContext(
          groupId: 1,
          toolName: 'save_note',
          arguments: resolution.normalizedArguments,
          history: const <ChatMessage>[],
          now: DateTime(2026, 4, 12),
        ),
      );

      expect(result.status, ToolExecutionStatus.success);
      expect(result.data['title'], 'Tool Runtime');
      expect(result.data['folder'], 'architecture');
    });
  });
}
