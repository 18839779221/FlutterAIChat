import '../models/chat_message.dart';
import '../models/trace/chat_trace_event.dart';
import '../models/tool/tool_definition.dart';
import '../models/tool/tool_invocation.dart';
import '../models/tool/tool_policy.dart';
import 'chat_trace_recorder.dart';
import 'tool_call_service.dart';
import 'tool_decision_service.dart';
import 'tool_executor.dart';
import 'tool_policy_service.dart';
import 'tool_registry.dart';
import '../tools/core/tool_argument_resolution.dart';
import '../tools/core/tool_execution_context.dart';
import '../tools/core/tool_runtime_registry.dart';

/// Coordinates single-step ToolCall flow: decide, policy-check, execute or
/// yield confirmation, then package result context for the chat layer.
class ToolOrchestratorService {
  ToolOrchestratorService({
    required ToolRegistry toolRegistry,
    ToolRuntimeRegistry? runtimeRegistry,
    required ToolDecisionService toolDecisionService,
    required ToolExecutor toolExecutor,
    ToolPolicyService? toolPolicyService,
    ChatTraceRecorder? traceRecorder,
  })  : _toolRegistry = toolRegistry,
        _runtimeRegistry = runtimeRegistry,
        _toolDecisionService = toolDecisionService,
        _toolPolicyService = toolPolicyService,
        _toolExecutor = toolExecutor,
        _traceRecorder = traceRecorder;

  final ToolRegistry _toolRegistry;
  final ToolRuntimeRegistry? _runtimeRegistry;
  final ToolDecisionService _toolDecisionService;
  final ToolPolicyService? _toolPolicyService;
  final ToolExecutor _toolExecutor;
  final ChatTraceRecorder? _traceRecorder;

  Future<ToolPreparationResult> prepareToolContext({
    required int groupId,
    required String userMessage,
    required List<ChatMessage> history,
    String? turnId,
  }) async {
    final now = DateTime.now();
    _recordTrace(
      turnId: turnId,
      stage: ChatTraceStage.toolPrepareStart,
      status: ChatTraceStatus.started,
      summary: '开始准备工具上下文',
      data: {'groupId': groupId},
    );
    final toolCall = await _toolDecisionService.decideTool(
      userMessage: userMessage,
      history: history,
      turnId: turnId,
    );
    if (toolCall == null) {
      return const ToolPreparationResult.noTool();
    }

    final runtimeHandler = _runtimeRegistry?.findHandler(toolCall.toolName);
    final toolDefinition =
        runtimeHandler?.definition ?? _toolRegistry.findByName(toolCall.toolName);
    if (toolDefinition == null) {
      return const ToolPreparationResult.noTool();
    }

    final normalizedArguments = runtimeHandler == null
        ? toolCall.arguments
        : await _normalizeHandlerArguments(
            handlerName: toolCall.toolName,
            resolution: await runtimeHandler.normalizeArguments(
              rawArguments: toolCall.arguments,
              userMessage: userMessage,
              history: history,
              now: now,
            ),
          );

    final policyDecision = await _resolvePolicyDecision(toolDefinition);
    if (policyDecision == ToolPolicyDecision.requireConfirmation) {
      return ToolPreparationResult(
        toolInvocation: ToolInvocation(
          toolName: toolCall.toolName,
          arguments: normalizedArguments,
          status: ToolInvocationStatus.awaitingConfirmation,
          summary: '准备执行工具：${toolDefinition.title}',
          requiresConfirmation: true,
        ),
        toolResult: null,
        additionalContextMessages: const [],
      );
      }

    final toolResult = runtimeHandler == null
        ? await _executeTool(
            toolDefinition: toolDefinition,
            arguments: normalizedArguments,
            groupId: groupId,
          )
        : await runtimeHandler.execute(
            _buildExecutionContext(
              groupId: groupId,
              toolName: toolCall.toolName,
              arguments: normalizedArguments,
              history: history,
              now: now,
            ),
          );
    _recordTrace(
      turnId: turnId,
      stage: ChatTraceStage.toolExecuteDone,
      status: toolResult.status == ToolExecutionStatus.success
          ? ChatTraceStatus.success
          : ChatTraceStatus.failure,
      summary: '工具执行完成',
      data: {
        'toolName': toolCall.toolName,
        'resultStatus': toolResult.status.name,
      },
    );
    final contextMessages = runtimeHandler == null
        ? [
            ChatMessage(
              text: _buildContextText(toolResult),
              role: MessageRole.system,
              status: MessageStatus.completed,
            ),
          ]
        : runtimeHandler.buildContextMessages(
            result: toolResult,
            context: _buildExecutionContext(
              groupId: groupId,
              toolName: toolCall.toolName,
              arguments: normalizedArguments,
              history: history,
              now: now,
            ),
          );
    final contextText =
        contextMessages.map((message) => message.text).join('\n').trim();
    _recordTrace(
      turnId: turnId,
      stage: ChatTraceStage.toolContextBuilt,
      status: ChatTraceStatus.success,
      summary: '工具上下文构建完成',
      data: {
        'toolName': toolCall.toolName,
        'contextLength': contextText.length,
      },
    );

    return ToolPreparationResult(
      toolInvocation: ToolInvocation(
        toolName: toolCall.toolName,
        arguments: normalizedArguments,
        status: ToolInvocationStatus.running,
        summary: '正在执行工具：${toolDefinition.title}',
        requiresConfirmation: false,
      ),
      toolResult: toolResult,
      additionalContextMessages: contextMessages,
    );
  }

  Future<void> trustTool(String toolName) async {
    await _toolPolicyService?.trustTool(toolName);
  }

  Future<void> untrustTool(String toolName) async {
    await _toolPolicyService?.untrustTool(toolName);
  }

  Future<ToolPreparationResult> executeToolInvocation({
    required int groupId,
    required ToolInvocation invocation,
    bool trustTool = false,
    String? turnId,
  }) async {
    if (trustTool) {
      await _toolPolicyService?.trustTool(invocation.toolName);
    }

    final runtimeHandler = _runtimeRegistry?.findHandler(invocation.toolName);
    final toolDefinition =
        runtimeHandler?.definition ?? _toolRegistry.findByName(invocation.toolName);
    if (toolDefinition == null) {
      return const ToolPreparationResult.noTool();
    }

    final executionContext = _buildExecutionContext(
      groupId: groupId,
      toolName: invocation.toolName,
      arguments: invocation.arguments,
      history: const [],
      now: DateTime.now(),
    );
    final toolResult = runtimeHandler == null
        ? await _executeTool(
            toolDefinition: toolDefinition,
            arguments: invocation.arguments,
            groupId: groupId,
          )
        : await runtimeHandler.execute(executionContext);
    _recordTrace(
      turnId: turnId,
      stage: ChatTraceStage.toolExecuteDone,
      status: toolResult.status == ToolExecutionStatus.success
          ? ChatTraceStatus.success
          : ChatTraceStatus.failure,
      summary: '工具执行完成',
      data: {
        'toolName': invocation.toolName,
        'resultStatus': toolResult.status.name,
      },
    );
    final contextMessages = runtimeHandler == null
        ? [
            ChatMessage(
              text: _buildContextText(toolResult),
              role: MessageRole.system,
              status: MessageStatus.completed,
            ),
          ]
        : runtimeHandler.buildContextMessages(
            result: toolResult,
            context: executionContext,
          );
    final contextText = contextMessages.map((message) => message.text).join('\n').trim();
    _recordTrace(
      turnId: turnId,
      stage: ChatTraceStage.toolContextBuilt,
      status: ChatTraceStatus.success,
      summary: '工具上下文构建完成',
      data: {
        'toolName': invocation.toolName,
        'contextLength': contextText.length,
      },
    );

    return ToolPreparationResult(
      toolInvocation: invocation.copyWith(
        status: ToolInvocationStatus.running,
        summary: '正在执行工具：${toolDefinition.title}',
        requiresConfirmation: false,
      ),
      toolResult: toolResult,
      additionalContextMessages: contextMessages,
    );
  }

  ToolExecutionContext _buildExecutionContext({
    required int groupId,
    required String toolName,
    required Map<String, dynamic> arguments,
    required List<ChatMessage> history,
    required DateTime now,
  }) {
    return ToolExecutionContext(
      groupId: groupId,
      toolName: toolName,
      arguments: arguments,
      history: history,
      now: now,
    );
  }

  Future<ToolPolicyDecision> _resolvePolicyDecision(
    ToolDefinition toolDefinition,
  ) async {
    final policyService = _toolPolicyService;
    if (policyService == null) {
      return toolDefinition.requiresConfirmation
          ? ToolPolicyDecision.requireConfirmation
          : ToolPolicyDecision.autoRun;
    }
    return policyService.resolveExecutionMode(toolDefinition);
  }

  Future<Map<String, dynamic>> _normalizeHandlerArguments({
    required String handlerName,
    required ToolArgumentResolution resolution,
  }) async {
    if (resolution.isValid) {
      return resolution.normalizedArguments;
    }

    return {
      'toolName': handlerName,
      'normalizationError': resolution.errorCode,
      'normalizationSummary': resolution.errorSummary,
    };
  }

  Future<ToolResult> _executeTool({
    required ToolDefinition toolDefinition,
    required Map<String, dynamic> arguments,
    required int groupId,
  }) async {
    switch (toolDefinition.name) {
      case 'search_chat_history':
        final query = arguments['query'];
        final maxResults = arguments['maxResults'];
        if (query is! String || query.trim().isEmpty) {
          return const ToolResult(
            toolName: 'search_chat_history',
            status: ToolExecutionStatus.failure,
            summary: '搜索历史记录失败',
            data: {'reason': 'invalid_arguments'},
            errorMessage: 'invalid_arguments',
          );
        }
        return _toolExecutor.executeSearchChatHistory(
          groupId: groupId,
          query: query,
          maxResults: maxResults is num ? maxResults.toInt() : 3,
        );
      case 'web_search':
        final query = arguments['query'];
        final maxResults = arguments['maxResults'];
        if (query is! String || query.trim().isEmpty) {
          return const ToolResult(
            toolName: 'web_search',
            status: ToolExecutionStatus.failure,
            summary: '联网搜索失败',
            data: {'reason': 'invalid_arguments'},
            errorMessage: 'invalid_arguments',
          );
        }
        return _toolExecutor.executeWebSearch(
          query: query,
          maxResults: maxResults is num ? maxResults.toInt() : 5,
        );
      case 'fetch_webpage':
        final url = arguments['url'];
        if (url is! String || url.trim().isEmpty) {
          return const ToolResult(
            toolName: 'fetch_webpage',
            status: ToolExecutionStatus.failure,
            summary: '读取网页失败',
            data: {'reason': 'invalid_arguments'},
            errorMessage: 'invalid_arguments',
          );
        }
        return _toolExecutor.executeFetchWebpage(
          url: url,
          extractMode: arguments['extractMode'] as String?,
        );
      case 'save_note':
        final title = arguments['title'];
        final content = arguments['content'];
        if (title is! String || content is! String) {
          return const ToolResult(
            toolName: 'save_note',
            status: ToolExecutionStatus.failure,
            summary: '保存笔记失败',
            data: {'reason': 'invalid_arguments'},
            errorMessage: 'invalid_arguments',
          );
        }
        return _toolExecutor.executeSaveNote(
          title: title,
          content: content,
          folder: arguments['folder'] as String?,
        );
      case 'create_reminder':
        final title = arguments['title'];
        if (title is! String || title.trim().isEmpty) {
          return const ToolResult(
            toolName: 'create_reminder',
            status: ToolExecutionStatus.failure,
            summary: '创建提醒失败',
            data: {'reason': 'invalid_arguments'},
            errorMessage: 'invalid_arguments',
          );
        }
        return _toolExecutor.executeCreateReminder(
          title: title,
          dueAt: arguments['dueAt'] as String?,
          note: arguments['note'] as String?,
        );
      case 'create_calendar_event':
        final title = arguments['title'];
        final startAt = arguments['startAt'];
        if (title is! String || startAt is! String) {
          return const ToolResult(
            toolName: 'create_calendar_event',
            status: ToolExecutionStatus.failure,
            summary: '创建日历事件失败',
            data: {'reason': 'invalid_arguments'},
            errorMessage: 'invalid_arguments',
          );
        }
        return _toolExecutor.executeCreateCalendarEvent(
          title: title,
          startAt: startAt,
          endAt: arguments['endAt'] as String?,
          location: arguments['location'] as String?,
          notes: arguments['notes'] as String?,
        );
      case 'share_result':
        final text = arguments['text'];
        if (text is! String || text.trim().isEmpty) {
          return const ToolResult(
            toolName: 'share_result',
            status: ToolExecutionStatus.failure,
            summary: '分享结果失败',
            data: {'reason': 'invalid_arguments'},
            errorMessage: 'invalid_arguments',
          );
        }
        return _toolExecutor.executeShareResult(
          text: text,
          subject: arguments['subject'] as String?,
        );
      default:
        return ToolResult(
          toolName: toolDefinition.name,
          status: ToolExecutionStatus.failure,
          summary: '工具执行失败',
          data: const {'reason': 'unsupported_tool'},
          errorMessage: 'unsupported_tool',
        );
    }
  }

  /// Builds a compact system prompt fragment so the next assistant turn can use
  /// tool output without needing to parse UI payloads.
  String _buildContextText(ToolResult toolResult) {
    final buffer = StringBuffer()
      ..writeln('以下是工具 `${toolResult.toolName}` 的执行结果，请结合这些信息回答用户。')
      ..writeln('状态：${toolResult.status.name}');

    final payload = toolResult.payload;
    if (payload['query'] is String) {
      buffer.writeln('查询词：${payload['query']}');
    }

    final matches = payload['matches'];
    if (matches is List && matches.isNotEmpty) {
      buffer.writeln('命中历史消息：');
      for (final match in matches) {
        if (match is Map) {
          final role = match['role'] ?? 'unknown';
          final text = match['text'] ?? '';
          buffer.writeln('- [$role] $text');
        }
      }
    } else if (toolResult.toolName == 'web_search') {
      final results = payload['results'];
      if (results is List && results.isNotEmpty) {
        buffer.writeln('联网搜索结果：');
        for (final result in results.take(3)) {
          if (result is Map) {
            final title = (result['title'] ?? '').toString().trim();
            final snippet = _truncateContextText(
              (result['snippet'] ?? '').toString().trim(),
              maxLength: 160,
            );
            final source = (result['source'] ?? '').toString().trim();
            final url = (result['url'] ?? '').toString().trim();
            final titleText = title.isEmpty ? url : title;
            final sourceText = source.isEmpty ? 'unknown' : source;
            buffer.writeln('- [$sourceText] $titleText');
            if (snippet.isNotEmpty) {
              buffer.writeln('  摘要：$snippet');
            }
            if (url.isNotEmpty) {
              buffer.writeln('  链接：$url');
            }
          }
        }
      } else if (toolResult.summary.isNotEmpty) {
        buffer.writeln('结果摘要：${toolResult.summary}');
      }
    } else if (toolResult.summary.isNotEmpty) {
      buffer.writeln('结果摘要：${toolResult.summary}');
    }

    return buffer.toString().trim();
  }

  String _truncateContextText(
    String value, {
    required int maxLength,
  }) {
    if (value.length <= maxLength) {
      return value;
    }
    return '${value.substring(0, maxLength)}...';
  }

  void _recordTrace({
    required String? turnId,
    required ChatTraceStage stage,
    required ChatTraceStatus status,
    required String summary,
    required Map<String, dynamic> data,
  }) {
    final traceRecorder = _traceRecorder;
    if (traceRecorder == null || turnId == null) {
      return;
    }
    traceRecorder.record(
      turnId: turnId,
      stage: stage,
      status: status,
      summary: summary,
      data: data,
    );
  }
}
