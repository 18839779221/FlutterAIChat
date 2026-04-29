import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_send_live_assertions.dart';
import 'chat_send_live_test_harness.dart';
import 'scenarios/news_multi_tool_scenario.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  test(
    'chat completions sendMessage creates a real turn and persists user message',
    () async {
      final harness = await ChatSendLiveTestHarness.bootstrap(
        providerId: 'minimax-openai-chat-completions',
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

  test(
    'chat completions news multi-tool scenario preserves continuation state',
    () async {
      final harness = await ChatSendLiveTestHarness.bootstrap(
        providerId: 'minimax-openai-chat-completions',
      );
      await harness.runScenario(buildNewsMultiToolScenario());
      final state = await harness.snapshotState();
      expectNoPlannerRequestFailure(state);
      expectTurnState(
        state,
        expectedStatus: ChatTurnStatus.completed,
      );
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
}
