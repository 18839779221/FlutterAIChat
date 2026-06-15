import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat/repositories/llm_local_defaults.dart';
import 'package:ai_chat/models/llm/api_protocol_resolver.dart';

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

  test(
      'loadInjectedLocalDefaults selects a valid responses provider from injected defaults',
      () {
    final tempDir = Directory.systemTemp.createTempSync(
      'headless_live_provider_matrix_test.',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final defaultsFile = File('${tempDir.path}/local_defaults.json');
    defaultsFile.writeAsStringSync(
      jsonEncode({
        'default_provider_id': 'test-responses',
        'providers': [
          {
            'id': 'test-responses',
            'name': 'Test Responses',
            'api_key': 'sk-test',
            'base_url': 'https://example.com/v1/responses',
            'models': [
              {'id': 'test-model', 'name': 'Test Model'},
            ],
          },
        ],
      }),
    );

    final defaults = loadInjectedLocalDefaults(
      environment: {'LIVE_LLM_LOCAL_DEFAULTS_PATH': defaultsFile.path},
      fallbackRelativePaths: const [],
    );

    expect(defaults, isNotNull);
    expect(defaults!.providers.map((provider) => provider.id), contains('test-responses'));

    final selection = selectHeadlessLiveProvider(
      defaults: defaults,
      style: ChatTurnProviderStyle.openaiResponses,
      environment: const {},
    );

    expect(
      defaults.providers.map((provider) => provider.id),
      contains(selection.provider.id),
    );
    expect(
      const ApiProtocolResolver().resolveStyle(selection.provider.baseUrl),
      ApiStyle.responses,
    );
  });

  test('matrix marks codex custom responses tool confirmation as opportunistic', () {
    final profile = headlessLiveProviderMatrix['codex-custom-responses'];
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
}
