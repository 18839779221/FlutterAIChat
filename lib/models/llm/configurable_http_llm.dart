import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/prompt/prompt_builder_service.dart';
import 'package:ai_chat/services/prompt/prompt_locale.dart';
import 'package:ai_chat/services/prompt/prompt_stage.dart';
import 'package:http/http.dart' as http;

import '../../repositories/app_settings_repository.dart';
import '../../utils/logger.dart';
import '../agent/model_turn_decision.dart';
import '../agent/planner_tool_choice.dart';
import '../agent/planner_tool_option.dart';
import '../chat_message.dart';
import '../chat_turn.dart';
import '../../services/session_summary_service.dart';
import 'adapters/anthropic_messages_adapter.dart';
import 'adapters/api_style_adapter.dart';
import 'adapters/chat_completions_adapter.dart';
import 'adapters/responses_adapter.dart';
import 'api_protocol_resolver.dart';
import 'api_stream_parser.dart';
import 'base_llm.dart';
import 'llm_config.dart';
import 'tool_loop/anthropic_messages_tool_loop_adapter.dart';
import 'tool_loop/openai_chat_completions_tool_loop_adapter.dart';
import 'tool_loop/openai_responses_tool_loop_adapter.dart';

class ConfigurableHttpLLM implements BaseLLM {
  static const String _tag = 'ConfigurableHttpLLM';
  static const Duration _defaultRequestTimeout = Duration(seconds: 60);
  static const Duration _defaultPlannerRequestTimeout = Duration(seconds: 60);
  static const int _defaultMainFlowNetworkRetryAttempts = 5;

  static const Map<ApiStyle, ApiStyleAdapter> _defaultAdapters = {
    ApiStyle.chatCompletions: ChatCompletionsAdapter(),
    ApiStyle.responses: ResponsesAdapter(),
    ApiStyle.anthropicMessages: AnthropicMessagesAdapter(),
  };

  final AppSettingsRepository _settingsRepository;
  final ApiProtocolResolver _protocolResolver;
  final ApiStreamParser _streamParser;
  final http.Client _httpClient;
  final Duration _requestTimeout;
  final Duration _plannerRequestTimeout;
  final int _mainFlowNetworkRetryAttempts;
  final Map<ApiStyle, ApiStyleAdapter> _adapters;
  final OpenAIChatCompletionsToolLoopAdapter _chatCompletionsToolLoopAdapter;
  final OpenAIResponsesToolLoopAdapter _responsesToolLoopAdapter;
  final AnthropicMessagesToolLoopAdapter _anthropicMessagesToolLoopAdapter;
  final PromptBuilderService _promptBuilder;

  ConfigurableHttpLLM({
    required AppSettingsRepository settingsRepository,
    ApiProtocolResolver? protocolResolver,
    ApiStreamParser? streamParser,
    http.Client? httpClient,
    Duration? requestTimeout,
    Duration? plannerRequestTimeout,
    int mainFlowNetworkRetryAttempts =
        _defaultMainFlowNetworkRetryAttempts,
    Map<ApiStyle, ApiStyleAdapter>? adapters,
    OpenAIChatCompletionsToolLoopAdapter? chatCompletionsToolLoopAdapter,
    OpenAIResponsesToolLoopAdapter? responsesToolLoopAdapter,
    AnthropicMessagesToolLoopAdapter? anthropicMessagesToolLoopAdapter,
    PromptBuilderService? promptBuilder,
  })  : _settingsRepository = settingsRepository,
        _protocolResolver = protocolResolver ?? const ApiProtocolResolver(),
        _streamParser = streamParser ?? const ApiStreamParser(),
        _httpClient = httpClient ?? http.Client(),
        _requestTimeout = requestTimeout ?? _defaultRequestTimeout,
        _plannerRequestTimeout =
            plannerRequestTimeout ?? _defaultPlannerRequestTimeout,
        _mainFlowNetworkRetryAttempts = mainFlowNetworkRetryAttempts,
        _adapters = adapters ?? _defaultAdapters,
        _chatCompletionsToolLoopAdapter = chatCompletionsToolLoopAdapter ??
            const OpenAIChatCompletionsToolLoopAdapter(),
        _responsesToolLoopAdapter =
            responsesToolLoopAdapter ?? const OpenAIResponsesToolLoopAdapter(),
        _anthropicMessagesToolLoopAdapter = anthropicMessagesToolLoopAdapter ??
            const AnthropicMessagesToolLoopAdapter(),
        _promptBuilder = promptBuilder ?? const PromptBuilderService() {
    assert(mainFlowNetworkRetryAttempts >= 1);
  }

  ApiStyleAdapter _adapterFor(ApiStyle apiStyle) {
    final adapter = _adapters[apiStyle];
    if (adapter == null) {
      throw StateError('No ApiStyleAdapter registered for $apiStyle');
    }
    return adapter;
  }

  @override
  String getModelName(ChatConfig config) {
    return 'deepseek-chat';
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
      Logger.d(
        _tag,
        '发送摘要 roles=${messages.map((message) => message.role.name).join(",")} totalChars=${messages.fold<int>(0, (sum, message) => sum + message.text.length)}',
      );

      final apiStyle = _protocolResolver.resolveStyle(runtimeConfig.apiUrl);
      final adapter = _adapterFor(apiStyle);
      final modelName = _resolveModelName(runtimeConfig, config);
      final request = http.Request(
        'POST',
        _protocolResolver.buildRequestUri(runtimeConfig.apiUrl, apiStyle),
      );
      request.headers.addAll(adapter.buildHeaders(runtimeConfig));
      request.body = jsonEncode(
        adapter.buildChatPayload(
          messages: messages,
          config: config,
          modelName: modelName,
          stream: true,
        ),
      );

      Logger.i(_tag, '请求体: ${request.body}');

      final response = await _performRetriableMainFlowRequest(
        label: 'chat_stream',
        operation: () => _httpClient.send(request).timeout(_requestTimeout),
      );
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
      final adapter = _adapterFor(apiStyle);
      final response = await _httpClient
          .post(
            _protocolResolver.buildRequestUri(runtimeConfig.apiUrl, apiStyle),
            headers: adapter.buildHeaders(runtimeConfig),
            body: jsonEncode(
              adapter.buildChatPayload(
                messages: [ChatMessage(text: 'test', role: MessageRole.user)],
                config: config,
                modelName: _resolveModelName(runtimeConfig, config),
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
      final summaryPrompt = _normalizeSummaryMessages(messages);

      final summary = await _sendTextRequest(
        runtimeConfig,
        config: ChatConfig(systemPrompt: ''),
        messages: summaryPrompt,
      );
      final trimmedSummary = summary.trim();
      if (trimmedSummary.isEmpty) {
        Logger.w(_tag, '生成摘要返回空结果');
        return '';
      }
      Logger.i(_tag, '生成摘要成功: $trimmedSummary');
      return trimmedSummary;
    } catch (e, stackTrace) {
      Logger.e(_tag, '生成摘要失败', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      throw Exception('生成摘要失败: $e');
    }
  }

  List<ChatMessage> _normalizeSummaryMessages(List<ChatMessage> messages) {
    final normalized = messages
        .map(
          (message) => ChatMessage(
            text: message.text,
            role: message.role,
            status: message.status,
          ),
        )
        .toList(growable: true);
    final firstSystemIndex =
        normalized.indexWhere((message) => message.role == MessageRole.system);
    final stagePrompt = _promptBuilder.buildSystemPrompt(
      stage: PromptStage.summary,
      locale: PromptLocale.english,
    );

    if (firstSystemIndex == -1) {
      normalized.insert(
        0,
        ChatMessage(
          text: stagePrompt,
          role: MessageRole.system,
        ),
      );
      return normalized;
    }

    if (normalized[firstSystemIndex].text.trim() ==
        SessionSummaryService.summaryInstructionPrompt.trim()) {
      normalized[firstSystemIndex] = ChatMessage(
        text: stagePrompt,
        role: MessageRole.system,
        status: normalized[firstSystemIndex].status,
      );
    }
    return normalized;
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
        config: ChatConfig(systemPrompt: ''),
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
  Future<String> processWebpageContent({
    required String webpageContent,
    required String prompt,
  }) async {
    try {
      final runtimeConfig = await _settingsRepository.getLlmConfig();
      _validateRuntimeConfig(runtimeConfig);
      final promptMessages = [
        ChatMessage(
          text:
              'Web page content:\n---\n$webpageContent\n---\n\nPrompt:\n$prompt\n\n'
              'Use only the webpage content above to answer the prompt.\n\n'
              'Requirements:\n'
              '- Follow the prompt closely and produce the result in the format it asks for when possible.\n'
              '- Do not rely on outside knowledge.\n'
              '- If the page does not contain enough relevant information, say so clearly.\n'
              '- Prefer concise paraphrase over copying long passages from the page.\n'
              '- Keep quotes minimal and only use them when exact wording matters.\n'
              '- Ignore unrelated navigation, boilerplate, repeated page chrome, and marketing copy.\n'
              '- Return processed page content, not meta commentary about the tool.',
          role: MessageRole.user,
        ),
      ];
      return (await _sendTextRequest(
        runtimeConfig,
        config: ChatConfig(systemPrompt: ''),
        messages: promptMessages,
      ))
          .trim();
    } catch (e, stackTrace) {
      Logger.e(_tag, '网页内容处理失败', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      throw Exception('网页内容处理失败: $e');
    }
  }

  @override
  Future<String> planNextAction({
    required List<ChatMessage> messages,
    required ChatConfig config,
  }) async {
    try {
      final runtimeConfig = await _settingsRepository.getLlmConfig();
      _validateRuntimeConfig(runtimeConfig);
      return (await _sendTextRequest(
        runtimeConfig,
        config: config,
        messages: messages,
        timeout: _plannerRequestTimeout,
        allowMainFlowRetry: true,
      ))
          .trim();
    } catch (e, stackTrace) {
      Logger.e(_tag, 'agent planner 请求失败', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      throw Exception('agent planner 请求失败: $e');
    }
  }

  @override
  Future<PlannerToolChoice?> planNextToolChoice({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
  }) async {
    try {
      final runtimeConfig = await _settingsRepository.getLlmConfig();
      _validateRuntimeConfig(runtimeConfig);
      final apiStyle = _protocolResolver.resolveStyle(runtimeConfig.apiUrl);
      final adapter = _adapterFor(apiStyle);
      final modelName = _resolveModelName(runtimeConfig, config);
      final payload = adapter.buildPlannerPayload(
        messages: messages,
        config: config,
        modelName: modelName,
        availableTools: availableTools,
        parallelToolCalls: false,
      );
      Logger.i(_tag, 'structured planner 请求体: ${jsonEncode(payload)}');
      final response = await _performRetriableMainFlowRequest(
        label: 'structured_planner',
        operation: () => _httpClient
            .post(
              _protocolResolver.buildRequestUri(runtimeConfig.apiUrl, apiStyle),
              headers: adapter.buildHeaders(runtimeConfig),
              body: jsonEncode(payload),
            )
            .timeout(_plannerRequestTimeout),
      );

      if (response.statusCode != 200) {
        Logger.w(
          _tag,
          'structured planner unsupported status=${response.statusCode} reason=${response.reasonPhrase ?? '-'} body=${_previewBody(response.body)}',
        );
        return null;
      }

      final responseText = utf8.decode(response.bodyBytes);
      if (responseText.trim().isEmpty) {
        Logger.w(
          _tag,
          'structured planner returned empty body, fallback to legacy planner',
        );
        return null;
      }

      final decoded = jsonDecode(responseText);
      if (decoded is! Map<String, dynamic>) {
        Logger.w(
          _tag,
          'structured planner returned non-object payload: ${_previewBody(responseText)}',
        );
        return null;
      }

      final choice = adapter.parsePlannerChoice(decoded);
      if (choice == null) {
        Logger.w(
          _tag,
          'structured planner parsed null choice. response=${_previewBody(responseText)} summary=${_summarizePlannerPayload(decoded)}',
        );
      }
      return choice;
    } catch (e, stackTrace) {
      Logger.w(
        _tag,
        'structured planner 请求失败，回退到 legacy planner: ${_previewBody(e.toString())}',
      );
      Logger.e(_tag, 'structured planner stack trace', stackTrace);
      return null;
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
      final adapter = _adapterFor(apiStyle);
      final modelName = _resolveModelName(runtimeConfig, config);
      final previousResponseId = _resolvePreviousResponseId(
        apiStyle: apiStyle,
        providerStyle: providerStyle,
        providerState: providerState,
      );
      final payload = adapter.buildPlannerPayload(
        messages: messages,
        config: config,
        modelName: modelName,
        availableTools: availableTools,
        parallelToolCalls: true,
        previousResponseId: previousResponseId,
        continuationItems: providerContinuationItems,
        providerState: providerState,
      );
      Logger.i(_tag, 'native planner 请求体: ${jsonEncode(payload)}');
      final response = await _performRetriableMainFlowRequest(
        label: 'native_planner',
        operation: () => _httpClient
            .post(
              _protocolResolver.buildRequestUri(runtimeConfig.apiUrl, apiStyle),
              headers: adapter.buildHeaders(runtimeConfig),
              body: jsonEncode(payload),
            )
            .timeout(_plannerRequestTimeout),
      );

      if (response.statusCode != 200) {
        final detail =
            'HTTP ${response.statusCode} ${response.reasonPhrase ?? '-'} ${_previewBody(response.body)}';
        Logger.w(
          _tag,
          'native planner unsupported status=${response.statusCode} reason=${response.reasonPhrase ?? '-'} body=${_previewBody(response.body)}',
        );
        throw Exception(detail);
      }
      final responseText = utf8.decode(response.bodyBytes);
      Logger.i(_tag, 'native planner 响应体: $responseText');
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

      final decision = _parseTurnDecisionForStyle(apiStyle, decoded);
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
      rethrow;
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

  String _resolveModelName(LLMConfig runtimeConfig, ChatConfig config) {
    final configuredModel = runtimeConfig.model.trim();
    if (configuredModel.isEmpty) {
      return getModelName(config);
    }

    return configuredModel;
  }

  ChatTurnProviderStyle _toProviderStyle(ApiStyle apiStyle) {
    switch (apiStyle) {
      case ApiStyle.responses:
        return ChatTurnProviderStyle.openaiResponses;
      case ApiStyle.chatCompletions:
        return ChatTurnProviderStyle.openaiChatCompletions;
      case ApiStyle.anthropicMessages:
        return ChatTurnProviderStyle.anthropicMessages;
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

  ModelTurnDecision? _parseTurnDecisionForStyle(
    ApiStyle apiStyle,
    Map<String, dynamic> payload,
  ) {
    switch (apiStyle) {
      case ApiStyle.responses:
        return _responsesToolLoopAdapter.parseDecision(payload);
      case ApiStyle.chatCompletions:
        return _chatCompletionsToolLoopAdapter.parseDecision(payload);
      case ApiStyle.anthropicMessages:
        return _anthropicMessagesToolLoopAdapter.parseDecision(payload);
    }
  }

  Future<String> _sendTextRequest(
    LLMConfig runtimeConfig, {
    required ChatConfig config,
    required List<ChatMessage> messages,
    Duration? timeout,
    bool allowMainFlowRetry = false,
  }) async {
    final apiStyle = _protocolResolver.resolveStyle(runtimeConfig.apiUrl);
    final adapter = _adapterFor(apiStyle);
    final modelName = _resolveModelName(runtimeConfig, config);
    final effectiveTimeout = timeout ?? _requestTimeout;

    if (apiStyle == ApiStyle.responses ||
        apiStyle == ApiStyle.anthropicMessages) {
      final request = http.Request(
        'POST',
        _protocolResolver.buildRequestUri(runtimeConfig.apiUrl, apiStyle),
      );
      request.headers.addAll(adapter.buildHeaders(runtimeConfig));
      request.body = jsonEncode(
        adapter.buildChatPayload(
          messages: messages,
          config: config,
          modelName: modelName,
          stream: true,
        ),
      );

      final response = allowMainFlowRetry
          ? await _performRetriableMainFlowRequest(
              label: 'text_request_stream',
              operation: () => _httpClient.send(request).timeout(effectiveTimeout),
            )
          : await _httpClient.send(request).timeout(effectiveTimeout);
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

    final response = allowMainFlowRetry
        ? await _performRetriableMainFlowRequest(
            label: 'text_request',
            operation: () => _httpClient
                .post(
                  _protocolResolver.buildRequestUri(runtimeConfig.apiUrl, apiStyle),
                  headers: adapter.buildHeaders(runtimeConfig),
                  body: jsonEncode(
                    adapter.buildChatPayload(
                      messages: messages,
                      config: config,
                      modelName: modelName,
                      stream: false,
                    ),
                  ),
                )
                .timeout(effectiveTimeout),
          )
        : await _httpClient
            .post(
              _protocolResolver.buildRequestUri(runtimeConfig.apiUrl, apiStyle),
              headers: adapter.buildHeaders(runtimeConfig),
              body: jsonEncode(
                adapter.buildChatPayload(
                  messages: messages,
                  config: config,
                  modelName: modelName,
                  stream: false,
                ),
              ),
            )
            .timeout(effectiveTimeout);

    if (response.statusCode != 200) {
      throw Exception('请求失败: ${response.statusCode}');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (data is! Map<String, dynamic>) {
      return '';
    }
    return adapter.extractNonStreamText(data);
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
        final contentType =
            message['content']?.runtimeType.toString() ?? 'null';
        return 'keys=${payload.keys.join(',')} hasToolCalls=$hasToolCalls contentType=$contentType';
      }
      return 'keys=${payload.keys.join(',')} choices=${choices.length}';
    }

    return 'keys=${payload.keys.join(',')}';
  }

  Future<T> _performRetriableMainFlowRequest<T>({
    required String label,
    required Future<T> Function() operation,
  }) async {
    Object? lastError;
    StackTrace? lastStackTrace;

    for (var attempt = 1; attempt <= _mainFlowNetworkRetryAttempts; attempt += 1) {
      try {
        if (attempt > 1) {
          Logger.i(
            _tag,
            'main flow request retry start label=$label attempt=$attempt/$_mainFlowNetworkRetryAttempts',
          );
        }
        return await operation();
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        final shouldRetry = attempt < _mainFlowNetworkRetryAttempts &&
            _isRetriableMainFlowNetworkError(error);
        if (!shouldRetry) {
          Error.throwWithStackTrace(error, stackTrace);
        }

        final delay = _retryDelayForAttempt(attempt);
        Logger.w(
          _tag,
          'main flow request retry scheduled label=$label attempt=$attempt/$_mainFlowNetworkRetryAttempts delayMs=${delay.inMilliseconds} reason=${_previewBody(error.toString())}',
        );
        await Future<void>.delayed(delay);
      }
    }

    if (lastError != null && lastStackTrace != null) {
      Error.throwWithStackTrace(lastError, lastStackTrace);
    }
    throw StateError('unexpected retry state for $label');
  }

  bool _isRetriableMainFlowNetworkError(Object error) {
    if (error is TimeoutException || error is SocketException) {
      return true;
    }

    if (error is http.ClientException) {
      final normalized = error.message.toLowerCase();
      return normalized.contains('socketexception') ||
          normalized.contains('connection reset') ||
          normalized.contains('timed out') ||
          normalized.contains('broken pipe') ||
          normalized.contains('failed host lookup') ||
          normalized.contains('network is unreachable');
    }

    final normalized = error.toString().toLowerCase();
    return normalized.contains('socketexception') ||
        normalized.contains('connection reset by peer') ||
        normalized.contains('connection closed before full header was received') ||
        normalized.contains('broken pipe') ||
        normalized.contains('failed host lookup') ||
        normalized.contains('network is unreachable') ||
        normalized.contains('timed out');
  }

  Duration _retryDelayForAttempt(int attempt) {
    final backoffSeconds = switch (attempt) {
      1 => 1,
      2 => 2,
      3 => 4,
      4 => 8,
      _ => 12,
    };
    return Duration(seconds: backoffSeconds);
  }
}
