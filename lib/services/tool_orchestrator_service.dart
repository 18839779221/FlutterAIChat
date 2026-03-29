import '../models/chat_message.dart';
import '../models/tool/tool_definition.dart';
import '../models/tool/tool_invocation.dart';
import '../models/tool/tool_policy.dart';
import 'tool_call_service.dart';
import 'tool_decision_service.dart';
import 'tool_executor.dart';
import 'tool_policy_service.dart';
import 'tool_registry.dart';

/// Coordinates single-step ToolCall flow: decide, policy-check, execute or
/// yield confirmation, then package result context for the chat layer.
class ToolOrchestratorService {
  ToolOrchestratorService({
    required ToolRegistry toolRegistry,
    required ToolDecisionService toolDecisionService,
    required ToolExecutor toolExecutor,
    ToolPolicyService? toolPolicyService,
  })  : _toolRegistry = toolRegistry,
        _toolDecisionService = toolDecisionService,
        _toolPolicyService = toolPolicyService,
        _toolExecutor = toolExecutor;

  final ToolRegistry _toolRegistry;
  final ToolDecisionService _toolDecisionService;
  final ToolPolicyService? _toolPolicyService;
  final ToolExecutor _toolExecutor;

  Future<ToolPreparationResult> prepareToolContext({
    required int groupId,
    required String userMessage,
    required List<ChatMessage> history,
  }) async {
    final toolCall = await _toolDecisionService.decideTool(
      userMessage: userMessage,
      history: history,
    );
    if (toolCall == null) {
      return const ToolPreparationResult.noTool();
    }

    final toolDefinition = _toolRegistry.findByName(toolCall.toolName);
    if (toolDefinition == null) {
      return const ToolPreparationResult.noTool();
    }

    final policyDecision = await _resolvePolicyDecision(toolDefinition);
    if (policyDecision == ToolPolicyDecision.requireConfirmation) {
      return ToolPreparationResult(
        toolInvocation: ToolInvocation(
          toolName: toolCall.toolName,
          arguments: toolCall.arguments,
          status: ToolInvocationStatus.awaitingConfirmation,
          summary: '准备执行工具：${toolDefinition.title}',
          requiresConfirmation: true,
        ),
        toolResult: null,
        additionalContextMessages: const [],
      );
    }

    final toolResult = await _executeTool(
      toolDefinition: toolDefinition,
      arguments: toolCall.arguments,
      groupId: groupId,
    );

    return ToolPreparationResult(
      toolInvocation: ToolInvocation(
        toolName: toolCall.toolName,
        arguments: toolCall.arguments,
        status: ToolInvocationStatus.running,
        summary: '正在执行工具：${toolDefinition.title}',
        requiresConfirmation: false,
      ),
      toolResult: toolResult,
      additionalContextMessages: [
        ChatMessage(
          text: _buildContextText(toolResult),
          role: MessageRole.system,
          status: MessageStatus.completed,
        ),
      ],
    );
  }

  Future<void> trustTool(String toolName) async {
    await _toolPolicyService?.trustTool(toolName);
  }

  Future<void> untrustTool(String toolName) async {
    await _toolPolicyService?.untrustTool(toolName);
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
    } else if (toolResult.summary.isNotEmpty) {
      buffer.writeln('结果摘要：${toolResult.summary}');
    }

    return buffer.toString().trim();
  }
}
