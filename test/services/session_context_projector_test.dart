import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/context/model_context_item.dart';
import 'package:ai_chat/services/session_context_projector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionContextProjector', () {
    test(
        'projects payload-backed tool result and user interaction result into compact context messages',
        () {
      final projector = SessionContextProjector();

      final messages = projector.projectEventsToContext([
        ChatEvent(
          turnId: 1,
          groupId: 1,
          sequence: 1,
          eventType: ChatEventType.toolResult,
          role: MessageRole.system,
          content: '已读取文件：db/version.txt',
          payloadJson: const {
            'toolName': 'Read',
            'status': 'success',
            'summary': '已读取文件：db/version.txt',
            'data': {
              'filePath': 'db/version.txt',
              'message': '数据库版本是 9',
            },
          },
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
      // assistantToolCall no longer projects (round-trip uses snapshot)
      expect(messages.map((m) => m.role.name), ['user', 'user']);
    });

    test('projects tool result from structured payload instead of summary-only text', () {
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
            'data': {
              'filePath': 'agent/my_hobbies.md',
              'message': '已读取文件：agent/my_hobbies.md',
            },
          },
        ),
      );

      expect(
        message?.text,
        '[user tool_result] Read path: agent/my_hobbies.md\n已读取文件：agent/my_hobbies.md',
      );
      expect(message?.role, MessageRole.user);
    });

    test('assistant events project to null (round-trip uses snapshot)', () {
      final projector = SessionContextProjector();
      for (final type in [
        ChatEventType.assistantToolCall,
        ChatEventType.assistantPlannerMessage,
        ChatEventType.assistantQuestionPrompt,
      ]) {
        final item = projector.projectEventToContextItem(
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: type,
            role: MessageRole.assistant,
            content: 'anything',
            payloadJson: const {'providerCallId': 'c1', 'toolName': 'X'},
          ),
        );
        expect(item, isNull, reason: '$type should not project');
      }
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
            'data': {
              'filePath': 'my_hobbies.md',
              'message': 'Successfully edited my_hobbies.md',
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
            'data': {
              'filePath': 'my_hobbies.md',
              'message': 'Successfully edited my_hobbies.md',
            },
          },
        ),
      );

      expect(item, isNotNull);
      expect(item!.type, ModelContextItemType.userToolResult);
      expect(item.toolName, 'Edit');
      expect(item.providerCallId, 'call_edit_1');
      expect(item.text, 'Edit path: my_hobbies.md\nSuccessfully edited my_hobbies.md');
      expect(message, isNotNull);
      expect(message!.role, MessageRole.user);
      expect(message.payloadJson?['providerCallId'], 'call_edit_1');
      expect(
        message.text,
        '[user tool_result] Edit path: my_hobbies.md\nSuccessfully edited my_hobbies.md',
      );
    });

    test('projects structured action result instead of falling back to summary', () {
      final projector = SessionContextProjector();

      final message = projector.projectEventToContext(
        ChatEvent(
          turnId: 1,
          groupId: 1,
          sequence: 1,
          eventType: ChatEventType.toolResult,
          role: MessageRole.system,
          content: '已创建提醒：今晚 8 点同步',
          payloadJson: const {
            'toolName': 'create_reminder',
            'status': 'success',
            'summary': '已创建提醒：今晚 8 点同步',
            'data': {
              'title': '同步',
              'scheduledAt': '今晚 8 点',
            },
          },
        ),
      );

      expect(
        message?.text,
        '[user tool_result] create_reminder status: success\ntitle: 同步\nscheduledAt: 今晚 8 点',
      );
      expect(message?.role, MessageRole.user);
    });

    test('projects skill tool result into invoked skill reminder text', () {
      final projector = SessionContextProjector();

      final message = projector.projectEventToContext(
        ChatEvent(
          turnId: 1,
          groupId: 1,
          sequence: 1,
          eventType: ChatEventType.toolResult,
          role: MessageRole.system,
          content: 'Skill loaded: verify',
          payloadJson: const {
            'toolName': 'skill',
            'status': 'success',
            'summary': 'Skill loaded: verify',
            'data': {
              'skillId': 'verify',
              'name': 'verify',
              'qualifiedPath': '/skills/installed/verify',
              'baseDirectory': '/skills/installed/verify',
              'instructionBody': 'After code changes, verify by:\n1. Run tests',
            },
          },
        ),
      );

      expect(message, isNotNull);
      expect(message!.role, MessageRole.user);
      expect(message.text, contains('<system-reminder>'));
      expect(message.text, contains('### Skill: verify'));
      expect(message.text, contains('Path: /skills/installed/verify'));
      expect(
        message.text,
        contains('Base directory for this skill: /skills/installed/verify'),
      );
      expect(message.text, contains('After code changes, verify by:'));
    });

    test('falls back to event content when tool error has no payload', () {
      final projector = SessionContextProjector();

      final message = projector.projectEventToContext(
        ChatEvent(
          turnId: 1,
          groupId: 1,
          sequence: 1,
          eventType: ChatEventType.toolError,
          role: MessageRole.system,
          content: 'Read failed: file not found',
        ),
      );

      expect(
        message?.text,
        '[user tool_result] Read failed: file not found',
      );
      expect(message?.role, MessageRole.user);
    });

    test(
        'falls back to event content when structured tool payload projects to empty text',
        () {
      final projector = SessionContextProjector();

      final message = projector.projectEventToContext(
        ChatEvent(
          turnId: 1,
          groupId: 1,
          sequence: 1,
          eventType: ChatEventType.toolResult,
          role: MessageRole.system,
          content: 'Tool finished but only summary is available',
          payloadJson: const {
            'toolName': 'unknown_tool',
            'status': 'success',
            'summary': '',
            'data': {},
          },
        ),
      );

      expect(
        message?.text,
        '[user tool_result] Tool finished but only summary is available',
      );
      expect(message?.role, MessageRole.user);
    });

    test(
        'projects AskUserQuestion answer as user tool_result when providerCallId is present',
        () {
      final projector = SessionContextProjector();

      final item = projector.projectEventToContextItem(
        ChatEvent(
          turnId: 1,
          groupId: 1,
          sequence: 3,
          eventType: ChatEventType.userInteractionResult,
          role: MessageRole.system,
          content: '用户回答：Android',
          payloadJson: const {'providerCallId': 'call_ask_1'},
        ),
      );

      expect(item?.type, ModelContextItemType.userToolResult);
      expect(item?.providerCallId, 'call_ask_1');
      expect(item?.text, contains('Android'));
    });

    test('projects snapshot text as a user context message', () {
      final projector = SessionContextProjector();

      final message = projector.projectSnapshotToContext(
        '当前目标：完成 Session 上下文管理',
      );

      expect(message.role, MessageRole.user);
      expect(message.text, contains('当前目标'));
      expect(message.status, MessageStatus.completed);
    });
  });
}
