import 'package:ai_chat/database/database_helper.dart';
import 'package:ai_chat/models/agent/chat_turn_step.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/repositories/chat_turn_repository.dart';
import 'package:ai_chat/repositories/chat_turn_step_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ChatTurnStepRepository', () {
    test('creates, lists and updates turn steps in order', () async {
      final storage =
          DatabaseHelper(databaseName: 'chat_turn_step_repository_test_v8.db');
      final turnRepository = ChatTurnRepository(storage);
      final stepRepository = ChatTurnStepRepository(storage);
      final groupId =
          await storage.insertGroup(ChatGroup(title: 'turn step repo group', lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions));
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.running,
          userInput: '先查历史再记笔记',
          goalSummary: '验证多步骤工具执行账本',
          providerStyle: ChatTurnProviderStyle.openaiResponses,
          modelName: 'gpt-5.4',
        ),
      );

      final stepId = await stepRepository.createStep(
        ChatTurnStep(
          turnId: turnId,
          stepIndex: 1,
          providerResponseId: 'resp_123',
          providerCallId: 'fc_1',
          toolName: 'search_chat_history',
          toolArgsJson: {'query': '数据库版本'},
          status: ChatTurnStepStatus.planned,
        ),
      );

      await stepRepository.createStep(
        ChatTurnStep(
          turnId: turnId,
          stepIndex: 2,
          toolName: 'Write',
          toolArgsJson: {'title': '数据库版本确认'},
          status: ChatTurnStepStatus.planned,
        ),
      );

      await stepRepository.markRunning(stepId);
      await stepRepository.markCompleted(
        stepId,
        resultSummary: '已确认数据库版本 7，发版时间 4 月 20 日',
        resultJson: const {
          'facts': {
            'databaseVersion': '7',
            'releaseDate': '4月20日',
          },
        },
      );

      final steps = await stepRepository.listSteps(turnId);

      expect(steps, hasLength(2));
      expect(steps.first.stepIndex, 1);
      expect(steps.first.providerResponseId, 'resp_123');
      expect(steps.first.providerCallId, 'fc_1');
      expect(steps.first.status, ChatTurnStepStatus.completed);
      expect(steps.first.resultSummary, '已确认数据库版本 7，发版时间 4 月 20 日');
      expect(
        steps.first.resultJson?['facts'],
        containsPair('databaseVersion', '7'),
      );
      expect(steps.last.stepIndex, 2);
      expect(steps.last.status, ChatTurnStepStatus.planned);

      await storage.deleteGroup(groupId);
    });

    test('completed interaction step keeps provider continuation fields',
        () async {
      final storage = DatabaseHelper(
          databaseName: 'chat_turn_step_repository_interaction_test_v8.db');
      final turnRepository = ChatTurnRepository(storage);
      final stepRepository = ChatTurnStepRepository(storage);
      final groupId =
          await storage.insertGroup(ChatGroup(title: 'turn step repo group', lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions));
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          groupId: groupId,
          status: ChatTurnStatus.awaitingUserInteraction,
          userInput: '请补充偏好信息',
          providerStyle: ChatTurnProviderStyle.openaiResponses,
          modelName: 'gpt-5.4',
        ),
      );

      final stepId = await stepRepository.createStep(
        ChatTurnStep(
          turnId: turnId,
          stepIndex: 1,
          providerResponseId: 'resp_ask_1',
          providerCallId: 'call_ask_1',
          toolName: 'ask_user_question',
          toolArgsJson: const {'questions': []},
          status: ChatTurnStepStatus.planned,
        ),
      );

      await stepRepository.markCompleted(
        stepId,
        resultSummary: 'user_answered',
        resultJson: const {
          'answersByQuestionId': {
            'storage_layer': 'SQLite',
          },
        },
      );

      final restored = await stepRepository.getStep(stepId);

      expect(restored, isNotNull);
      expect(restored!.providerResponseId, 'resp_ask_1');
      expect(restored.providerCallId, 'call_ask_1');
      expect(restored.status, ChatTurnStepStatus.completed);
      expect(
        restored.resultJson?['answersByQuestionId'],
        containsPair('storage_layer', 'SQLite'),
      );

      await storage.deleteGroup(groupId);
    });
  });
}
