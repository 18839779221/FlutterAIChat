import 'package:ai_chat/services/chat_service.dart';

import '../agent/model_turn_decision.dart';
import '../chat/runtime_stream_entry.dart';
import '../agent/planner_tool_option.dart';
import '../chat_message.dart';

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
  List<RuntimeStreamEntry> entries,
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

  /// Planner decision built from append-only transcript context.
  Future<ModelTurnDecision?> planTurnDecision({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
    void Function(LlmRetryProgress progress)? onRetryScheduled,
  }) async {
    return null;
  }
}
