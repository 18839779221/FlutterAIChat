import '../chat_message.dart';

abstract class MessageContextStrategy {
  /// 从历史消息中选择合适的消息作为上下文
  List<ChatMessage> selectContext(List<ChatMessage> history, int maxTokens);
  
  /// 估算消息的token数量（粗略估计）
  int estimateTokens(ChatMessage message) {
    // 简单估算：中文字符按2个token，其他字符按1个token计算
    if (message.text.length <= 1) return message.text.length;
    return message.text.split('')
        .map((char) => char.codeUnitAt(0) > 127 ? 2 : 1)
        .reduce((a, b) => a + b);
  }
} 