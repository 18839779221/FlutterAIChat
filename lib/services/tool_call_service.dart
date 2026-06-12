import 'dart:async';

import '../models/chat_event.dart';
import '../models/llm/llm_config.dart';
import '../models/tool/tool_access_snapshot.dart';
import '../models/tool/tool_definition.dart';
import '../models/tool/tool_invocation.dart';
import 'chat_trace_recorder.dart';
import 'tool_executor.dart';
import 'tool_orchestrator_service.dart';
import 'tool_policy_service.dart';
import '../tools/adapters/tool_host_adapters.dart';
import '../tools/core/tool_runtime_registry.dart';
import '../tools/default_tool_runtime_registry.dart';

typedef ToolExecutionStartedCallback = FutureOr<void> Function({
  required ToolInvocation invocation,
  required ToolAccessSnapshot toolAccess,
});

class ToolPreparationResult {
  /// Tool invocation payload for pending confirmation or running-state display.
  final ToolInvocation? toolInvocation;

  /// Final tool execution result once a tool has actually run.
  final ToolResult? toolResult;

  /// Shared access snapshot used by planner/runtime/event projection.
  final ToolAccessSnapshot? toolAccess;

  /// Whether the runtime execution has already been surfaced to the transcript
  /// and step ledger before this result returns.
  final bool executionStarted;

  const ToolPreparationResult({
    this.toolInvocation,
    this.toolAccess,
    required this.toolResult,
    this.executionStarted = false,
  });

  const ToolPreparationResult.noTool()
      : toolInvocation = null,
        toolAccess = null,
        toolResult = null,
        executionStarted = false;
}

/// Runtime facade for executing tool invocations that have already been
/// decided by the agent loop.
class ToolCallService {
  final ToolRuntimeRegistry _runtimeRegistry;

  ToolCallService({
    ToolRuntimeRegistry? runtimeRegistry,
    required ToolExecutor toolExecutor,
    ToolPolicyService? toolPolicyService,
    ChatTraceRecorder? traceRecorder,
    ToolHostAdapters hostAdapters = const ToolHostAdapters(),
  })  : _runtimeRegistry = runtimeRegistry ??
            buildDefaultToolRuntimeRegistry(toolExecutor: toolExecutor),
        _orchestrator = ToolOrchestratorService(
          runtimeRegistry: runtimeRegistry ??
              buildDefaultToolRuntimeRegistry(toolExecutor: toolExecutor),
          toolPolicyService: toolPolicyService,
          traceRecorder: traceRecorder,
          hostAdapters: hostAdapters,
        );

  final ToolOrchestratorService _orchestrator;

  ToolDefinition? findDefinition(String toolName) {
    return _runtimeRegistry.findHandler(toolName)?.definition;
  }

  Future<ToolPreparationResult> executeToolInvocation({
    required int groupId,
    required ToolInvocation invocation,
    bool trustTool = false,
    String? turnId,
    List<ChatEvent> currentTurnEvents = const <ChatEvent>[],
    LLMConfig? sideRuntimeConfigOverride,
    ToolExecutionStartedCallback? onExecutionStarted,
  }) {
    return _orchestrator.executeToolInvocation(
      groupId: groupId,
      invocation: invocation,
      trustTool: trustTool,
      turnId: turnId,
      currentTurnEvents: currentTurnEvents,
      sideRuntimeConfigOverride: sideRuntimeConfigOverride,
      onExecutionStarted: onExecutionStarted,
    );
  }
}
