import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/context/model_context_item.dart';
import 'package:ai_chat/services/session_context_projector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionContextProjector', () {
    test(
        'projects tool result and user interaction result into compact context messages',
        () {
      final projector = SessionContextProjector();

      final messages = projector.projectEventsToContext([
        ChatEvent(
          turnId: 1,
          groupId: 1,
          sequence: 1,
          eventType: ChatEventType.toolResult,
          role: MessageRole.system,
          content: '以下是工具 `read` 的执行结果，请结合这些信息回答用户。\n结果摘要：数据库版本是 9',
        ),
        ChatEvent(
          turnId: 1,
          groupId: 1,
          sequence: 2,
          eventType: ChatEventType.userInteractionResult,
          role: MessageRole.system,
          content: '用户回答：目标平台仅 Android',
        ),
        ChatEvent(
          turnId: 1,
          groupId: 1,
          sequence: 3,
          eventType: ChatEventType.assistantToolCall,
          role: MessageRole.assistant,
          content: '准备执行工具：read',
        ),
      ]);

      expect(messages.map((m) => m.text).join('\n'), contains('数据库版本是 9'));
      expect(messages.map((m) => m.text).join('\n'), contains('目标平台仅 Android'));
      expect(
        messages.map((m) => m.text).join('\n'),
        contains('[assistant tool_use]'),
      );
      expect(messages.map((m) => m.text).join('\n'), contains('read'));
      expect(messages.map((m) => m.role.name), ['user', 'user', 'assistant']);
    });

    test('uses tool-provided model context text from payload', () {
      final projector = SessionContextProjector();

      final message = projector.projectEventToContext(
        ChatEvent(
          turnId: 1,
          groupId: 1,
          sequence: 1,
          eventType: ChatEventType.toolResult,
          role: MessageRole.system,
          content: '已读取文件：my_hobbies.md',
          payloadJson: const {
            'toolName': 'Read',
            'status': 'success',
            'summary': '已读取文件：my_hobbies.md',
            'toolResultText': '已读取文件：agent/my_hobbies.md',
            'data': {
              'filePath': 'agent/my_hobbies.md',
            },
          },
        ),
      );

      expect(
        message?.text,
        '[user tool_result] 已读取文件：agent/my_hobbies.md',
      );
      expect(message?.role, MessageRole.user);
    });

    test('projects assistant tool call into tagged tool-use context message', () {
      final projector = SessionContextProjector();
      final item = projector.projectEventToContextItem(
        ChatEvent(
          turnId: 1,
          groupId: 1,
          sequence: 1,
          eventType: ChatEventType.assistantToolCall,
          role: MessageRole.assistant,
          content: '准备执行工具：编辑文件',
          payloadJson: const {
            'toolName': 'Edit',
            'providerCallId': 'call_edit_1',
            'arguments': {
              'file_path': 'my_hobbies.md',
              'old_string': '篮球',
              'new_string': '篮球\n游戏',
            },
          },
        ),
      );

      final message = projector.projectEventToContext(
        ChatEvent(
          turnId: 1,
          groupId: 1,
          sequence: 1,
          eventType: ChatEventType.assistantToolCall,
          role: MessageRole.assistant,
          content: '准备执行工具：编辑文件',
          payloadJson: const {
            'toolName': 'Edit',
            'providerCallId': 'call_edit_1',
            'arguments': {
              'file_path': 'my_hobbies.md',
              'old_string': '篮球',
              'new_string': '篮球\n游戏',
            },
          },
        ),
      );

      expect(item, isNotNull);
      expect(item!.type, ModelContextItemType.assistantToolUse);
      expect(item.toolName, 'Edit');
      expect(item.providerCallId, 'call_edit_1');
      expect(message, isNotNull);
      expect(message!.role, MessageRole.assistant);
      expect(message.payloadJson?['providerCallId'], 'call_edit_1');
      expect(message.text, contains('[assistant tool_use]'));
      expect(message.text, contains('Edit'));
      expect(message.text, contains('my_hobbies.md'));
    });

    test(
        'projects successful outcome tool result as user tool-result instead of assistant summary',
        () {
      final projector = SessionContextProjector();
      final item = projector.projectEventToContextItem(
        ChatEvent(
          turnId: 1,
          groupId: 1,
          sequence: 1,
          eventType: ChatEventType.toolResult,
          role: MessageRole.system,
          content: '已编辑文件：my_hobbies.md',
          payloadJson: const {
            'toolName': 'Edit',
            'providerCallId': 'call_edit_1',
            'status': 'success',
            'summary': '已编辑文件：my_hobbies.md',
            'toolResultText': 'Successfully edited my_hobbies.md',
            'data': {
              'filePath': 'my_hobbies.md',
            },
          },
        ),
      );

      final message = projector.projectEventToContext(
        ChatEvent(
          turnId: 1,
          groupId: 1,
          sequence: 1,
          eventType: ChatEventType.toolResult,
          role: MessageRole.system,
          content: '已编辑文件：my_hobbies.md',
          payloadJson: const {
            'toolName': 'Edit',
            'providerCallId': 'call_edit_1',
            'status': 'success',
            'summary': '已编辑文件：my_hobbies.md',
            'toolResultText': 'Successfully edited my_hobbies.md',
            'data': {
              'filePath': 'my_hobbies.md',
            },
          },
        ),
      );

      expect(item, isNotNull);
      expect(item!.type, ModelContextItemType.userToolResult);
      expect(item.toolName, 'Edit');
      expect(item.providerCallId, 'call_edit_1');
      expect(item.text, 'Successfully edited my_hobbies.md');
      expect(message, isNotNull);
      expect(message!.role, MessageRole.user);
      expect(message.payloadJson?['providerCallId'], 'call_edit_1');
      expect(
        message.text,
        '[user tool_result] Successfully edited my_hobbies.md',
      );
    });

    test('projects snapshot text as a system context message', () {
      final projector = SessionContextProjector();

      final message = projector.projectSnapshotToContext(
        '当前目标：完成 Session 上下文管理',
      );

      expect(message.role, MessageRole.system);
      expect(message.text, contains('当前目标'));
      expect(message.status, MessageStatus.completed);
    });
  });
}
