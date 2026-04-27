import 'package:ai_chat/services/chat_service.dart';

import '../agent/model_turn_decision.dart';
import '../agent/planner_tool_option.dart';
import '../chat_message.dart';
import '../chat_turn.dart';

abstract class BaseLLM {
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

  /// Provider-native multi-tool planner decision.
  Future<ModelTurnDecision?> planTurnDecision({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
    ChatTurnProviderStyle? providerStyle,
    Map<String, dynamic>? providerState,
    List<Map<String, dynamic>> providerContinuationItems = const [],
  }) async {
    return null;
  }
}
