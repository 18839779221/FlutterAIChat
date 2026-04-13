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
import '../models/tool/tool_definition.dart';
import 'chat_service.dart';
import 'planner_prompt_builder.dart';
import 'planner_tool_exposure_service.dart';
import 'turn_ledger_builder_service.dart';
import 'transcript_builder_service.dart';
import '../utils/logger.dart';

class AgentPlannerService {
  static const _tag = 'AgentPlannerService';
  static const _legacyAllowedToolNames = [
    'search_chat_history',
    'web_search',
    'fetch_webpage',
    'save_note',
    'create_reminder',
    'create_calendar_event',
    'share_result',
  ];

  final BaseLLM _llm;
  final List<ToolDefinition> _availableTools;
  final PlannerToolExposureService _toolExposureService;
  final PlannerPromptBuilder _promptBuilder;
  final TurnLedgerBuilderService _turnLedgerBuilder;

  AgentPlannerService({
    required BaseLLM llm,
    List<ToolDefinition> availableTools = const [],
    PlannerToolExposureService? toolExposureService,
    PlannerPromptBuilder? promptBuilder,
    TurnLedgerBuilderService? turnLedgerBuilder,
  })  : _llm = llm,
        _availableTools = availableTools,
        _toolExposureService =
            toolExposureService ?? PlannerToolExposureService(),
        _promptBuilder = promptBuilder ?? PlannerPromptBuilder(),
        _turnLedgerBuilder =
            turnLedgerBuilder ?? const TurnLedgerBuilderService();

  Future<ModelTurnDecision?> planNextDecision({
    required ChatTurn turn,
    required List<ChatEvent> transcript,
    required List<ChatTurnStep> steps,
    required ChatConfig config,
    required AgentLoopLimits limits,
  }) async {
    final visibleTools = _resolveVisibleTools(turn.userInput);
    final allowedToolNames = _resolveAllowedToolNames(visibleTools);
    final plannerToolOptions = visibleTools
        .map(
          (tool) => PlannerToolOption(
            name: tool.name,
            description: tool.descriptionForModel,
            inputSchema: tool.toPlannerJsonSchema(),
          ),
        )
        .toList(growable: false);
    final messages = <ChatMessage>[
      ChatMessage(
        text: _promptBuilder.buildSystemPrompt(
          visibleTools: visibleTools,
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
        );
      }
      Logger.w(
        _tag,
        'native planner returned null, fallback to compatibility path',
      );
    } catch (error, stackTrace) {
      Logger.w(
        _tag,
        'native planner decision unavailable, fallback to legacy path: ${_preview(error.toString())}',
      );
      Logger.e(_tag, 'native planner decision stack trace', stackTrace);
    }
    try {
      final raw = await _requestLegacyPlannerRaw(
        turn: turn,
        transcript: transcript,
        config: config,
        limits: limits,
      );
      final decision = _parseLegacyDecision(
        raw,
        allowedToolNames: allowedToolNames,
      );
      final repeatedEmptyRetrievalDecision =
          _buildRepeatedEmptyRetrievalDecision(
        decision: decision,
        steps: steps,
      );
      if (repeatedEmptyRetrievalDecision != null) {
        return repeatedEmptyRetrievalDecision;
      }
      return decision;
    } catch (_) {
      return const ModelTurnDecision(
        toolCalls: [],
        assistantMessage: '抱歉，我暂时无法规划下一步动作，请直接重试。',
        diagnosticCode: 'planner_request_failed',
        providerState: {},
        isTerminal: true,
      );
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
      final visibleTools = _resolveVisibleTools(turn.userInput);
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
    final visibleTools = _resolveVisibleTools(turn.userInput);
    final messages = <ChatMessage>[
      ChatMessage(
        text: _promptBuilder.buildSystemPrompt(
          visibleTools: visibleTools,
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
  }) {
    if (decision.toolCalls.isEmpty) {
      return decision;
    }

    final filteredCalls = <ModelToolCall>[];
    for (final toolCall in decision.toolCalls) {
      if (!allowedToolNames.contains(toolCall.toolName.trim())) {
        Logger.w(
          _tag,
          'native planner emitted unsupported tool: ${toolCall.toolName}',
        );
        continue;
      }
      filteredCalls.add(toolCall);
    }

    if (filteredCalls.isEmpty) {
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

  ModelTurnDecision? _buildRepeatedEmptyRetrievalDecision({
    required ModelTurnDecision decision,
    required List<ChatTurnStep> steps,
  }) {
    if (decision.toolCalls.length != 1) {
      return null;
    }
    final toolCall = decision.toolCalls.single;

    final latestCompletedStep = _findLatestCompletedStep(steps);
    if (latestCompletedStep == null) {
      return null;
    }

    if (latestCompletedStep.toolName != toolCall.toolName) {
      return null;
    }
    if (!_deepEquals(latestCompletedStep.toolArgsJson, toolCall.arguments)) {
      return null;
    }
    if (!_isEmptyRetrievalResult(latestCompletedStep)) {
      return null;
    }

    Logger.w(
      _tag,
      'legacy planner repeated empty retrieval, short-circuiting tool loop: ${toolCall.toolName} args=${toolCall.arguments}',
    );
    return const ModelTurnDecision(
      toolCalls: [],
      assistantMessage:
          '我刚才没有在当前聊天记录里找到相关信息。请补充更明确的关键词，或者直接告诉我数据库版本和确认时间，我再继续帮你整理笔记和提醒。',
      diagnosticCode: 'planner_repeated_empty_retrieval',
      providerState: {},
      isTerminal: true,
    );
  }

  ChatTurnStep? _findLatestCompletedStep(List<ChatTurnStep> steps) {
    for (var index = steps.length - 1; index >= 0; index--) {
      final step = steps[index];
      if (step.status == ChatTurnStepStatus.completed) {
        return step;
      }
    }
    return null;
  }

  bool _isEmptyRetrievalResult(ChatTurnStep step) {
    final result = step.resultJson;
    if (result == null) {
      return false;
    }

    switch (step.toolName) {
      case 'search_chat_history':
        return (result['matchCount'] is int ? result['matchCount'] as int : -1) ==
                0 &&
            result['matches'] is List &&
            (result['matches'] as List).isEmpty;
      case 'web_search':
        return result['results'] is List && (result['results'] as List).isEmpty;
      case 'fetch_webpage':
        final content = result['content'];
        return content is String && content.trim().isEmpty;
      default:
        return false;
    }
  }

  bool _deepEquals(dynamic left, dynamic right) {
    if (left is Map && right is Map) {
      if (left.length != right.length) {
        return false;
      }
      for (final entry in left.entries) {
        if (!right.containsKey(entry.key)) {
          return false;
        }
        if (!_deepEquals(entry.value, right[entry.key])) {
          return false;
        }
      }
      return true;
    }

    if (left is List && right is List) {
      if (left.length != right.length) {
        return false;
      }
      for (var index = 0; index < left.length; index++) {
        if (!_deepEquals(left[index], right[index])) {
          return false;
        }
      }
      return true;
    }

    return left == right;
  }

  ModelTurnDecision _parseLegacyDecision(
    String raw, {
    required List<String> allowedToolNames,
  }) {
    try {
      final payloads = _extractJsonObjects(_unwrapCodeFence(raw));
      if (payloads.isEmpty) {
        return const ModelTurnDecision(
          toolCalls: [],
          assistantMessage: '抱歉，我暂时无法规划下一步动作，请直接重试。',
          diagnosticCode: 'planner_parse_failed',
          providerState: {},
          isTerminal: true,
        );
      }

      final toolCalls = <ModelToolCall>[];
      String? response;
      for (var index = 0; index < payloads.length; index++) {
        final decoded = jsonDecode(payloads[index]);
        if (decoded is! Map<String, dynamic>) {
          continue;
        }
        final action = _normalizeStringField(decoded['action']);
        if (action == 'respond') {
          response ??= _normalizeStringField(decoded['response']);
          continue;
        }
        if (action != 'call_tool') {
          continue;
        }

        final toolCall = ToolCall.fromJson({
          'toolName': _normalizeStringField(decoded['toolName']),
          'arguments': decoded['arguments'],
        });
        if (!allowedToolNames.contains(toolCall.toolName)) {
          Logger.w(
            _tag,
            'planner emitted unsupported tool: ${toolCall.toolName}',
          );
          continue;
        }
        toolCalls.add(
          ModelToolCall(
            toolName: toolCall.toolName,
            arguments: toolCall.arguments,
            sequence: index + 1,
          ),
        );
      }

      if (toolCalls.isNotEmpty) {
        return ModelTurnDecision(
          toolCalls: toolCalls,
          assistantMessage: null,
          diagnosticCode: toolCalls.length == 1
              ? 'planner_action_call_tool'
              : 'planner_action_call_tools',
          providerState: const {},
          isTerminal: false,
        );
      }

      if (response != null && response.isNotEmpty) {
        return ModelTurnDecision(
          toolCalls: const [],
          assistantMessage: response,
          diagnosticCode: 'planner_action_respond',
          providerState: const {},
          isTerminal: true,
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
    return const ModelTurnDecision(
      toolCalls: [],
      assistantMessage: '抱歉，我暂时无法规划下一步动作，请直接重试。',
      diagnosticCode: 'planner_parse_failed',
      providerState: {},
      isTerminal: true,
    );
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

  List<ToolDefinition> _resolveVisibleTools(String userInput) {
    if (_availableTools.isEmpty) {
      return const [];
    }
    return _toolExposureService.selectVisibleTools(
      userInput: userInput,
      allTools: _availableTools,
    );
  }

  List<String> _resolveAllowedToolNames(List<ToolDefinition> visibleTools) {
    if (visibleTools.isNotEmpty) {
      return visibleTools.map((tool) => tool.name).toList(growable: false);
    }
    return _legacyAllowedToolNames;
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
