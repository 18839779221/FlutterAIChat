import 'package:ai_chat/services/chat_service.dart';

import '../chat_message.dart';

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
} 