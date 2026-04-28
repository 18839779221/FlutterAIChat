import 'dart:collection';
import 'dart:convert';

import '../models/agent/agent_loop_limits.dart';
import '../models/agent/chat_turn_step.dart';
import '../models/agent/model_tool_call.dart';
import '../models/agent/model_turn_decision.dart';
import '../models/agent/planner_tool_option.dart';
import '../models/chat_event.dart';
import '../models/chat_message.dart';
import '../models/chat_turn.dart';
import '../models/llm/base_llm.dart';
import '../models/tool/tool_access_snapshot.dart';
import '../models/tool/tool_definition.dart';
import '../models/tool/tool_result.dart';
import 'chat_service.dart';
import 'planner_tool_exposure_service.dart';
import 'prompt/prompt_builder_service.dart';
import 'prompt/prompt_locale.dart';
import 'tool_policy_service.dart';
import '../utils/logger.dart';
import 'prompt/prompt_stage.dart';

class AgentPlannerService {
  static const _tag = 'AgentPlannerService';

  final BaseLLM _llm;
  final List<ToolDefinition> _availableTools;
  final PlannerToolExposureService _toolExposureService;
  final ToolPolicyService? _toolPolicyService;
  final PromptBuilderService _promptBuilder;

  AgentPlannerService({
    required BaseLLM llm,
    List<ToolDefinition> availableTools = const [],
    PlannerToolExposureService? toolExposureService,
    ToolPolicyService? toolPolicyService,
    PromptBuilderService? promptBuilder,
  })  : _llm = llm,
        _availableTools = availableTools,
        _toolExposureService =
            toolExposureService ?? PlannerToolExposureService(),
        _toolPolicyService = toolPolicyService,
        _promptBuilder = promptBuilder ?? const PromptBuilderService();

  Future<ModelTurnDecision?> planNextDecision({
    required ChatTurn turn,
    required List<ChatEvent> transcript,
    required List<ChatTurnStep> steps,
    required ChatConfig config,
    required AgentLoopLimits limits,
    List<ChatMessage>? plannerMessages,
  }) async {
    final visibleToolAccess = await _resolveVisibleToolAccess(turn.userInput);
    final visibleTools = visibleToolAccess
        .map((access) => access.definition)
        .toList(growable: false);
    final allowedToolNames = _resolveAllowedToolNames(visibleTools);
    final plannerToolOptions = _buildPlannerToolOptions(
      visibleToolAccess,
      locale: config.promptLocale,
    );
    final plannerConfig = ChatConfig(
      systemPrompt: _promptBuilder.buildSystemPrompt(
        stage: PromptStage.planner,
        locale: config.promptLocale,
        userSystemPrompt: _resolveUserSystemPrompt(config),
      ),
      userSystemPrompt: _resolveUserSystemPrompt(config),
      promptLocale: config.promptLocale,
    );
    final messages = plannerMessages ??
        transcript
            .map(_eventToMessage)
            .whereType<ChatMessage>()
            .toList(growable: false);

    try {
      Logger.d(
        _tag,
        'planner decision start turnId=${turn.id} iteration=${turn.iterationCount} toolCalls=${turn.toolCallCount} transcriptEvents=${transcript.length} stepCount=${steps.length} userInput=${_preview(turn.userInput)}',
      );
      final continuationItems = _buildProviderContinuationItems(
        turn: turn,
        transcript: transcript,
      );
      final decision = await _llm.planTurnDecision(
        messages: messages,
        config: plannerConfig,
        availableTools: plannerToolOptions,
        providerStyle: turn.providerStyle,
        providerState: turn.providerStateJson,
        providerContinuationItems: continuationItems,
      );
      if (decision != null) {
        return _sanitizeDecision(
          decision,
          allowedToolNames: allowedToolNames,
        );
      }
      Logger.w(
        _tag,
        'native planner returned null, terminating turn with planner_request_failed',
      );
      return _plannerRequestFailedDecision();
    } catch (error, stackTrace) {
      final detail = _preview(error.toString());
      Logger.w(
        _tag,
        'native planner decision unavailable, terminating turn: $detail',
      );
      Logger.e(_tag, 'native planner decision stack trace', stackTrace);
      return _plannerRequestFailedDecision(detail: detail);
    }
  }

  String _resolveUserSystemPrompt(ChatConfig config) {
    final explicit = config.userSystemPrompt.trim();
    if (explicit.isNotEmpty) {
      return explicit;
    }
    return config.systemPrompt.trim();
  }

  ModelTurnDecision _sanitizeDecision(
    ModelTurnDecision decision, {
    required List<String> allowedToolNames,
  }) {
    if (decision.toolCalls.isEmpty) {
      return decision;
    }

    final originalCount = decision.toolCalls.length;
    final filteredCalls = <ModelToolCall>[];
    final seenToolCalls = <String>{};
    var duplicateCount = 0;
    var unsupportedCount = 0;
    for (final toolCall in decision.toolCalls) {
      if (!allowedToolNames.contains(toolCall.toolName.trim())) {
        unsupportedCount += 1;
        Logger.w(
          _tag,
          'native planner emitted unsupported tool: ${toolCall.toolName}',
        );
        continue;
      }
      final fingerprint = _decisionToolCallFingerprint(toolCall);
      if (!seenToolCalls.add(fingerprint)) {
        duplicateCount += 1;
        Logger.w(
          _tag,
          'native planner emitted duplicate tool call in same decision: ${toolCall.toolName} args=${_compactJson(toolCall.arguments)}',
        );
        continue;
      }
      filteredCalls.add(toolCall);
    }

    if (duplicateCount > 0 || unsupportedCount > 0) {
      Logger.i(
        _tag,
        'planner decision sanitized original=$originalCount retained=${filteredCalls.length} duplicates=$duplicateCount unsupported=$unsupportedCount',
      );
      Logger.trace(
        _tag,
        'planner.sanitized',
        data: {
          'originalToolCalls': originalCount,
          'retainedToolCalls': filteredCalls.length,
          if (duplicateCount > 0) 'filteredDuplicates': duplicateCount,
          if (unsupportedCount > 0) 'filteredUnsupported': unsupportedCount,
        },
      );
    }

    if (filteredCalls.isEmpty) {
      final hasAssistantMessage =
          (decision.assistantMessage ?? '').trim().isNotEmpty;
      if (hasAssistantMessage) {
        return ModelTurnDecision(
          toolCalls: const [],
          assistantMessage: decision.assistantMessage,
          diagnosticCode: decision.diagnosticCode,
          providerState: decision.providerState,
          providerStyle: decision.providerStyle,
          modelName: decision.modelName,
          isTerminal: decision.isTerminal,
        );
      }
      return const ModelTurnDecision(
        toolCalls: [],
        assistantMessage: '抱歉，我暂时无法规划下一步动作，请直接重试。',
        diagnosticCode: 'planner_unsupported_tool',
        providerState: {},
        isTerminal: true,
      );
    }

    return ModelTurnDecision(
      toolCalls: filteredCalls,
      assistantMessage: decision.assistantMessage,
      diagnosticCode: decision.diagnosticCode,
      providerState: decision.providerState,
      providerStyle: decision.providerStyle,
      modelName: decision.modelName,
      isTerminal: decision.isTerminal && filteredCalls.isEmpty,
    );
  }

  ModelTurnDecision _plannerRequestFailedDecision({String? detail}) {
    final normalizedDetail = detail?.trim();
    final assistantMessage =
        (normalizedDetail != null && normalizedDetail.isNotEmpty)
            ? '当前模型请求失败，已中断本轮流程。\n原因：$normalizedDetail'
            : '抱歉，我暂时无法规划下一步动作，请直接重试。';
    return ModelTurnDecision(
      toolCalls: [],
      assistantMessage: assistantMessage,
      diagnosticCode: 'planner_request_failed',
      providerState: {},
      isTerminal: true,
    );
  }

  String _decisionToolCallFingerprint(ModelToolCall toolCall) {
    return '${toolCall.toolName.trim()}:${_compactJson(toolCall.arguments)}';
  }

  String _compactJson(Map<String, dynamic> value) {
    return jsonEncode(_normalizeJsonValue(value));
  }

  Object? _normalizeJsonValue(Object? value) {
    if (value is Map) {
      final sortedKeys = value.keys.map((key) => key.toString()).toList()
        ..sort();
      return {
        for (final key in sortedKeys) key: _normalizeJsonValue(value[key]),
      };
    }
    if (value is List) {
      return value.map(_normalizeJsonValue).toList(growable: false);
    }
    return value;
  }

  List<Map<String, dynamic>> _buildProviderContinuationItems({
    required ChatTurn turn,
    required List<ChatEvent> transcript,
  }) {
    switch (turn.providerStyle) {
      case ChatTurnProviderStyle.openaiResponses:
        return _buildResponsesContinuationFromTranscript(
          turn: turn,
          transcript: transcript,
        );
      case ChatTurnProviderStyle.anthropicMessages:
        return _buildAnthropicContinuationFromTranscript(
          turn: turn,
          transcript: transcript,
        );
      case ChatTurnProviderStyle.openaiChatCompletions:
        return _buildChatCompletionsContinuationFromTranscript(
          transcript: transcript,
        );
      case null:
        return const [];
    }
  }

  List<Map<String, dynamic>> _buildResponsesContinuationFromTranscript({
    required ChatTurn turn,
    required List<ChatEvent> transcript,
  }) {
    final responseId = turn.providerStateJson?['response_id'];
    if (responseId is! String || responseId.trim().isEmpty) {
      return const [];
    }

    final orderedCallIds = LinkedHashSet<String>();
    final toolCalls = <String, Map<String, dynamic>>{};
    final outputsByCallId = <String, String>{};
    final interactionAnswersByCallId = <String, String>{};

    for (final event in transcript) {
      final payload = event.payloadJson ?? const <String, dynamic>{};
      final providerCallId = (payload['providerCallId'] ?? '').toString().trim();
      switch (event.eventType) {
        case ChatEventType.assistantToolCall:
        case ChatEventType.assistantQuestionPrompt:
          final providerResponseId =
              (payload['providerResponseId'] ?? '').toString().trim();
          if (providerResponseId == responseId && providerCallId.isNotEmpty) {
            orderedCallIds.add(providerCallId);
            toolCalls[providerCallId] = payload;
          }
          break;
        case ChatEventType.toolResult:
        case ChatEventType.toolError:
          if (providerCallId.isNotEmpty) {
            outputsByCallId[providerCallId] =
                _encodeProviderEventOutput(event: event);
          }
          break;
        case ChatEventType.userInteractionResult:
          if (providerCallId.isNotEmpty &&
              (event.content ?? '').trim().isNotEmpty) {
            interactionAnswersByCallId[providerCallId] = event.content!.trim();
          }
          break;
        default:
          break;
      }
    }

    final items = <Map<String, dynamic>>[];
    for (final callId in orderedCallIds) {
      final interactionAnswer = interactionAnswersByCallId[callId];
      if (interactionAnswer != null) {
        items.add({
          'type': 'user_interaction_answer',
          'toolCallId': callId,
          'content': interactionAnswer,
        });
        continue;
      }
      final toolCall = toolCalls[callId];
      if (toolCall == null) {
        continue;
      }
      items.add({
        'type': 'assistant_tool_call',
        'toolCallId': callId,
        'toolName': toolCall['toolName'],
        'arguments': toolCall['arguments'] ?? const <String, dynamic>{},
      });
      final output = outputsByCallId[callId];
      if (output != null) {
        items.add({
          'type': 'tool_result',
          'toolCallId': callId,
          'toolName': toolCall['toolName'],
          'output': output,
        });
      }
    }
    return items;
  }

  List<Map<String, dynamic>> _buildAnthropicContinuationFromTranscript({
    required ChatTurn turn,
    required List<ChatEvent> transcript,
  }) {
    final messageId = turn.providerStateJson?['message_id'];
    if (messageId is! String || messageId.trim().isEmpty) {
      return const [];
    }

    final contentBlocks = turn.providerStateJson?['content_blocks'];
    final assistantContentBlocks = contentBlocks is List
        ? contentBlocks
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false)
        : const <Map<String, dynamic>>[];

    final orderedCallIds = LinkedHashSet<String>();
    for (final block in assistantContentBlocks) {
      if (block['type'] != 'tool_use') {
        continue;
      }
      final toolUseId = (block['id'] ?? '').toString().trim();
      if (toolUseId.isNotEmpty) {
        orderedCallIds.add(toolUseId);
      }
    }

    final toolCalls = <String, Map<String, dynamic>>{};
    final toolResults = <String, String>{};
    for (final event in transcript) {
      final payload = event.payloadJson ?? const <String, dynamic>{};
      final providerCallId = (payload['providerCallId'] ?? '').toString().trim();
      switch (event.eventType) {
        case ChatEventType.assistantToolCall:
          final providerResponseId =
              (payload['providerResponseId'] ?? '').toString().trim();
          if (providerResponseId == messageId && providerCallId.isNotEmpty) {
            orderedCallIds.add(providerCallId);
            toolCalls[providerCallId] = payload;
          }
          break;
        case ChatEventType.toolResult:
        case ChatEventType.toolError:
          if (providerCallId.isNotEmpty) {
            toolResults[providerCallId] = _encodeProviderEventOutput(event: event);
          }
          break;
        default:
          break;
      }
    }

    final matchedCallIds = orderedCallIds
        .where((callId) => toolResults.containsKey(callId))
        .toList(growable: false);
    if (matchedCallIds.isEmpty) {
      return const [];
    }

    final items = <Map<String, dynamic>>[];
    if (assistantContentBlocks.isNotEmpty) {
      items.add({
        'role': 'assistant',
        'content': assistantContentBlocks,
      });
      items.add({
        'role': 'user',
        'content': [
          for (final callId in matchedCallIds)
            {
              'type': 'tool_result',
              'tool_use_id': callId,
              'content': toolResults[callId],
            },
        ],
      });
      return items;
    }

    for (final callId in matchedCallIds) {
      final toolCall = toolCalls[callId];
      if (toolCall == null) {
        continue;
      }
      items.add({
        'role': 'assistant',
        'content': [
          {
            'type': 'tool_use',
            'id': callId,
            'name': toolCall['toolName'],
            'input': toolCall['arguments'] ?? const <String, dynamic>{},
          },
        ],
      });
      items.add({
        'role': 'user',
        'content': [
          {
            'type': 'tool_result',
            'tool_use_id': callId,
            'content': toolResults[callId],
          },
        ],
      });
    }

    return items;
  }

  List<Map<String, dynamic>> _buildChatCompletionsContinuationFromTranscript({
    required List<ChatEvent> transcript,
  }) {
    final toolCalls = <String, Map<String, dynamic>>{};
    final toolResults = <String, String>{};
    final interactionAnswers = <String, String>{};

    for (final event in transcript) {
      final payload = event.payloadJson ?? const <String, dynamic>{};
      final providerCallId = (payload['providerCallId'] ?? '').toString().trim();
      if (providerCallId.isEmpty) {
        continue;
      }
      switch (event.eventType) {
        case ChatEventType.assistantToolCall:
        case ChatEventType.assistantQuestionPrompt:
          toolCalls[providerCallId] = payload;
          break;
        case ChatEventType.toolResult:
        case ChatEventType.toolError:
          toolResults[providerCallId] = _encodeProviderEventOutput(event: event);
          break;
        case ChatEventType.userInteractionResult:
          if ((event.content ?? '').trim().isNotEmpty) {
            interactionAnswers[providerCallId] = event.content!.trim();
          }
          break;
        default:
          break;
      }
    }

    final items = <Map<String, dynamic>>[];
    for (final entry in toolCalls.entries) {
      final interactionAnswer = interactionAnswers[entry.key];
      if (interactionAnswer != null) {
        items.add({
          'type': 'user_interaction_answer',
          'toolCallId': entry.key,
          'content': interactionAnswer,
        });
        continue;
      }
      items.add({
        'type': 'assistant_tool_call',
        'toolCallId': entry.key,
        'toolName': entry.value['toolName'],
        'arguments': entry.value['arguments'] ?? const <String, dynamic>{},
      });
      final result = toolResults[entry.key];
      if (result != null) {
        items.add({
          'type': 'tool_result',
          'toolCallId': entry.key,
          'toolName': entry.value['toolName'],
          'output': result,
        });
      }
    }
    return items;
  }

  String _encodeProviderEventOutput({
    required ChatEvent event,
  }) {
    final payload = event.payloadJson ?? const <String, dynamic>{};
    final output = <String, dynamic>{
      'status':
          event.eventType == ChatEventType.toolError ? 'failure' : 'success',
    };
    final summary = (payload['summary'] ?? event.content ?? '').toString().trim();
    if (summary.isNotEmpty) {
      output['summary'] = summary;
    }
    final error = (payload['errorMessage'] ?? payload['error'] ?? event.status ?? '')
        .toString()
        .trim();
    if (error.isNotEmpty) {
      output['error'] = error;
    }
    final data = payload['data'];
    if (data is Map && data.isNotEmpty) {
      output['data'] = Map<String, dynamic>.from(data);
    }
    return jsonEncode(output);
  }

  Future<List<ToolAccessSnapshot>> _resolveVisibleToolAccess(
    String userInput,
  ) async {
    if (_availableTools.isEmpty) {
      return const [];
    }
    final accessSnapshots = <ToolAccessSnapshot>[];
    for (final tool in _availableTools) {
      accessSnapshots.add(await _resolveToolAccess(tool));
    }
    return _toolExposureService.selectVisibleToolAccess(
      userInput: userInput,
      allTools: accessSnapshots,
    );
  }

  List<PlannerToolOption> _buildPlannerToolOptions(
    List<ToolAccessSnapshot> visibleToolAccess, {
    PromptLocale locale = PromptLocale.english,
  }) {
    return visibleToolAccess
        .map(
          (access) => PlannerToolOption(
            name: access.definition.name,
            description: access.definition.resolveDescriptionForModel(locale),
            inputSchema: access.definition.toPlannerJsonSchema(locale: locale),
            executionPolicy: access.executionPolicyLabel,
          ),
        )
        .toList(growable: false);
  }

  Future<ToolAccessSnapshot> _resolveToolAccess(ToolDefinition tool) async {
    final toolPolicyService = _toolPolicyService;
    if (toolPolicyService == null) {
      throw StateError(
        'toolPolicyService is required when planner resolves tool access',
      );
    }
    return toolPolicyService.resolveToolAccess(tool);
  }

  List<String> _resolveAllowedToolNames(List<ToolDefinition> visibleTools) {
    return visibleTools.map((tool) => tool.name).toList(growable: false);
  }

  String _preview(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 240) {
      return normalized;
    }
    return '${normalized.substring(0, 240)}...';
  }

  ChatMessage? _eventToMessage(ChatEvent event) {
    final projectedRole = _projectPlannerRole(event);
    if (projectedRole == null) {
      return null;
    }
    final content = _resolvePlannerEventContent(event);
    if (content.isEmpty) {
      return null;
    }
    return ChatMessage(
      text: content,
      role: projectedRole,
      timestamp: event.createdAt,
      status: MessageStatus.completed,
    );
  }

  String _resolvePlannerEventContent(ChatEvent event) {
    final modelContextText = _extractPlannerEventModelContextText(event);
    if (modelContextText != null) {
      return modelContextText;
    }
    final content = event.content?.trim() ?? '';
    return content;
  }

  String? _extractPlannerEventModelContextText(ChatEvent event) {
    if (event.eventType != ChatEventType.toolResult &&
        event.eventType != ChatEventType.toolError) {
      return null;
    }
    final payload = event.payloadJson;
    if (payload == null) {
      return null;
    }
    return ToolResult.fromJson(payload).resolvedToolResultText;
  }

  MessageRole? _projectPlannerRole(ChatEvent event) {
    switch (event.eventType) {
      case ChatEventType.userMessage:
        return MessageRole.user;
      case ChatEventType.userInteractionResult:
        return MessageRole.user;
      case ChatEventType.assistantPlannerMessage:
      case ChatEventType.assistantQuestionPrompt:
      case ChatEventType.toolResult:
      case ChatEventType.toolError:
      case ChatEventType.finalAnswer:
        return MessageRole.assistant;
      case ChatEventType.assistantReasoningDelta:
      case ChatEventType.assistantTextDelta:
      case ChatEventType.assistantTextFinal:
      case ChatEventType.assistantToolCall:
      case ChatEventType.assistantToolConfirmation:
      case ChatEventType.toolExecutionStarted:
      case ChatEventType.turnStatus:
      case ChatEventType.error:
        return null;
    }
  }
}
