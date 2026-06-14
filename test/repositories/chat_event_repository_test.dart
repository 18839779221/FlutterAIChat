import 'package:ai_chat/database/database_helper.dart';
import 'package:ai_chat/models/chat_event.dart';
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

    test('concurrent append methods preserve every event with unique sequence',
        () async {
      final storage = DatabaseHelper(
        databaseName: 'chat_event_repository_concurrent_test.db',
      );
      final turnRepository = ChatTurnRepository(storage);
      final repository = ChatEventRepository(storage);
      final groupId =
          await storage.insertGroup(ChatGroup(title: 'concurrent event group'));
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.running,
          userInput: '并发执行多个 fetch_webpage',
        ),
      );

      await repository.appendUserMessage(
        turnId: turnId,
        groupId: groupId,
        content: '并发执行多个 fetch_webpage',
      );

      await Future.wait([
        repository.appendToolError(
          turnId: turnId,
          groupId: groupId,
          content: 'call_00 failed',
          errorCode: 'network_error',
          payloadJson: const {
            'providerCallId': 'call_00',
            'summary': 'call_00 failed',
            'errorMessage': 'network_error',
          },
        ),
        repository.appendToolResult(
          turnId: turnId,
          groupId: groupId,
          content: 'call_01 ok',
          payloadJson: const {
            'providerCallId': 'call_01',
            'summary': 'call_01 ok',
          },
        ),
        repository.appendToolError(
          turnId: turnId,
          groupId: groupId,
          content: 'call_02 failed',
          errorCode: 'network_error',
          payloadJson: const {
            'providerCallId': 'call_02',
            'summary': 'call_02 failed',
            'errorMessage': 'network_error',
          },
        ),
        repository.appendToolError(
          turnId: turnId,
          groupId: groupId,
          content: 'call_03 failed',
          errorCode: 'network_error',
          payloadJson: const {
            'providerCallId': 'call_03',
            'summary': 'call_03 failed',
            'errorMessage': 'network_error',
          },
        ),
        repository.appendToolError(
          turnId: turnId,
          groupId: groupId,
          content: 'call_04 failed',
          errorCode: 'network_error',
          payloadJson: const {
            'providerCallId': 'call_04',
            'summary': 'call_04 failed',
            'errorMessage': 'network_error',
          },
        ),
      ]);

      final events = await repository.listEventsByTurn(turnId);
      final sequences = events.map((event) => event.sequence).toList();
      final providerCallIds = events
          .map((event) => event.payloadJson?['providerCallId'])
          .whereType<String>()
          .toList();

      expect(events, hasLength(6));
      expect(sequences, [1, 2, 3, 4, 5, 6]);
      expect(
        providerCallIds,
        containsAll(const [
          'call_00',
          'call_01',
          'call_02',
          'call_03',
          'call_04',
        ]),
      );

      await storage.deleteGroup(groupId);
    });

    test('appendAssistantTurnSnapshot persists apiStyle + raw message JSON',
        () async {
      final storage = DatabaseHelper(
        databaseName: 'chat_event_repository_snapshot_test.db',
      );
      final turnRepository = ChatTurnRepository(storage);
      final repository = ChatEventRepository(storage);
      final groupId = await storage.insertGroup(
        ChatGroup(
          title: 'snapshot group',
        ),
      );
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.running,
          userInput: 'hello',
        ),
      );

      final raw = {
        'role': 'assistant',
        'content': 'Let me search',
        'reasoning_content': 'think first',
        'tool_calls': [
          {
            'id': 'call_1',
            'type': 'function',
            'function': {'name': 'search', 'arguments': '{"q":"x"}'},
          },
        ],
      };

      final event = await repository.appendAssistantTurnSnapshot(
        turnId: turnId,
        groupId: groupId,
        apiStyle: ChatTurnProviderStyle.openaiChatCompletions,
        rawAssistantMessageJson: raw,
      );

      expect(event.eventType, ChatEventType.assistantTurnSnapshot);
      expect(event.role, MessageRole.assistant);
      expect(event.payloadJson?['apiStyle'], 'openaiChatCompletions');
      expect(event.payloadJson?['rawAssistantMessage'], raw);

      final stored = await repository.listEventsByTurn(turnId);
      expect(stored, hasLength(1));
      expect(
        stored.single.payloadJson?['rawAssistantMessage'],
        raw,
      );

      await storage.deleteGroup(groupId);
    });
  });
}
