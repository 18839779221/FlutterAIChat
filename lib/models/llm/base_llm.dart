import 'package:ai_chat/services/chat_service.dart';

import '../chat_message.dart';
import '../tool/tool_definition.dart';

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

  /// 非流式工具决策入口
  Future<String> decideToolCall({
    required String userMessage,
    required List<ChatMessage> history,
    required List<ToolDefinition> tools,
  });
}
