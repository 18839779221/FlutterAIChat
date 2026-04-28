import 'dart:convert';
import 'dart:io';

import 'package:ai_chat/models/agent/model_turn_decision.dart';
import 'package:ai_chat/models/agent/planner_tool_option.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/llm/api_protocol_resolver.dart';
import 'package:ai_chat/models/llm/configurable_http_llm.dart';
import 'package:ai_chat/models/llm/llm_provider_config.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/repositories/llm_local_defaults.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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
          'planTurnDecision supports live tool continuation round-trip',
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
              messages: [
                ChatMessage(
                  text:
                      'Continue from the tool result. '
                      'If the tool result contains a schema version, '
                      'reply with exactly "schema_version=10" and nothing else.',
                  role: MessageRole.user,
                ),
              ],
              config: ChatConfig(systemPrompt: ''),
              availableTools: const [],
              providerStyle: initialDecision.providerStyle,
              providerState: initialDecision.providerState,
              providerContinuationItems: _buildToolContinuationItems(
                decision: initialDecision,
                toolResultOutput: 'schema_version=10',
              ),
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
          'responses provider previous_response_id probe returns support or explicit rejection',
          () async {
            final liveProvider = provider!;
            final style = const ApiProtocolResolver().resolveStyle(
              liveProvider.baseUrl,
            );
            if (style != ApiStyle.responses) {
              return;
            }

            final probeResult = await _probePreviousResponseIdSupport(
              provider: liveProvider,
            );

            expect(
              probeResult.isSupported || probeResult.isExplicitlyUnsupported,
              isTrue,
              reason:
                  'Expected responses provider to either support previous_response_id '
                  'or reject it explicitly, but got: ${probeResult.detail}',
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
      });
    }
  });
}

const String _missingProviderSelectionMessage =
    'Live LLM tests are opt-in. Set LIVE_LLM_PROVIDER_IDS to one or more '
    'provider ids from config/local_defaults.json, for example: '
    'LIVE_LLM_PROVIDER_IDS=beehears-responses,minimax-anthropic';

Set<String> _readSelectedProviderIds() {
  final raw = Platform.environment['LIVE_LLM_PROVIDER_IDS'] ?? '';
  return raw
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet();
}

LlmLocalDefaults? _tryLoadLocalDefaults() {
  final file = File('config/local_defaults.json');
  if (!file.existsSync()) {
    return null;
  }
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, dynamic>) {
    return null;
  }
  return LlmLocalDefaults.fromJson(decoded);
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

class _PreviousResponseIdProbeResult {
  final bool isSupported;
  final bool isExplicitlyUnsupported;
  final String detail;

  const _PreviousResponseIdProbeResult({
    required this.isSupported,
    required this.isExplicitlyUnsupported,
    required this.detail,
  });
}

Future<_PreviousResponseIdProbeResult> _probePreviousResponseIdSupport({
  required LlmProviderConfig provider,
}) async {
  final resolver = const ApiProtocolResolver();
  final uri = resolver.buildRequestUri(provider.baseUrl, ApiStyle.responses);
  final client = http.Client();

  try {
    final firstResponse = await client.post(
      uri,
      headers: {
        'Authorization': 'Bearer ${provider.apiKey}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': provider.models.first.id,
        'input': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'input_text',
                'text': 'Reply with exactly "ack".',
              },
            ],
          },
        ],
        'stream': false,
        'store': true,
      }),
    );

    final firstBody = utf8.decode(firstResponse.bodyBytes);
    if (firstResponse.statusCode != 200 || firstBody.trim().isEmpty) {
      return _PreviousResponseIdProbeResult(
        isSupported: false,
        isExplicitlyUnsupported: false,
        detail:
            'initial request failed: ${firstResponse.statusCode} ${firstBody.trim()}',
      );
    }

    final decoded = jsonDecode(firstBody);
    if (decoded is! Map<String, dynamic>) {
      return const _PreviousResponseIdProbeResult(
        isSupported: false,
        isExplicitlyUnsupported: false,
        detail: 'initial request returned non-object payload',
      );
    }

    final responseId = (decoded['id'] as String? ?? '').trim();
    if (responseId.isEmpty) {
      return const _PreviousResponseIdProbeResult(
        isSupported: false,
        isExplicitlyUnsupported: false,
        detail: 'initial request did not return response id',
      );
    }

    final secondResponse = await client.post(
      uri,
      headers: {
        'Authorization': 'Bearer ${provider.apiKey}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': provider.models.first.id,
        'input': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'input_text',
                'text': 'Reply with exactly "ack-2".',
              },
            ],
          },
        ],
        'stream': false,
        'store': true,
        'previous_response_id': responseId,
      }),
    );

    final secondBody = utf8.decode(secondResponse.bodyBytes);
    if (secondResponse.statusCode == 200 && secondBody.trim().isNotEmpty) {
      return const _PreviousResponseIdProbeResult(
        isSupported: true,
        isExplicitlyUnsupported: false,
        detail: 'provider accepted previous_response_id',
      );
    }

    final normalized = secondBody.toLowerCase();
    final explicitUnsupported = normalized.contains('previous_response_id') &&
        (normalized.contains('unsupported') ||
            normalized.contains('not supported') ||
            normalized.contains('only supported'));

    return _PreviousResponseIdProbeResult(
      isSupported: false,
      isExplicitlyUnsupported: explicitUnsupported,
      detail:
          'follow-up response: ${secondResponse.statusCode} ${secondBody.trim()}',
    );
  } finally {
    client.close();
  }
}

List<Map<String, dynamic>> _buildToolContinuationItems({
  required ModelTurnDecision decision,
  required String toolResultOutput,
}) {
  final providerStyle = decision.providerStyle;
  final toolCall = decision.toolCalls.single;
  final providerCallId = toolCall.providerCallId;
  if (providerStyle == null || providerCallId == null || providerCallId.isEmpty) {
    throw StateError('Live continuation test requires providerStyle and providerCallId.');
  }

  switch (providerStyle) {
    case ChatTurnProviderStyle.openaiResponses:
      return [
        {
          'type': 'assistant_tool_call',
          'toolCallId': providerCallId,
          'toolName': toolCall.toolName,
          'arguments': toolCall.arguments,
        },
        {
          'type': 'tool_result',
          'toolCallId': providerCallId,
          'toolName': toolCall.toolName,
          'output': toolResultOutput,
        },
      ];
    case ChatTurnProviderStyle.openaiChatCompletions:
      return [
        {
          'type': 'assistant_tool_call',
          'toolCallId': providerCallId,
          'toolName': toolCall.toolName,
          'arguments': toolCall.arguments,
        },
        {
          'type': 'tool_result',
          'toolCallId': providerCallId,
          'toolName': toolCall.toolName,
          'output': toolResultOutput,
        },
      ];
    case ChatTurnProviderStyle.anthropicMessages:
      return [
        {
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': providerCallId,
              'content': toolResultOutput,
            },
          ],
        },
      ];
  }
}
