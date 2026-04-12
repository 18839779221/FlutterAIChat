import '../models/chat_message.dart';
import '../models/tool/tool_invocation.dart';
import 'chat_trace_recorder.dart';
import 'tool_executor.dart';
import 'tool_orchestrator_service.dart';
import 'tool_policy_service.dart';
import '../tools/core/tool_runtime_registry.dart';
import '../tools/default_tool_runtime_registry.dart';

class ToolPreparationResult {
  /// Tool invocation payload for pending confirmation or running-state display.
  final ToolInvocation? toolInvocation;

  /// Final tool execution result once a tool has actually run.
  final ToolResult? toolResult;

  /// Additional system messages that should be merged into the next LLM context.
  final List<ChatMessage> additionalContextMessages;

  const ToolPreparationResult({
    this.toolInvocation,
    required this.toolResult,
    required this.additionalContextMessages,
  });

  const ToolPreparationResult.noTool()
      : toolInvocation = null,
        toolResult = null,
        additionalContextMessages = const [];
}

/// Runtime facade for executing tool invocations that have already been
/// decided by the agent loop.
class ToolCallService {
  ToolCallService({
    ToolRuntimeRegistry? runtimeRegistry,
    required ToolExecutor toolExecutor,
    ToolPolicyService? toolPolicyService,
    ChatTraceRecorder? traceRecorder,
  }) : _orchestrator = ToolOrchestratorService(
          runtimeRegistry:
              runtimeRegistry ??
              buildDefaultToolRuntimeRegistry(toolExecutor: toolExecutor),
          toolPolicyService: toolPolicyService,
          traceRecorder: traceRecorder,
        );

  final ToolOrchestratorService _orchestrator;

  Future<ToolPreparationResult> executeToolInvocation({
    required int groupId,
    required ToolInvocation invocation,
    bool trustTool = false,
    String? turnId,
  }) {
    return _orchestrator.executeToolInvocation(
      groupId: groupId,
      invocation: invocation,
      trustTool: trustTool,
      turnId: turnId,
    );
  }
}
