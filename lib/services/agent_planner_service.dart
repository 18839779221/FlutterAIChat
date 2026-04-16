import 'dart:convert';

import '../models/agent/agent_action.dart';
import '../models/agent/agent_loop_limits.dart';
import '../models/agent/chat_turn_step.dart';
import '../models/agent/model_tool_call.dart';
import '../models/agent/model_turn_decision.dart';
import '../models/agent/planner_tool_option.dart';
import '../models/chat_event.dart';
import '../models/chat_message.dart';
import '../models/chat_turn.dart';
import '../models/llm/base_llm.dart';
import '../models/tool/tool_call.dart';
import '../models/tool/tool_access_snapshot.dart';
import '../models/tool/tool_definition.dart';
import 'chat_service.dart';
import 'planner_prompt_builder.dart';
import 'planner_tool_exposure_service.dart';
import 'tool_policy_service.dart';
import 'turn_ledger_builder_service.dart';
import 'transcript_builder_service.dart';
import '../utils/logger.dart';

class AgentPlannerService {
  static const _tag = 'AgentPlannerService';

  final BaseLLM _llm;
  final List<ToolDefinition> _availableTools;
  final PlannerToolExposureService _toolExposureService;
  final PlannerPromptBuilder _promptBuilder;
  final TurnLedgerBuilderService _turnLedgerBuilder;
  final ToolPolicyService? _toolPolicyService;

  AgentPlannerService({
    required BaseLLM llm,
    List<ToolDefinition> availableTools = const [],
    PlannerToolExposureService? toolExposureService,
    PlannerPromptBuilder? promptBuilder,
    TurnLedgerBuilderService? turnLedgerBuilder,
    ToolPolicyService? toolPolicyService,
  })  : _llm = llm,
        _availableTools = availableTools,
        _toolExposureService =
            toolExposureService ?? PlannerToolExposureService(),
        _promptBuilder = promptBuilder ?? PlannerPromptBuilder(),
        _turnLedgerBuilder =
            turnLedgerBuilder ?? const TurnLedgerBuilderService(),
        _toolPolicyService = toolPolicyService;

  Future<ModelTurnDecision?> planNextDecision({
    required ChatTurn turn,
    required List<ChatEvent> transcript,
    required List<ChatTurnStep> steps,
    required ChatConfig config,
    required AgentLoopLimits limits,
  }) async {
    final visibleToolAccess =
        await _resolveVisibleToolAccess(turn.userInput);
    final visibleTools = visibleToolAccess
        .map((access) => access.definition)
        .toList(growable: false);
    final plannerPromptTools =
        _buildPlannerPromptTools(visibleToolAccess);
    final allowedToolNames = _resolveAllowedToolNames(visibleTools);
    final plannerToolOptions = _buildPlannerToolOptions(visibleToolAccess);
    final messages = <ChatMessage>[
      ChatMessage(
        text: _promptBuilder.buildSystemPrompt(
          visibleTools: plannerPromptTools,
          allowMultiToolPlanning: true,
        ),
        role: MessageRole.system,
      ),
      ChatMessage(
        text: '${_turnLedgerBuilder.buildPlannerSummary(
          turn: turn,
          steps: steps,
        )}\n'
            '当前轮次：${turn.iterationCount}\n'
            '已调用工具数：${turn.toolCallCount}\n'
            '最大轮次：${limits.maxIterations}',
        role: MessageRole.system,
      ),
      ...transcript.map(_eventToMessage),
    ];

    try {
      Logger.d(
        _tag,
        'planner decision start turnId=${turn.id} iteration=${turn.iterationCount} toolCalls=${turn.toolCallCount} transcriptEvents=${transcript.length} stepCount=${steps.length} userInput=${_preview(turn.userInput)}',
      );
      final decision = await _llm.planTurnDecision(
        messages: messages,
        config: config,
        availableTools: plannerToolOptions,
        providerStyle: turn.providerStyle,
        providerState: turn.providerStateJson,
        providerContinuationItems: _buildProviderContinuationItems(
          turn: turn,
          steps: steps,
        ),
      );
      if (decision != null) {
        return _sanitizeDecision(
          decision,
          allowedToolNames: allowedToolNames,
          steps: steps,
        );
      }
      Logger.w(
        _tag,
        'native planner returned null, terminating turn with planner_request_failed',
      );
      return _plannerRequestFailedDecision();
    } catch (error, stackTrace) {
      Logger.w(
        _tag,
        'native planner decision unavailable, terminating turn: ${_preview(error.toString())}',
      );
      Logger.e(_tag, 'native planner decision stack trace', stackTrace);
      return _plannerRequestFailedDecision();
    }
  }

  Future<AgentAction> planNextAction({
    required ChatTurn turn,
    required List<ChatEvent> transcript,
    required ChatConfig config,
    required AgentLoopLimits limits,
  }) async {
    try {
      final raw = await _requestLegacyPlannerRaw(
        turn: turn,
        transcript: transcript,
        config: config,
        limits: limits,
      );
      final visibleToolAccess =
          await _resolveVisibleToolAccess(turn.userInput);
      final visibleTools = visibleToolAccess
          .map((access) => access.definition)
          .toList(growable: false);
      final allowedToolNames = _resolveAllowedToolNames(visibleTools);
      return _parseAction(raw, allowedToolNames: allowedToolNames);
    } catch (_) {
      return const AgentAction.respond(
        '抱歉，我暂时无法规划下一步动作，请直接重试。',
        diagnosticCode: 'planner_request_failed',
      );
    }
  }

  Future<String> _requestLegacyPlannerRaw({
    required ChatTurn turn,
    required List<ChatEvent> transcript,
    required ChatConfig config,
    required AgentLoopLimits limits,
  }) async {
    final visibleToolAccess = await _resolveVisibleToolAccess(turn.userInput);
    final plannerPromptTools = _buildPlannerPromptTools(visibleToolAccess);
    final messages = <ChatMessage>[
      ChatMessage(
        text: _promptBuilder.buildSystemPrompt(
          visibleTools: plannerPromptTools,
        ),
        role: MessageRole.system,
      ),
      ChatMessage(
        text: '${TranscriptBuilderService.buildPlannerContextText(
          turn: turn,
          transcript: transcript,
        )}\n'
            '当前轮次：${turn.iterationCount}\n'
            '已调用工具数：${turn.toolCallCount}\n'
            '最大轮次：${limits.maxIterations}',
        role: MessageRole.system,
      ),
      ...transcript.map(_eventToMessage),
    ];

    try {
      Logger.d(
        _tag,
        'planner start turnId=${turn.id} iteration=${turn.iterationCount} toolCalls=${turn.toolCallCount} transcriptEvents=${transcript.length} userInput=${_preview(turn.userInput)}',
      );
      final raw = await _llm.planNextAction(
        messages: messages,
        config: config,
      );
      Logger.d(_tag, 'planner raw output: ${_preview(raw)}');
      return raw;
    } catch (error, stackTrace) {
      Logger.e(_tag, 'planner request failed for turnId=${turn.id}', error);
      Logger.e(_tag, 'planner request stack trace', stackTrace);
      throw Exception('planner_request_failed');
    }
  }

  ModelTurnDecision _sanitizeDecision(
    ModelTurnDecision decision, {
    required List<String> allowedToolNames,
    required List<ChatTurnStep> steps,
  }) {
    if (decision.toolCalls.isEmpty) {
      return decision;
    }

    final seenToolCalls = steps
        .where((step) =>
            step.status == ChatTurnStepStatus.planned ||
            step.status == ChatTurnStepStatus.running ||
            step.status == ChatTurnStepStatus.completed)
        .map((step) => _toolCallFingerprint(step.toolName, step.toolArgsJson))
        .toSet();
    final filteredCalls = <ModelToolCall>[];
    final blockedDuplicates = <String>[];
    for (final toolCall in decision.toolCalls) {
      if (!allowedToolNames.contains(toolCall.toolName.trim())) {
        Logger.w(
          _tag,
          'native planner emitted unsupported tool: ${toolCall.toolName}',
        );
        continue;
      }
      final fingerprint =
          _toolCallFingerprint(toolCall.toolName, toolCall.arguments);
      if (seenToolCalls.contains(fingerprint)) {
        blockedDuplicates.add(fingerprint);
        Logger.w(
          _tag,
          'native planner emitted duplicate tool call in same turn: ${toolCall.toolName} args=${_compactJson(toolCall.arguments)}',
        );
        continue;
      }
      seenToolCalls.add(fingerprint);
      filteredCalls.add(toolCall);
    }

    if (filteredCalls.isEmpty) {
      if (blockedDuplicates.isNotEmpty) {
        return ModelTurnDecision(
          toolCalls: const [],
          assistantMessage: '当前回合里相同工具调用已经执行过，请基于现有结果总结，或改用其他工具。',
          diagnosticCode: 'planner_duplicate_tool_call',
          providerState: decision.providerState,
          providerStyle: decision.providerStyle,
          modelName: decision.modelName,
          isTerminal: true,
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

  ModelTurnDecision _plannerRequestFailedDecision() {
    return const ModelTurnDecision(
      toolCalls: [],
      assistantMessage: '抱歉，我暂时无法规划下一步动作，请直接重试。',
      diagnosticCode: 'planner_request_failed',
      providerState: {},
      isTerminal: true,
    );
  }

  String _toolCallFingerprint(
    String toolName,
    Map<String, dynamic> arguments,
  ) {
    return '$toolName:${_compactJson(arguments)}';
  }

  String _compactJson(Map<String, dynamic> value) {
    return jsonEncode(_normalizeJsonValue(value));
  }

  Object? _normalizeJsonValue(Object? value) {
    if (value is Map) {
      final sortedKeys = value.keys.map((key) => key.toString()).toList()..sort();
      return {
        for (final key in sortedKeys)
          key: _normalizeJsonValue(value[key]),
      };
    }
    if (value is List) {
      return value.map(_normalizeJsonValue).toList(growable: false);
    }
    return value;
  }

  List<Map<String, dynamic>> _buildProviderContinuationItems({
    required ChatTurn turn,
    required List<ChatTurnStep> steps,
  }) {
    if (turn.providerStyle != ChatTurnProviderStyle.openaiResponses) {
      return const [];
    }
    final responseId = turn.providerStateJson?['response_id'];
    if (responseId is! String || responseId.trim().isEmpty) {
      return const [];
    }

    final items = <Map<String, dynamic>>[];
    for (final step in steps) {
      if (step.providerResponseId != responseId ||
          (step.providerCallId ?? '').trim().isEmpty) {
        continue;
      }
      if (step.status != ChatTurnStepStatus.completed &&
          step.status != ChatTurnStepStatus.failed) {
        continue;
      }
      items.add({
        'type': 'function_call_output',
        'call_id': step.providerCallId!.trim(),
        'output': _encodeProviderStepOutput(step),
      });
    }
    return items;
  }

  String _encodeProviderStepOutput(ChatTurnStep step) {
    final payload = <String, dynamic>{
      'status': step.status == ChatTurnStepStatus.completed
          ? 'success'
          : 'failure',
      if ((step.resultSummary ?? '').trim().isNotEmpty)
        'summary': step.resultSummary!.trim(),
      if ((step.errorCode ?? '').trim().isNotEmpty) 'error': step.errorCode,
      if ((step.resultJson ?? const {}).isNotEmpty) 'data': step.resultJson,
    };
    return jsonEncode(payload);
  }

  AgentAction _parseAction(
    String raw, {
    required List<String> allowedToolNames,
  }) {
    try {
      final normalized = _normalize(raw);
      final decoded = jsonDecode(normalized);
      if (decoded is! Map<String, dynamic>) {
        return const AgentAction.respond('抱歉，我暂时无法规划下一步动作，请直接重试。');
      }

      final action = _normalizeStringField(decoded['action']);
      if (action == 'respond') {
        final response = _normalizeStringField(decoded['response']);
        if (response != null && response.isNotEmpty) {
          Logger.d(_tag, 'parsed respond action');
          return AgentAction.respond(
            response,
            diagnosticCode: 'planner_action_respond',
          );
        }
      }

      if (action == 'call_tool') {
        final toolCall = ToolCall.fromJson({
          'toolName': _normalizeStringField(decoded['toolName']),
          'arguments': decoded['arguments'],
        });
        if (!allowedToolNames.contains(toolCall.toolName)) {
          Logger.w(
              _tag, 'planner emitted unsupported tool: ${toolCall.toolName}');
          return const AgentAction.respond(
            '抱歉，我暂时无法规划下一步动作，请直接重试。',
            diagnosticCode: 'planner_unsupported_tool',
          );
        }
        Logger.d(
          _tag,
          'parsed call_tool action: ${toolCall.toolName} args=${toolCall.arguments}',
        );
        return AgentAction.callTool(
          toolCall,
          diagnosticCode: 'planner_action_call_tool',
        );
      }
    } catch (error, stackTrace) {
      Logger.e(
        _tag,
        'planner output parse failed, raw=${_preview(raw)}',
        error,
      );
      Logger.e(_tag, 'planner parse stack trace', stackTrace);
    }

    Logger.w(_tag, 'planner output fell back to respond, raw=${_preview(raw)}');
    return const AgentAction.respond(
      '抱歉，我暂时无法规划下一步动作，请直接重试。',
      diagnosticCode: 'planner_parse_failed',
    );
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

  List<PlannerPromptTool> _buildPlannerPromptTools(
    List<ToolAccessSnapshot> visibleToolAccess,
  ) {
    return visibleToolAccess
        .map(
          (access) => PlannerPromptTool(
            definition: access.definition,
            executionPolicy: access.executionPolicyLabel,
          ),
        )
        .toList(growable: false);
  }

  List<PlannerToolOption> _buildPlannerToolOptions(
    List<ToolAccessSnapshot> visibleToolAccess,
  ) {
    return visibleToolAccess
        .map(
          (access) => PlannerToolOption(
            name: access.definition.name,
            description:
                '${access.definition.descriptionForModel}\nExecution policy: ${access.executionPolicyLabel}',
            inputSchema: access.definition.toPlannerJsonSchema(),
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

  String? _normalizeStringField(dynamic value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  String _preview(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 240) {
      return normalized;
    }
    return '${normalized.substring(0, 240)}...';
  }

  String _normalize(String raw) {
    final trimmed = _unwrapCodeFence(raw);

    final firstObject = _extractFirstJsonObject(trimmed);
    if (firstObject != null) {
      return firstObject;
    }

    return trimmed;
  }

  String _unwrapCodeFence(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith('```')) {
      return trimmed;
    }
    final match = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```').firstMatch(trimmed);
    if (match == null) {
      return trimmed;
    }
    return match.group(1)!.trim();
  }

  String? _extractFirstJsonObject(String value) {
    final objects = _extractJsonObjects(value);
    if (objects.isEmpty) {
      return null;
    }
    return objects.first;
  }

  List<String> _extractJsonObjects(String value) {
    final objects = <String>[];
    var start = -1;
    var depth = 0;
    var inString = false;
    var isEscaped = false;

    for (var index = 0; index < value.length; index++) {
      final char = value[index];

      if (inString) {
        if (isEscaped) {
          isEscaped = false;
          continue;
        }
        if (char == r'\') {
          isEscaped = true;
          continue;
        }
        if (char == '"') {
          inString = false;
        }
        continue;
      }

      if (char == '"') {
        inString = true;
        continue;
      }

      if (char == '{') {
        if (depth == 0) {
          start = index;
        }
        depth++;
        continue;
      }

      if (char == '}' && depth > 0) {
        depth--;
        if (depth == 0 && start >= 0) {
          objects.add(value.substring(start, index + 1).trim());
          start = -1;
        }
      }
    }

    return objects;
  }

  ChatMessage _eventToMessage(ChatEvent event) {
    return ChatMessage(
      text: event.content ?? '',
      role: event.role ?? MessageRole.system,
      timestamp: event.createdAt,
      status: MessageStatus.completed,
    );
  }
}
