import 'package:ai_chat/services/chat_service.dart';

import '../agent/model_turn_decision.dart';
import '../agent/planner_tool_option.dart';
import '../chat_message.dart';
import '../chat_turn.dart';
import '../context/planner_context_carrier.dart';
import 'streaming_message_event.dart';

class LlmRetryProgress {
  final String label;
  final int attempt;
  final int maxAttempts;
  final Duration delay;
  final Object error;

  const LlmRetryProgress({
    required this.label,
    required this.attempt,
    required this.maxAttempts,
    required this.delay,
    required this.error,
  });
}

typedef PlannerRuntimeStreamListener = void Function(
  StreamingMessageEvent event,
);

/// Optional capability for LLMs that can surface runtime-only planner stream
/// snapshots while still returning one final decision to the loop.
abstract class PlannerRuntimeStreamingCapable {
  void setPlannerRuntimeStreamListener(
    PlannerRuntimeStreamListener? listener,
  );
}

abstract class BaseLLM {
  /// Architecture:
  /// - docs/architecture/append-only-transcript.md
  ///
  /// Invariant:
  /// - planner-visible context is reconstructed from append-only transcript
  /// - provider/runtime state must not become planner continuation input
  /// 模型名称
  String getModelName(ChatConfig config);

  /// 获取模型配置
  Map<String, dynamic> get config;

  /// 生成对话摘要
  Future<String> summarizeConversation(List<ChatMessage> messages);

  /// Tool-internal webpage processing entry used by `fetch_webpage`.
  Future<String> processWebpageContent({
    required String webpageContent,
    required String prompt,
  }) {
    throw UnimplementedError('processWebpageContent is not implemented');
  }

  /// Planner decision built from carrier-shaped planner context.
  ///
  /// The carriers are produced by `SessionContextService.buildPlannerCarriers`
  /// and validated by `PlannerInvariantValidator` before reaching the adapter.
  /// Adapters splice [RawAssistantCarrier]s verbatim and materialize
  /// [SyntheticCarrier]s using provider-specific role mappings.
  Future<ModelTurnDecision?> planTurnDecision({
    required List<PlannerContextCarrier> carriers,
    required ChatTurnProviderStyle activeApiStyle,
    required bool currentTurnRunning,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
    void Function(LlmRetryProgress progress)? onRetryScheduled,
  }) async {
    return null;
  }
}

/// Optional capability for LLMs that can accept per-call runtime overrides for
/// side-model tasks without changing the base interface for older fakes/tests.
abstract class RuntimeConfigurableBaseLlm {
  Future<String> summarizeConversationWithConfig(
    List<ChatMessage> messages, {
    required ChatConfig config,
  });

  Future<String> runSideTextTaskWithConfig(
    List<ChatMessage> messages, {
    required ChatConfig config,
    required String requestLabel,
    Duration? timeout,
  });

  Future<String> processWebpageContentWithConfig({
    required String webpageContent,
    required String prompt,
    required ChatConfig config,
  }) {
    throw UnimplementedError(
      'processWebpageContentWithConfig is not implemented',
    );
  }
}
