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
      final unstableFreeProviderReason = _unstableFreeProviderIds
              .contains(providerId)
          ? 'Provider "$providerId" is an unstable free channel; exclude it from flow-contract acceptance.'
          : null;

      group(providerId, () {
        test(
          'planTurnDecision returns direct assistant text when no tool flow is required',
          () async {
            final llm = await _buildLiveLlm(provider!);
            final decision = await llm.planTurnDecision(
              messages: [
                ChatMessage(
                  text:
                      'Reply with exactly "live_direct_answer_ok" and do not call any tool.',
                  role: MessageRole.user,
                ),
              ],
              config: ChatConfig(
                systemPrompt:
                    'Answer directly when the user asks for a plain reply. '
                    'Do not invent tool calls when no tool is available.',
              ),
              availableTools: const [],
            );

            expect(decision, isNotNull);
            expect(decision!.toolCalls, isEmpty);
            expect((decision.assistantMessage ?? '').trim(), isNotEmpty);
            expect(decision.providerStyle, isNotNull);
            expect(decision.modelName?.trim(), isNotEmpty);
          },
          skip: missingProviderReason ?? unstableFreeProviderReason,
          tags: const ['live-llm'],
        );

        test(
          'planTurnDecision returns a parseable live decision',
          () async {
            final llm = await _buildLiveLlm(provider!);
            final decision = await llm.planTurnDecision(
              messages: [
                ChatMessage(
                  text: 'You must call the only available tool exactly once. '
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
                  text: 'You must call the only available tool exactly once. '
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
            expect((continuationDecision.assistantMessage ?? '').trim(),
                isNotEmpty);
          },
          skip: missingProviderReason,
          tags: const ['live-llm'],
        );

        test(
          'planTurnDecision preserves assistant text before live tool result replay',
          () async {
            final llm = await _buildLiveLlm(provider!);
            final initialDecision = await llm.planTurnDecision(
              messages: [
                ChatMessage(
                  text:
                      'Call the available search_chat_history tool exactly once. '
                      'Use query "schema version".',
                  role: MessageRole.user,
                ),
              ],
              config: ChatConfig(
                systemPrompt:
                    'Use the available tool when the user explicitly requires it.',
              ),
              availableTools: const [_searchChatHistoryTool],
            );

            expect(initialDecision, isNotNull);
            expect(initialDecision!.toolCalls, isNotEmpty);
            final firstToolCall = initialDecision.toolCalls.single;
            expect(firstToolCall.providerCallId?.trim(), isNotEmpty);

            final continuationDecision = await llm.planTurnDecision(
              messages: _buildToolReplayMessages(
                decision: initialDecision,
                toolResultOutput:
                    'tool_result_payload: schema_version=10; source=live-test-ledger',
                assistantPlannerText:
                    'I will inspect the stored schema information before answering.',
                continuationInstruction:
                    'Continue from the tool result. Mention schema_version=10 exactly once.',
              ),
              config: ChatConfig(systemPrompt: ''),
              availableTools: const [],
            );

            expect(continuationDecision, isNotNull);
            expect(continuationDecision!.toolCalls, isEmpty);
            expect((continuationDecision.assistantMessage ?? '').trim(),
                isNotEmpty);
          },
          skip: missingProviderReason ?? unstableFreeProviderReason,
          tags: const ['live-llm'],
        );

        test(
          'planTurnDecision parses structured ask_user_question tool payload',
          () async {
            final llm = await _buildLiveLlm(provider!);
            final decision = await llm.planTurnDecision(
              messages: [
                ChatMessage(
                  text: 'You must call ask_user_question exactly once. '
                      'Ask the user to choose one delivery mode.',
                  role: MessageRole.user,
                ),
              ],
              config: ChatConfig(
                systemPrompt:
                    'When the user explicitly requires ask_user_question, call it once. '
                    'Return a structured question payload instead of plain text.',
              ),
              availableTools: const [_askUserQuestionTool],
            );

            expect(decision, isNotNull);
            expect(decision!.toolCalls, isNotEmpty);
            final toolCall = decision.toolCalls.single;
            expect(toolCall.toolName, 'ask_user_question');
            expect(toolCall.providerCallId?.trim(), isNotEmpty);
            final questions = toolCall.arguments['questions'];
            expect(questions, isA<List>());
            expect(questions, isNotEmpty);
            final firstQuestion = (questions as List).first;
            expect(firstQuestion, isA<Map>());
            final normalizedQuestion =
                Map<String, dynamic>.from(firstQuestion as Map);
            expect(normalizedQuestion['id'], isA<String>());
            expect(normalizedQuestion['question'], isA<String>());
          },
          skip: missingProviderReason ?? unstableFreeProviderReason,
          tags: const ['live-llm'],
        );

        test(
          'planner stream preserves assistant text when provider emits text before a tool call',
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
                      'First write a short visible note, then call search_chat_history exactly once. '
                      'Use query "schema version".',
                  role: MessageRole.user,
                ),
              ],
              config: ChatConfig(
                systemPrompt:
                    'If you call a tool, you may also emit brief assistant text before the tool call. '
                    'Preserve both when the provider supports that shape.',
              ),
              availableTools: const [_searchChatHistoryTool],
            );

            expect(decision, isNotNull);
            expect(
              decision!.toolCalls.isNotEmpty ||
                  (decision.assistantMessage ?? '').trim().isNotEmpty,
              isTrue,
            );
            if (decision.toolCalls.isNotEmpty) {
              expect(
                  decision.toolCalls.single.providerCallId?.trim(), isNotEmpty);
            }
            final streamedAssistantText = emittedSnapshots.any(
              (snapshot) => snapshot.any(
                (entry) =>
                    entry.kind == RuntimeStreamEntryKind.assistantText &&
                    entry.text.trim().isNotEmpty,
              ),
            );
            if ((decision.assistantMessage ?? '').trim().isNotEmpty) {
              expect(streamedAssistantText, isTrue);
            }
          },
          skip: missingProviderReason ?? unstableFreeProviderReason,
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
              webpageContent: 'Project bulletin\n'
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
                systemPrompt: 'You must call create_artifact exactly once. '
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
            expect(
                decision.toolCalls.single.providerCallId?.trim(), isNotEmpty);
            expect(
                decision.toolCalls.single.arguments['source'], isA<String>());
            expect(decision.toolCalls.single.arguments['source'].toString(),
                isNotEmpty);
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

        test(
          'planner handles real create_artifact food-ranking prompt end-to-end',
          () async {
            final llm = await _buildLiveLlm(provider!);
            final emittedSnapshots = <List<RuntimeStreamEntry>>[];
            llm.setPlannerRuntimeStreamListener((entries) {
              emittedSnapshots.add(List<RuntimeStreamEntry>.from(entries));
            });

            final decision = await llm.planTurnDecision(
              messages: [
                ChatMessage(
                  text: '帮我制作一个精美的HTML介绍中国各地美食从顶级到差强人意的排序',
                  role: MessageRole.user,
                ),
                ChatMessage(
                  text: '我来为你创建一个精美的中国美食排名HTML页面。先搜索一下相关信息来确保内容准确。',
                  role: MessageRole.assistant,
                ),
                ChatMessage(
                  text: '',
                  role: MessageRole.assistant,
                  payloadJson: const {
                    'providerCallId': 'call_function_1fflbyxnuria_1',
                    'toolName': 'web_search',
                    'arguments': {
                      'maxResults': 3,
                      'query': '中国各地美食特色 排行榜 2025',
                    },
                    'status': 'running',
                    'summary': '正在执行工具：Web Search',
                    'requiresConfirmation': false,
                  },
                ),
                ChatMessage(
                  text:
                      '[user tool_result] web_search query: 中国各地美食特色 排行榜 2025\n'
                      '1. 2025 中國美食排行榜熱騰騰出爐！ 網友討論度超高的大陸小吃有哪些？\n'
                      'snippet: 2025 中國美食排行榜熱騰騰出爐！ 網友討論度超高的大陸小吃有哪些？\n'
                      '2. 酸菜魚、螺螄粉退燒？2025十大中國美食討論度揭曉\n'
                      'snippet: 麻辣乾鍋（或稱麻辣香鍋）是近年在台灣興起、深受年輕族群喜愛的中國特色料理。\n'
                      '3. 2025中国十大美食之都,你最爱哪个城市\n'
                      'snippet: 下面，就让我们一起来看看这个排行榜，看看你去过几个城市，最爱哪个城市呢？',
                  role: MessageRole.user,
                ),
              ],
              config: ChatConfig(
                systemPrompt:
                    'You must call create_artifact exactly once when the user asks for a polished HTML page. '
                    'Return a provider-native decision, not a plain-text answer. '
                    'Prefer a mobile-friendly layout, keep the artifact self-contained, '
                    'put visible content before scripts, and keep the page concise.',
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
            expect(
                decision.toolCalls.single.providerCallId?.trim(), isNotEmpty);
            expect(decision.toolCalls.single.arguments['type'], 'html');
            expect(
                decision.toolCalls.single.arguments['source'], isA<String>());
            expect(
              decision.toolCalls.single.arguments['source'].toString(),
              isNotEmpty,
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
          },
          skip: missingProviderReason ??
              (providerId == 'minimax-anthropic'
                  ? null
                  : 'This regression case currently targets minimax-anthropic only.'),
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
    'LIVE_LLM_PROVIDER_IDS=aigocode,minimax-openai,deepseek-openai,deepseek-anthropic';

const Set<String> _unstableFreeProviderIds = {
  'ofox',
  'openrouter',
};

const PlannerToolOption _searchChatHistoryTool = PlannerToolOption(
  name: 'search_chat_history',
  description: 'Searches prior chat history by query text and returns matches.',
  inputSchema: {
    'type': 'object',
    'properties': {
      'query': {'type': 'string'},
    },
    'required': ['query'],
  },
);

const PlannerToolOption _askUserQuestionTool = PlannerToolOption(
  name: 'ask_user_question',
  description:
      'Ask the user a structured clarification question and wait for their answer.',
  inputSchema: {
    'type': 'object',
    'properties': {
      'questions': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'id': {'type': 'string'},
            'header': {'type': 'string'},
            'question': {'type': 'string'},
            'options': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'label': {'type': 'string'},
                  'description': {'type': 'string'},
                },
                'required': ['label', 'description'],
              },
            },
          },
          'required': ['id', 'question'],
        },
      },
    },
    'required': ['questions'],
  },
);

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
    requestTimeout: const Duration(seconds: 60),
    plannerRequestTimeout: const Duration(seconds: 60),
    mainFlowNetworkRetryAttempts: 1,
  );
}

List<ChatMessage> _buildToolReplayMessages({
  required ModelTurnDecision decision,
  required String toolResultOutput,
  String? assistantPlannerText,
  String? continuationInstruction,
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
      text: assistantPlannerText ?? '[assistant tool_use]',
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
      text: continuationInstruction ??
          'Continue from the tool result. '
              'If the tool result contains a schema version, '
              'reply with exactly "schema_version=10" and nothing else.',
      role: MessageRole.user,
    ),
  ];
}
