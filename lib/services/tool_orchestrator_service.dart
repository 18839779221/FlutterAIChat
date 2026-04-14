import '../models/chat_message.dart';
import '../models/tool/tool_access_snapshot.dart';
import '../models/tool/tool_definition.dart';
import '../models/tool/tool_policy.dart';
import '../models/tool/tool_invocation.dart';
import '../models/tool/tool_result.dart';
import '../models/trace/chat_trace_event.dart';
import '../tools/adapters/tool_host_adapters.dart';
import '../tools/core/tool_execution_context.dart';
import '../tools/core/tool_runtime_registry.dart';
import '../utils/logger.dart';
import 'chat_trace_recorder.dart';
import 'tool_call_service.dart';
import 'tool_policy_service.dart';

/// Executes already-decided tool invocations and packages runtime context back
/// to the caller.
class ToolOrchestratorService {
  static const _tag = 'ToolOrchestratorService';
  ToolOrchestratorService({
    ToolRuntimeRegistry? runtimeRegistry,
    ToolPolicyService? toolPolicyService,
    ChatTraceRecorder? traceRecorder,
    ToolHostAdapters hostAdapters = const ToolHostAdapters(),
  })  : _runtimeRegistry = runtimeRegistry,
        _toolPolicyService = toolPolicyService,
        _traceRecorder = traceRecorder,
        _hostAdapters = hostAdapters;

  final ToolRuntimeRegistry? _runtimeRegistry;
  final ToolPolicyService? _toolPolicyService;
  final ChatTraceRecorder? _traceRecorder;
  final ToolHostAdapters _hostAdapters;

  Future<ToolPreparationResult> executeToolInvocation({
    required int groupId,
    required ToolInvocation invocation,
    bool trustTool = false,
    String? turnId,
  }) async {
    if (trustTool) {
      await _toolPolicyService?.trustTool(invocation.toolName);
    }

    Logger.i(
      _tag,
      'executeToolInvocation start groupId=$groupId tool=${invocation.toolName} trustTool=$trustTool rawArgs=${invocation.arguments}',
    );
    final runtimeHandler = _runtimeRegistry?.findHandler(invocation.toolName);
    if (runtimeHandler == null) {
      Logger.w(
        _tag,
        'no runtime handler found for tool=${invocation.toolName}',
      );
      return const ToolPreparationResult.noTool();
    }
    final toolDefinition = runtimeHandler.definition;
    if (toolDefinition.resolvedRuntimeKind == ToolRuntimeKind.userInteraction) {
      throw UnsupportedError(
        'user interaction tools must suspend the turn before runtime execution',
      );
    }
    final alreadyConfirmed =
        invocation.status == ToolInvocationStatus.awaitingConfirmation;
    final toolAccess = await _resolveToolAccess(toolDefinition);
    if (!alreadyConfirmed &&
        toolAccess.executionDecision ==
            ToolPolicyDecision.requireConfirmation) {
      Logger.i(
        _tag,
        'tool requires confirmation before execution tool=${invocation.toolName}',
      );
      return ToolPreparationResult(
        toolInvocation: invocation.copyWith(
          status: ToolInvocationStatus.awaitingConfirmation,
          summary: '请确认执行工具：${toolDefinition.title}',
          requiresConfirmation: true,
        ),
        toolAccess: toolAccess,
        toolResult: null,
        additionalContextMessages: const [],
      );
    }
    if (toolAccess.executionDecision == ToolPolicyDecision.blocked) {
      Logger.w(
        _tag,
        'tool execution blocked by policy tool=${invocation.toolName}',
      );
      final failureResult = _attachToolAccess(
        ToolResult(
          toolName: invocation.toolName,
          status: ToolExecutionStatus.failure,
          summary: '工具执行被策略阻止',
          errorMessage: 'tool_blocked',
          data: {
            'reason': 'tool_blocked',
          },
        ),
        toolAccess,
      );
      return ToolPreparationResult(
        toolInvocation: invocation.copyWith(
          status: ToolInvocationStatus.cancelled,
          summary: '工具执行已阻止：${toolDefinition.title}',
          requiresConfirmation: false,
        ),
        toolAccess: toolAccess,
        toolResult: failureResult,
        additionalContextMessages: const [],
      );
    }
    final normalizedArguments = await runtimeHandler.normalizeArguments(
      rawArguments: invocation.arguments,
      userMessage: invocation.summary,
      history: const <ChatMessage>[],
      now: DateTime.now(),
    );
    if (!normalizedArguments.isValid) {
      final failureResult = _attachToolAccess(
        ToolResult(
          toolName: invocation.toolName,
          status: ToolExecutionStatus.failure,
          summary: normalizedArguments.errorSummary ?? '工具执行失败：参数无效',
          errorMessage: normalizedArguments.errorCode ?? 'invalid_arguments',
          data: {
            'reason': normalizedArguments.errorCode ?? 'invalid_arguments',
          },
        ),
        toolAccess,
      );
      Logger.w(
        _tag,
        'tool argument validation failed tool=${invocation.toolName} error=${normalizedArguments.errorCode ?? 'invalid_arguments'} rawArgs=${invocation.arguments}',
      );
      _recordTrace(
        turnId: turnId,
        stage: ChatTraceStage.toolExecuteDone,
        status: ChatTraceStatus.failure,
        summary: '工具参数校验失败',
        data: {
          'toolName': invocation.toolName,
          'resultStatus': failureResult.status.name,
          'errorCode': failureResult.errorMessage,
        },
      );
      return ToolPreparationResult(
        toolInvocation: invocation.copyWith(
          status: ToolInvocationStatus.running,
          summary: '正在执行工具：${toolDefinition.title}',
          requiresConfirmation: false,
        ),
        toolAccess: toolAccess,
        toolResult: failureResult,
        additionalContextMessages: const [],
      );
    }

    final executionContext = ToolExecutionContext(
      groupId: groupId,
      toolName: invocation.toolName,
      arguments: normalizedArguments.normalizedArguments,
      history: const <ChatMessage>[],
      now: DateTime.now(),
      hostAdapters: _hostAdapters,
    );
    Logger.i(
      _tag,
      'tool normalized arguments tool=${invocation.toolName} args=${normalizedArguments.normalizedArguments}',
    );
    final toolResult = _attachToolAccess(
      await runtimeHandler.execute(executionContext),
      toolAccess,
    );
    Logger.i(
      _tag,
      'tool execution finished tool=${invocation.toolName} status=${toolResult.status.name} summary=${toolResult.summary}',
    );
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
    final contextMessages = runtimeHandler.buildContextMessages(
      result: toolResult,
      context: executionContext,
    );
    _recordTrace(
      turnId: turnId,
      stage: ChatTraceStage.toolContextBuilt,
      status: ChatTraceStatus.success,
      summary: '工具上下文构建完成',
      data: {
        'toolName': invocation.toolName,
        'contextLength': contextMessages
            .map((message) => message.text)
            .join('\n')
            .trim()
            .length,
      },
    );

    return ToolPreparationResult(
      toolInvocation: invocation.copyWith(
        status: ToolInvocationStatus.running,
        summary: '正在执行工具：${toolDefinition.title}',
        requiresConfirmation: false,
      ),
      toolAccess: toolAccess,
      toolResult: toolResult,
      additionalContextMessages: contextMessages,
    );
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

  Future<ToolAccessSnapshot> _resolveToolAccess(ToolDefinition tool) async {
    final toolPolicyService = _toolPolicyService;
    if (toolPolicyService == null) {
      throw StateError(
        'toolPolicyService is required when runtime resolves tool access',
      );
    }
    return toolPolicyService.resolveToolAccess(tool);
  }

  ToolResult _attachToolAccess(
    ToolResult result,
    ToolAccessSnapshot toolAccess,
  ) {
    return ToolResult(
      toolName: result.toolName,
      status: result.status,
      summary: result.summary,
      data: result.data,
      errorMessage: result.errorMessage,
      executionPolicy: toolAccess.executionPolicyLabel,
      toolAccess: toolAccess.toJson(),
    );
  }
}
