import '../models/chat_message.dart';
import '../models/tool/tool_definition.dart';
import '../models/tool/tool_result.dart';
import '../models/trace/chat_trace_event.dart';
import '../models/tool/tool_invocation.dart';
import '../models/tool/tool_policy.dart';
import 'chat_trace_recorder.dart';
import 'tool_call_service.dart';
import 'tool_decision_service.dart';
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
    required Object toolExecutor,
    ToolPolicyService? toolPolicyService,
    ChatTraceRecorder? traceRecorder,
  })  : _runtimeRegistry = runtimeRegistry,
        _toolDecisionService = toolDecisionService,
        _toolPolicyService = toolPolicyService,
        _traceRecorder = traceRecorder;

  final ToolRuntimeRegistry? _runtimeRegistry;
  final ToolDecisionService _toolDecisionService;
  final ToolPolicyService? _toolPolicyService;
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
    if (runtimeHandler == null) {
      return const ToolPreparationResult.noTool();
    }
    final toolDefinition = runtimeHandler.definition;

    final normalizedArguments = await _normalizeHandlerArguments(
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

    final toolResult = await runtimeHandler.execute(
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
    final contextMessages = runtimeHandler.buildContextMessages(
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
    if (runtimeHandler == null) {
      return const ToolPreparationResult.noTool();
    }
    final toolDefinition = runtimeHandler.definition;

    final executionContext = _buildExecutionContext(
      groupId: groupId,
      toolName: invocation.toolName,
      arguments: invocation.arguments,
      history: const [],
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
