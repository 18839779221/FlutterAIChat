import '../models/chat_message.dart';
import '../models/llm/base_llm.dart';
import '../utils/logger.dart';

class ChatService {
  static const String _tag = 'ChatService';
  final BaseLLM _llm;
  static const int _maxContextMessages = 10;

  ChatService(this._llm);

  Stream<String> sendMessageStream(String message, List<ChatMessage> history) async* {
    try {
      Logger.i(_tag, '准备发送消息，历史消息数: ${history.length}');
      
      // 构建消息历史，只取最近的几条
      final recentHistory = history.length > _maxContextMessages 
          ? history.sublist(history.length - _maxContextMessages) 
          : history;
      
      // 添加当前消息
      final messages = [
        ...recentHistory,
        ChatMessage(
          text: message,
          role: MessageRole.user,
        ),
      ];

      await for (final content in _llm.chatStream(messages)) {
        yield content;
      }
    } catch (e, stackTrace) {
      Logger.e(_tag, '发送消息失败', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      throw Exception('发送消息失败: $e');
    }
  }
}