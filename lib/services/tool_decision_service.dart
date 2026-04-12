import '../models/chat_message.dart';
import '../models/trace/chat_trace_event.dart';
import '../models/llm/base_llm.dart';
import '../models/tool/tool_call.dart';
import '../utils/logger.dart';
import 'chat_trace_recorder.dart';
import 'tool_registry.dart';

class ToolDecisionService {
  static const String _tag = 'ToolDecisionService';

  ToolDecisionService({
    required BaseLLM llm,
    ToolRegistry? toolRegistry,
    ChatTraceRecorder? traceRecorder,
  })  : _llm = llm,
        _toolRegistry = toolRegistry ?? ToolRegistry(),
        _traceRecorder = traceRecorder;

  final BaseLLM _llm;
  final ToolRegistry _toolRegistry;
  final ChatTraceRecorder? _traceRecorder;

  Future<ToolCall?> decideTool({
    required String userMessage,
    required List<ChatMessage> history,
    String? turnId,
  }) async {
    Logger.i(_tag, '开始工具决策，候选工具数: ${_toolRegistry.getAllTools().length}');
    final tools = _toolRegistry.getAllTools();
    final rawDecision = await _llm.decideToolCall(
      userMessage: userMessage,
      history: history,
      tools: tools,
    );
    Logger.i(_tag, '工具决策原始输出: ${_preview(rawDecision)}');

    final toolCall = _tryParseToolCall(rawDecision);
    if (toolCall == null) {
      Logger.w(_tag, '工具决策解析失败，回退为普通回答');
      _recordDecisionTrace(
        turnId: turnId,
        status: ChatTraceStatus.failure,
        data: {
          'reason': 'parse_failed',
          'rawDecisionPreview': _preview(rawDecision),
        },
      );
      return null;
    }

    if (toolCall.toolName == 'none') {
      Logger.i(_tag, '工具决策结果为 none');
      _recordDecisionTrace(
        turnId: turnId,
        status: ChatTraceStatus.success,
        data: {
          'toolName': 'none',
        },
      );
      return null;
    }

    final toolDefinition = _toolRegistry.findByName(toolCall.toolName);
    if (toolDefinition == null) {
      Logger.w(_tag, '工具决策命中了未知工具: ${toolCall.toolName}');
      _recordDecisionTrace(
        turnId: turnId,
        status: ChatTraceStatus.failure,
        data: {
          'toolName': toolCall.toolName,
          'reason': 'unknown_tool',
        },
      );
      return null;
    }

    if (!_matchesUserIntent(toolCall, userMessage)) {
      Logger.w(_tag, '工具决策与用户意图不匹配: ${toolCall.toolName} <- $userMessage');
      _recordDecisionTrace(
        turnId: turnId,
        status: ChatTraceStatus.failure,
        data: {
          'toolName': toolCall.toolName,
          'reason': 'intent_mismatch',
        },
      );
      return null;
    }

    if (!_hasValidStructuredArguments(toolCall)) {
      Logger.w(_tag, '工具决策参数校验失败: ${toolCall.toolName} ${toolCall.arguments}');
      _recordDecisionTrace(
        turnId: turnId,
        status: ChatTraceStatus.failure,
        data: {
          'toolName': toolCall.toolName,
          'reason': 'invalid_arguments',
        },
      );
      return null;
    }

    Logger.i(_tag, '工具决策命中: ${toolCall.toolName}');
    _recordDecisionTrace(
      turnId: turnId,
      status: ChatTraceStatus.success,
      data: {
        'toolName': toolCall.toolName,
        'arguments': toolCall.arguments,
      },
    );
    return toolCall;
  }

  void _recordDecisionTrace({
    required String? turnId,
    required ChatTraceStatus status,
    required Map<String, dynamic> data,
  }) {
    final traceRecorder = _traceRecorder;
    if (traceRecorder == null || turnId == null) {
      return;
    }
    traceRecorder.record(
      turnId: turnId,
      stage: ChatTraceStage.toolDecisionDone,
      status: status,
      summary: '工具决策完成',
      data: data,
    );
  }

  ToolCall? _tryParseToolCall(String rawDecision) {
    try {
      return ToolCall.fromRawJson(_normalizeRawDecision(rawDecision));
    } catch (error) {
      Logger.w(_tag, '工具决策 JSON 解析失败: $error');
      return null;
    }
  }

  String _normalizeRawDecision(String rawDecision) {
    final trimmed = rawDecision.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }

    if (trimmed.startsWith('```')) {
      final fenceMatch = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```').firstMatch(trimmed);
      if (fenceMatch != null) {
        return fenceMatch.group(1)!.trim();
      }
    }

    final firstBrace = trimmed.indexOf('{');
    final lastBrace = trimmed.lastIndexOf('}');
    if (firstBrace >= 0 && lastBrace > firstBrace) {
      return trimmed.substring(firstBrace, lastBrace + 1).trim();
    }

    return trimmed;
  }

  String _preview(String rawDecision) {
    final normalized = rawDecision.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 240) {
      return normalized;
    }
    return '${normalized.substring(0, 240)}...';
  }

  bool _hasValidStructuredArguments(ToolCall toolCall) {
    switch (toolCall.toolName) {
      case 'create_reminder':
        final dueAt = toolCall.arguments['dueAt'];
        if (dueAt is! String || dueAt.trim().isEmpty) {
          return false;
        }
        return DateTime.tryParse(dueAt.trim()) != null;
      case 'create_calendar_event':
        final startAt = toolCall.arguments['startAt'];
        if (startAt is! String || startAt.trim().isEmpty) {
          return false;
        }
        final parsedStartAt = DateTime.tryParse(startAt.trim());
        if (parsedStartAt == null) {
          return false;
        }

        final endAt = toolCall.arguments['endAt'];
        if (endAt == null) {
          return true;
        }
        if (endAt is! String || endAt.trim().isEmpty) {
          return false;
        }
        return DateTime.tryParse(endAt.trim()) != null;
      default:
        return true;
    }
  }

  bool _matchesUserIntent(ToolCall toolCall, String userMessage) {
    switch (toolCall.toolName) {
      case 'fetch_webpage':
        return _extractFirstUrl(userMessage) != null;
      default:
        return true;
    }
  }
}

String? _extractFirstUrl(String text) {
  final match = RegExp(r'https?://[^\s]+', caseSensitive: false).firstMatch(text);
  return match?.group(0);
}
