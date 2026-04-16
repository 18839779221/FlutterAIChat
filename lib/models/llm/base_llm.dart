import 'package:ai_chat/services/chat_service.dart';

import '../agent/model_turn_decision.dart';
import '../agent/planner_tool_option.dart';
import '../chat_message.dart';
import '../chat_turn.dart';

abstract class BaseLLM {
  /// 模型名称
  String getModelName(ChatConfig config);

  /// 流式对话
  Stream<String> chatStream(List<ChatMessage> messages, ChatConfig config);

  /// 获取模型配置
  Map<String, dynamic> get config;

  /// 验证API密钥
  Future<bool> validateApiKey(ChatConfig config);

  /// 生成对话摘要
  Future<String> summarizeConversation(List<ChatMessage> messages);

  /// 非流式结构化整理调试入口
  Future<String> structureSummaryCard(String sourceText);

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
