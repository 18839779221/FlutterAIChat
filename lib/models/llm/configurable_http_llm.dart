import 'dart:async';
import 'dart:convert';

import 'package:ai_chat/services/chat_service.dart';
import 'package:http/http.dart' as http;

import '../../repositories/app_settings_repository.dart';
import '../../utils/logger.dart';
import '../chat_message.dart';
import 'api_protocol_resolver.dart';
import 'api_stream_parser.dart';
import 'base_llm.dart';
import 'llm_config.dart';

class ConfigurableHttpLLM implements BaseLLM {
  static const String _tag = 'ConfigurableHttpLLM';

  final AppSettingsRepository _settingsRepository;
  final ApiProtocolResolver _protocolResolver;
  final ApiStreamParser _streamParser;

  ConfigurableHttpLLM({
    required AppSettingsRepository settingsRepository,
    ApiProtocolResolver? protocolResolver,
    ApiStreamParser? streamParser,
  }) : _settingsRepository = settingsRepository,
       _protocolResolver = protocolResolver ?? const ApiProtocolResolver(),
       _streamParser = streamParser ?? const ApiStreamParser();

  @override
  String getModelName(ChatConfig config) {
    return config.useReasoning ? 'deepseek-reasoner' : 'deepseek-chat';
  }

  @override
  Map<String, dynamic> get config => {
    'apiKey': '<runtime>',
    'apiUrl': '<runtime>',
    'model': '<runtime>',
  };

  @override
  Stream<String> chatStream(List<ChatMessage> messages, ChatConfig config) async* {
    try {
      Logger.i(_tag, '准备发送消息，消息数量: ${messages.length}');
      final runtimeConfig = await _settingsRepository.getLlmConfig();
      _validateRuntimeConfig(runtimeConfig);
      _logMessages(messages);

      final apiStyle = _protocolResolver.resolveStyle(runtimeConfig.apiUrl);
      final modelName = _resolveModelName(runtimeConfig, config);
      final request = http.Request(
        'POST',
        _protocolResolver.buildRequestUri(runtimeConfig.apiUrl, apiStyle),
      );
      request.headers.addAll(_buildHeaders(runtimeConfig));
      request.body = jsonEncode(
        apiStyle == ApiStyle.responses
            ? _buildResponsesPayload(messages, config, modelName, stream: true)
            : _buildChatCompletionsPayload(messages, config, modelName, stream: true),
      );

      Logger.i(_tag, '请求体: ${request.body}');

      final response = await http.Client().send(request);
      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        throw Exception(
          'API请求失败: ${response.statusCode} ${response.reasonPhrase} ${errorBody.trim()}',
        );
      }

      Logger.i(_tag, '开始接收流式响应');
      yield* _streamParser.parse(response, apiStyle);
    } catch (e, stackTrace) {
      Logger.e(_tag, '发送消息失败', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      throw Exception('发送消息失败: $e');
    }
  }

  @override
  Future<bool> validateApiKey(ChatConfig config) async {
    try {
      final runtimeConfig = await _settingsRepository.getLlmConfig();
      _validateRuntimeConfig(runtimeConfig);
      final apiStyle = _protocolResolver.resolveStyle(runtimeConfig.apiUrl);
      final response = await http.post(
        _protocolResolver.buildRequestUri(runtimeConfig.apiUrl, apiStyle),
        headers: _buildHeaders(runtimeConfig),
        body: jsonEncode(
          apiStyle == ApiStyle.responses
              ? _buildResponsesPayload(
                  [ChatMessage(text: 'test', role: MessageRole.user)],
                  config,
                  _resolveModelName(runtimeConfig, config),
                  stream: false,
                )
              : _buildChatCompletionsPayload(
                  [ChatMessage(text: 'test', role: MessageRole.user)],
                  config,
                  _resolveModelName(runtimeConfig, config),
                  stream: false,
                ),
        ),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async {
    try {
      Logger.i(_tag, '开始生成对话摘要，消息数量: ${messages.length}');
      final runtimeConfig = await _settingsRepository.getLlmConfig();
      _validateRuntimeConfig(runtimeConfig);
      final summaryPrompt = [
        ChatMessage(
          text: '请用简短的一句话（10-20字）总结以下对话的主题，只返回总结内容，不要有任何其他说明：',
          role: MessageRole.system,
        ),
        ...messages,
      ];

      final summary = await _sendTextRequest(
        runtimeConfig,
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        messages: summaryPrompt,
      );
      Logger.i(_tag, '生成摘要成功: $summary');
      return summary.trim();
    } catch (e, stackTrace) {
      Logger.e(_tag, '生成摘要失败', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      throw Exception('生成摘要失败: $e');
    }
  }

  @override
  Future<String> structureSummaryCard(String sourceText) async {
    try {
      final runtimeConfig = await _settingsRepository.getLlmConfig();
      _validateRuntimeConfig(runtimeConfig);
      final promptMessages = [
        ChatMessage(
          text:
              '请将用户提供的文本整理为固定 JSON，对象中必须只包含 title、summary、keyPoints、actionItems、risks 这 5 个字段；其中 title 和 summary 是字符串，其余 3 个字段是字符串数组。不要输出 Markdown，不要输出解释，不要输出代码块。',
          role: MessageRole.system,
        ),
        ChatMessage(text: sourceText, role: MessageRole.user),
      ];
      return (
        await _sendTextRequest(
          runtimeConfig,
          config: ChatConfig(useReasoning: false, systemPrompt: ''),
          messages: promptMessages,
        )
      ).trim();
    } catch (e, stackTrace) {
      Logger.e(_tag, '结构化整理失败', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      throw Exception('结构化整理失败: $e');
    }
  }

  void _validateRuntimeConfig(LLMConfig config) {
    if (config.apiKey.trim().isEmpty) {
      throw Exception('请先在设置页配置 API Key');
    }

    if (config.model.trim().isEmpty) {
      throw Exception('请先在设置页配置 Model');
    }

    final parsed = Uri.tryParse(config.apiUrl.trim());
    if (parsed == null || !parsed.hasScheme || !parsed.hasAuthority) {
      throw Exception('请先在设置页配置有效的 Base URL');
    }
  }

  Map<String, String> _buildHeaders(LLMConfig config) {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${config.apiKey}',
    };
  }

  String _resolveModelName(LLMConfig runtimeConfig, ChatConfig config) {
    final configuredModel = runtimeConfig.model.trim();
    if (configuredModel.isEmpty) {
      return getModelName(config);
    }

    if (config.useReasoning && configuredModel == 'deepseek-chat') {
      return 'deepseek-reasoner';
    }

    return configuredModel;
  }

  Map<String, dynamic> _buildChatCompletionsPayload(
    List<ChatMessage> messages,
    ChatConfig config,
    String modelName, {
    required bool stream,
  }) {
    final normalizedMessages = messages.where((msg) => msg.text.trim().isNotEmpty).toList();
    return {
      'model': modelName,
      'messages': normalizedMessages.map((msg) => {
        'role': msg.role.toString().split('.').last,
        'content': msg.text,
      }).toList(),
      'stream': stream,
    };
  }

  Map<String, dynamic> _buildResponsesPayload(
    List<ChatMessage> messages,
    ChatConfig config,
    String modelName, {
    required bool stream,
  }) {
    final normalizedMessages = messages.where((msg) => msg.text.trim().isNotEmpty).toList();
    return {
      'model': modelName,
      'input': normalizedMessages.map((msg) => {
        'role': msg.role.toString().split('.').last,
        'content': [
          {
            'type': msg.role == MessageRole.assistant ? 'output_text' : 'input_text',
            'text': msg.text,
          },
        ],
      }).toList(),
      'stream': stream,
      'store': false,
      if (config.useReasoning) 'reasoning': {'effort': 'medium'},
    };
  }

  Future<String> _sendTextRequest(
    LLMConfig runtimeConfig, {
    required ChatConfig config,
    required List<ChatMessage> messages,
  }) async {
    final apiStyle = _protocolResolver.resolveStyle(runtimeConfig.apiUrl);
    final modelName = _resolveModelName(runtimeConfig, config);

    if (apiStyle == ApiStyle.responses) {
      final request = http.Request(
        'POST',
        _protocolResolver.buildRequestUri(runtimeConfig.apiUrl, apiStyle),
      );
      request.headers.addAll(_buildHeaders(runtimeConfig));
      request.body = jsonEncode(
        _buildResponsesPayload(messages, config, modelName, stream: true),
      );

      final response = await http.Client().send(request);
      if (response.statusCode != 200) {
        throw Exception('请求失败: ${response.statusCode} ${response.reasonPhrase}');
      }

      final buffer = StringBuffer();
      await for (final chunk in _streamParser.parse(response, apiStyle)) {
        final data = jsonDecode(chunk);
        if (data['type'] == 'content') {
          buffer.write(data['content']);
        }
      }
      return buffer.toString();
    }

    final response = await http.post(
      _protocolResolver.buildRequestUri(runtimeConfig.apiUrl, apiStyle),
      headers: _buildHeaders(runtimeConfig),
      body: jsonEncode(
        _buildChatCompletionsPayload(messages, config, modelName, stream: false),
      ),
    );

    if (response.statusCode != 200) {
      throw Exception('请求失败: ${response.statusCode}');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes));
    return data['choices'][0]['message']['content'].toString();
  }

  void _logMessages(List<ChatMessage> messages) {
    for (var i = 0; i < messages.length; i++) {
      final msg = messages[i];
      Logger.i(_tag, '消息[$i] ${msg.role}: ${msg.text}');
    }
  }
}
