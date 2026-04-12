import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';
import '../models/llm/base_llm.dart';
import '../models/response/structured_summary_card.dart';
import '../models/trace/chat_trace_event.dart';
import '../models/tool/tool_invocation.dart';
import 'chat_trace_recorder.dart';
import 'tool_call_service.dart';
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
  static const String debugStructuredSuccessMarker =
      '#debug-structured-success';
  final BaseLLM _llm;
  final MessageContextStrategy _contextStrategy;
  final ResponseParserService _responseParserService;
  final ToolCallService? _toolCallService;
  final ChatTraceRecorder? _traceRecorder;
  final int maxTokens;

  ChatService({
    required BaseLLM llm,
    MessageContextStrategy? contextStrategy,
    ResponseParserService? responseParserService,
    ToolCallService? toolCallService,
    ChatTraceRecorder? traceRecorder,
    this.maxTokens = 4000, // 默认token限制
  })  : _llm = llm,
        _contextStrategy = contextStrategy ?? TokenBasedStrategy(),
        _responseParserService =
            responseParserService ?? ResponseParserService(),
        _toolCallService = toolCallService,
        _traceRecorder = traceRecorder;

  // 暴露LLM实例供外部使用
  BaseLLM get llm => _llm;

  Stream<String> sendMessageStream(
    String message,
    List<ChatMessage> history,
    ChatConfig config, {
    String? turnId,
  }) async* {
    try {
      Logger.i(_tag, '准备发送消息，历史消息数: ${history.length}');

      // 使用策略选择上下文消息
      final contextMessages = _ensureRecentCriticalContext(
        history,
        _contextStrategy.selectContext(history, maxTokens),
      );
      Logger.i(_tag, '选择的上下文消息数: ${contextMessages.length}');
      _recordTrace(
        turnId: turnId,
        stage: ChatTraceStage.contextSelected,
        status: ChatTraceStatus.success,
        summary: '上下文选择完成',
        data: {
          'historyCount': history.length,
          'selectedCount': contextMessages.length,
        },
      );

      // 添加当前消息
      final messages = [
        ...contextMessages,
        ChatMessage(
          text: message,
          role: MessageRole.user,
        ),
      ];

      if (config.systemPrompt.isNotEmpty) {
        messages.insert(
            0,
            ChatMessage(
              text: config.systemPrompt,
              role: MessageRole.system,
            ));
      }

      _recordTrace(
        turnId: turnId,
        stage: ChatTraceStage.llmRequestStart,
        status: ChatTraceStatus.started,
        summary: '开始请求 LLM',
        data: {
          'messageCount': messages.length,
          'useReasoning': config.useReasoning,
        },
      );
      var hasRecordedFirstToken = false;
      await for (final content in _llm.chatStream(messages, config)) {
        if (!hasRecordedFirstToken) {
          hasRecordedFirstToken = true;
          _recordTrace(
            turnId: turnId,
            stage: ChatTraceStage.llmFirstToken,
            status: ChatTraceStatus.success,
            summary: '收到首个 LLM token',
            data: const {},
          );
        }
        yield content;
      }
      _recordTrace(
        turnId: turnId,
        stage: ChatTraceStage.llmDone,
        status: ChatTraceStatus.success,
        summary: 'LLM 请求完成',
        data: {
          'receivedFirstToken': hasRecordedFirstToken,
        },
      );
    } catch (e, stackTrace) {
      Logger.e(_tag, '发送消息失败', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      _recordTrace(
        turnId: turnId,
        stage: ChatTraceStage.llmDone,
        status: ChatTraceStatus.failure,
        summary: 'LLM 请求失败',
        data: {
          'error': e.toString(),
        },
      );
      throw Exception('发送消息失败: $e');
    }
  }

  List<ChatMessage> _ensureRecentCriticalContext(
    List<ChatMessage> history,
    List<ChatMessage> selectedMessages,
  ) {
    if (history.isEmpty) {
      return selectedMessages;
    }

    final latestMessage = history.last;
    final alreadyIncluded = selectedMessages.any(
      (message) =>
          identical(message, latestMessage) ||
          (message.role == latestMessage.role &&
              message.timestamp == latestMessage.timestamp &&
              message.text == latestMessage.text),
    );
    if (alreadyIncluded) {
      return selectedMessages;
    }

    // Tool/system context is critical for the immediate follow-up answer. When
    // the generic context strategy drops it entirely because the message is too
    // long, keep a truncated version instead of sending the user turn alone.
    if (latestMessage.role != MessageRole.system) {
      return selectedMessages;
    }

    final fallbackMessages = <ChatMessage>[
      ...selectedMessages,
      _truncateMessageForContext(latestMessage),
    ];
    Logger.w(_tag, '上下文策略丢弃了最近系统消息，已注入截断后的保底上下文');
    return fallbackMessages;
  }

  ChatMessage _truncateMessageForContext(ChatMessage message) {
    final maxContextChars = maxTokens.clamp(200, 1200);
    final normalizedText = message.text.trim();
    if (normalizedText.length <= maxContextChars) {
      return message;
    }

    return message.copyWith(
      text: '${normalizedText.substring(0, maxContextChars)}\n...[truncated]',
    );
  }

  Future<ToolPreparationResult> prepareToolAssistance({
    required int groupId,
    required String userMessage,
    required List<ChatMessage> history,
    String? turnId,
  }) async {
    final toolCallService = _toolCallService;
    if (toolCallService == null) {
      return const ToolPreparationResult.noTool();
    }

    try {
      return await toolCallService.prepareToolContext(
        groupId: groupId,
        userMessage: userMessage,
        history: history,
        turnId: turnId,
      );
    } catch (e, stackTrace) {
      Logger.e(_tag, '工具预处理失败', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      return const ToolPreparationResult.noTool();
    }
  }

  Future<ToolPreparationResult> executeToolInvocation({
    required int groupId,
    required ToolInvocation invocation,
    bool trustTool = false,
    String? turnId,
  }) async {
    final toolCallService = _toolCallService;
    if (toolCallService == null) {
      return const ToolPreparationResult.noTool();
    }

    try {
      return await toolCallService.executeToolInvocation(
        groupId: groupId,
        invocation: invocation,
        trustTool: trustTool,
        turnId: turnId,
      );
    } catch (e, stackTrace) {
      Logger.e(_tag, '工具执行失败', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      return const ToolPreparationResult.noTool();
    }
  }

  Future<StructuredSummaryParseResult> structureMessageForDebug(
      String sourceText) async {
    try {
      if (kDebugMode && sourceText.contains(debugStructuredSuccessMarker)) {
        return const StructuredSummaryParseResult.structured(
          StructuredSummaryCard(
            title: 'Debug Structured Summary',
            summary:
                'Generated from the local debug structured-output shortcut.',
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

  void _recordTrace({
    required String? turnId,
    required ChatTraceStage stage,
    required ChatTraceStatus status,
    required String summary,
    required Map<String, dynamic> data,
  }) {
    final traceRecorder = _traceRecorder;
    if (traceRecorder == null || turnId == null) {
      return;
    }
    traceRecorder.record(
      turnId: turnId,
      stage: stage,
      status: status,
      summary: summary,
      data: data,
    );
  }
}
