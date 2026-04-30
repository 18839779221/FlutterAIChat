import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/prompt/prompt_builder_service.dart';
import 'package:ai_chat/services/prompt/prompt_locale.dart';
import 'package:ai_chat/services/prompt/prompt_stage.dart';
import 'package:http/http.dart' as http;

import '../../repositories/app_settings_repository.dart';
import '../../services/model_budget_registry.dart';
import '../../utils/logger.dart';
import '../agent/model_turn_decision.dart';
import '../agent/planner_tool_option.dart';
import '../chat_message.dart';
import '../chat_turn.dart';
import '../session/model_budget_profile.dart';
import '../../services/session_summary_service.dart';
import 'adapters/anthropic_messages_adapter.dart';
import 'adapters/api_style_adapter.dart';
import 'adapters/chat_completions_adapter.dart';
import 'adapters/responses_adapter.dart';
import 'api_protocol_resolver.dart';
import 'api_stream_parser.dart';
import 'base_llm.dart';
import 'llm_config.dart';
import 'llm_request_options.dart';
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
  final ModelBudgetRegistry _modelBudgetRegistry;

  ConfigurableHttpLLM({
    required AppSettingsRepository settingsRepository,
    ApiProtocolResolver? protocolResolver,
    ApiStreamParser? streamParser,
    http.Client? httpClient,
    Duration? requestTimeout,
    Duration? plannerRequestTimeout,
    int mainFlowNetworkRetryAttempts = _defaultMainFlowNetworkRetryAttempts,
    Map<ApiStyle, ApiStyleAdapter>? adapters,
    OpenAIChatCompletionsToolLoopAdapter? chatCompletionsToolLoopAdapter,
    OpenAIResponsesToolLoopAdapter? responsesToolLoopAdapter,
    AnthropicMessagesToolLoopAdapter? anthropicMessagesToolLoopAdapter,
    PromptBuilderService? promptBuilder,
    ModelBudgetRegistry? modelBudgetRegistry,
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
        _promptBuilder = promptBuilder ?? const PromptBuilderService(),
        _modelBudgetRegistry = modelBudgetRegistry ?? ModelBudgetRegistry() {
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
  Future<String> summarizeConversation(List<ChatMessage> messages) async {
    try {
      Logger.i(_tag, '开始生成对话摘要，消息数量: ${messages.length}');
      final runtimeConfig = await _settingsRepository.getLlmConfig();
      _validateRuntimeConfig(runtimeConfig);
      final summaryPrompt = _normalizeSummaryMessages(messages);

      final summary = await _runSideModelTextTask(
        runtimeConfig,
        config: ChatConfig(systemPrompt: ''),
        messages: summaryPrompt,
        requestLabel: 'side_summary',
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
      return (await _runSideModelTextTask(
        runtimeConfig,
        config: ChatConfig(systemPrompt: ''),
        messages: promptMessages,
        requestLabel: 'side_webpage',
      ))
          .trim();
    } catch (e, stackTrace) {
      Logger.e(_tag, '网页内容处理失败', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      throw Exception('网页内容处理失败: $e');
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
    void Function(LlmRetryProgress progress)? onRetryScheduled,
  }) async {
    try {
      final runtimeConfig = await _settingsRepository.getLlmConfig();
      _validateRuntimeConfig(runtimeConfig);
      final apiStyle = _protocolResolver.resolveStyle(runtimeConfig.apiUrl);
      final adapter = _adapterFor(apiStyle);
      final modelName = _resolveModelName(runtimeConfig, config);
      final requestOptions = _requestOptionsFor(
        modelName: modelName,
        purpose: LlmRequestPurpose.planner,
        apiStyle: apiStyle,
      );
      final previousResponseId = _resolvePreviousResponseId(
        apiStyle: apiStyle,
        providerStyle: providerStyle,
        providerState: providerState,
      );
      Map<String, dynamic> payload = adapter.buildPlannerPayload(
        messages: messages,
        config: config,
        modelName: modelName,
        availableTools: availableTools,
        parallelToolCalls: true,
        requestOptions: requestOptions,
        previousResponseId: previousResponseId,
        continuationItems: providerContinuationItems,
        providerState: providerState,
      );
      Logger.i(_tag, 'native planner 请求体: ${jsonEncode(payload)}');
      Future<http.Response> sendPlannerRequest(
        Map<String, dynamic> requestPayload,
      ) {
        return _performRetriableMainFlowRequest(
          label: 'native_planner',
          onRetryScheduled: onRetryScheduled,
          operation: () => _httpClient
              .post(
                _protocolResolver.buildRequestUri(runtimeConfig.apiUrl, apiStyle),
                headers: adapter.buildHeaders(runtimeConfig),
                body: jsonEncode(requestPayload),
              )
              .timeout(_plannerRequestTimeout),
        );
      }

      var response = await sendPlannerRequest(payload);
      if (_shouldRetryResponsesWithoutPreviousResponseId(
        apiStyle: apiStyle,
        previousResponseId: previousResponseId,
        response: response,
        hasContinuationItems: providerContinuationItems.isNotEmpty,
      )) {
        Logger.w(
          _tag,
          'native planner provider rejected previous_response_id; retrying with stateless responses continuation',
        );
        payload = adapter.buildPlannerPayload(
          messages: messages,
          config: config,
          modelName: modelName,
          availableTools: availableTools,
          parallelToolCalls: true,
          requestOptions: requestOptions,
          previousResponseId: null,
          continuationItems: providerContinuationItems,
          providerState: providerState,
        );
        Logger.i(_tag, 'native planner fallback 请求体: ${jsonEncode(payload)}');
        response = await sendPlannerRequest(payload);
      }

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

  LlmRequestOptions _requestOptionsFor({
    required String modelName,
    required LlmRequestPurpose purpose,
    required ApiStyle apiStyle,
  }) {
    final profile = _modelBudgetRegistry.resolve(modelName);
    return LlmRequestOptions(
      maxOutputTokens: _resolveMaxOutputTokens(
        profile: profile,
        purpose: purpose,
      ),
      allowReasoning: _allowReasoningFor(
        apiStyle: apiStyle,
        purpose: purpose,
      ),
    );
  }

  int _resolveMaxOutputTokens({
    required ModelBudgetProfile profile,
    required LlmRequestPurpose purpose,
  }) {
    switch (purpose) {
      case LlmRequestPurpose.planner:
        return profile.reservedOutputTokens;
      case LlmRequestPurpose.summary:
      case LlmRequestPurpose.webpageProcessing:
      case LlmRequestPurpose.sideTask:
        return profile.reservedOutputTokens + profile.reasoningReserveTokens;
    }
  }

  bool _allowReasoningFor({
    required ApiStyle apiStyle,
    required LlmRequestPurpose purpose,
  }) {
    if (apiStyle != ApiStyle.anthropicMessages) {
      return true;
    }
    switch (purpose) {
      case LlmRequestPurpose.planner:
        return false;
      case LlmRequestPurpose.summary:
      case LlmRequestPurpose.webpageProcessing:
      case LlmRequestPurpose.sideTask:
        return true;
    }
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

  bool _shouldRetryResponsesWithoutPreviousResponseId({
    required ApiStyle apiStyle,
    required String? previousResponseId,
    required http.Response response,
    required bool hasContinuationItems,
  }) {
    if (apiStyle != ApiStyle.responses ||
        !hasContinuationItems ||
        previousResponseId == null ||
        previousResponseId.trim().isEmpty ||
        response.statusCode != 400) {
      return false;
    }
    final normalizedBody = response.body.toLowerCase();
    return normalizedBody.contains('previous_response_id') &&
        (normalizedBody.contains('not supported') ||
            normalizedBody.contains('only supported'));
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

  Future<String> _runSideModelTextTask(
    LLMConfig runtimeConfig, {
    required ChatConfig config,
    required List<ChatMessage> messages,
    required String requestLabel,
    Duration? timeout,
  }) async {
    final effectiveTimeout = timeout ?? _requestTimeout;
    final apiStyle = _protocolResolver.resolveStyle(runtimeConfig.apiUrl);
    final adapter = _adapterFor(apiStyle);
    final modelName = _resolveModelName(runtimeConfig, config);
    final requestOptions = _requestOptionsFor(
      modelName: modelName,
      purpose: switch (requestLabel) {
        'side_summary' => LlmRequestPurpose.summary,
        'side_webpage' => LlmRequestPurpose.webpageProcessing,
        _ => LlmRequestPurpose.sideTask,
      },
      apiStyle: apiStyle,
    );
    final payload = adapter.buildPlannerPayload(
      messages: messages,
      config: config,
      modelName: modelName,
      availableTools: const [],
      parallelToolCalls: false,
      requestOptions: requestOptions,
    );
    Logger.i(_tag, '$requestLabel 请求体: ${jsonEncode(payload)}');
    final response = await _performRetriableMainFlowRequest(
      label: requestLabel,
      operation: () => _httpClient
          .post(
            _protocolResolver.buildRequestUri(runtimeConfig.apiUrl, apiStyle),
            headers: adapter.buildHeaders(runtimeConfig),
            body: jsonEncode(payload),
          )
          .timeout(effectiveTimeout),
    );
    if (response.statusCode != 200) {
      throw Exception('请求失败: ${response.statusCode}');
    }

    final responseText = utf8.decode(response.bodyBytes);
    final decoded = jsonDecode(responseText);
    if (decoded is! Map<String, dynamic>) {
      return '';
    }
    final decision = _parseTurnDecisionForStyle(apiStyle, decoded);
    if (decision != null) {
      if (decision.toolCalls.isNotEmpty) {
        Logger.w(_tag, '$requestLabel 意外返回 tool calls，已忽略');
      }
      return (decision.assistantMessage ?? '').trim();
    }
    return adapter.extractNonStreamText(decoded).trim();
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
    void Function(LlmRetryProgress progress)? onRetryScheduled,
  }) async {
    Object? lastError;
    StackTrace? lastStackTrace;

    for (var attempt = 1;
        attempt <= _mainFlowNetworkRetryAttempts;
        attempt += 1) {
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
        onRetryScheduled?.call(
          LlmRetryProgress(
            label: label,
            attempt: attempt,
            maxAttempts: _mainFlowNetworkRetryAttempts,
            delay: delay,
            error: error,
          ),
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
        normalized
            .contains('connection closed before full header was received') ||
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

enum LlmRequestPurpose {
  planner,
  summary,
  webpageProcessing,
  sideTask,
}
