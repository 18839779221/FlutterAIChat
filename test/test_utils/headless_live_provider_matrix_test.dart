import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat/repositories/llm_local_defaults.dart';

import 'headless_live_provider_matrix.dart';
import 'local_test_provider_selector.dart';
import 'package:ai_chat/models/chat_turn.dart';

void main() {
  test('matrix explicitly includes default responses provider profile', () {
    final profile = headlessLiveProviderMatrix['beehears-responses'];
    expect(profile, isNotNull);
    expect(
      profile!.askUserInteraction,
      StructuredCheckpointExpectation.required,
    );
    expect(
      profile.toolConfirmation,
      StructuredCheckpointExpectation.required,
    );
    expect(
      profile.multiToolContinuation,
      StructuredCheckpointExpectation.required,
    );
  });

  test('matrix explicitly includes preferred chat completions provider profile',
      () {
    final profile = headlessLiveProviderMatrix['minimax-openai-chat-completions'];
    expect(profile, isNotNull);
    expect(
      profile!.askUserInteraction,
      StructuredCheckpointExpectation.opportunistic,
    );
    expect(
      profile.toolConfirmation,
      StructuredCheckpointExpectation.required,
    );
    expect(
      profile.multiToolContinuation,
      StructuredCheckpointExpectation.opportunistic,
    );
  });

  test('matrix marks deepseek anthropic as required ask-user provider', () {
    final profile = headlessLiveProviderMatrix['deepseek-anthropic'];
    expect(profile, isNotNull);
    expect(
      profile!.askUserInteraction,
      StructuredCheckpointExpectation.required,
    );
    expect(
      profile.toolConfirmation,
      StructuredCheckpointExpectation.opportunistic,
    );
    expect(
      profile.multiToolContinuation,
      StructuredCheckpointExpectation.required,
    );
  });

  test('matrix marks minimax anthropic checkpoints as opportunistic', () {
    final profile = headlessLiveProviderMatrix['minimax-anthropic'];
    expect(profile, isNotNull);
    expect(
      profile!.askUserInteraction,
      StructuredCheckpointExpectation.opportunistic,
    );
    expect(
      profile.toolConfirmation,
      StructuredCheckpointExpectation.opportunistic,
    );
    expect(
      profile.multiToolContinuation,
      StructuredCheckpointExpectation.opportunistic,
    );
  });

  test('legacy provider override ids resolve to current chat completions ids', () {
    final defaults = LlmLocalDefaults.fromJson({
      'providers': [
        {
          'id': 'minimax-openai-chat-completions',
          'name': 'MiniMax OpenAI Chat Completions',
          'api_key': 'sk-test',
          'base_url': 'https://api.minimaxi.com/v1/chat/completions',
          'models': [
            {'id': 'MiniMax-M2.5', 'name': 'MiniMax M2.5'},
          ],
        },
      ],
    });

    final selection = selectHeadlessLiveProvider(
      defaults: defaults,
      style: ChatTurnProviderStyle.openaiChatCompletions,
      environment: const {
        'HEADLESS_LIVE_PROVIDER_CHAT_COMPLETIONS': 'minimax-openai',
      },
    );

    expect(selection.provider.id, 'minimax-openai-chat-completions');
    expect(selection.selectionReason, contains('alias=minimax-openai'));
  });
}
