import 'dart:io';

import 'package:ai_chat/models/agent/model_turn_decision.dart';
import 'package:ai_chat/models/agent/planner_tool_option.dart';
import 'package:ai_chat/models/chat/runtime_stream_entry.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/llm/api_protocol_resolver.dart';
import 'package:ai_chat/models/llm/configurable_http_llm.dart';
import 'package:ai_chat/models/llm/llm_provider_config.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/repositories/llm_local_defaults.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_utils/local_test_provider_selector.dart';

void main() {
  final selectedProviderIds = _readSelectedProviderIds();
  final liveDefaults = _tryLoadLocalDefaults();

  group('ConfigurableHttpLLM live contract', () {
    if (selectedProviderIds.isEmpty) {
      test(
        'skips when LIVE_LLM_PROVIDER_IDS is not configured',
        () {},
        skip: _missingProviderSelectionMessage,
        tags: const ['live-llm'],
      );
      return;
    }

    for (final providerId in selectedProviderIds) {
      final provider = liveDefaults?.providers
          .where((item) => item.id == providerId)
          .firstOrNull;
      final missingProviderReason = provider == null
          ? 'Provider "$providerId" was not found in config/local_defaults.json.'
          : null;

      group(providerId, () {
        test(
          'planTurnDecision returns a parseable live decision',
          () async {
            final llm = await _buildLiveLlm(provider!);
            final decision = await llm.planTurnDecision(
              messages: [
                ChatMessage(
                  text:
                      'You must call the only available tool exactly once. '
                      'Do not answer directly. Query for "database schema drift".',
                  role: MessageRole.user,
                ),
              ],
              config: ChatConfig(
                systemPrompt:
                    'Use the available tool when the user explicitly requires it. '
                    'If a tool is available and the user says you must call it, '
                    'call that tool instead of answering directly.',
              ),
              availableTools: const [
                PlannerToolOption(
                  name: 'search_chat_history',
                  description:
                      'Searches prior chat history by query text and returns matches.',
                  inputSchema: {
                    'type': 'object',
                    'properties': {
                      'query': {'type': 'string'},
                    },
                    'required': ['query'],
                  },
                ),
              ],
            );

            expect(decision, isNotNull);
            expect(
              decision!.toolCalls.isNotEmpty ||
                  (decision.assistantMessage ?? '').trim().isNotEmpty,
              isTrue,
            );
          },
          skip: missingProviderReason,
          tags: const ['live-llm'],
        );

        test(
          'planTurnDecision supports live transcript replay round-trip',
          () async {
            final llm = await _buildLiveLlm(provider!);
            final initialDecision = await llm.planTurnDecision(
              messages: [
                ChatMessage(
                  text:
                      'You must call the only available tool exactly once. '
                      'Do not answer directly. Query for "database schema drift".',
                  role: MessageRole.user,
                ),
              ],
              config: ChatConfig(
                systemPrompt:
                    'Use the available tool when the user explicitly requires it. '
                    'If a tool is available and the user says you must call it, '
                    'call that tool instead of answering directly.',
              ),
              availableTools: const [
                PlannerToolOption(
                  name: 'search_chat_history',
                  description:
                      'Searches prior chat history by query text and returns matches.',
                  inputSchema: {
                    'type': 'object',
                    'properties': {
                      'query': {'type': 'string'},
                    },
                    'required': ['query'],
                  },
                ),
              ],
            );

            expect(initialDecision, isNotNull);
            expect(initialDecision!.toolCalls, isNotEmpty);
            final firstToolCall = initialDecision.toolCalls.single;
            expect(firstToolCall.toolName, 'search_chat_history');
            expect(firstToolCall.providerCallId?.trim(), isNotEmpty);
            expect(initialDecision.providerStyle, isNotNull);

            final continuationDecision = await llm.planTurnDecision(
              messages: _buildToolReplayMessages(
                decision: initialDecision,
                toolResultOutput: 'schema_version=10',
              ),
              config: ChatConfig(systemPrompt: ''),
              availableTools: const [],
            );

            expect(continuationDecision, isNotNull);
            expect(continuationDecision!.toolCalls, isEmpty);
            expect(
              (continuationDecision.assistantMessage ?? '').trim(),
              contains('schema_version=10'),
            );
          },
          skip: missingProviderReason,
          tags: const ['live-llm'],
        );

        test(
          'summarizeConversation returns a non-empty factual summary',
          () async {
            final llm = await _buildLiveLlm(provider!);
            final summary = await llm.summarizeConversation([
              ChatMessage(
                text:
                    'Project Sunbird launches on May 3. Primary risk is API schema drift.',
                role: MessageRole.user,
              ),
              ChatMessage(
                text:
                    'Mitigation: add contract tests for planner payloads and live provider checks.',
                role: MessageRole.assistant,
              ),
            ]);

            expect(summary.trim(), isNotEmpty);
            final normalized = summary.toLowerCase();
            expect(
              normalized.contains('sunbird') ||
                  normalized.contains('schema') ||
                  normalized.contains('contract'),
              isTrue,
            );
          },
          skip: missingProviderReason,
          tags: const ['live-llm'],
        );

        test(
          'processWebpageContent returns prompt-aligned output',
          () async {
            final llm = await _buildLiveLlm(provider!);
            final result = await llm.processWebpageContent(
              webpageContent:
                  'Project bulletin\n'
                  'Codename: Sunbird\n'
                  'Owner: Platform Team\n'
                  'Decision: Add live provider contract tests.\n',
              prompt:
                  'Return only the codename and nothing else if it is present.',
            );

            expect(result.trim(), isNotEmpty);
            expect(result.toLowerCase(), contains('sunbird'));
          },
          skip: missingProviderReason,
          tags: const ['live-llm'],
        );

        test(
          'planner stream emits create_artifact tool-call argument deltas',
          () async {
            final llm = await _buildLiveLlm(provider!);
            final emittedSnapshots = <List<RuntimeStreamEntry>>[];
            llm.setPlannerRuntimeStreamListener((entries) {
              emittedSnapshots.add(List<RuntimeStreamEntry>.from(entries));
            });

            final decision = await llm.planTurnDecision(
              messages: [
                ChatMessage(
                  text:
                      'Create a tiny HTML artifact and call create_artifact exactly once. '
                      'The artifact must be self-contained, start with visible content, '
                      'and keep the source concise.',
                  role: MessageRole.user,
                ),
              ],
              config: ChatConfig(
                systemPrompt:
                    'You must call create_artifact exactly once. '
                    'Return only the tool call and no ordinary answer. '
                    'The artifact should prefer <style> first, visible content before scripts, '
                    'and a compact one-screen layout when possible.',
              ),
              availableTools: const [
                PlannerToolOption(
                  name: 'create_artifact',
                  description:
                      'Creates a self-contained HTML artifact that is shown inline.',
                  inputSchema: {
                    'type': 'object',
                    'properties': {
                      'id': {'type': 'string'},
                      'type': {'type': 'string'},
                      'title': {'type': 'string'},
                      'source': {'type': 'string'},
                    },
                    'required': ['id', 'type', 'title', 'source'],
                  },
                ),
              ],
            );

            expect(decision, isNotNull);
            expect(decision!.toolCalls, hasLength(1));
            expect(decision.toolCalls.single.toolName, 'create_artifact');
            expect(decision.toolCalls.single.arguments['source'], isA<String>());
            expect(
              decision.toolCalls.single.arguments['type'],
              anyOf('html', 'webview'),
            );
            expect(
              emittedSnapshots.any(
                (snapshot) => snapshot.any(
                  (entry) =>
                      entry.kind == RuntimeStreamEntryKind.toolCallArguments &&
                      entry.toolName == 'create_artifact' &&
                      entry.text.trim().isNotEmpty,
                ),
              ),
              isTrue,
            );
            expect(
              emittedSnapshots.any(
                (snapshot) => snapshot.any(
                  (entry) =>
                      entry.kind == RuntimeStreamEntryKind.toolCallArguments &&
                      entry.toolName == 'create_artifact' &&
                      ((entry.payload?['toolCallIndex'] is int) ||
                          entry.providerCallId != null),
                ),
              ),
              isTrue,
            );
          },
          skip: missingProviderReason,
          tags: const ['live-llm'],
        );
      });
    }
  });
}

const String _missingProviderSelectionMessage =
    'Live LLM tests are opt-in. Set LIVE_LLM_PROVIDER_IDS to one or more '
    'provider ids, and optionally set LIVE_LLM_LOCAL_DEFAULTS_PATH when the '
    'current workspace does not contain your local defaults file. Example: '
    'LIVE_LLM_LOCAL_DEFAULTS_PATH=/abs/path/config/local_defaults.json '
    'LIVE_LLM_PROVIDER_IDS=minimax-openai,minimax-anthropic';

Set<String> _readSelectedProviderIds() {
  final raw = Platform.environment['LIVE_LLM_PROVIDER_IDS'] ?? '';
  return raw
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet();
}

LlmLocalDefaults? _tryLoadLocalDefaults() {
  return loadInjectedLocalDefaults(
    fallbackRelativePaths: const ['config/local_defaults.json'],
  );
}

Future<ConfigurableHttpLLM> _buildLiveLlm(LlmProviderConfig provider) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final defaults = _tryLoadLocalDefaults();
  final repository = AppSettingsRepository(
    preferences,
    localDefaultsLoader: () async => defaults,
  );
  final modelId = provider.models.first.id;
  await repository.selectProviderAndModel(
    providerId: provider.id,
    modelId: modelId,
  );

  return ConfigurableHttpLLM(
    settingsRepository: repository,
    protocolResolver: const ApiProtocolResolver(),
    requestTimeout: const Duration(seconds: 20),
    plannerRequestTimeout: const Duration(seconds: 12),
    mainFlowNetworkRetryAttempts: 1,
  );
}

List<ChatMessage> _buildToolReplayMessages({
  required ModelTurnDecision decision,
  required String toolResultOutput,
}) {
  final toolCall = decision.toolCalls.single;
  final providerCallId = toolCall.providerCallId;
  if (providerCallId == null || providerCallId.isEmpty) {
    throw StateError(
      'Live transcript replay test requires providerCallId.',
    );
  }
  return [
    ChatMessage(
      text: 'Please look up the current database schema version.',
      role: MessageRole.user,
    ),
    ChatMessage(
      text: '[assistant tool_use]',
      role: MessageRole.assistant,
      payloadJson: {
        'modelContextType': 'assistantToolUse',
        'providerCallId': providerCallId,
        'toolName': toolCall.toolName,
        'arguments': toolCall.arguments,
      },
    ),
    ChatMessage(
      text: toolResultOutput,
      role: MessageRole.user,
      payloadJson: {
        'modelContextType': 'userToolResult',
        'providerCallId': providerCallId,
        'toolName': toolCall.toolName,
      },
    ),
    ChatMessage(
      text:
          'Continue from the tool result. '
          'If the tool result contains a schema version, '
          'reply with exactly "schema_version=10" and nothing else.',
      role: MessageRole.user,
    ),
  ];
}
