import 'dart:io';

import 'package:ai_chat/database/database_helper.dart';
import 'package:ai_chat/models/agent/chat_turn_step.dart';
import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/debug/debug_cache_panel_projection.dart';
import 'package:ai_chat/models/interaction/ask_user_question_request.dart';
import 'package:ai_chat/models/interaction/ask_user_question_response.dart';
import 'package:ai_chat/models/llm/api_protocol_resolver.dart';
import 'package:ai_chat/models/llm/llm_factory.dart';
import 'package:ai_chat/models/llm/llm_provider_config.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/repositories/chat_event_repository.dart';
import 'package:ai_chat/repositories/chat_turn_repository.dart';
import 'package:ai_chat/repositories/session_context_snapshot_repository.dart';
import 'package:ai_chat/repositories/chat_turn_step_repository.dart';
import 'package:ai_chat/services/file_tools/file_tool_budget_service.dart';
import 'package:ai_chat/services/file_tools/file_tool_discovery_service.dart';
import 'package:ai_chat/services/file_tools/file_tool_host_adapters.dart';
import 'package:ai_chat/services/file_tools/file_tool_path_policy.dart';
import 'package:ai_chat/services/file_tools/file_tool_read_formatter.dart';
import 'package:ai_chat/services/file_tools/file_tool_root_service.dart';
import 'package:ai_chat/services/file_tools/file_tool_session_guard.dart';
import 'package:ai_chat/services/file_tools/file_tool_write_service.dart';
import 'package:ai_chat/services/agent_planner_service.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/chat_trace_recorder.dart';
import 'package:ai_chat/services/default_tool_adapters.dart';
import 'package:ai_chat/services/debug/llm_cache_stats_service.dart';
import 'package:ai_chat/services/model_budget_registry.dart';
import 'package:ai_chat/services/session_context_projector.dart';
import 'package:ai_chat/services/session_context_service.dart';
import 'package:ai_chat/services/session_summary_service.dart';
import 'package:ai_chat/services/session_token_budget_service.dart';
import 'package:ai_chat/services/tool_call_service.dart';
import 'package:ai_chat/services/tool_executor.dart';
import 'package:ai_chat/services/tool_policy_service.dart';
import 'package:ai_chat/services/transcript_builder_service.dart';
import 'package:ai_chat/services/turn_harness.dart';
import 'package:ai_chat/services/turn_verifier.dart';
import 'package:ai_chat/tools/adapters/tool_host_adapters.dart';
import 'package:ai_chat/tools/default_tool_runtime_registry.dart';
import 'package:ai_chat/utils/logger.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'chat_send_live_assertions.dart';
import 'chat_send_live_fixture_builder.dart';
import 'chat_send_live_scenario.dart';
import '../../test_utils/local_test_provider_selector.dart';

int _chatSendLiveDatabaseCounter = 0;

class ChatSendLiveTestHarness {
  final ProviderContainer container;
  final DatabaseHelper databaseHelper;
  final AppSettingsRepository settingsRepository;
  final ChatService chatService;
  final String databasePath;
  final ChatSendLiveFixtureBuilder fixtureBuilder;
  final Directory workspaceRoot;
  final ChatTurnProviderStyle activeProviderStyle;
  final HeadlessLiveProviderProfile providerProfile;
  final List<Directory> _workspaceRoots;

  ChatSendLiveTestHarness._({
    required this.container,
    required this.databaseHelper,
    required this.settingsRepository,
    required this.chatService,
    required this.databasePath,
    required this.fixtureBuilder,
    required this.workspaceRoot,
    required this.activeProviderStyle,
    required this.providerProfile,
    required List<Directory> workspaceRoots,
  }) : _workspaceRoots = workspaceRoots;

  static Future<ChatSendLiveTestHarness> bootstrap({
    String? providerId,
    ChatTurnProviderStyle? providerStyle,
  }) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    WidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final localDefaults = loadInjectedLocalDefaults();
    final settingsRepository = AppSettingsRepository(
      preferences,
      localDefaultsLoader: () async => localDefaults,
    );
    if (localDefaults != null) {
      for (final provider in localDefaults.providers) {
        await settingsRepository.saveProvider(provider);
      }
      final defaultProviderId = localDefaults.defaultProviderId;
      LlmProviderConfig? defaultProvider;
      if (defaultProviderId == null) {
        if (localDefaults.providers.isNotEmpty) {
          defaultProvider = localDefaults.providers.first;
        }
      } else {
        for (final provider in localDefaults.providers) {
          if (provider.id == defaultProviderId) {
            defaultProvider = provider;
            break;
          }
        }
      }
      if (defaultProvider != null) {
        final defaultModelId =
            localDefaults.defaultModelId ?? defaultProvider.models.first.id;
        await settingsRepository.setDefaultProviderAndModel(
          providerId: defaultProvider.id,
          modelId: defaultModelId,
        );
        await settingsRepository.selectProviderAndModel(
          providerId: defaultProvider.id,
          modelId: defaultModelId,
        );
      }
    }
    LlmProviderConfig? selectedProvider;
    String? selectionReason;
    if (providerId != null) {
      final provider = await settingsRepository.getProviderById(providerId);
      if (provider == null) {
        throw StateError('Unknown provider id: $providerId');
      }
      selectedProvider = provider;
      selectionReason = 'selected from explicit provider id';
    } else if (providerStyle != null && localDefaults != null) {
      final selection = selectHeadlessLiveProvider(
        defaults: localDefaults,
        style: providerStyle,
      );
      selectedProvider = selection.provider;
      selectionReason = selection.selectionReason;
    }
    if (selectedProvider != null) {
      await settingsRepository.selectProviderAndModel(
        providerId: selectedProvider.id,
        modelId: selectedProvider.models.first.id,
      );
      debugPrint(
        'Headless live provider selected: ${selectedProvider.id}'
        '${selectionReason == null ? '' : ' ($selectionReason)'}',
      );
    }
    final activeProviderStyle =
        providerStyle ??
        (selectedProvider == null
            ? ChatTurnProviderStyle.openaiChatCompletions
            : ApiProtocolResolver()
                .resolveStyle(selectedProvider.baseUrl)
                .toChatTurnProviderStyle());
    final providerProfile =
        selectedProvider == null
            ? const HeadlessLiveProviderProfile(
                askUserInteraction: StructuredCheckpointExpectation.required,
                toolConfirmation: StructuredCheckpointExpectation.required,
                multiToolContinuation:
                    StructuredCheckpointExpectation.required,
              )
            : resolveHeadlessLiveProviderProfile(selectedProvider.id);

    _chatSendLiveDatabaseCounter += 1;
    final databaseName =
        'chat_send_live_${DateTime.now().microsecondsSinceEpoch}_'
        '$_chatSendLiveDatabaseCounter.db';
    final databaseHelper = DatabaseHelper(databaseName: databaseName);
    await databaseHelper.testDatabaseConnection();

    final traceRecorder = ChatTraceRecorder();
    final llm = LLMFactory.createLLM(
      LLMType.configurable,
      settingsRepository: settingsRepository,
    );
    final fixtureBuilder = ChatSendLiveFixtureBuilder();
    final workspaceRoot = await fixtureBuilder.createWorkspaceRoot(
      scenarioId: 'tool_sandbox',
    );
    final fileToolAdapters =
        await _buildTestFileToolHostAdapters(workspaceRoot);
    final toolExecutor = ToolExecutor(
      chatStorage: databaseHelper,
      webSearcher: ({
        required query,
        maxResults,
      }) async {
        final config = await settingsRepository.getLlmConfig();
        final provider =
            (config.additionalConfig['web_search.provider'] as String?)
                    ?.trim() ??
                'tavily';
        if (provider != 'tavily') {
          return ToolResult(
            toolName: 'web_search',
            status: ToolExecutionStatus.failure,
            summary: '联网搜索失败',
            data: {
              'query': query,
              'provider': provider,
              'reason': 'unsupported_provider',
            },
            errorMessage: 'unsupported_provider',
          );
        }
        final tavilyWebSearcher = buildTavilyWebSearcher();
        return tavilyWebSearcher(
          query: query,
          maxResults: maxResults,
          apiKey:
              config.additionalConfig['web_search.tavily_api_key'] as String?,
          baseUrl:
              config.additionalConfig['web_search.tavily_base_url'] as String?,
        );
      },
      webpageFetcher: buildDefaultWebpageFetcher(sideModelLlm: llm),
      reminderCreator: buildDefaultReminderCreator(),
      calendarEventCreator: buildDefaultCalendarEventCreator(),
      resultSharer: buildDefaultResultSharer(),
    );
    final runtimeRegistry = buildDefaultToolRuntimeRegistry(
      toolExecutor: toolExecutor,
    );
    final toolPolicyService = ToolPolicyService(
      repository: settingsRepository,
    );
    final toolCallService = ToolCallService(
      runtimeRegistry: runtimeRegistry,
      traceRecorder: traceRecorder,
      toolExecutor: toolExecutor,
      toolPolicyService: toolPolicyService,
      hostAdapters: ToolHostAdapters(fileTools: fileToolAdapters),
    );
    final chatService = ChatService(
      llm: llm,
      toolCallService: toolCallService,
    );
    final turnRepository = ChatTurnRepository(databaseHelper);
    final turnStepRepository = ChatTurnStepRepository(databaseHelper);
    final eventRepository = ChatEventRepository(databaseHelper);
    final sessionContextService = SessionContextService(
      chatTurnRepository: turnRepository,
      chatEventRepository: eventRepository,
      snapshotRepository: SessionContextSnapshotRepository(databaseHelper),
      chatStorage: databaseHelper,
      contextProjector: SessionContextProjector(),
      tokenBudgetService: SessionTokenBudgetService(
        modelBudgetRegistry: ModelBudgetRegistry(),
      ),
      summaryService: SessionSummaryService(chatService: chatService),
      chatService: chatService,
    );
    final turnHarness = TurnHarness(
      plannerService: AgentPlannerService(
        llm: llm,
        toolPolicyService: toolPolicyService,
        availableTools: runtimeRegistry.getDefinitionsForPlatform('android'),
      ),
      turnRepository: turnRepository,
      turnStepRepository: turnStepRepository,
      eventRepository: eventRepository,
      transcriptBuilderService: TranscriptBuilderService(
        eventRepository: eventRepository,
      ),
      turnVerifier: TurnVerifier(),
      toolCallService: toolCallService,
      chatStorage: databaseHelper,
      sessionContextService: sessionContextService,
    );

    final container = ProviderContainer(
      overrides: [
        appSettingsRepositoryProvider.overrideWithValue(settingsRepository),
        databaseProvider.overrideWith((ref) => databaseHelper),
        traceRecorderProvider.overrideWithValue(traceRecorder),
        chatServiceFactoryProvider.overrideWithValue(chatService),
        turnHarnessProvider.overrideWithValue(turnHarness),
        scrollControllerProvider.overrideWith((ref) => ScrollController()),
        textControllerProvider.overrideWith((ref) => TextEditingController()),
        focusNodeProvider.overrideWith((ref) => FocusNode()),
      ],
    );

    return ChatSendLiveTestHarness._(
      container: container,
      databaseHelper: databaseHelper,
      settingsRepository: settingsRepository,
      chatService: chatService,
      databasePath: databaseName,
      fixtureBuilder: fixtureBuilder,
      workspaceRoot: workspaceRoot,
      activeProviderStyle: activeProviderStyle,
      providerProfile: providerProfile,
      workspaceRoots: <Directory>[workspaceRoot],
    );
  }

  Future<void> sendUserMessage(String text) async {
    await _ensureActiveGroup();
    await container.read(chatSendCoordinatorProvider).sendMessage(
          text,
          scheduleAutoSummary: () {},
          cancelActiveStream:
              container.read(chatControllerProvider).cancelStreamSubscription,
        );
  }

  Future<List<ChatMessage>> listMessages() async {
    final group = container.read(currentGroupProvider);
    if (group?.id == null) {
      return const [];
    }
    return databaseHelper.getMessagesByGroup(group!.id!);
  }

  Future<List<ChatTurn>> listTurns() async {
    final group = container.read(currentGroupProvider);
    if (group?.id == null) {
      return const [];
    }
    return ChatTurnRepository(databaseHelper).getTurnsByGroup(group!.id!);
  }

  Future<ChatSendLiveStateSnapshot> snapshotState() async {
    final group = container.read(currentGroupProvider);
    final groupId = group?.id;
    if (groupId == null) {
      return const ChatSendLiveStateSnapshot(
        groupId: null,
        messages: <ChatMessage>[],
        turns: <ChatTurn>[],
        steps: [],
        events: [],
      );
    }

    final messages = await databaseHelper.getMessagesByGroup(groupId);
    final turns = await ChatTurnRepository(databaseHelper).getTurnsByGroup(
      groupId,
    );
    final latestTurn = turns.isEmpty ? null : turns.last;
    final List<ChatTurnStep> steps = latestTurn == null
        ? const <ChatTurnStep>[]
        : await ChatTurnStepRepository(databaseHelper)
            .listSteps(latestTurn.id!);
    final List<ChatEvent> events = latestTurn == null
        ? const <ChatEvent>[]
        : await ChatEventRepository(databaseHelper).listEventsByTurn(
            latestTurn.id!,
          );
    return ChatSendLiveStateSnapshot(
      groupId: groupId,
      messages: messages,
      turns: turns,
      steps: steps,
      events: events,
    );
  }

  Future<Directory> prepareWorkspaceFixture({
    required String scenarioId,
    Map<String, String> files = const {},
  }) async {
    await fixtureBuilder.populateWorkspace(
      root: workspaceRoot,
      files: files,
    );
    return workspaceRoot;
  }

  Future<void> runScenario(ScenarioCase scenario) async {
    await sendUserMessage(scenario.userMessage);
  }

  Future<ChatSendLiveAutoRunResult> runScenarioWithAutoContinuation(
    ScenarioCase scenario, {
    int maxContinuations = 4,
    bool autoConfirmTools = true,
  }) async {
    await runScenario(scenario);
    return autoContinueCurrentTurn(
      maxContinuations: maxContinuations,
      autoConfirmTools: autoConfirmTools,
    );
  }

  Future<ChatSendLiveAutoRunResult> autoContinueCurrentTurn({
    int maxContinuations = 4,
    bool autoConfirmTools = true,
  }) async {
    final checkpoints = <ChatSendLiveStateSnapshot>[];
    for (var continuation = 0; continuation <= maxContinuations; continuation += 1) {
      final state = await snapshotState();
      checkpoints.add(state);
      final status = state.latestTurn?.status;
      if (status == null ||
          status == ChatTurnStatus.completed ||
          status == ChatTurnStatus.failed ||
          status == ChatTurnStatus.cancelled ||
          status == ChatTurnStatus.maxIterationsReached) {
        return ChatSendLiveAutoRunResult(checkpoints: checkpoints);
      }

      if (status == ChatTurnStatus.awaitingUserInteraction) {
        final promptMessage = activeAskUserQuestionMessage();
        if (promptMessage == null) {
          throw StateError(
            'Turn is awaiting user interaction but no active question message exists.',
          );
        }
        await submitQuestionAnswers(
          message: promptMessage,
          response: _buildFirstOptionResponse(promptMessage),
        );
        continue;
      }

      if (status == ChatTurnStatus.awaitingToolConfirmation) {
        if (!autoConfirmTools) {
          return ChatSendLiveAutoRunResult(checkpoints: checkpoints);
        }
        final pendingConfirmation = activePendingToolConfirmation();
        if (pendingConfirmation == null) {
          throw StateError(
            'Turn is awaiting tool confirmation but no pending confirmation exists.',
          );
        }
        await confirmToolInvocation(
          message: pendingConfirmation.message,
          trustTool: true,
        );
        continue;
      }

      throw StateError('Unsupported live auto-continuation status: $status');
    }

    return ChatSendLiveAutoRunResult(checkpoints: checkpoints);
  }

  ChatMessage? activeAskUserQuestionMessage() {
    return container.read(activeAskUserQuestionMessageProvider);
  }

  PendingToolConfirmation? activePendingToolConfirmation() {
    return container.read(activePendingToolConfirmationProvider);
  }

  Future<void> submitQuestionAnswers({
    required ChatMessage message,
    required AskUserQuestionResponse response,
  }) async {
    await container.read(chatSendCoordinatorProvider).submitQuestionAnswers(
          message,
          response: response,
        );
  }

  Future<void> confirmToolInvocation({
    required ChatMessage message,
    bool trustTool = true,
  }) async {
    await container.read(chatSendCoordinatorProvider).confirmToolInvocation(
          message,
          trustTool: trustTool,
        );
  }

  bool workspaceFileExists(String relativePath) {
    return File(path.join(workspaceRoot.path, relativePath)).existsSync();
  }

  Future<String> readWorkspaceFile(String relativePath) {
    return File(path.join(workspaceRoot.path, relativePath)).readAsString();
  }

  Future<String> summarizeMessages(List<ChatMessage> messages) {
    return chatService.llm.summarizeConversation(messages);
  }

  Future<void> clearLogFile() async {
    final logFilePath = Logger.logFilePath;
    if (logFilePath == null || logFilePath.trim().isEmpty) {
      return;
    }
    final file = File(logFilePath);
    if (!file.existsSync()) {
      return;
    }
    await file.writeAsString('');
  }

  Future<DebugCachePanelProjection> readRecentCacheStats({
    int sampleSize = 100,
  }) {
    return LlmCacheStatsService().readRecentStats(sampleSize: sampleSize);
  }

  Future<String> readLogFileText() async {
    final logFilePath = Logger.logFilePath;
    if (logFilePath == null || logFilePath.trim().isEmpty) {
      return '';
    }
    final file = File(logFilePath);
    if (!file.existsSync()) {
      return '';
    }
    return file.readAsString();
  }

  Future<void> dispose() async {
    container.dispose();
    for (final workspaceRoot in _workspaceRoots.reversed) {
      if (workspaceRoot.existsSync()) {
        await workspaceRoot.delete(recursive: true);
      }
    }
  }

  Future<void> _ensureActiveGroup() async {
    final currentGroup = container.read(currentGroupProvider);
    if (currentGroup?.id != null) {
      return;
    }
    final groupId = await databaseHelper.insertGroup(
      ChatGroup(
        title: 'Headless Live Test',
        lockedProviderStyle: activeProviderStyle,
      ),
    );
    container.read(currentGroupProvider.notifier).state = ChatGroup(
      id: groupId,
      title: 'Headless Live Test',
      lockedProviderStyle: activeProviderStyle,
    );
  }

  AskUserQuestionResponse _buildFirstOptionResponse(ChatMessage message) {
    final payload = message.payloadJson;
    if (payload == null) {
      throw StateError('Ask-user prompt message is missing payloadJson.');
    }
    final request = AskUserQuestionRequest.fromJson(payload);
    final answersByQuestionId = <String, String>{};
    final selectedOptionLabelsByQuestionId = <String, List<String>>{};

    for (final question in request.questions) {
      final firstOption = question.options.firstOrNull;
      if (firstOption == null) {
        throw StateError(
          'Question ${question.id} has no selectable options for auto continuation.',
        );
      }
      answersByQuestionId[question.id] = firstOption.label;
      selectedOptionLabelsByQuestionId[question.id] = [firstOption.label];
    }

    return AskUserQuestionResponse(
      answersByQuestionId: answersByQuestionId,
      selectedOptionLabelsByQuestionId: selectedOptionLabelsByQuestionId,
      freeTextAnswersByQuestionId: const {},
    );
  }
}

class ChatSendLiveAutoRunResult {
  final List<ChatSendLiveStateSnapshot> checkpoints;

  const ChatSendLiveAutoRunResult({
    required this.checkpoints,
  });

  ChatSendLiveStateSnapshot get finalState => checkpoints.last;

  ChatSendLiveStateSnapshot? get firstAwaitingUserInteractionState {
    for (final state in checkpoints) {
      if (state.latestTurn?.status == ChatTurnStatus.awaitingUserInteraction) {
        return state;
      }
    }
    return null;
  }

  ChatSendLiveStateSnapshot? get firstAwaitingToolConfirmationState {
    for (final state in checkpoints) {
      if (state.latestTurn?.status == ChatTurnStatus.awaitingToolConfirmation) {
        return state;
      }
    }
    return null;
  }
}

Future<FileToolHostAdapters> _buildTestFileToolHostAdapters(
  Directory workspaceRoot,
) async {
  final rootService = FileToolRootService(rootDirectory: workspaceRoot);
  await rootService.ensureReady();
  await rootService.resolveDirectory('memories').create(recursive: true);
  await rootService.resolveDirectory('artifacts').create(recursive: true);
  await rootService.resolveDirectory('tmp').create(recursive: true);

  final pathPolicy = FileToolPathPolicy(rootService: rootService);
  final sessionGuard = FileToolSessionGuard();
  const budgetService = FileToolBudgetService();
  const readFormatter = FileToolReadFormatter();
  final discoveryService = FileToolDiscoveryService(
    rootService: rootService,
    pathPolicy: pathPolicy,
    budgetService: budgetService,
  );
  final writeService = FileToolWriteService(
    rootService: rootService,
    sessionGuard: sessionGuard,
  );

  return FileToolHostAdapters(
    rootService: rootService,
    pathPolicy: pathPolicy,
    sessionGuard: sessionGuard,
    budgetService: budgetService,
    readFormatter: readFormatter,
    discoveryService: discoveryService,
    writeService: writeService,
  );
}
