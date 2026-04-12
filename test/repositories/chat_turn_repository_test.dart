import 'package:ai_chat/database/database_helper.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/repositories/chat_turn_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ChatTurnRepository', () {
    test('create and load turn, then update status and counters', () async {
      final storage = DatabaseHelper(databaseName: 'chat_turn_repository_test.db');
      final repository = ChatTurnRepository(storage);
      final groupId = await storage.insertGroup(ChatGroup(title: 'turn repo group'));

      final turn = ChatTurn(
        groupId: groupId,
        status: ChatTurnStatus.running,
        userInput: '帮我查一下文档',
      );

      final turnId = await repository.createTurn(turn);
      final created = await repository.getTurn(turnId);

      expect(created, isNotNull);
      expect(created!.status, ChatTurnStatus.running);
      expect(created.iterationCount, 0);
      expect(created.toolCallCount, 0);

      await repository.markAwaitingToolConfirmation(turnId);
      await repository.incrementIterationAndToolCount(turnId);

      final updated = await repository.getTurn(turnId);
      expect(updated, isNotNull);
      expect(updated!.status, ChatTurnStatus.awaitingToolConfirmation);
      expect(updated.iterationCount, 1);
      expect(updated.toolCallCount, 1);

      await storage.deleteGroup(groupId);
    });

    test('can mark turn cancelled', () async {
      final storage =
          DatabaseHelper(databaseName: 'chat_turn_repository_cancel_test.db');
      final repository = ChatTurnRepository(storage);
      final groupId = await storage.insertGroup(ChatGroup(title: 'turn repo group'));

      final turn = ChatTurn(
        groupId: groupId,
        status: ChatTurnStatus.awaitingToolConfirmation,
        userInput: '提醒我交周报',
      );

      final turnId = await repository.createTurn(turn);
      await repository.markCancelled(
        turnId,
        stopReason: 'cancelled_by_user',
      );

      final updated = await repository.getTurn(turnId);
      expect(updated, isNotNull);
      expect(updated!.status, ChatTurnStatus.cancelled);
      expect(updated.stopReason, 'cancelled_by_user');

      await storage.deleteGroup(groupId);
    });
  });
}
