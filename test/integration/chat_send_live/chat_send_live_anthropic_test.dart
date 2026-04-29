import 'dart:io';

import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/interaction/ask_user_question_response.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_send_live_assertions.dart';
import 'chat_send_live_scenario.dart';
import 'chat_send_live_test_harness.dart';
import 'scenarios/ask_user_resume_scenario.dart';
import 'scenarios/news_multi_tool_scenario.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  test(
    'headless live harness boots with a real test db',
    () async {
      final harness = await ChatSendLiveTestHarness.bootstrap();
      expect(harness.databasePath, isNotEmpty);
      await harness.dispose();
    },
    tags: const ['live-headless-agent'],
  );

  test(
    'sendMessage creates a real turn and persists user message',
    () async {
      final harness = await ChatSendLiveTestHarness.bootstrap(
        providerId: 'deepseek-anthropic',
      );
      await harness.sendUserMessage(
        '直接回复 OK，不要调用任何工具，也不要输出其他内容。',
      );
      final turns = await harness.listTurns();
      final messages = await harness.listMessages();
      expectAtLeastOneTurn(turns);
      expect(messages.any((message) => message.isUser), isTrue);
      await harness.dispose();
    },
    tags: const ['live-headless-agent'],
  );

  test('scenario exposes multiple provider targets', () {
    const scenario = ScenarioCase(
      id: 'news_multi_tool',
      title: 'News multi-tool',
      userMessage: '帮我搜索并整理 Google 最新新闻',
      providerTargets: [
        ProviderMatrixTarget(
          providerId: 'deepseek-anthropic',
          style: ChatTurnProviderStyle.anthropicMessages,
        ),
        ProviderMatrixTarget(
          providerId: 'beehears-responses',
          style: ChatTurnProviderStyle.openaiResponses,
        ),
      ],
    );
    expect(scenario.providerTargets.length, greaterThan(1));
  });

  test(
    'fixture builder creates real workspace files for file tools',
    () async {
      final harness = await ChatSendLiveTestHarness.bootstrap();
      final workspace = await harness.prepareWorkspaceFixture(
        scenarioId: 'file_tools_fixture',
        files: const {
          'docs/spec.md': 'initial content',
          'notes/todo.md': 'todo',
        },
      );
      expect(File('${workspace.path}/docs/spec.md').existsSync(), isTrue);
      await harness.dispose();
    },
    tags: const ['live-headless-agent'],
  );

  test(
    'assertion helpers inspect persisted turn ledger state',
    () async {
      final harness = await ChatSendLiveTestHarness.bootstrap(
        providerId: 'deepseek-anthropic',
      );
      await harness.sendUserMessage(
        '直接回复 TEST_OK，不要调用任何工具，也不要输出其他内容。',
      );
      final state = await harness.snapshotState();
      expectTurnState(
        state,
        expectedStatus: ChatTurnStatus.completed,
      );
      expectEventTypes(
        state,
        includesInOrder: const [
          ChatEventType.userMessage,
          ChatEventType.finalAnswer,
        ],
      );
      await harness.dispose();
    },
    tags: const ['live-headless-agent'],
  );

  test(
    'news multi-tool scenario preserves anthropic multi-tool continuation state',
    () async {
      final harness = await ChatSendLiveTestHarness.bootstrap(
        providerId: 'deepseek-anthropic',
      );
      await harness.runScenario(buildNewsMultiToolScenario());
      final state = await harness.snapshotState();
      expectNoPlannerRequestFailure(state);
      expectToolCallContinuationCoverage(
        state,
        toolName: 'web_search',
        minimumDistinctCallCount: 2,
      );
      expectProviderIdsAligned(state);
      await harness.dispose();
    },
    tags: const ['live-headless-agent'],
  );

  test(
    'ask-user scenario resumes the same anthropic turn after structured answers',
    () async {
      final harness = await ChatSendLiveTestHarness.bootstrap(
        providerId: 'deepseek-anthropic',
      );
      await harness.runScenario(buildAskUserResumeScenario());

      final waitingState = await harness.snapshotState();
      expectTurnState(
        waitingState,
        expectedStatus: ChatTurnStatus.awaitingUserInteraction,
      );
      expectEventTypes(
        waitingState,
        includesInOrder: const [
          ChatEventType.userMessage,
          ChatEventType.assistantQuestionPrompt,
        ],
      );

      final promptMessage = harness.activeAskUserQuestionMessage();
      expect(promptMessage, isNotNull);

      await harness.submitQuestionAnswers(
        message: promptMessage!,
        response: AskUserQuestionResponse.fromJson(const {
          'answersByQuestionId': {
            'storage_layer': 'SQLite',
          },
          'selectedOptionLabelsByQuestionId': {
            'storage_layer': ['SQLite'],
          },
          'freeTextAnswersByQuestionId': {},
        }),
      );

      final resumedState = await harness.snapshotState();
      expectNoPlannerRequestFailure(resumedState);
      expectTurnState(
        resumedState,
        expectedStatus: ChatTurnStatus.completed,
      );
      expectEventTypes(
        resumedState,
        includesInOrder: const [
          ChatEventType.assistantQuestionPrompt,
          ChatEventType.userInteractionResult,
          ChatEventType.finalAnswer,
        ],
      );
      expectAskUserContinuationCoverage(waitingState, resumedState);
      await harness.dispose();
    },
    tags: const ['live-headless-agent'],
  );
}
