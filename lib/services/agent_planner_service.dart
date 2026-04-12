import 'dart:convert';

import '../models/agent/agent_action.dart';
import '../models/agent/agent_loop_limits.dart';
import '../models/chat_event.dart';
import '../models/chat_message.dart';
import '../models/chat_turn.dart';
import '../models/llm/base_llm.dart';
import '../models/tool/tool_call.dart';
import 'chat_service.dart';
import '../utils/logger.dart';

class AgentPlannerService {
  static const _tag = 'AgentPlannerService';
  static const _allowedToolNames = [
    'search_chat_history',
    'web_search',
    'fetch_webpage',
    'save_note',
    'create_reminder',
    'create_calendar_event',
    'share_result',
  ];

  final BaseLLM _llm;

  AgentPlannerService({
    required BaseLLM llm,
  }) : _llm = llm;

  Future<AgentAction> planNextAction({
    required ChatTurn turn,
    required List<ChatEvent> transcript,
    required ChatConfig config,
    required AgentLoopLimits limits,
  }) async {
    final messages = <ChatMessage>[
      ChatMessage(
        text: '你是一个对话回合规划器。'
            '你每次只能做一件事：'
            '1. 直接回复用户，返回 {"action":"respond","response":"..."}'
            '2. 调用一个工具，返回 {"action":"call_tool","toolName":"...","arguments":{...}}'
            '只能调用这些工具名：${_allowedToolNames.join('、')}。'
            '只返回 JSON，不要输出 Markdown，不要输出解释。',
        role: MessageRole.system,
      ),
      ChatMessage(
        text: '用户目标：${turn.userInput}\n'
            '当前轮次：${turn.iterationCount}\n'
            '已调用工具数：${turn.toolCallCount}\n'
            '最大轮次：${limits.maxIterations}',
        role: MessageRole.system,
      ),
      ...transcript.map(_eventToMessage),
    ];

    try {
      final raw = await _llm.planNextAction(
        messages: messages,
        config: config,
      );
      Logger.d(_tag, 'planner raw output: ${_preview(raw)}');
      return _parseAction(raw);
    } catch (_) {
      return const AgentAction.respond('抱歉，我暂时无法规划下一步动作，请直接重试。');
    }
  }

  AgentAction _parseAction(String raw) {
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
          return AgentAction.respond(response);
        }
      }

      if (action == 'call_tool') {
        final toolCall = ToolCall.fromJson({
          'toolName': _normalizeStringField(decoded['toolName']),
          'arguments': decoded['arguments'],
        });
        if (!_allowedToolNames.contains(toolCall.toolName)) {
          Logger.w(_tag, 'planner emitted unsupported tool: ${toolCall.toolName}');
          return const AgentAction.respond('抱歉，我暂时无法规划下一步动作，请直接重试。');
        }
        Logger.d(
          _tag,
          'parsed call_tool action: ${toolCall.toolName} args=${toolCall.arguments}',
        );
        return AgentAction.callTool(toolCall);
      }
    } catch (_) {
      // fall through to fallback
    }

    Logger.w(_tag, 'planner output fell back to respond');
    return const AgentAction.respond('抱歉，我暂时无法规划下一步动作，请直接重试。');
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
    final trimmed = raw.trim();
    if (trimmed.startsWith('```')) {
      final match =
          RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```').firstMatch(trimmed);
      if (match != null) {
        return match.group(1)!.trim();
      }
    }

    final firstBrace = trimmed.indexOf('{');
    final lastBrace = trimmed.lastIndexOf('}');
    if (firstBrace >= 0 && lastBrace > firstBrace) {
      return trimmed.substring(firstBrace, lastBrace + 1).trim();
    }

    return trimmed;
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
