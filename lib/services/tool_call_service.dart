import '../models/chat_message.dart';
import '../models/llm/base_llm.dart';
import '../models/tool/tool_invocation.dart';
import 'chat_trace_recorder.dart';
import 'tool_decision_service.dart';
import 'tool_executor.dart';
import 'tool_orchestrator_service.dart';
import 'tool_policy_service.dart';
import 'tool_registry.dart';
import '../tools/core/tool_runtime_registry.dart';

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

/// Compatibility facade that preserves the old entry point while delegating the
/// real decision/policy/execution flow to the orchestrator service.
class ToolCallService {
  ToolCallService({
    required BaseLLM llm,
    ToolRegistry? toolRegistry,
    ToolRuntimeRegistry? runtimeRegistry,
    required ToolExecutor toolExecutor,
    ToolPolicyService? toolPolicyService,
    ChatTraceRecorder? traceRecorder,
  }) : _orchestrator = ToolOrchestratorService(
          toolRegistry: toolRegistry ?? ToolRegistry(runtimeRegistry: runtimeRegistry),
          runtimeRegistry: runtimeRegistry,
          toolDecisionService: ToolDecisionService(
            llm: llm,
            toolRegistry: toolRegistry ?? ToolRegistry(runtimeRegistry: runtimeRegistry),
            traceRecorder: traceRecorder,
          ),
          toolPolicyService: toolPolicyService,
          toolExecutor: toolExecutor,
          traceRecorder: traceRecorder,
        );

  final ToolOrchestratorService _orchestrator;

  Future<ToolPreparationResult> prepareToolContext({
    required int groupId,
    required String userMessage,
    required List<ChatMessage> history,
    String? turnId,
  }) {
    return _orchestrator.prepareToolContext(
      groupId: groupId,
      userMessage: userMessage,
      history: history,
      turnId: turnId,
    );
  }

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
