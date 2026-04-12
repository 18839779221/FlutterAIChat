import 'package:ai_chat/database/database_helper.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/repositories/chat_event_repository.dart';
import 'package:ai_chat/repositories/chat_turn_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ChatEventRepository', () {
    test('append methods assign increasing sequence and list in order', () async {
      final storage = DatabaseHelper(databaseName: 'chat_event_repository_test.db');
      final turnRepository = ChatTurnRepository(storage);
      final repository = ChatEventRepository(storage);
      final groupId = await storage.insertGroup(ChatGroup(title: 'event repo group'));
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.running,
          userInput: '先查历史再回答',
        ),
      );

      await repository.appendUserMessage(
        turnId: turnId,
        groupId: groupId,
        content: '先查历史再回答',
      );
      await repository.appendToolResult(
        turnId: turnId,
        groupId: groupId,
        content: '已找到 2 条结果',
        payloadJson: const {'matches': 2},
      );

      final events = await repository.listEventsByTurn(turnId);

      expect(events, hasLength(2));
      expect(events.first.sequence, 1);
      expect(events.first.role, MessageRole.user);
      expect(events.last.sequence, 2);
      expect(events.last.payloadJson, const {'matches': 2});

      await storage.deleteGroup(groupId);
    });
  });
}
