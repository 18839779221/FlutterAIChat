import 'dart:convert';

import '../models/agent/agent_loop_limits.dart';
import '../models/agent/chat_turn_step.dart';
import '../models/agent/model_tool_call.dart';
import '../models/agent/model_turn_decision.dart';
import '../models/agent/planner_tool_option.dart';
import '../models/chat_event.dart';
import '../models/chat_turn.dart';
import '../models/context/planner_context_carrier.dart';
import '../models/llm/base_llm.dart';
import '../models/llm/streaming_message_event.dart';
import '../models/tool/tool_access_snapshot.dart';
import '../models/tool/tool_definition.dart';
import 'chat_service.dart';
import 'debug/streaming_trace_recorder.dart';
import 'planner_tool_exposure_service.dart';
import 'prompt/prompt_builder_service.dart';
import 'prompt/prompt_locale.dart';
import 'tool_policy_service.dart';
import '../utils/logger.dart';
import 'prompt/prompt_stage.dart';

enum PlannerRequestTraceStage {
  requestStarted,
  firstChunk,
  requestCompleted,
}

class PlannerRequestTraceEvent {
  const PlannerRequestTraceEvent({
    required this.turnId,
    required this.requestId,
    required this.stage,
    required this.timestamp,
    this.phase,
    this.toolName,
  });

  final int turnId;
  final String requestId;
  final PlannerRequestTraceStage stage;
  final DateTime timestamp;
  final String? phase;
  final String? toolName;
}

class AgentPlannerService {
  static const _tag = 'AgentPlannerService';
  // Architecture:
  // - docs/architecture/agent-loop-boundaries-and-decoupling.md
  //
  // Invariant:
  // - Planner-visible context is reconstructed from append-only transcript.
  // - Provider-native continuation must not become a parallel truth source.

  final BaseLLM _llm;
  final List<ToolDefinition> _availableTools;
  final PlannerToolExposureService _toolExposureService;
  final ToolPolicyService? _toolPolicyService;
  final PromptBuilderService _promptBuilder;
  final void Function(LlmRetryProgress progress)? _onPlannerRetryScheduled;
  final void Function(StreamingMessageEvent event)? _onPlannerRuntimeStream;
  final void Function(PlannerRequestTraceEvent event)? _onPlannerRequestTrace;

  AgentPlannerService({
    required BaseLLM llm,
    List<ToolDefinition> availableTools = const [],
    PlannerToolExposureService? toolExposureService,
    ToolPolicyService? toolPolicyService,
    PromptBuilderService? promptBuilder,
    void Function(LlmRetryProgress progress)? onPlannerRetryScheduled,
    void Function(StreamingMessageEvent event)? onPlannerRuntimeStream,
    void Function(PlannerRequestTraceEvent event)? onPlannerRequestTrace,
  })  : _llm = llm,
        _availableTools = availableTools,
        _toolExposureService =
            toolExposureService ?? PlannerToolExposureService(),
        _toolPolicyService = toolPolicyService,
        _promptBuilder = promptBuilder ?? const PromptBuilderService(),
        _onPlannerRetryScheduled = onPlannerRetryScheduled,
        _onPlannerRuntimeStream = onPlannerRuntimeStream,
        _onPlannerRequestTrace = onPlannerRequestTrace;

  Future<ModelTurnDecision?> planNextDecision({
    required ChatTurn turn,
    required List<ChatEvent> transcript,
    required List<ChatTurnStep> steps,
    required ChatConfig config,
    required AgentLoopLimits limits,
    required List<PlannerContextCarrier> carriers,
    required ChatTurnProviderStyle activeApiStyle,
    required bool currentTurnRunning,
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
    final runtimeStreamTraceId = streamingTraceIdForTurn(turn.id!);
    final plannerRequestId = _buildPlannerRequestId(turn);
    _emitPlannerRequestTrace(
      PlannerRequestTraceEvent(
        turnId: turn.id!,
        requestId: plannerRequestId,
        stage: PlannerRequestTraceStage.requestStarted,
        timestamp: DateTime.now(),
      ),
    );
    var hasRecordedFirstChunk = false;
    final plannerRuntimeStreamListener =
        (_onPlannerRuntimeStream == null && _onPlannerRequestTrace == null)
            ? null
            : (StreamingMessageEvent event) {
                if (!hasRecordedFirstChunk) {
                  hasRecordedFirstChunk = true;
                  _emitPlannerRequestTrace(
                    PlannerRequestTraceEvent(
                      turnId: turn.id!,
                      requestId: plannerRequestId,
                      stage: PlannerRequestTraceStage.firstChunk,
                      timestamp: DateTime.now(),
                    ),
                  );
                }
                if (_onPlannerRuntimeStream != null) {
                  _onPlannerRuntimeStream!(
                    event.copyWithMergedRuntimeMetadata({
                      'streamTraceId': runtimeStreamTraceId,
                      'streamTurnId': turn.id.toString(),
                    }),
                  );
                }
              };

    try {
      if (_llm is PlannerRuntimeStreamingCapable) {
        (_llm as PlannerRuntimeStreamingCapable)
            .setPlannerRuntimeStreamListener(plannerRuntimeStreamListener);
      }
      Logger.d(
        _tag,
        'planner decision start turnId=${turn.id} iteration=${turn.iterationCount} toolCalls=${turn.toolCallCount} transcriptEvents=${transcript.length} stepCount=${steps.length} userInput=${_preview(turn.userInput)}',
      );
      final decision = await _llm.planTurnDecision(
        carriers: carriers,
        activeApiStyle: activeApiStyle,
        currentTurnRunning: currentTurnRunning,
        config: plannerConfig,
        availableTools: plannerToolOptions,
        onRetryScheduled: _onPlannerRetryScheduled,
      );
      if (decision != null) {
        _emitPlannerRequestTrace(
          PlannerRequestTraceEvent(
            turnId: turn.id!,
            requestId: plannerRequestId,
            stage: PlannerRequestTraceStage.requestCompleted,
            timestamp: DateTime.now(),
            phase: _phaseForDecision(decision),
            toolName: decision.toolCalls.length == 1
                ? decision.toolCalls.single.toolName.trim()
                : null,
          ),
        );
        return _sanitizeDecision(
          decision,
          allowedToolNames: allowedToolNames,
        );
      }
      _emitPlannerRequestTrace(
        PlannerRequestTraceEvent(
          turnId: turn.id!,
          requestId: plannerRequestId,
          stage: PlannerRequestTraceStage.requestCompleted,
          timestamp: DateTime.now(),
        ),
      );
      Logger.w(
        _tag,
        'native planner returned null, terminating turn with planner_request_failed',
      );
      return _plannerRequestFailedDecision();
    } catch (error, stackTrace) {
      _emitPlannerRequestTrace(
        PlannerRequestTraceEvent(
          turnId: turn.id!,
          requestId: plannerRequestId,
          stage: PlannerRequestTraceStage.requestCompleted,
          timestamp: DateTime.now(),
        ),
      );
      final detail = _preview(error.toString());
      Logger.w(
        _tag,
        'native planner decision unavailable, terminating turn: $detail',
      );
      Logger.e(_tag, 'native planner decision stack trace', stackTrace);
      return _plannerRequestFailedDecision(detail: detail);
    } finally {
      if (_llm is PlannerRuntimeStreamingCapable) {
        (_llm as PlannerRuntimeStreamingCapable)
            .setPlannerRuntimeStreamListener(null);
      }
    }
  }

  String _resolveUserSystemPrompt(ChatConfig config) {
    final explicit = config.userSystemPrompt.trim();
    if (explicit.isNotEmpty) {
      return explicit;
    }
    return config.systemPrompt.trim();
  }

  void _emitPlannerRequestTrace(PlannerRequestTraceEvent event) {
    _onPlannerRequestTrace?.call(event);
  }

  String _buildPlannerRequestId(ChatTurn turn) {
    final turnId = turn.id ?? 0;
    return 'planner_${turnId}_${turn.iterationCount}_${DateTime.now().microsecondsSinceEpoch}';
  }

  String? _phaseForDecision(ModelTurnDecision decision) {
    if (decision.toolCalls.isNotEmpty) {
      return 'tool_call';
    }
    final assistantMessage = (decision.assistantMessage ?? '').trim();
    if (decision.isTerminal && assistantMessage.isNotEmpty) {
      return 'final_answer';
    }
    return null;
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
          visibleReasoning: decision.visibleReasoning,
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
      visibleReasoning: decision.visibleReasoning,
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

}
