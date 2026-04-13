import '../models/chat_message.dart';
import '../models/tool/tool_access_snapshot.dart';
import '../models/tool/tool_invocation.dart';
import 'chat_trace_recorder.dart';
import 'tool_executor.dart';
import 'tool_orchestrator_service.dart';
import 'tool_policy_service.dart';
import '../tools/adapters/tool_host_adapters.dart';
import '../tools/core/tool_runtime_registry.dart';
import '../tools/default_tool_runtime_registry.dart';

class ToolPreparationResult {
  /// Tool invocation payload for pending confirmation or running-state display.
  final ToolInvocation? toolInvocation;

  /// Final tool execution result once a tool has actually run.
  final ToolResult? toolResult;

  /// Shared access snapshot used by planner/runtime/event projection.
  final ToolAccessSnapshot? toolAccess;

  /// Tool-handler-produced raw context kept for diagnostics and future adapters.
  /// The orchestrator should not inject these messages verbatim into planner or
  /// final-answer prompts.
  final List<ChatMessage> additionalContextMessages;

  const ToolPreparationResult({
    this.toolInvocation,
    this.toolAccess,
    required this.toolResult,
    required this.additionalContextMessages,
  });

  const ToolPreparationResult.noTool()
      : toolInvocation = null,
        toolAccess = null,
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
    ToolHostAdapters hostAdapters = const ToolHostAdapters(),
  }) : _orchestrator = ToolOrchestratorService(
          runtimeRegistry: runtimeRegistry ??
              buildDefaultToolRuntimeRegistry(toolExecutor: toolExecutor),
          toolPolicyService: toolPolicyService,
          traceRecorder: traceRecorder,
          hostAdapters: hostAdapters,
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
