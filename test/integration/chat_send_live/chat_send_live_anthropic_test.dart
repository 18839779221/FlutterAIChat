import 'dart:io';

import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_send_live_assertions.dart';
import 'chat_send_live_scenario.dart';
import 'chat_send_live_test_harness.dart';
import 'scenarios/ask_user_resume_scenario.dart';
import 'scenarios/file_ops_real_workspace_scenario.dart';
import 'scenarios/mixed_success_failure_scenario.dart';
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
        providerStyle: ChatTurnProviderStyle.anthropicMessages,
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
          style: ChatTurnProviderStyle.anthropicMessages,
        ),
        ProviderMatrixTarget(
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
        providerStyle: ChatTurnProviderStyle.anthropicMessages,
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
        providerStyle: ChatTurnProviderStyle.anthropicMessages,
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
        providerStyle: ChatTurnProviderStyle.anthropicMessages,
      );
      final autoRunResult = await harness.runScenarioWithAutoContinuation(
        buildAskUserResumeScenario(),
      );

      final waitingState = autoRunResult.firstAwaitingUserInteractionState;
      expect(waitingState, isNotNull);
      expectTurnState(
        waitingState!,
        expectedStatus: ChatTurnStatus.awaitingUserInteraction,
      );
      expectEventTypes(
        waitingState,
        includesInOrder: const [
          ChatEventType.userMessage,
          ChatEventType.assistantQuestionPrompt,
        ],
      );

      final resumedState = autoRunResult.finalState;
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

  test(
    'mixed success failure scenario persists both toolResult and toolError states',
    () async {
      final harness = await ChatSendLiveTestHarness.bootstrap(
        providerStyle: ChatTurnProviderStyle.anthropicMessages,
      );
      await harness.runScenario(buildMixedSuccessFailureScenario());
      final state = await harness.snapshotState();
      expectNoPlannerRequestFailure(state);
      expectEventTypes(
        state,
        includes: const [
          ChatEventType.toolResult,
          ChatEventType.toolError,
          ChatEventType.finalAnswer,
        ],
      );
      expectToolCallContinuationCoverage(
        state,
        toolName: 'web_search',
        minimumDistinctCallCount: 1,
      );
      expectAnyToolErrorWithProviderCallId(state, toolName: 'Read');
      await harness.dispose();
    },
    tags: const ['live-headless-agent'],
  );

  test(
    'real workspace file scenario uses persisted file tools and resumes after write confirmation',
    () async {
      final harness = await ChatSendLiveTestHarness.bootstrap(
        providerStyle: ChatTurnProviderStyle.anthropicMessages,
      );
      await harness.prepareWorkspaceFixture(
        scenarioId: 'file_ops_real_workspace',
        files: const {
          'docs/spec.md':
              '# Release Spec\n\nTODO: confirm Android rollout window.\n',
          'docs/notes.md': 'Background notes only.\n',
        },
      );

      final autoRunResult = await harness.runScenarioWithAutoContinuation(
        buildRealWorkspaceFileOpsScenario(),
      );
      final waitingState = autoRunResult.firstAwaitingToolConfirmationState;
      expect(waitingState, isNotNull);
      expectTurnState(
        waitingState!,
        expectedStatus: ChatTurnStatus.awaitingToolConfirmation,
      );
      expectEventTypes(
        waitingState,
        includes: const [
          ChatEventType.toolResult,
          ChatEventType.assistantToolConfirmation,
        ],
      );

      final resumedState = autoRunResult.finalState;
      expectNoPlannerRequestFailure(resumedState);
      expectTurnState(
        resumedState,
        expectedStatus: ChatTurnStatus.completed,
      );
      expectEventTypes(
        resumedState,
        includes: const [
          ChatEventType.assistantToolConfirmation,
          ChatEventType.toolExecutionStarted,
          ChatEventType.toolResult,
          ChatEventType.finalAnswer,
        ],
      );
      expect(harness.workspaceFileExists('artifacts/summary.md'), isTrue);
      expect(
        await harness.readWorkspaceFile('artifacts/summary.md'),
        contains('TODO'),
      );
      await harness.dispose();
    },
    tags: const ['live-headless-agent'],
  );
}
