import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';
import '../models/llm/base_llm.dart';
import '../models/response/structured_summary_card.dart';
import 'response_parser_service.dart';
import '../utils/logger.dart';
import '../models/context/message_context_strategy.dart';
import '../models/context/context_strategies.dart';

class ChatConfig {
  bool useReasoning = false;
  String systemPrompt = "";

  ChatConfig({
    required this.useReasoning,
    required this.systemPrompt,
  });
}

class ChatService {
  static const String _tag = 'ChatService';
  static const String debugStructuredSuccessMarker = '#debug-structured-success';
  final BaseLLM _llm;
  final MessageContextStrategy _contextStrategy;
  final ResponseParserService _responseParserService;
  final int maxTokens;

  ChatService({
    required BaseLLM llm,
    MessageContextStrategy? contextStrategy,
    ResponseParserService? responseParserService,
    this.maxTokens = 4000, // 默认token限制
  }) : _llm = llm,
       _contextStrategy = contextStrategy ?? TokenBasedStrategy(),
       _responseParserService = responseParserService ?? ResponseParserService();

  // 暴露LLM实例供外部使用
  BaseLLM get llm => _llm;

  Stream<String> sendMessageStream(String message, List<ChatMessage> history, ChatConfig config) async* {
    try {
      Logger.i(_tag, '准备发送消息，历史消息数: ${history.length}');
      
      // 使用策略选择上下文消息
      final contextMessages = _contextStrategy.selectContext(history, maxTokens);
      Logger.i(_tag, '选择的上下文消息数: ${contextMessages.length}');
      
      // 添加当前消息
      final messages = [
        ...contextMessages,
        ChatMessage(
          text: message,
          role: MessageRole.user,
        ),
      ];

      if (config.systemPrompt.isNotEmpty) {
        messages.insert(0, ChatMessage(
          text: config.systemPrompt,
          role: MessageRole.system,
        ));
      }

      await for (final content in _llm.chatStream(messages, config)) {
        yield content;
      }
    } catch (e, stackTrace) {
      Logger.e(_tag, '发送消息失败', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      throw Exception('发送消息失败: $e');
    }
  }

  Future<StructuredSummaryParseResult> structureMessageForDebug(String sourceText) async {
    try {
      if (kDebugMode && sourceText.contains(debugStructuredSuccessMarker)) {
        return const StructuredSummaryParseResult.structured(
          StructuredSummaryCard(
            title: 'Debug Structured Summary',
            summary: 'Generated from the local debug structured-output shortcut.',
            keyPoints: ['Local shortcut is active'],
            actionItems: ['Verify structured card rendering'],
            risks: ['Do not rely on this marker outside debug validation'],
          ),
        );
      }

      final rawOutput = await _llm.structureSummaryCard(sourceText);
      return _responseParserService.parseStructuredSummaryCard(rawOutput);
    } catch (e, stackTrace) {
      Logger.e(_tag, '结构化整理请求失败', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      return const StructuredSummaryParseResult.fallback();
    }
  }
}
