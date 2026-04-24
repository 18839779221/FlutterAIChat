import 'dart:async';
import 'dart:convert';

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
  static const String _modelContextTypeKey = 'modelContextType';
  static const String _assistantToolUseContextType = 'assistantToolUse';
  static const String _userToolResultContextType = 'userToolResult';

  final AppSettingsRepository _settingsRepository;
  final ApiProtocolResolver _protocolResolver;
  final ApiStreamParser _streamParser;
  final http.Client _httpClient;
  final Duration _requestTimeout;
  final Duration _plannerRequestTimeout;
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
        _chatCompletionsToolLoopAdapter = chatCompletionsToolLoopAdapter ??
            const OpenAIChatCompletionsToolLoopAdapter(),
        _responsesToolLoopAdapter =
            responsesToolLoopAdapter ?? const OpenAIResponsesToolLoopAdapter(),
        _anthropicMessagesToolLoopAdapter = anthropicMessagesToolLoopAdapter ??
            const AnthropicMessagesToolLoopAdapter(),
        _promptBuilder = promptBuilder ?? const PromptBuilderService();

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
      Logger.d(
        _tag,
        '发送摘要 roles=${messages.map((message) => message.role.name).join(",")} totalChars=${messages.fold<int>(0, (sum, message) => sum + message.text.length)}',
      );

      final apiStyle = _protocolResolver.resolveStyle(runtimeConfig.apiUrl);
      final modelName = _resolveModelName(runtimeConfig, config);
      final request = http.Request(
        'POST',
        _protocolResolver.buildRequestUri(runtimeConfig.apiUrl, apiStyle),
      );
      request.headers.addAll(_buildHeaders(runtimeConfig, apiStyle));
      request.body = jsonEncode(
        _buildPayloadForStyle(
          apiStyle,
          messages,
          config,
          modelName,
          stream: true,
        ),
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
            headers: _buildHeaders(runtimeConfig, apiStyle),
            body: jsonEncode(
              _buildPayloadForStyle(
                apiStyle,
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
      final summaryPrompt = _normalizeSummaryMessages(messages);

      final summary = await _sendTextRequest(
        runtimeConfig,
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
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
      final modelName = _resolveModelName(runtimeConfig, config);
      final payload = _buildPlannerPayloadForStyle(
        apiStyle,
        messages,
        config,
        modelName,
        availableTools: availableTools,
        parallelToolCalls: false,
      );
      Logger.i(_tag, 'structured planner 请求体: ${jsonEncode(payload)}');
      final response = await _httpClient
          .post(
            _protocolResolver.buildRequestUri(runtimeConfig.apiUrl, apiStyle),
            headers: _buildHeaders(runtimeConfig, apiStyle),
            body: jsonEncode(payload),
          )
          .timeout(_plannerRequestTimeout);

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

      final choice = _parsePlannerChoiceForStyle(apiStyle, decoded);
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
      final modelName = _resolveModelName(runtimeConfig, config);
      final previousResponseId = _resolvePreviousResponseId(
        apiStyle: apiStyle,
        providerStyle: providerStyle,
        providerState: providerState,
      );
      final normalizedContinuationItems = _normalizePlannerContinuationItems(
        apiStyle: apiStyle,
        providerState: providerState,
        continuationItems: providerContinuationItems,
      );
      final payload = _buildPlannerPayloadForStyle(
        apiStyle,
        messages,
        config,
        modelName,
        availableTools: availableTools,
        parallelToolCalls: true,
        previousResponseId: previousResponseId,
        continuationItems: normalizedContinuationItems,
      );
      Logger.i(_tag, 'native planner 请求体: ${jsonEncode(payload)}');
      final response = await _httpClient
          .post(
            _protocolResolver.buildRequestUri(runtimeConfig.apiUrl, apiStyle),
            headers: _buildHeaders(runtimeConfig, apiStyle),
            body: jsonEncode(payload),
          )
          .timeout(_plannerRequestTimeout);

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

  Map<String, String> _buildHeaders(LLMConfig config, ApiStyle apiStyle) {
    if (apiStyle == ApiStyle.anthropicMessages) {
      return {
        'Content-Type': 'application/json',
        'x-api-key': config.apiKey,
        'anthropic-version': '2023-06-01',
      };
    }
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

  Map<String, dynamic> _buildChatCompletionsPayload(
    List<ChatMessage> messages,
    ChatConfig config,
    String modelName, {
    required bool stream,
  }) {
    final normalizedMessages =
        _normalizeMessagesWithConfiguredSystemPrompt(messages, config);
    final transcriptState = _HistoricalToolTranscriptState('call_ctx_');
    return {
      'model': modelName,
      'messages': normalizedMessages
          .map(
            (msg) => _buildChatCompletionsMessage(
              msg,
              transcriptState: transcriptState,
            ),
          )
          .toList(),
      'stream': stream,
    };
  }

  Map<String, dynamic> _buildPayloadForStyle(
    ApiStyle apiStyle,
    List<ChatMessage> messages,
    ChatConfig config,
    String modelName, {
    required bool stream,
  }) {
    switch (apiStyle) {
      case ApiStyle.responses:
        return _buildResponsesPayload(
          messages,
          config,
          modelName,
          stream: stream,
        );
      case ApiStyle.chatCompletions:
        return _buildChatCompletionsPayload(
          messages,
          config,
          modelName,
          stream: stream,
        );
      case ApiStyle.anthropicMessages:
        return _buildAnthropicMessagesPayload(
          messages,
          config,
          modelName,
          stream: stream,
        );
    }
  }

  Map<String, dynamic> _buildResponsesPayload(
    List<ChatMessage> messages,
    ChatConfig config,
    String modelName, {
    required bool stream,
  }) {
    final normalizedMessages =
        _normalizeMessagesWithConfiguredSystemPrompt(messages, config);
    final transcriptState = _HistoricalToolTranscriptState('fc_ctx_');
    return {
      'model': modelName,
      'input': normalizedMessages
          .map(
            (msg) => _buildResponsesInputItem(
              msg,
              transcriptState: transcriptState,
            ),
          )
          .toList(),
      'stream': stream,
      'store': false,
      if (config.useReasoning) 'reasoning': {'effort': 'medium'},
    };
  }

  List<ChatMessage> _normalizeMessagesWithConfiguredSystemPrompt(
    List<ChatMessage> messages,
    ChatConfig config,
  ) {
    final normalizedMessages =
        messages.where((msg) => msg.text.trim().isNotEmpty).toList();
    final configuredSystemPrompt = config.systemPrompt.trim();
    if (configuredSystemPrompt.isEmpty) {
      return normalizedMessages;
    }

    final alreadyPresent = normalizedMessages.any(
      (message) =>
          message.role == MessageRole.system &&
          message.text.trim() == configuredSystemPrompt,
    );
    if (alreadyPresent) {
      return normalizedMessages;
    }

    return [
      ChatMessage(
        text: configuredSystemPrompt,
        role: MessageRole.system,
      ),
      ...normalizedMessages,
    ];
  }

  Map<String, dynamic> _buildAnthropicMessagesPayload(
    List<ChatMessage> messages,
    ChatConfig config,
    String modelName, {
    required bool stream,
    List<Map<String, dynamic>> continuationItems = const [],
  }) {
    final systemSegments = <String>[];
    final configuredSystemPrompt = config.systemPrompt.trim();
    if (configuredSystemPrompt.isNotEmpty) {
      systemSegments.add(configuredSystemPrompt);
    }

    final normalizedMessages = <Map<String, dynamic>>[];
    final transcriptState = _HistoricalToolTranscriptState('toolu_ctx_');
    for (final message in messages) {
      final trimmedText = message.text.trim();
      if (trimmedText.isEmpty) {
        continue;
      }
      if (message.role == MessageRole.system) {
        systemSegments.add(trimmedText);
        continue;
      }
      normalizedMessages.add(
        _buildAnthropicMessage(
          message,
          transcriptState: transcriptState,
        ),
      );
    }

    if (continuationItems.isNotEmpty) {
      normalizedMessages.addAll(
        continuationItems.map((item) => Map<String, dynamic>.from(item)),
      );
    }

    return {
      'model': modelName,
      if (systemSegments.isNotEmpty) 'system': systemSegments.join('\n\n'),
      'messages': normalizedMessages,
      'stream': stream,
      'max_tokens': 4096,
    };
  }

  Map<String, dynamic> _buildChatCompletionsMessage(
    ChatMessage message, {
    required _HistoricalToolTranscriptState transcriptState,
  }) {
    final contextType = _modelContextTypeOf(message);
    if (contextType == _assistantToolUseContextType) {
      final toolName = _toolNameOf(message);
      if (toolName != null) {
        final callId = transcriptState.register(toolName);
        return {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {
              'id': callId,
              'type': 'function',
              'function': {
                'name': toolName,
                'arguments': jsonEncode(_toolArgumentsOf(message) ?? const {}),
              },
            },
          ],
        };
      }
    }
    if (contextType == _userToolResultContextType) {
      final invocation = transcriptState.consume(
        preferredToolName: _toolNameOf(message),
      );
      if (invocation != null) {
        return {
          'role': 'tool',
          'tool_call_id': invocation.id,
          'content': message.text,
        };
      }
    }
    return {
      'role': message.role.toString().split('.').last,
      'content': message.text,
    };
  }

  Map<String, dynamic> _buildResponsesInputItem(
    ChatMessage message, {
    required _HistoricalToolTranscriptState transcriptState,
  }) {
    final contextType = _modelContextTypeOf(message);
    if (contextType == _assistantToolUseContextType) {
      final toolName = _toolNameOf(message);
      if (toolName != null) {
        final callId = transcriptState.register(toolName);
        return {
          'type': 'function_call',
          'call_id': callId,
          'name': toolName,
          'arguments': jsonEncode(_toolArgumentsOf(message) ?? const {}),
        };
      }
    }
    if (contextType == _userToolResultContextType) {
      final invocation = transcriptState.consume(
        preferredToolName: _toolNameOf(message),
      );
      if (invocation != null) {
        return {
          'type': 'function_call_output',
          'call_id': invocation.id,
          'output': message.text,
        };
      }
    }
    return {
      'role': message.role.toString().split('.').last,
      'content': [
        {
          'type': message.role == MessageRole.assistant
              ? 'output_text'
              : 'input_text',
          'text': message.text,
        },
      ],
    };
  }

  Map<String, dynamic> _buildAnthropicMessage(
    ChatMessage message, {
    required _HistoricalToolTranscriptState transcriptState,
  }) {
    final contextType = _modelContextTypeOf(message);
    if (contextType == _assistantToolUseContextType) {
      final toolName = _toolNameOf(message);
      if (toolName != null) {
        final toolUseId = transcriptState.register(toolName);
        return {
          'role': 'assistant',
          'content': [
            {
              'type': 'tool_use',
              'id': toolUseId,
              'name': toolName,
              'input': _toolArgumentsOf(message) ?? const {},
            },
          ],
        };
      }
    }
    if (contextType == _userToolResultContextType) {
      final invocation = transcriptState.consume(
        preferredToolName: _toolNameOf(message),
      );
      if (invocation != null) {
        return {
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': invocation.id,
              'content': message.text,
            },
          ],
        };
      }
    }
    return {
      'role': message.role == MessageRole.assistant ? 'assistant' : 'user',
      'content': [
        {
          'type': 'text',
          'text': message.text,
        },
      ],
    };
  }

  Map<String, dynamic> _buildPlannerChatCompletionsPayload(
    List<ChatMessage> messages,
    ChatConfig config,
    String modelName, {
    required List<PlannerToolOption> availableTools,
    required bool parallelToolCalls,
    List<Map<String, dynamic>> continuationItems = const [],
  }) {
    final payload = _buildChatCompletionsPayload(
      messages,
      config,
      modelName,
      stream: false,
    );
    final payloadMessages = List<Map<String, dynamic>>.from(
      (payload['messages'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item)),
    );
    if (continuationItems.isNotEmpty) {
      payload['messages'] = [
        ...payloadMessages,
        ..._buildChatCompletionsContinuationMessages(continuationItems),
      ];
    }
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

  Map<String, dynamic> _buildPlannerPayloadForStyle(
    ApiStyle apiStyle,
    List<ChatMessage> messages,
    ChatConfig config,
    String modelName, {
    required List<PlannerToolOption> availableTools,
    required bool parallelToolCalls,
    String? previousResponseId,
    List<Map<String, dynamic>> continuationItems = const [],
  }) {
    switch (apiStyle) {
      case ApiStyle.responses:
        return _buildPlannerResponsesPayload(
          messages,
          config,
          modelName,
          availableTools: availableTools,
          parallelToolCalls: parallelToolCalls,
          previousResponseId: previousResponseId,
          continuationItems: continuationItems,
        );
      case ApiStyle.chatCompletions:
        return _buildPlannerChatCompletionsPayload(
          messages,
          config,
          modelName,
          availableTools: availableTools,
          parallelToolCalls: parallelToolCalls,
          continuationItems: continuationItems,
        );
      case ApiStyle.anthropicMessages:
        return _buildPlannerAnthropicMessagesPayload(
          messages,
          config,
          modelName,
          availableTools: availableTools,
          continuationItems: continuationItems,
        );
    }
  }

  Map<String, dynamic> _buildPlannerAnthropicMessagesPayload(
    List<ChatMessage> messages,
    ChatConfig config,
    String modelName, {
    required List<PlannerToolOption> availableTools,
    List<Map<String, dynamic>> continuationItems = const [],
  }) {
    final payload = _buildAnthropicMessagesPayload(
      messages,
      config,
      modelName,
      stream: false,
      continuationItems: continuationItems,
    );
    final tools = availableTools
        .map(
          (tool) => {
            'name': tool.name,
            'description': tool.description,
            'input_schema': tool.inputSchema,
          },
        )
        .toList(growable: false);
    if (tools.isNotEmpty) {
      payload['tools'] = tools;
      payload['tool_choice'] = {'type': 'auto'};
    }
    return payload;
  }

  List<Map<String, dynamic>> _buildChatCompletionsContinuationMessages(
    List<Map<String, dynamic>> continuationItems,
  ) {
    final messages = <Map<String, dynamic>>[];
    for (final rawItem in continuationItems) {
      final item = Map<String, dynamic>.from(rawItem);
      final type = item['type'];
      if (type == 'assistant_tool_call') {
        final toolCallId = _normalizeText(item['toolCallId']);
        final toolName = _normalizeText(item['toolName']);
        final arguments = item['arguments'];
        if (toolCallId == null || toolName == null || arguments is! Map) {
          continue;
        }
        messages.add({
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {
              'id': toolCallId,
              'type': 'function',
              'function': {
                'name': toolName,
                'arguments': jsonEncode(arguments),
              },
            },
          ],
        });
        continue;
      }
      if (type == 'tool_result') {
        final toolCallId = _normalizeText(item['toolCallId']);
        final output = _normalizeText(item['output']);
        if (toolCallId == null || output == null) {
          continue;
        }
        messages.add({
          'role': 'tool',
          'tool_call_id': toolCallId,
          'content': output,
        });
        continue;
      }
      if (type == 'user_interaction_answer') {
        final content = _normalizeText(item['content']);
        if (content == null) {
          continue;
        }
        messages.add({
          'role': 'user',
          'content': content,
        });
      }
    }
    return messages;
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
    // Responses tool-loop continuation relies on previous_response_id, so the
    // planner response must remain server-addressable instead of being forced
    // into stateless store:false mode.
    payload['store'] = true;
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
      final continuationInputItems =
          _buildResponsesContinuationInputItems(continuationItems);
      final input = _shouldUseResponsesContinuationInputOnly(
        previousResponseId: previousResponseId,
        continuationItems: continuationInputItems,
      )
          ? <dynamic>[]
          : List<dynamic>.from(
              payload['input'] as List<dynamic>? ?? const <dynamic>[],
            );
      for (final item in continuationInputItems) {
        input.add(Map<String, dynamic>.from(item));
      }
      payload['input'] = input;
    }
    return payload;
  }

  List<Map<String, dynamic>> _buildResponsesContinuationInputItems(
    List<Map<String, dynamic>> continuationItems,
  ) {
    final items = <Map<String, dynamic>>[];
    for (final item in continuationItems) {
      final type = item['type'];
      if (type == 'user_interaction_answer') {
        final content = _normalizeText(item['content']);
        if (content == null) {
          continue;
        }
        items.add({
          'role': 'user',
          'content': [
            {
              'type': 'input_text',
              'text': content,
            },
          ],
        });
        continue;
      }
      items.add(Map<String, dynamic>.from(item));
    }
    return items;
  }

  PlannerToolChoice? _parsePlannerChatCompletionsChoice(
    Map<String, dynamic> payload,
  ) {
    final choices = payload['choices'];
    if (choices is! List || choices.isEmpty) {
      return null;
    }

    final firstChoice = choices.first;
    if (firstChoice is! Map) {
      return null;
    }

    final message = firstChoice['message'];
    if (message is! Map) {
      return null;
    }

    final normalizedMessage = message.cast<String, dynamic>();
    final toolCallChoice = _parseChatCompletionsToolCall(normalizedMessage);
    if (toolCallChoice != null) {
      return toolCallChoice;
    }

    final content = _extractChatCompletionsMessageText(normalizedMessage);
    if (content != null) {
      return PlannerToolChoice.respond(content);
    }

    return null;
  }

  PlannerToolChoice? _parsePlannerResponsesChoice(
    Map<String, dynamic> payload,
  ) {
    final output = payload['output'];
    if (output is List) {
      for (final item in output) {
        if (item is! Map) {
          continue;
        }
        final normalizedItem = item.cast<String, dynamic>();
        final type = normalizedItem['type'];
        if (type == 'function_call') {
          final toolCallChoice = _parseResponsesToolCall(normalizedItem);
          if (toolCallChoice != null) {
            return toolCallChoice;
          }
        }
        if (type == 'message') {
          final response = _extractResponsesMessageText(normalizedItem);
          if (response != null) {
            return PlannerToolChoice.respond(response);
          }
        }
      }
    }

    final outputText = _normalizeText(payload['output_text']);
    if (outputText != null) {
      return PlannerToolChoice.respond(outputText);
    }

    return null;
  }

  PlannerToolChoice? _parsePlannerChoiceForStyle(
    ApiStyle apiStyle,
    Map<String, dynamic> payload,
  ) {
    switch (apiStyle) {
      case ApiStyle.responses:
        return _parsePlannerResponsesChoice(payload);
      case ApiStyle.chatCompletions:
        return _parsePlannerChatCompletionsChoice(payload);
      case ApiStyle.anthropicMessages:
        return _parsePlannerAnthropicChoice(payload);
    }
  }

  PlannerToolChoice? _parsePlannerAnthropicChoice(
    Map<String, dynamic> payload,
  ) {
    final content = payload['content'];
    if (content is! List) {
      return null;
    }
    for (final item in content) {
      if (item is! Map) {
        continue;
      }
      final normalizedItem = item.cast<String, dynamic>();
      if (normalizedItem['type'] == 'tool_use') {
        final toolName = _normalizeText(normalizedItem['name']);
        final arguments = _decodeToolArguments(normalizedItem['input']);
        if (toolName != null && arguments != null) {
          return PlannerToolChoice.callTool(
            toolName: toolName,
            arguments: arguments,
          );
        }
      }
      final response = _extractAnthropicContentText(normalizedItem);
      if (response != null) {
        return PlannerToolChoice.respond(response);
      }
    }
    return null;
  }

  PlannerToolChoice? _parseChatCompletionsToolCall(
    Map<String, dynamic> message,
  ) {
    final toolCalls = message['tool_calls'];
    if (toolCalls is! List || toolCalls.isEmpty) {
      return null;
    }

    final firstToolCall = toolCalls.first;
    if (firstToolCall is! Map) {
      return null;
    }

    final function = firstToolCall['function'];
    if (function is! Map) {
      return null;
    }

    final toolName = _normalizeText(function['name']);
    final arguments = _decodeToolArguments(function['arguments']);
    if (toolName == null || arguments == null) {
      return null;
    }

    return PlannerToolChoice.callTool(
      toolName: toolName,
      arguments: arguments,
    );
  }

  PlannerToolChoice? _parseResponsesToolCall(
    Map<String, dynamic> item,
  ) {
    final toolName = _normalizeText(item['name']);
    final arguments = _decodeToolArguments(item['arguments']);
    if (toolName == null || arguments == null) {
      return null;
    }

    return PlannerToolChoice.callTool(
      toolName: toolName,
      arguments: arguments,
    );
  }

  String? _extractChatCompletionsMessageText(Map<String, dynamic> message) {
    final content = message['content'];
    final inlineText = _normalizeText(content);
    if (inlineText != null) {
      return inlineText;
    }

    if (content is List) {
      final buffer = StringBuffer();
      for (final item in content) {
        if (item is! Map) {
          continue;
        }
        final normalizedItem = item.cast<String, dynamic>();
        final text = _normalizeText(
          normalizedItem['text'] ?? normalizedItem['content'],
        );
        if (text != null) {
          buffer.write(text);
        }
      }
      final aggregated = buffer.toString().trim();
      if (aggregated.isNotEmpty) {
        return aggregated;
      }
    }

    return null;
  }

  String? _extractResponsesMessageText(Map<String, dynamic> item) {
    final content = item['content'];
    if (content is! List) {
      return null;
    }

    final buffer = StringBuffer();
    for (final part in content) {
      if (part is! Map) {
        continue;
      }
      final normalizedPart = part.cast<String, dynamic>();
      if (normalizedPart['type'] != 'output_text') {
        continue;
      }
      final text = _normalizeText(normalizedPart['text']);
      if (text != null) {
        buffer.write(text);
      }
    }

    final aggregated = buffer.toString().trim();
    if (aggregated.isEmpty) {
      return null;
    }
    return aggregated;
  }

  String? _extractAnthropicContentText(Map<String, dynamic> item) {
    final type = item['type'];
    if (type != 'text' && type != 'thinking' && type != 'redacted_thinking') {
      return null;
    }
    final text = _normalizeText(item['text'] ?? item['thinking']);
    return text;
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

  Map<String, dynamic>? _decodeToolArguments(dynamic rawArguments) {
    if (rawArguments is Map) {
      return rawArguments.cast<String, dynamic>();
    }

    final encoded = _normalizeText(rawArguments);
    if (encoded == null) {
      return null;
    }

    final decoded = jsonDecode(encoded);
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }

    return null;
  }

  String? _modelContextTypeOf(ChatMessage message) {
    final payload = message.payloadJson;
    if (payload == null) {
      return null;
    }
    return _normalizeText(payload[_modelContextTypeKey]);
  }

  String? _toolNameOf(ChatMessage message) {
    final payload = message.payloadJson;
    if (payload == null) {
      return null;
    }
    return _normalizeText(payload['toolName']);
  }

  Map<String, dynamic>? _toolArgumentsOf(ChatMessage message) {
    final payload = message.payloadJson;
    if (payload == null) {
      return null;
    }
    return _decodeToolArguments(payload['arguments']);
  }

  String? _normalizeText(dynamic value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  bool _shouldUseResponsesContinuationInputOnly({
    required String? previousResponseId,
    required List<Map<String, dynamic>> continuationItems,
  }) {
    return previousResponseId != null &&
        previousResponseId.isNotEmpty &&
        continuationItems.isNotEmpty;
  }

  List<Map<String, dynamic>> _normalizePlannerContinuationItems({
    required ApiStyle apiStyle,
    required Map<String, dynamic>? providerState,
    required List<Map<String, dynamic>> continuationItems,
  }) {
    if (apiStyle != ApiStyle.anthropicMessages || continuationItems.isEmpty) {
      return continuationItems;
    }

    final hasAssistantContinuation = continuationItems.any((item) {
      if (item['role'] != 'assistant') {
        return false;
      }
      final content = item['content'];
      return content is List && content.isNotEmpty;
    });
    if (hasAssistantContinuation) {
      return continuationItems;
    }

    final contentBlocks = providerState?['content_blocks'];
    if (contentBlocks is! List) {
      return continuationItems;
    }
    final normalizedBlocks = contentBlocks
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    if (normalizedBlocks.isEmpty) {
      return continuationItems;
    }

    return [
      {
        'role': 'assistant',
        'content': normalizedBlocks,
      },
      ...continuationItems,
    ];
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

    if (apiStyle == ApiStyle.responses ||
        apiStyle == ApiStyle.anthropicMessages) {
      final request = http.Request(
        'POST',
        _protocolResolver.buildRequestUri(runtimeConfig.apiUrl, apiStyle),
      );
      request.headers.addAll(_buildHeaders(runtimeConfig, apiStyle));
      request.body = jsonEncode(
        _buildPayloadForStyle(
          apiStyle,
          messages,
          config,
          modelName,
          stream: true,
        ),
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
          headers: _buildHeaders(runtimeConfig, apiStyle),
          body: jsonEncode(
            _buildPayloadForStyle(
              apiStyle,
              messages,
              config,
              modelName,
              stream: false,
            ),
          ),
        )
        .timeout(effectiveTimeout);

    if (response.statusCode != 200) {
      throw Exception('请求失败: ${response.statusCode}');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (apiStyle == ApiStyle.chatCompletions) {
      return data['choices'][0]['message']['content'].toString();
    }
    final content = data['content'];
    if (content is List) {
      final buffer = StringBuffer();
      for (final item in content) {
        if (item is! Map) {
          continue;
        }
        final text = _extractAnthropicContentText(item.cast<String, dynamic>());
        if (text != null) {
          buffer.write(text);
        }
      }
      return buffer.toString();
    }
    return '';
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
}

class _HistoricalToolTranscriptState {
  _HistoricalToolTranscriptState(this._idPrefix);

  final String _idPrefix;
  final List<_HistoricalToolInvocation> _pendingInvocations =
      <_HistoricalToolInvocation>[];
  int _nextId = 0;

  String register(String toolName) {
    _nextId += 1;
    final invocation = _HistoricalToolInvocation(
      id: '$_idPrefix$_nextId',
      toolName: toolName,
    );
    _pendingInvocations.add(invocation);
    return invocation.id;
  }

  _HistoricalToolInvocation? consume({String? preferredToolName}) {
    if (_pendingInvocations.isEmpty) {
      return null;
    }
    if (preferredToolName != null) {
      for (var index = 0; index < _pendingInvocations.length; index += 1) {
        final invocation = _pendingInvocations[index];
        if (invocation.toolName == preferredToolName) {
          _pendingInvocations.removeAt(index);
          return invocation;
        }
      }
    }
    return _pendingInvocations.removeAt(0);
  }
}

class _HistoricalToolInvocation {
  const _HistoricalToolInvocation({
    required this.id,
    required this.toolName,
  });

  final String id;
  final String toolName;
}
