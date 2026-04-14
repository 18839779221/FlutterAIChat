import 'package:ai_chat/models/chat_turn.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatTurn serialization', () {
    test('toMap and fromMap round-trip status counters and timestamps', () {
      final createdAt = DateTime.fromMillisecondsSinceEpoch(1712900000000);
      final updatedAt = createdAt.add(const Duration(minutes: 5));
      final completedAt = updatedAt.add(const Duration(minutes: 1));
      final turn = ChatTurn(
        id: 7,
        groupId: 3,
        status: ChatTurnStatus.awaitingToolConfirmation,
        userInput: '请先查一下历史记录',
        iterationCount: 2,
        toolCallCount: 1,
        stopReason: 'waiting_for_user_confirmation',
        errorMessage: 'tool requires confirmation',
        createdAt: createdAt,
        updatedAt: updatedAt,
        completedAt: completedAt,
      );

      final serialized = turn.toMap();
      final restored = ChatTurn.fromMap(serialized);

      expect(serialized['status'], 'awaitingToolConfirmation');
      expect(serialized['iteration_count'], 2);
      expect(serialized['tool_call_count'], 1);
      expect(restored.id, 7);
      expect(restored.groupId, 3);
      expect(restored.status, ChatTurnStatus.awaitingToolConfirmation);
      expect(restored.userInput, '请先查一下历史记录');
      expect(restored.iterationCount, 2);
      expect(restored.toolCallCount, 1);
      expect(restored.stopReason, 'waiting_for_user_confirmation');
      expect(restored.errorMessage, 'tool requires confirmation');
      expect(restored.createdAt, createdAt);
      expect(restored.updatedAt, updatedAt);
      expect(restored.completedAt, completedAt);
    });

    test('fromMap falls back to running when status is unknown', () {
      final restored = ChatTurn.fromMap({
        'id': 1,
        'group_id': 9,
        'status': 'unexpected',
        'user_input': 'hello',
        'iteration_count': 0,
        'tool_call_count': 0,
        'created_at': 1712900000000,
        'updated_at': 1712900000000,
        'completed_at': null,
      });

      expect(restored.status, ChatTurnStatus.running);
    });

    test('fromMap can restore awaiting user interaction status', () {
      final restored = ChatTurn.fromMap({
        'id': 2,
        'group_id': 9,
        'status': 'awaitingUserInteraction',
        'user_input': '需要更多信息',
        'iteration_count': 1,
        'tool_call_count': 1,
        'created_at': 1712900000000,
        'updated_at': 1712900000000,
        'completed_at': null,
      });

      expect(restored.status, ChatTurnStatus.awaitingUserInteraction);
    });
  });
}
