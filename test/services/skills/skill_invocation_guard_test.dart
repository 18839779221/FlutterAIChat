import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/services/skills/skill_invocation_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SkillInvocationGuard', () {
    test('detects a successful skill invocation in current turn events', () {
      const guard = SkillInvocationGuard();

      final invoked = guard.wasSkillInvoked(
        events: [
          _toolResultEvent(
            status: 'success',
            data: const {'skillId': 'edge-to-edge', 'name': 'edge-to-edge'},
          ),
        ],
        skillId: 'edge-to-edge',
        skillName: 'edge-to-edge',
      );

      expect(invoked, isTrue);
    });

    test('ignores failed skill results', () {
      const guard = SkillInvocationGuard();

      final invoked = guard.wasSkillInvoked(
        events: [
          _toolResultEvent(
            status: 'failure',
            data: const {'skillId': 'edge-to-edge', 'name': 'edge-to-edge'},
          ),
        ],
        skillId: 'edge-to-edge',
        skillName: 'edge-to-edge',
      );

      expect(invoked, isFalse);
    });

    test('does not treat another skill as duplicate', () {
      const guard = SkillInvocationGuard();

      final invoked = guard.wasSkillInvoked(
        events: [
          _toolResultEvent(
            status: 'success',
            data: const {
              'skillId': 'verify-workflow',
              'name': 'Verify Workflow'
            },
          ),
        ],
        skillId: 'edge-to-edge',
        skillName: 'edge-to-edge',
      );

      expect(invoked, isFalse);
    });

    test('falls back to normalized skill name when skill id is absent', () {
      const guard = SkillInvocationGuard();

      final invoked = guard.wasSkillInvoked(
        events: [
          _toolResultEvent(
            status: 'success',
            data: const {'name': 'Verify Workflow'},
          ),
        ],
        skillId: 'verify-workflow',
        skillName: 'Verify Workflow',
      );

      expect(invoked, isTrue);
    });
  });
}

ChatEvent _toolResultEvent({
  required String status,
  required Map<String, dynamic> data,
}) {
  return ChatEvent(
    turnId: 1,
    groupId: 1,
    sequence: 1,
    eventType: ChatEventType.toolResult,
    role: MessageRole.system,
    payloadJson: {
      'toolName': 'skill',
      'status': status,
      'data': data,
    },
  );
}
