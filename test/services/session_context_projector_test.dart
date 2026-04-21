import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_message.dart';
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
        isNot(contains('准备执行工具：read')),
      );
      expect(messages.map((m) => m.role.name), ['assistant', 'user']);
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
        '已读取文件：agent/my_hobbies.md',
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
