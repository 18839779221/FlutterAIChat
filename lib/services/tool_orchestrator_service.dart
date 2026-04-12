import '../models/chat_message.dart';
import '../models/tool/tool_invocation.dart';
import '../models/tool/tool_result.dart';
import '../models/trace/chat_trace_event.dart';
import '../tools/core/tool_execution_context.dart';
import '../tools/core/tool_runtime_registry.dart';
import 'chat_trace_recorder.dart';
import 'tool_call_service.dart';
import 'tool_policy_service.dart';

/// Executes already-decided tool invocations and packages runtime context back
/// to the caller.
class ToolOrchestratorService {
  ToolOrchestratorService({
    ToolRuntimeRegistry? runtimeRegistry,
    ToolPolicyService? toolPolicyService,
    ChatTraceRecorder? traceRecorder,
  })  : _runtimeRegistry = runtimeRegistry,
        _toolPolicyService = toolPolicyService,
        _traceRecorder = traceRecorder;

  final ToolRuntimeRegistry? _runtimeRegistry;
  final ToolPolicyService? _toolPolicyService;
  final ChatTraceRecorder? _traceRecorder;

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
    if (runtimeHandler == null) {
      return const ToolPreparationResult.noTool();
    }
    final toolDefinition = runtimeHandler.definition;
    final normalizedArguments = await runtimeHandler.normalizeArguments(
      rawArguments: invocation.arguments,
      userMessage: invocation.summary,
      history: const <ChatMessage>[],
      now: DateTime.now(),
    );
    if (!normalizedArguments.isValid) {
      final failureResult = ToolResult(
        toolName: invocation.toolName,
        status: ToolExecutionStatus.failure,
        summary:
            normalizedArguments.errorSummary ?? '工具执行失败：参数无效',
        errorMessage: normalizedArguments.errorCode ?? 'invalid_arguments',
        data: {
          'reason': normalizedArguments.errorCode ?? 'invalid_arguments',
        },
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
    );
    final toolResult = await runtimeHandler.execute(executionContext);
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
        'contextLength':
            contextMessages.map((message) => message.text).join('\n').trim().length,
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
