import '../chat_message.dart';

abstract class BaseLLM {
  /// 模型名称
  String get modelName;
  
  /// 流式对话
  Stream<String> chatStream(List<ChatMessage> messages);
  
  /// 获取模型配置
  Map<String, dynamic> get config;
  
  /// 验证API密钥
  Future<bool> validateApiKey();
} 