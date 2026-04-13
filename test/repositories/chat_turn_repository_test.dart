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
      final storage =
          DatabaseHelper(databaseName: 'chat_turn_repository_test_v8.db');
      final repository = ChatTurnRepository(storage);
      final groupId =
          await storage.insertGroup(ChatGroup(title: 'turn repo group'));

      final turn = ChatTurn(
        groupId: groupId,
        status: ChatTurnStatus.running,
        userInput: '帮我查一下文档',
        goalSummary: '先搜索再回答',
        providerStyle: ChatTurnProviderStyle.openaiChatCompletions,
        modelName: 'gpt-5.4',
        providerStateJson: const {'response_id': 'resp_1'},
      );

      final turnId = await repository.createTurn(turn);
      final created = await repository.getTurn(turnId);

      expect(created, isNotNull);
      expect(created!.status, ChatTurnStatus.running);
      expect(created.iterationCount, 0);
      expect(created.toolCallCount, 0);
      expect(created.goalSummary, '先搜索再回答');
      expect(
        created.providerStyle,
        ChatTurnProviderStyle.openaiChatCompletions,
      );
      expect(created.modelName, 'gpt-5.4');
      expect(created.providerStateJson, containsPair('response_id', 'resp_1'));

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
      final storage = DatabaseHelper(
          databaseName: 'chat_turn_repository_cancel_test_v8.db');
      final repository = ChatTurnRepository(storage);
      final groupId =
          await storage.insertGroup(ChatGroup(title: 'turn repo group'));

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

    test('can update runtime provider state for an existing turn', () async {
      final storage = DatabaseHelper(
          databaseName: 'chat_turn_repository_runtime_state_test_v8.db');
      final repository = ChatTurnRepository(storage);
      final groupId =
          await storage.insertGroup(ChatGroup(title: 'turn repo group'));

      final turnId = await repository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.running,
          userInput: '继续执行 tool loop',
        ),
      );

      await repository.updateRuntimeState(
        turnId,
        providerStyle: ChatTurnProviderStyle.openaiResponses,
        modelName: 'gpt-5.4',
        providerStateJson: const {'response_id': 'resp_2'},
      );

      final updated = await repository.getTurn(turnId);
      expect(updated, isNotNull);
      expect(updated!.providerStyle, ChatTurnProviderStyle.openaiResponses);
      expect(updated.modelName, 'gpt-5.4');
      expect(updated.providerStateJson, containsPair('response_id', 'resp_2'));

      await storage.deleteGroup(groupId);
    });
  });
}
