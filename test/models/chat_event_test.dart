import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatEvent serialization', () {
    test('toMap and fromMap round-trip payload and sequence fields', () {
      final createdAt = DateTime.fromMillisecondsSinceEpoch(1712900000000);
      final event = ChatEvent(
        id: 11,
        turnId: 5,
        groupId: 2,
        sequence: 4,
        eventType: ChatEventType.toolResult,
        role: MessageRole.system,
        status: 'success',
        content: '找到了 3 条相关结果',
        payloadJson: const {
          'toolName': 'search_chat_history',
          'matches': 3,
        },
        createdAt: createdAt,
      );

      final serialized = event.toMap();
      final restored = ChatEvent.fromMap(serialized);

      expect(serialized['event_type'], 'toolResult');
      expect(serialized['sequence'], 4);
      expect(restored.id, 11);
      expect(restored.turnId, 5);
      expect(restored.groupId, 2);
      expect(restored.sequence, 4);
      expect(restored.eventType, ChatEventType.toolResult);
      expect(restored.role, MessageRole.system);
      expect(restored.status, 'success');
      expect(restored.content, '找到了 3 条相关结果');
      expect(restored.payloadJson, const {
        'toolName': 'search_chat_history',
        'matches': 3,
      });
      expect(restored.createdAt, createdAt);
    });

    test('fromMap falls back to error when event type is unknown', () {
      final restored = ChatEvent.fromMap({
        'id': 1,
        'turn_id': 1,
        'group_id': 1,
        'sequence': 1,
        'event_type': 'unexpected',
        'role': 'assistant',
        'status': null,
        'content': 'fallback',
        'payload_json': null,
        'created_at': 1712900000000,
      });

      expect(restored.eventType, ChatEventType.error);
    });

    test('fromMap can restore interaction event types', () {
      final restored = ChatEvent.fromMap({
        'id': 2,
        'turn_id': 1,
        'group_id': 1,
        'sequence': 2,
        'event_type': 'assistantQuestionPrompt',
        'role': 'assistant',
        'status': null,
        'content': '请先回答几个问题',
        'payload_json': null,
        'created_at': 1712900000000,
      });

      expect(restored.eventType, ChatEventType.assistantQuestionPrompt);
    });
  });
}
