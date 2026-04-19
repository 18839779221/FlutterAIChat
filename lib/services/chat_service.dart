import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';
import '../models/llm/base_llm.dart';
import '../models/response/structured_summary_card.dart';
import '../models/tool/tool_invocation.dart';
import 'prompt/prompt_locale.dart';
import 'tool_call_service.dart';
import 'response_parser_service.dart';
import '../utils/logger.dart';

class ChatConfig {
  bool useReasoning = false;
  String systemPrompt = "";
  String userSystemPrompt = "";
  PromptLocale promptLocale = PromptLocale.english;

  ChatConfig({
    required this.useReasoning,
    required this.systemPrompt,
    this.userSystemPrompt = '',
    this.promptLocale = PromptLocale.english,
  });
}

class ChatService {
  static const String _tag = 'ChatService';
  static const String debugStructuredSuccessMarker =
      '#debug-structured-success';
  final BaseLLM _llm;
  final ResponseParserService _responseParserService;
  final ToolCallService? _toolCallService;

  ChatService({
    required BaseLLM llm,
    ResponseParserService? responseParserService,
    ToolCallService? toolCallService,
  })  : _llm = llm,
        _responseParserService =
            responseParserService ?? ResponseParserService(),
        _toolCallService = toolCallService;

  // 暴露LLM实例供外部使用
  BaseLLM get llm => _llm;

  Stream<String> streamFinalAnswer({
    required List<ChatMessage> messages,
    required ChatConfig config,
  }) async* {
    final responseBuffer = StringBuffer();
    await for (final content in _llm.chatStream(messages, config)) {
      try {
        final decoded = jsonDecode(content);
        if (decoded is Map<String, dynamic> && decoded['type'] == 'content') {
          final chunk = decoded['content'];
          if (chunk is String && chunk.isNotEmpty) {
            responseBuffer.write(chunk);
            yield chunk;
          }
        }
      } catch (_) {
        if (content.isNotEmpty) {
          responseBuffer.write(content);
          yield content;
        }
      }
    }
    final finalResponse = responseBuffer.toString().trim();
    if (finalResponse.isNotEmpty) {
      Logger.i(_tag, '最终响应: $finalResponse');
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
}
