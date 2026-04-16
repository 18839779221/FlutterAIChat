import 'dart:async';
import 'dart:convert';

import 'package:ai_chat/services/chat_service.dart';
import 'package:http/http.dart' as http;

import '../../repositories/app_settings_repository.dart';
import '../../utils/logger.dart';
import '../agent/model_turn_decision.dart';
import '../agent/planner_tool_option.dart';
import '../chat_message.dart';
import '../chat_turn.dart';
import 'api_protocol_resolver.dart';
import 'api_stream_parser.dart';
import 'base_llm.dart';
import 'llm_config.dart';
import 'tool_loop/openai_chat_completions_tool_loop_adapter.dart';
import 'tool_loop/openai_responses_tool_loop_adapter.dart';

class ConfigurableHttpLLM implements BaseLLM {
  static const String _tag = 'ConfigurableHttpLLM';
  static const Duration _defaultRequestTimeout = Duration(seconds: 60);
  static const Duration _defaultPlannerRequestTimeout = Duration(seconds: 25);

  final AppSettingsRepository _settingsRepository;
  final ApiProtocolResolver _protocolResolver;
  final ApiStreamParser _streamParser;
  final http.Client _httpClient;
  final Duration _requestTimeout;
  final Duration _plannerRequestTimeout;
  final OpenAIChatCompletionsToolLoopAdapter _chatCompletionsToolLoopAdapter;
  final OpenAIResponsesToolLoopAdapter _responsesToolLoopAdapter;

  ConfigurableHttpLLM({
    required AppSettingsRepository settingsRepository,
    ApiProtocolResolver? protocolResolver,
    ApiStreamParser? streamParser,
    http.Client? httpClient,
    Duration? requestTimeout,
    Duration? plannerRequestTimeout,
    OpenAIChatCompletionsToolLoopAdapter? chatCompletionsToolLoopAdapter,
    OpenAIResponsesToolLoopAdapter? responsesToolLoopAdapter,
  })  : _settingsRepository = settingsRepository,
        _protocolResolver = protocolResolver ?? const ApiProtocolResolver(),
        _streamParser = streamParser ?? const ApiStreamParser(),
        _httpClient = httpClient ?? http.Client(),
        _requestTimeout = requestTimeout ?? _defaultRequestTimeout,
        _plannerRequestTimeout =
            plannerRequestTimeout ?? _defaultPlannerRequestTimeout,
        _chatCompletionsToolLoopAdapter = chatCompletionsToolLoopAdapter ??
            const OpenAIChatCompletionsToolLoopAdapter(),
        _responsesToolLoopAdapter =
            responsesToolLoopAdapter ?? const OpenAIResponsesToolLoopAdapter();

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
  Stream<String> chatStream(
      List<ChatMessage> messages, ChatConfig config) async* {
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
            : _buildChatCompletionsPayload(messages, config, modelName,
                stream: true),
      );

      Logger.i(_tag, '请求体: ${request.body}');

      final response = await _httpClient.send(request).timeout(_requestTimeout);
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
      final response = await _httpClient
          .post(
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
          )
          .timeout(_requestTimeout);
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
      return (await _sendTextRequest(
        runtimeConfig,
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
        messages: promptMessages,
      ))
          .trim();
    } catch (e, stackTrace) {
      Logger.e(_tag, '结构化整理失败', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      throw Exception('结构化整理失败: $e');
    }
  }

  @override
  Future<ModelTurnDecision?> planTurnDecision({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
    ChatTurnProviderStyle? providerStyle,
    Map<String, dynamic>? providerState,
    List<Map<String, dynamic>> providerContinuationItems = const [],
  }) async {
    try {
      final runtimeConfig = await _settingsRepository.getLlmConfig();
      _validateRuntimeConfig(runtimeConfig);
      final apiStyle = _protocolResolver.resolveStyle(runtimeConfig.apiUrl);
      final modelName = _resolveModelName(runtimeConfig, config);
      final previousResponseId = _resolvePreviousResponseId(
        apiStyle: apiStyle,
        providerStyle: providerStyle,
        providerState: providerState,
      );
      final payload = apiStyle == ApiStyle.responses
          ? _buildPlannerResponsesPayload(
              messages,
              config,
              modelName,
              availableTools: availableTools,
              parallelToolCalls: true,
              previousResponseId: previousResponseId,
              continuationItems: providerContinuationItems,
            )
          : _buildPlannerChatCompletionsPayload(
              messages,
              config,
              modelName,
              availableTools: availableTools,
              parallelToolCalls: true,
            );
      Logger.i(_tag, 'native planner 请求体: ${jsonEncode(payload)}');
      final response = await _httpClient
          .post(
            _protocolResolver.buildRequestUri(runtimeConfig.apiUrl, apiStyle),
            headers: _buildHeaders(runtimeConfig),
            body: jsonEncode(payload),
          )
          .timeout(_plannerRequestTimeout);

      if (response.statusCode != 200) {
        Logger.w(
          _tag,
          'native planner unsupported status=${response.statusCode} reason=${response.reasonPhrase ?? '-'} body=${_previewBody(response.body)}',
        );
        return null;
      }

      final responseText = utf8.decode(response.bodyBytes);
      if (responseText.trim().isEmpty) {
        Logger.w(
          _tag,
          'native planner returned empty body',
        );
        return null;
      }

      final decoded = jsonDecode(responseText);
      if (decoded is! Map<String, dynamic>) {
        Logger.w(
          _tag,
          'native planner returned non-object payload: ${_previewBody(responseText)}',
        );
        return null;
      }

      final decision = apiStyle == ApiStyle.responses
          ? _responsesToolLoopAdapter.parseDecision(decoded)
          : _chatCompletionsToolLoopAdapter.parseDecision(decoded);
      if (decision == null) {
        Logger.w(
          _tag,
          'native planner parsed null decision. response=${_previewBody(responseText)} summary=${_summarizePlannerPayload(decoded)}',
        );
        return null;
      }
      if (decision.toolCalls.length > 1) {
        Logger.i(
          _tag,
          'native planner multi-tool raw response: ${_previewBody(responseText)}',
        );
        Logger.i(
          _tag,
          'native planner multi-tool parsed calls: ${decision.toolCalls.map((call) => '${call.toolName}:${jsonEncode(call.arguments)}').join(' | ')}',
        );
      }
      return decision.copyWith(
        providerStyle: _toProviderStyle(apiStyle),
        modelName: modelName,
      );
    } catch (e, stackTrace) {
      Logger.w(
        _tag,
        'native planner 请求失败: ${_previewBody(e.toString())}',
      );
      Logger.e(_tag, 'native planner stack trace', stackTrace);
      return null;
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

  ChatTurnProviderStyle _toProviderStyle(ApiStyle apiStyle) {
    switch (apiStyle) {
      case ApiStyle.responses:
        return ChatTurnProviderStyle.openaiResponses;
      case ApiStyle.chatCompletions:
        return ChatTurnProviderStyle.openaiChatCompletions;
    }
  }

  String? _resolvePreviousResponseId({
    required ApiStyle apiStyle,
    ChatTurnProviderStyle? providerStyle,
    Map<String, dynamic>? providerState,
  }) {
    if (apiStyle != ApiStyle.responses ||
        providerStyle != ChatTurnProviderStyle.openaiResponses ||
        providerState == null) {
      return null;
    }
    final responseId = providerState['response_id'];
    if (responseId is! String) {
      return null;
    }
    final trimmed = responseId.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  Map<String, dynamic> _buildChatCompletionsPayload(
    List<ChatMessage> messages,
    ChatConfig config,
    String modelName, {
    required bool stream,
  }) {
    final normalizedMessages =
        messages.where((msg) => msg.text.trim().isNotEmpty).toList();
    return {
      'model': modelName,
      'messages': normalizedMessages
          .map((msg) => {
                'role': msg.role.toString().split('.').last,
                'content': msg.text,
              })
          .toList(),
      'stream': stream,
    };
  }

  Map<String, dynamic> _buildResponsesPayload(
    List<ChatMessage> messages,
    ChatConfig config,
    String modelName, {
    required bool stream,
  }) {
    final normalizedMessages =
        messages.where((msg) => msg.text.trim().isNotEmpty).toList();
    return {
      'model': modelName,
      'input': normalizedMessages
          .map((msg) => {
                'role': msg.role.toString().split('.').last,
                'content': [
                  {
                    'type': msg.role == MessageRole.assistant
                        ? 'output_text'
                        : 'input_text',
                    'text': msg.text,
                  },
                ],
              })
          .toList(),
      'stream': stream,
      'store': false,
      if (config.useReasoning) 'reasoning': {'effort': 'medium'},
    };
  }

  Map<String, dynamic> _buildPlannerChatCompletionsPayload(
    List<ChatMessage> messages,
    ChatConfig config,
    String modelName, {
    required List<PlannerToolOption> availableTools,
    required bool parallelToolCalls,
  }) {
    final payload = _buildChatCompletionsPayload(
      messages,
      config,
      modelName,
      stream: false,
    );
    final tools = availableTools
        .map(
          (tool) => {
            'type': 'function',
            'function': {
              'name': tool.name,
              'description': tool.description,
              'parameters': tool.inputSchema,
            },
          },
        )
        .toList(growable: false);
    if (tools.isNotEmpty) {
      payload['tools'] = tools;
      payload['tool_choice'] = 'auto';
      payload['parallel_tool_calls'] = parallelToolCalls;
    }
    return payload;
  }

  Map<String, dynamic> _buildPlannerResponsesPayload(
    List<ChatMessage> messages,
    ChatConfig config,
    String modelName, {
    required List<PlannerToolOption> availableTools,
    required bool parallelToolCalls,
    String? previousResponseId,
    List<Map<String, dynamic>> continuationItems = const [],
  }) {
    final payload = _buildResponsesPayload(
      messages,
      config,
      modelName,
      stream: false,
    );
    final tools = availableTools
        .map(
          (tool) => {
            'type': 'function',
            'name': tool.name,
            'description': tool.description,
            'parameters': tool.inputSchema,
          },
        )
        .toList(growable: false);
    if (tools.isNotEmpty) {
      payload['tools'] = tools;
      payload['tool_choice'] = 'auto';
      payload['parallel_tool_calls'] = parallelToolCalls;
    }
    if (previousResponseId != null && previousResponseId.isNotEmpty) {
      payload['previous_response_id'] = previousResponseId;
    }
    if (continuationItems.isNotEmpty) {
      final input = _shouldUseResponsesContinuationInputOnly(
        previousResponseId: previousResponseId,
        continuationItems: continuationItems,
      )
          ? <dynamic>[]
          : List<dynamic>.from(
              payload['input'] as List<dynamic>? ?? const <dynamic>[],
            );
      for (final item in continuationItems) {
        input.add(Map<String, dynamic>.from(item));
      }
      payload['input'] = input;
    }
    return payload;
  }

  bool _shouldUseResponsesContinuationInputOnly({
    required String? previousResponseId,
    required List<Map<String, dynamic>> continuationItems,
  }) {
    return previousResponseId != null &&
        previousResponseId.isNotEmpty &&
        continuationItems.isNotEmpty;
  }

  Future<String> _sendTextRequest(
    LLMConfig runtimeConfig, {
    required ChatConfig config,
    required List<ChatMessage> messages,
    Duration? timeout,
  }) async {
    final apiStyle = _protocolResolver.resolveStyle(runtimeConfig.apiUrl);
    final modelName = _resolveModelName(runtimeConfig, config);
    final effectiveTimeout = timeout ?? _requestTimeout;

    if (apiStyle == ApiStyle.responses) {
      final request = http.Request(
        'POST',
        _protocolResolver.buildRequestUri(runtimeConfig.apiUrl, apiStyle),
      );
      request.headers.addAll(_buildHeaders(runtimeConfig));
      request.body = jsonEncode(
        _buildResponsesPayload(messages, config, modelName, stream: true),
      );

      final response =
          await _httpClient.send(request).timeout(effectiveTimeout);
      if (response.statusCode != 200) {
        throw Exception(
            '请求失败: ${response.statusCode} ${response.reasonPhrase}');
      }

      final buffer = StringBuffer();
      await for (final chunk in _streamParser
          .parse(response, apiStyle)
          .timeout(effectiveTimeout)) {
        final data = jsonDecode(chunk);
        if (data['type'] == 'content') {
          buffer.write(data['content']);
        }
      }
      return buffer.toString();
    }

    final response = await _httpClient
        .post(
          _protocolResolver.buildRequestUri(runtimeConfig.apiUrl, apiStyle),
          headers: _buildHeaders(runtimeConfig),
          body: jsonEncode(
            _buildChatCompletionsPayload(messages, config, modelName,
                stream: false),
          ),
        )
        .timeout(effectiveTimeout);

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

  String _previewBody(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      return '<empty>';
    }
    if (normalized.length <= 240) {
      return normalized;
    }
    return '${normalized.substring(0, 240)}...';
  }

  String _summarizePlannerPayload(Map<String, dynamic> payload) {
    final output = payload['output'];
    if (output is List) {
      final itemTypes = output
          .whereType<Map>()
          .map((item) => item['type']?.toString() ?? '<unknown>')
          .join(',');
      return 'keys=${payload.keys.join(',')} outputTypes=[$itemTypes]';
    }

    final choices = payload['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map && first['message'] is Map) {
        final message = (first['message'] as Map).cast<String, dynamic>();
        final hasToolCalls = message['tool_calls'] is List;
        final contentType = message['content']?.runtimeType.toString() ?? 'null';
        return 'keys=${payload.keys.join(',')} hasToolCalls=$hasToolCalls contentType=$contentType';
      }
      return 'keys=${payload.keys.join(',')} choices=${choices.length}';
    }

    return 'keys=${payload.keys.join(',')}';
  }
}
