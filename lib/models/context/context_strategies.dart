import 'message_context_strategy.dart';
import '../chat_message.dart';

/// 固定数量消息策略
class FixedCountStrategy extends MessageContextStrategy {
  final int maxMessages;

  FixedCountStrategy({this.maxMessages = 10});

  @override
  List<ChatMessage> selectContext(List<ChatMessage> history, int maxTokens) {
    if (history.isEmpty) return [];
    return history.length <= maxMessages 
        ? history 
        : history.sublist(history.length - maxMessages);
  }
}

/// 基于Token数量的策略
class TokenBasedStrategy extends MessageContextStrategy {
  @override
  List<ChatMessage> selectContext(List<ChatMessage> history, int maxTokens) {
    if (history.isEmpty) return [];
    
    int totalTokens = 0;
    final selectedMessages = <ChatMessage>[];
    
    // 从最近的消息开始添加
    for (var message in history.reversed) {
      final tokens = estimateTokens(message);
      if (totalTokens + tokens > maxTokens) break;
      
      selectedMessages.insert(0, message);
      totalTokens += tokens;
    }
    
    return selectedMessages;
  }
}

/// 智能选择策略（基于重要性和时间）
class SmartSelectionStrategy extends MessageContextStrategy {
  final double relevanceThreshold;
  final Duration maxTimeGap;

  SmartSelectionStrategy({
    this.relevanceThreshold = 0.5,
    this.maxTimeGap = const Duration(hours: 1),
  });

  @override
  List<ChatMessage> selectContext(List<ChatMessage> history, int maxTokens) {
    if (history.isEmpty) return [];
    
    final now = DateTime.now();
    int totalTokens = 0;
    final selectedMessages = <ChatMessage>[];
    
    // 计算消息的重要性分数
    final messagesWithScores = history.map((msg) {
      final timeScore = _calculateTimeScore(msg.timestamp, now);
      // TODO: 可以添加更多评分因素，如消息长度、关键词匹配等
      return MapEntry(msg, timeScore);
    }).toList();
    
    // 按分数排序
    messagesWithScores.sort((a, b) => b.value.compareTo(a.value));
    
    // 选择高分消息，同时确保不超过token限制
    for (var entry in messagesWithScores) {
      final tokens = estimateTokens(entry.key);
      if (totalTokens + tokens > maxTokens) break;
      if (entry.value < relevanceThreshold) break;
      
      selectedMessages.add(entry.key);
      totalTokens += tokens;
    }
    
    // 按时间顺序排序
    selectedMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return selectedMessages;
  }

  double _calculateTimeScore(DateTime messageTime, DateTime now) {
    final difference = now.difference(messageTime);
    if (difference > maxTimeGap) return 0;
    return 1 - (difference.inMilliseconds / maxTimeGap.inMilliseconds);
  }
}

/// 混合策略
class HybridStrategy extends MessageContextStrategy {
  final List<MessageContextStrategy> strategies;
  final List<double> weights;

  HybridStrategy({
    required this.strategies,
    required this.weights,
  }) : assert(strategies.length == weights.length),
       assert(weights.every((w) => w >= 0 && w <= 1)),
       assert(weights.reduce((a, b) => a + b) == 1);

  @override
  List<ChatMessage> selectContext(List<ChatMessage> history, int maxTokens) {
    final results = <List<ChatMessage>>[];
    
    // 获取每个策略的结果
    for (var i = 0; i < strategies.length; i++) {
      final tokensForStrategy = (maxTokens * weights[i]).round();
      results.add(strategies[i].selectContext(history, tokensForStrategy));
    }
    
    // 合并结果并去重
    final selectedMessages = <ChatMessage>{};
    for (var messages in results) {
      selectedMessages.addAll(messages);
    }
    
    // 确保不超过token限制
    int totalTokens = 0;
    final finalSelection = <ChatMessage>[];
    
    for (var message in selectedMessages) {
      final tokens = estimateTokens(message);
      if (totalTokens + tokens > maxTokens) break;
      
      finalSelection.add(message);
      totalTokens += tokens;
    }
    
    // 按时间顺序排序
    finalSelection.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return finalSelection;
  }
} 