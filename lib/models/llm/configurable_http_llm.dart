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
import '../context/planner_context_carrier.dart';
import '../session/model_budget_profile.dart';
import '../../services/session_summary_service.dart';
import 'adapters/api_style_adapter.dart';
import 'adapters/chat_completions_adapter.dart';
import 'adapters/sdk_anthropic_messages_adapter.dart';
import 'adapters/sdk_chat_completions_adapter.dart';
import 'adapters/sdk_responses_adapter.dart';
import 'api_protocol_resolver.dart';
import 'base_llm.dart';
import 'llm_cache_usage.dart';
import 'llm_cache_request_options.dart';
import 'llm_cache_strategy.dart';
import 'llm_config.dart';
import 'llm_request_purpose.dart';
import 'llm_request_options.dart';
import 'llm_usage_extractor.dart';
import 'planner_invariant_validator.dart';
import 'streaming_decision_accumulator.dart';
import 'streaming_message_event.dart';
import 'runtime/anthropic_messages_runtime.dart';
import 'runtime/openai_chat_completions_runtime.dart';
import 'runtime/openai_responses_runtime.dart';
import 'runtime/protocol_request_spec.dart';
import 'runtime/protocol_runtime_registry.dart';

class ConfigurableHttpLLM
    implements BaseLLM, PlannerRuntimeStreamingCapable {
  static const String _tag = 'ConfigurableHttpLLM';
  // Architecture:
  // - docs/architecture/append-only-transcript.md
  // - docs/architecture/agent-loop-boundaries-and-decoupling.md
  //
  // Invariant:
  // - planner requests consume transcript-derived messages only.
  // - provider adapters may transform wire format, but must not own semantic state.
  static const Duration _defaultRequestTimeout = Duration(seconds: 60);
  static const Duration _defaultPlannerRequestTimeout = Duration(seconds: 60);
  static const Duration _defaultPlannerStreamOverallTimeout =
      Duration(minutes: 3);
  static const int _defaultMainFlowNetworkRetryAttempts = 5;

  // Provider 维护边界：
  // - 所有三个 provider 都已迁移到 SDK-first / runtime-first 架构。
  // - 使用 SDK 类型构建请求，避免手动 JSON 构造。
  // - 旧的自研 adapter 保留为 deprecated，仅用于极端兼容场景。
  static const Map<ApiStyle, ApiStyleAdapter> _defaultAdapters = {
    ApiStyle.chatCompletions: SdkChatCompletionsAdapter(),
    ApiStyle.responses: SdkResponsesAdapter(),
    ApiStyle.anthropicMessages: SdkAnthropicMessagesAdapter(),
  };

  final AppSettingsRepository _settingsRepository;
  final ApiProtocolResolver _protocolResolver;
  final Duration _requestTimeout;
  final Duration _plannerRequestTimeout;
  final Duration _plannerStreamIdleTimeout;
  final Duration _plannerStreamOverallTimeout;
  final int _mainFlowNetworkRetryAttempts;
  Map<ApiStyle, ApiStyleAdapter> _adapters;
  final ProtocolRuntimeRegistry _runtimeRegistry;
  final PromptBuilderService _promptBuilder;
  final ModelBudgetRegistry _modelBudgetRegistry;
  final void Function(
    String tag,
    String message, {
    LogLevel level,
    Map<String, dynamic>? data,
  }) _traceEmitter;
  final Duration Function(int attempt) _retryDelayBuilder;
  PlannerRuntimeStreamListener? _plannerRuntimeStreamListener;

  ConfigurableHttpLLM({
    required AppSettingsRepository settingsRepository,
    ApiProtocolResolver? protocolResolver,
    http.Client? httpClient,
    Duration? requestTimeout,
    Duration? plannerRequestTimeout,
    Duration? plannerStreamIdleTimeout,
    Duration? plannerStreamOverallTimeout,
    int mainFlowNetworkRetryAttempts = _defaultMainFlowNetworkRetryAttempts,
    Map<ApiStyle, ApiStyleAdapter>? adapters,
    ProtocolRuntimeRegistry? runtimeRegistry,
    PromptBuilderService? promptBuilder,
    ModelBudgetRegistry? modelBudgetRegistry,
    void Function(
      String tag,
      String message, {
      LogLevel level,
      Map<String, dynamic>? data,
    })? traceEmitter,
    Duration Function(int attempt)? retryDelayBuilder,
  })  : _settingsRepository = settingsRepository,
        _protocolResolver = protocolResolver ?? const ApiProtocolResolver(),
        _requestTimeout = requestTimeout ?? _defaultRequestTimeout,
        _plannerRequestTimeout =
            plannerRequestTimeout ?? _defaultPlannerRequestTimeout,
        _plannerStreamIdleTimeout =
            plannerStreamIdleTimeout ??
                plannerRequestTimeout ??
                _defaultPlannerRequestTimeout,
        _plannerStreamOverallTimeout =
            plannerStreamOverallTimeout ??
                _resolveDefaultPlannerStreamOverallTimeout(
                  plannerStreamIdleTimeout ??
                      plannerRequestTimeout ??
                      _defaultPlannerRequestTimeout,
                ),
        _mainFlowNetworkRetryAttempts = mainFlowNetworkRetryAttempts,
        _adapters = adapters ?? _defaultAdapters,
        _runtimeRegistry = runtimeRegistry ??
            ProtocolRuntimeRegistry(
              runtimes: {
                ApiStyle.chatCompletions: OpenAiChatCompletionsRuntime(
                  httpClient: httpClient,
                ),
                ApiStyle.responses: OpenAiResponsesRuntime(
                  httpClient: httpClient,
                ),
                ApiStyle.anthropicMessages: AnthropicMessagesRuntime(
                  httpClient: httpClient,
                ),
              },
            ),
        _promptBuilder = promptBuilder ?? const PromptBuilderService(),
        _modelBudgetRegistry = modelBudgetRegistry ?? ModelBudgetRegistry(),
        _traceEmitter = traceEmitter ?? Logger.trace,
        _retryDelayBuilder = retryDelayBuilder ?? _defaultRetryDelayForAttempt {
    assert(mainFlowNetworkRetryAttempts >= 1);
  }

  @override
  void setPlannerRuntimeStreamListener(
    PlannerRuntimeStreamListener? listener,
  ) {
    _plannerRuntimeStreamListener = listener;
  }

  ApiStyleAdapter _adapterFor(ApiStyle apiStyle) {
    final adapter = _adapters[apiStyle];
    if (adapter == null) {
      throw StateError('No ApiStyleAdapter registered for $apiStyle');
    }
    Logger.i(_tag, 'adapter selected style=$apiStyle impl=${adapter.runtimeType}');
    return adapter;
  }

  /// Switch the Chat Completions adapter between SDK and legacy modes.
  ///
  /// [type] should be `'sdk'` or `'legacy'`. Any other value defaults to SDK.
  void setChatCompletionsAdapter(String type) {
    final adapter = type == 'legacy'
        // ignore: deprecated_member_use_from_same_package
        ? const LegacyChatCompletionsAdapter()
        : const SdkChatCompletionsAdapter();
    _adapters = Map.of(_adapters)..[ApiStyle.chatCompletions] = adapter;
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
    required List<PlannerContextCarrier> carriers,
    required ChatTurnProviderStyle activeApiStyle,
    required bool currentTurnRunning,
    required ChatConfig config,
    required List<PlannerToolOption> availableTools,
    void Function(LlmRetryProgress progress)? onRetryScheduled,
  }) async {
    try {
      const PlannerInvariantValidator().validate(
        carriers: carriers,
        activeApiStyle: activeApiStyle,
        currentTurnRunning: currentTurnRunning,
      );
      final runtimeConfig = await _settingsRepository.getLlmConfig();
      _validateRuntimeConfig(runtimeConfig);
      final apiStyle = _protocolResolver.resolveStyle(runtimeConfig.apiUrl);
      if (_toProviderStyle(apiStyle) != activeApiStyle) {
        throw InconsistentProviderStateError(
          'runtime apiStyle=$apiStyle resolves to ${_toProviderStyle(apiStyle)} '
          'but active session-locked style is $activeApiStyle',
        );
      }
      final adapter = _adapterFor(apiStyle);
      final modelName = _resolveModelName(runtimeConfig, config);
      final requestOptions = adapter.normalizeRequestOptions(
        _requestOptionsFor(
          modelName: modelName,
          purpose: LlmRequestPurpose.planner,
          apiStyle: apiStyle,
        ),
        purpose: LlmRequestPurpose.planner,
      );
      final traceContext = _requestTraceContext(
        label: 'native_planner',
        apiStyle: apiStyle,
        modelName: modelName,
        purpose: LlmRequestPurpose.planner,
        requestOptions: requestOptions,
        messageCount: carriers.length,
        messages: const [],
      );
      final requestSpec = adapter.buildPlannerRequestSpecFromCarriers(
        carriers: carriers,
        config: config,
        modelName: modelName,
        availableTools: availableTools,
        parallelToolCalls: true,
        runtimeConfig: runtimeConfig,
        requestOptions: requestOptions,
      );
      final payload = _requestSpecToJsonMap(requestSpec);
      if (adapter.capabilities.supportsPlannerStreaming) {
        final streamedResult = await _planTurnDecisionStreaming(
          runtimeConfig: runtimeConfig,
          apiStyle: apiStyle,
          requestSpec: requestSpec,
          traceContext: traceContext,
          onRetryScheduled: onRetryScheduled,
        );
        final streamedDecision = streamedResult.decision;
        if (streamedDecision == null) {
          Logger.w(
            _tag,
            'native planner streaming parsed null decision. summary=${_summarizeStreamingPlannerAttempt(streamedResult.debugSnapshot)}',
          );
          return null;
        }
        return streamedDecision.copyWith(
          providerStyle: _toProviderStyle(apiStyle),
          modelName: modelName,
        );
      }
      _emitRequestStart(traceContext, payload);
      Logger.i(_tag, 'native planner 请求体: ${jsonEncode(payload)}');
      final execution = await _performRetriableMainFlowRequest(
        label: 'native_planner',
        onRetryScheduled: onRetryScheduled,
        operation: () => _runtimeRegistry
            .runtimeFor(apiStyle)
            .execute(
              requestSpec: requestSpec,
              runtimeConfig: runtimeConfig,
              timeout: _plannerRequestTimeout,
            ),
      );
      final decoded = execution.rawResponseJson;
      Logger.i(_tag, 'native planner 响应体: ${jsonEncode(decoded)}');
      if (decoded.isEmpty) {
        Logger.w(_tag, 'native planner returned empty body');
        return null;
      }

      final decision = adapter.parseDecision(decoded);
      if (decision == null) {
        Logger.w(
          _tag,
          'native planner parsed null decision. response=${_previewBody(jsonEncode(decoded))} summary=${_summarizePlannerPayload(decoded)}',
        );
        return null;
      }
      // Capture provider raw assistant message for round-trip replay.
      final rawAssistantMessage = adapter.extractRawAssistantMessage(decoded);
      final decisionWithRaw = rawAssistantMessage == null
          ? decision
          : decision.copyWith(
              providerState: {
                ...decision.providerState,
                'raw_assistant_message': rawAssistantMessage,
              },
            );
      _emitRequestDone(
        traceContext,
        totalMs: _elapsedMilliseconds(traceContext.startedAt),
        payloadBytes: _payloadBytes(payload),
        cacheUsage: execution.cacheUsage ?? LlmUsageExtractor.extract(decoded),
      );
      if (decision.toolCalls.length > 1) {
        Logger.i(
          _tag,
          'native planner multi-tool raw response: ${_previewBody(jsonEncode(decoded))}',
        );
        Logger.i(
          _tag,
          'native planner multi-tool parsed calls: ${decision.toolCalls.map((call) => '${call.toolName}:${jsonEncode(call.arguments)}').join(' | ')}',
        );
      }
      return decisionWithRaw.copyWith(
        providerStyle: _toProviderStyle(apiStyle),
        modelName: modelName,
      );
    } catch (e, stackTrace) {
      Logger.w(
        _tag,
        'native planner 请求失败: ${_previewBody(e.toString())}',
      );
      _traceEmitter(
        _tag,
        'llm.request.failed',
        level: LogLevel.error,
        data: {
          'label': 'native_planner',
          'apiStyle': _protocolResolver.resolveStyle(
            (await _settingsRepository.getLlmConfig()).apiUrl,
          ).name,
          'model': (await _settingsRepository.getLlmConfig()).model,
          'purpose': LlmRequestPurpose.planner.name,
          'error': e.toString(),
        },
      );
      Logger.e(_tag, 'native planner stack trace', stackTrace);
      rethrow;
    }
  }

  Future<_StreamingPlannerAttemptResult> _planTurnDecisionStreaming({
    required LLMConfig runtimeConfig,
    required ApiStyle apiStyle,
    required ProtocolRequestSpec requestSpec,
    required _RequestTraceContext traceContext,
    void Function(LlmRetryProgress progress)? onRetryScheduled,
  }) async {
    final streamingPayload = _requestSpecToJsonMap(requestSpec);
    _emitRequestStart(traceContext, streamingPayload);
    Logger.i(
      _tag,
      'native planner streaming 请求体: ${jsonEncode(streamingPayload)}',
    );
    return _performRetriableMainFlowRequest(
      label: 'native_planner',
      onRetryScheduled: onRetryScheduled,
      operation: () => _runStreamingPlannerAttempt(
        runtimeConfig: runtimeConfig,
        apiStyle: apiStyle,
        requestSpec: requestSpec,
        traceContext: traceContext,
      ),
    );
  }

  Future<_StreamingPlannerAttemptResult> _runStreamingPlannerAttempt({
    required LLMConfig runtimeConfig,
    required ApiStyle apiStyle,
    required ProtocolRequestSpec requestSpec,
    required _RequestTraceContext traceContext,
  }) async {
    final execution = await _runtimeRegistry.runtimeFor(apiStyle).streamExecute(
          requestSpec: requestSpec,
          runtimeConfig: runtimeConfig,
          idleTimeout: _plannerStreamIdleTimeout,
          overallTimeout: _plannerStreamOverallTimeout,
        );
    final streamingPayload = _requestSpecToJsonMap(requestSpec);
    final fallbackJson = execution.nonStreamingFallbackJson;
    if (fallbackJson != null) {
      Logger.i(
        _tag,
        'native planner streaming fallback 响应体: ${jsonEncode(fallbackJson)}',
      );
      if (fallbackJson.isEmpty) {
        _emitRequestDone(
          traceContext,
          totalMs: _elapsedMilliseconds(traceContext.startedAt),
          payloadBytes: _payloadBytes(streamingPayload),
        );
        return const _StreamingPlannerAttemptResult.completed(null);
      }
      _emitRequestDone(
        traceContext,
        totalMs: _elapsedMilliseconds(traceContext.startedAt),
        payloadBytes: _payloadBytes(streamingPayload),
        cacheUsage: LlmUsageExtractor.extract(fallbackJson),
      );
      final adapter = _adapterFor(apiStyle);
      return _StreamingPlannerAttemptResult.completed(
        adapter.parseDecision(fallbackJson),
      );
    }

    final accumulator = StreamingDecisionAccumulator();
    DateTime? firstChunkAt;
    LlmCacheUsage? streamUsage;
    await _consumePlannerStreamWithTimeouts(
      events: execution.events,
      accumulator: accumulator,
      onFirstChunk: () {
        firstChunkAt ??= DateTime.now();
        _emitFirstChunk(
          traceContext,
          firstChunkMs: firstChunkAt!.difference(traceContext.startedAt).inMilliseconds,
        );
      },
      onEvent: (event) {
        _plannerRuntimeStreamListener?.call(event);
        final metadata = event.providerMetadata;
        if (metadata != null && metadata.containsKey('_usage')) {
          final usageMap = metadata['_usage'] as Map<String, dynamic>?;
          if (usageMap != null) {
            streamUsage = LlmCacheUsage(
              inputTokens: usageMap['input_tokens'] as int? ?? usageMap['inputTokens'] as int?,
              outputTokens: usageMap['output_tokens'] as int? ?? usageMap['outputTokens'] as int?,
              cachedInputTokens: usageMap['cached_input_tokens'] as int? ?? usageMap['cachedInputTokens'] as int?,
              cacheReadInputTokens: usageMap['cache_read_input_tokens'] as int? ?? usageMap['cacheReadInputTokens'] as int?,
              cacheWriteInputTokens: usageMap['cache_creation_input_tokens'] as int? ?? usageMap['cacheWriteInputTokens'] as int?,
              rawUsage: usageMap,
            );
          }
        }
      },
    );

    _emitRequestDone(
      traceContext,
      totalMs: _elapsedMilliseconds(traceContext.startedAt),
      payloadBytes: _payloadBytes(streamingPayload),
      firstChunkMs: firstChunkAt?.difference(traceContext.startedAt).inMilliseconds,
      cacheUsage: streamUsage ?? execution.cacheUsage,
    );
    final debugSnapshot = accumulator.debugSnapshot();
    Logger.i(
      _tag,
      'native planner streaming snapshot: ${_summarizeStreamingPlannerAttempt(debugSnapshot)}',
    );
    final adapter = _adapterFor(apiStyle);
    final builtDecision = accumulator.buildDecision();
    // Capture provider raw assistant message for round-trip replay.
    final snapshot = accumulator.currentSnapshot();
    final rawAssistantMessage =
        builtDecision == null ? null : adapter.assembleRawFromStreamingSnapshot(snapshot);
    final decisionWithRaw = (builtDecision == null || rawAssistantMessage == null)
        ? builtDecision
        : builtDecision.copyWith(
            providerState: {
              ...builtDecision.providerState,
              'streaming_preview_identity': _buildStreamingPreviewIdentity(
                snapshot,
              ),
              'raw_assistant_message': rawAssistantMessage,
            },
          );
    return _StreamingPlannerAttemptResult.completed(
      decisionWithRaw,
      debugSnapshot: debugSnapshot,
    );
  }

  Future<void> _consumePlannerStreamWithTimeouts({
    required Stream<StreamingMessageEvent> events,
    required StreamingDecisionAccumulator accumulator,
    void Function()? onFirstChunk,
    void Function(StreamingMessageEvent)? onEvent,
  }) {
    final startedAt = DateTime.now();
    var chunkCount = 0;
    DateTime? lastChunkAt;

    void logChunkProgress(String phase) {
      final snapshot = accumulator.debugSnapshot();
      final assistantChars =
          (snapshot['assistantTextLength'] as int?) ?? 0;
      final reasoningChars = (snapshot['reasoningLength'] as int?) ?? 0;
      final toolDrafts =
          (snapshot['toolDrafts'] as List<dynamic>?) ?? const <dynamic>[];
      Logger.temp(
        _tag,
        'planner stream $phase',
        reason: 'diagnose create_artifact timeout on device',
        data: {
          'chunkCount': chunkCount,
          'elapsedMs': DateTime.now().difference(startedAt).inMilliseconds,
          'idleMs': lastChunkAt == null
              ? null
              : DateTime.now().difference(lastChunkAt!).inMilliseconds,
          'assistantChars': assistantChars,
          'reasoningChars': reasoningChars,
          'toolDraftCount': toolDrafts.length,
          'toolDraftSummary': _summarizeStreamingPlannerAttempt(snapshot),
        },
      );
    }

    Logger.temp(
      _tag,
      'planner stream start',
      reason: 'diagnose create_artifact timeout on device',
      data: {
        'idleTimeoutMs': _plannerStreamIdleTimeout.inMilliseconds,
        'overallTimeoutMs': _plannerStreamOverallTimeout.inMilliseconds,
      },
    );

    return (() async {
      var firstChunkEmitted = false;
      await for (final event in events.timeout(
        _plannerStreamIdleTimeout,
        onTimeout: (sink) {
          Logger.temp(
            _tag,
            'planner stream idle timeout',
            level: LogLevel.warning,
            reason: 'diagnose create_artifact timeout on device',
            data: {
              'chunkCount': chunkCount,
              'elapsedMs': DateTime.now().difference(startedAt).inMilliseconds,
              'idleTimeoutMs': _plannerStreamIdleTimeout.inMilliseconds,
              'lastChunkAgoMs': lastChunkAt == null
                  ? null
                  : DateTime.now().difference(lastChunkAt!).inMilliseconds,
            },
          );
          logChunkProgress('idle-timeout snapshot');
          sink.addError(
            TimeoutException(
              'planner stream idle timeout after '
              '${_plannerStreamIdleTimeout.inMilliseconds}ms',
            ),
          );
        },
      )) {
        if (!firstChunkEmitted) {
          firstChunkEmitted = true;
          onFirstChunk?.call();
          Logger.temp(
            _tag,
            'planner stream first chunk',
            reason: 'diagnose create_artifact timeout on device',
            data: {
              'elapsedMs': DateTime.now().difference(startedAt).inMilliseconds,
            },
          );
        }
        chunkCount += 1;
        lastChunkAt = DateTime.now();
        onEvent?.call(event);
        accumulator.consume(event);
        if (chunkCount <= 3 || chunkCount % 20 == 0) {
          logChunkProgress('progress');
        }
      }
      logChunkProgress('completed');
    }()).timeout(
      _plannerStreamOverallTimeout,
      onTimeout: () {
        Logger.temp(
          _tag,
          'planner stream overall timeout',
          level: LogLevel.warning,
          reason: 'diagnose create_artifact timeout on device',
          data: {
            'chunkCount': chunkCount,
            'elapsedMs': DateTime.now().difference(startedAt).inMilliseconds,
            'overallTimeoutMs': _plannerStreamOverallTimeout.inMilliseconds,
            'lastChunkAgoMs': lastChunkAt == null
                ? null
                : DateTime.now().difference(lastChunkAt!).inMilliseconds,
          },
        );
        logChunkProgress('overall-timeout snapshot');
        throw TimeoutException(
          'planner stream overall timeout after '
          '${_plannerStreamOverallTimeout.inMilliseconds}ms',
        );
      },
    );
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
      allowReasoning: true,
      cache: _defaultCacheOptionsFor(apiStyle),
    );
  }

  LlmCacheRequestOptions _defaultCacheOptionsFor(ApiStyle apiStyle) {
    switch (apiStyle) {
      case ApiStyle.responses:
      case ApiStyle.chatCompletions:
        return const LlmCacheRequestOptions(
          strategy: LlmCacheStrategy.providerHints,
          retention: 'in-memory',
        );
      case ApiStyle.anthropicMessages:
        return const LlmCacheRequestOptions(
          strategy: LlmCacheStrategy.providerHints,
          markStableSystemPrefix: true,
        );
    }
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

  _RequestTraceContext _requestTraceContext({
    required String label,
    required ApiStyle apiStyle,
    required String modelName,
    required LlmRequestPurpose purpose,
    required LlmRequestOptions requestOptions,
    required int messageCount,
    required List<ChatMessage> messages,
  }) {
    return _RequestTraceContext(
      label: label,
      apiStyle: apiStyle,
      modelName: modelName,
      purpose: purpose,
      estimatedInputTokens: _estimateInputTokens(messages),
      messageCount: messageCount,
      cacheStrategy: requestOptions.cache.strategy,
      cacheKey: requestOptions.cache.cacheKey,
      cacheRetention: requestOptions.cache.retention,
      markStableSystemPrefix: requestOptions.cache.markStableSystemPrefix,
      startedAt: DateTime.now(),
    );
  }

  int _estimateInputTokens(List<ChatMessage> messages) {
    return messages.fold<int>(
      0,
      (total, message) => total + _estimateTextTokens(message.text),
    );
  }

  int _estimateTextTokens(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return 0;
    }
    return trimmed.runes.fold<int>(
      0,
      (total, rune) => total + (rune > 127 ? 2 : 1),
    );
  }

  int _payloadBytes(Map<String, dynamic> payload) {
    return utf8.encode(jsonEncode(payload)).length;
  }

  void _emitRequestStart(
    _RequestTraceContext context,
    Map<String, dynamic> payload,
  ) {
    _traceEmitter(
      _tag,
      'llm.request.start',
      data: {
        'label': context.label,
        'apiStyle': context.apiStyle.name,
        'model': context.modelName,
        'purpose': context.purpose.name,
        'estimatedInputTokens': context.estimatedInputTokens,
        'messageCount': context.messageCount,
        'payloadBytes': _payloadBytes(payload),
        'cacheStrategy': context.cacheStrategy.name,
        'cacheKeyPresent': context.cacheKey != null && context.cacheKey!.isNotEmpty,
        if ((context.cacheRetention ?? '').isNotEmpty)
          'cacheRetention': context.cacheRetention,
        if (context.markStableSystemPrefix) 'markStableSystemPrefix': true,
      },
    );
  }

  void _emitFirstChunk(
    _RequestTraceContext context, {
    required int firstChunkMs,
  }) {
    _traceEmitter(
      _tag,
      'llm.first_chunk',
      data: {
        'label': context.label,
        'apiStyle': context.apiStyle.name,
        'model': context.modelName,
        'purpose': context.purpose.name,
        'firstChunkMs': firstChunkMs,
        'cacheStrategy': context.cacheStrategy.name,
      },
    );
  }

  void _emitRequestDone(
    _RequestTraceContext context, {
    required int totalMs,
    required int payloadBytes,
    int? firstChunkMs,
    LlmCacheUsage? cacheUsage,
  }) {
    _traceEmitter(
      _tag,
      'llm.request.done',
      data: {
        'label': context.label,
        'apiStyle': context.apiStyle.name,
        'model': context.modelName,
        'purpose': context.purpose.name,
        'estimatedInputTokens': context.estimatedInputTokens,
        'messageCount': context.messageCount,
        'payloadBytes': payloadBytes,
        'firstChunkMs': firstChunkMs,
        'totalMs': totalMs,
        'cacheStrategy': context.cacheStrategy.name,
        if (cacheUsage != null) 'inputTokens': cacheUsage.inputTokens,
        if (cacheUsage != null) 'outputTokens': cacheUsage.outputTokens,
        if (cacheUsage != null) 'cachedInputTokens': cacheUsage.cachedInputTokens,
        if (cacheUsage != null)
          'cacheReadInputTokens': cacheUsage.cacheReadInputTokens,
        if (cacheUsage != null)
          'cacheWriteInputTokens': cacheUsage.cacheWriteInputTokens,
        if (cacheUsage != null)
          'cacheMissInputTokens': cacheUsage.cacheMissInputTokens,
        if (cacheUsage != null) 'usageKeys': cacheUsage.rawUsage.keys.toList(),
        if (cacheUsage != null && cacheUsage.rawUsage.isNotEmpty)
          'rawUsage': cacheUsage.rawUsage,
      },
    );
  }

  int _elapsedMilliseconds(DateTime startedAt) {
    return DateTime.now().difference(startedAt).inMilliseconds;
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
    final purpose = switch (requestLabel) {
      'side_summary' => LlmRequestPurpose.summary,
      'side_webpage' => LlmRequestPurpose.webpageProcessing,
      _ => LlmRequestPurpose.sideTask,
    };
    final requestOptions = adapter.normalizeRequestOptions(
      _requestOptionsFor(
        modelName: modelName,
        purpose: purpose,
        apiStyle: apiStyle,
      ),
      purpose: purpose,
    );
    final traceContext = _requestTraceContext(
      label: requestLabel,
      apiStyle: apiStyle,
      modelName: modelName,
      purpose: purpose,
      requestOptions: requestOptions,
      messageCount: messages.length,
      messages: messages,
    );
    // Side-model tasks (summary / webpage processing) have no provider
    // round-trip history — every message is our-side synthetic. Wrap as
    // SyntheticCarrier and use the unified carrier-based payload builder.
    final sideCarriers = <PlannerContextCarrier>[
      for (final m in messages)
        if (m.text.trim().isNotEmpty)
          switch (m.role) {
            MessageRole.system => SyntheticCarrier.system(m.text),
            MessageRole.user => SyntheticCarrier.user(m.text),
            MessageRole.assistant => SyntheticCarrier.user(m.text),
          },
    ];
    final payload = adapter.buildPlannerPayloadFromCarriers(
      carriers: sideCarriers,
      config: config,
      modelName: modelName,
      availableTools: const [],
      parallelToolCalls: false,
      requestOptions: requestOptions,
    );
    final requestSpec = adapter.buildPlannerRequestSpecFromCarriers(
      carriers: sideCarriers,
      config: config,
      modelName: modelName,
      availableTools: const [],
      parallelToolCalls: false,
      runtimeConfig: runtimeConfig,
      requestOptions: requestOptions,
    );
    _emitRequestStart(traceContext, payload);
    Logger.i(_tag, '$requestLabel 请求体: ${jsonEncode(payload)}');
    final execution = await _performRetriableMainFlowRequest(
      label: requestLabel,
      operation: () => _runtimeRegistry.runtimeFor(apiStyle).execute(
            requestSpec: requestSpec,
            runtimeConfig: runtimeConfig,
            timeout: effectiveTimeout,
          ),
    );
    final decoded = execution.rawResponseJson;
    final decision = adapter.parseDecision(decoded);
    _emitRequestDone(
      traceContext,
      totalMs: _elapsedMilliseconds(traceContext.startedAt),
      payloadBytes: _payloadBytes(payload),
      cacheUsage: execution.cacheUsage ?? LlmUsageExtractor.extract(decoded),
    );
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

  String _summarizeStreamingPlannerAttempt(Map<String, dynamic>? snapshot) {
    if (snapshot == null || snapshot.isEmpty) {
      return 'no_snapshot';
    }
    final toolDrafts = snapshot['toolDrafts'];
    final toolDraftSummary = toolDrafts is List
        ? toolDrafts
            .whereType<Map>()
            .map(
              (draft) =>
                  '#${draft['sequence']}'
                  ':name=${draft['toolName'] ?? '-'}'
                  ':id=${draft['providerCallId'] ?? '-'}'
                  ':done=${draft['isCompleted'] == true}'
                  ':argsLen=${draft['rawArgumentsLength'] ?? 0}',
            )
            .join('|')
        : '';
    return 'assistantLen=${snapshot['assistantTextLength'] ?? 0} '
        'reasoningLen=${snapshot['reasoningLength'] ?? 0} '
        'providerKeys=${snapshot['providerStateKeys'] ?? const []} '
        'toolDrafts=${toolDraftSummary.isEmpty ? '[]' : '[$toolDraftSummary]'}';
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

        final delay = _retryDelayBuilder(attempt);
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

  static Duration _defaultRetryDelayForAttempt(int attempt) {
    final backoffSeconds = switch (attempt) {
      1 => 1,
      2 => 2,
      3 => 4,
      4 => 8,
      _ => 12,
    };
    return Duration(seconds: backoffSeconds);
  }

  static Duration _resolveDefaultPlannerStreamOverallTimeout(
    Duration idleTimeout,
  ) {
    final tripled = Duration(milliseconds: idleTimeout.inMilliseconds * 3);
    if (tripled > _defaultPlannerStreamOverallTimeout) {
      return tripled;
    }
    return _defaultPlannerStreamOverallTimeout;
  }

  Map<String, dynamic> _requestSpecToJsonMap(ProtocolRequestSpec requestSpec) {
    switch (requestSpec) {
      case JsonProtocolRequestSpec(:final payload):
        return payload;
      case ChatCompletionsRequestSpec(:final request):
        return request.toJson();
      case ResponsesRequestSpec(:final request):
        return request.toJson();
      case AnthropicMessagesRequestSpec(:final request):
        return request.toJson();
    }
  }

  Map<String, dynamic>? _buildStreamingPreviewIdentity(
    StreamingDecisionAccumulatorSnapshot snapshot,
  ) {
    final messageId = snapshot.messageId?.trim();
    if (messageId == null || messageId.isEmpty) {
      return null;
    }
    String? reasoningBlockId;
    String? textBlockId;
    for (final block in snapshot.blocks) {
      if (block.type == StreamingContentBlockType.thinking &&
          block.text.trim().isNotEmpty) {
        reasoningBlockId ??= block.contentBlockId;
      } else if (block.type == StreamingContentBlockType.text &&
          block.text.trim().isNotEmpty) {
        textBlockId ??= block.contentBlockId;
      }
    }
    if (reasoningBlockId == null && textBlockId == null) {
      return null;
    }
    return {
      'messageId': messageId,
      if (reasoningBlockId != null) 'reasoningBlockId': reasoningBlockId,
      if (textBlockId != null) 'textBlockId': textBlockId,
    };
  }
}

class _StreamingPlannerAttemptResult {
  const _StreamingPlannerAttemptResult.completed(
    this.decision, {
    this.debugSnapshot,
  });

  final ModelTurnDecision? decision;
  final Map<String, dynamic>? debugSnapshot;
}

class _RequestTraceContext {
  final String label;
  final ApiStyle apiStyle;
  final String modelName;
  final LlmRequestPurpose purpose;
  final int estimatedInputTokens;
  final int messageCount;
  final LlmCacheStrategy cacheStrategy;
  final String? cacheKey;
  final String? cacheRetention;
  final bool markStableSystemPrefix;
  final DateTime startedAt;

  const _RequestTraceContext({
    required this.label,
    required this.apiStyle,
    required this.modelName,
    required this.purpose,
    required this.estimatedInputTokens,
    required this.messageCount,
    required this.cacheStrategy,
    required this.cacheKey,
    required this.cacheRetention,
    required this.markStableSystemPrefix,
    required this.startedAt,
  });
}
