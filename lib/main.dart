import 'dart:async';
import 'dart:io';

import 'package:ai_chat/bootstrap/app_bootstrap_scope.dart';
import 'package:ai_chat/bootstrap/app_runtime.dart';
import 'package:ai_chat/bootstrap/bootstrap_startup_probe.dart';
import 'package:ai_chat/constants/route_constant.dart';
import 'package:ai_chat/pages/component_motion_debug_page.dart';
import 'package:ai_chat/pages/debug_hub_page.dart';
import 'package:ai_chat/pages/layout_debug_page.dart';
import 'package:ai_chat/pages/webview_debug_page.dart';
import 'package:ai_chat/pages/test_page.dart';
import 'package:ai_chat/pages/chat_page.dart';
import 'package:ai_chat/pages/settings_page.dart';
import 'package:ai_chat/models/llm/llm_factory.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/repositories/artifact_repository.dart';
import 'package:ai_chat/repositories/chat_event_repository.dart';
import 'package:ai_chat/repositories/chat_turn_repository.dart';
import 'package:ai_chat/repositories/chat_turn_step_repository.dart';
import 'package:ai_chat/repositories/session_context_snapshot_repository.dart';
import 'package:ai_chat/storage/chat_storage.dart';
import 'package:ai_chat/storage/chat_storage_factory.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/theme/app_theme_controller.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/utils/logger.dart';
import 'package:ai_chat/services/agent_planner_service.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/chat_trace_recorder.dart';
import 'package:ai_chat/services/default_file_tool_adapters.dart';
import 'package:ai_chat/services/default_tool_adapters.dart';
import 'package:ai_chat/services/follow_up_dispatch_queue.dart';
import 'package:ai_chat/services/model_budget_registry.dart';
import 'package:ai_chat/services/model_capability_resolver.dart';
import 'package:ai_chat/services/model_capability_sources/anthropic_model_capability_source.dart';
import 'package:ai_chat/services/model_capability_sources/catalog_model_capability_source.dart';
import 'package:ai_chat/services/model_capability_sources/gemini_model_capability_source.dart';
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
import 'package:ai_chat/services/workspace/workspace_runtime_service.dart';
import 'package:ai_chat/services/workspace/workspace_tool_host_adapters.dart';
import 'package:ai_chat/services/attachments/chat_attachment_storage_service.dart';
import 'package:ai_chat/services/attachments/image_picker_chat_attachment_picker_service.dart';
import 'package:ai_chat/services/artifact/artifact_file_storage_service.dart';
import 'package:ai_chat/services/skills/github_skill_fetcher.dart';
import 'package:ai_chat/services/skills/github_skill_source_resolver.dart';
import 'package:ai_chat/services/skills/skill_index_service.dart';
import 'package:ai_chat/services/skills/skill_installer_service.dart';
import 'package:ai_chat/services/skills/skill_runtime_service.dart';
import 'package:ai_chat/services/skills/skill_storage_service.dart';
import 'package:ai_chat/tools/adapters/tool_host_adapters.dart';
import 'package:ai_chat/tools/default_tool_runtime_registry.dart';
import 'package:ai_chat/tools/handlers/create_artifact_guideline_tool_handler.dart';
import 'package:ai_chat/tools/handlers/create_artifact_tool_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final startupProbe = BootstrapStartupProbe()..mark('bootstrap.start');
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );

  runApp(
    AppBootstrapScope<AppRuntime>(
      initializeRuntime: _initializeRuntime,
      startupProbe: startupProbe,
      child: const _RootApp(),
    ),
  );
}

Future<AppRuntime> _initializeRuntime() async {
  await Logger.initialize();
  final preferences = await SharedPreferences.getInstance();
  final settingsRepository = AppSettingsRepository(preferences);
  final storage = _createChatStorage(preferences);
  await storage.testDatabaseConnection();
  final chatCompletionsAdapterType =
      await settingsRepository.getChatCompletionsAdapterType();
  final modelBudgetRegistry = ModelBudgetRegistry();
  final modelCapabilityResolver = ModelCapabilityResolver(
    settingsRepository: settingsRepository,
    budgetRegistry: modelBudgetRegistry,
    providerSources: [
      AnthropicModelCapabilitySource(),
      GeminiModelCapabilitySource(),
    ],
    catalogSource: CatalogModelCapabilitySource(),
  );
  final llm = LLMFactory.createLLM(
    LLMType.configurable,
    settingsRepository: settingsRepository,
    chatCompletionsAdapterType: chatCompletionsAdapterType,
    modelCapabilityResolver: modelCapabilityResolver,
  );
  final fileToolAdapters = await buildDefaultFileToolHostAdapters();
  final appSupportDirectory = await getApplicationSupportDirectory();
  final agentRootDirectory = Directory(
    path.join(appSupportDirectory.path, 'agent'),
  );
  final artifactFileStorageService = ArtifactFileStorageService(
    rootDirectory: agentRootDirectory,
    workspaceIdResolver: (groupId) async {
      return (await storage.getGroupById(groupId))?.workspaceId;
    },
  );
  final skillStorageService = SkillStorageService(
    rootDirectoryProvider: () async => agentRootDirectory,
  );
  const gitHubSkillSourceResolver = GitHubSkillSourceResolver();
  final gitHubSkillFetcher = GitHubSkillFetcher();
  final skillIndexService = SkillIndexService(
    storageService: skillStorageService,
  );
  final skillRuntimeService = SkillRuntimeService(
    storageService: skillStorageService,
    settingsRepository: settingsRepository,
    indexService: skillIndexService,
  );
  final skillInstallerService = SkillInstallerService(
    storageService: skillStorageService,
    sourceResolver: gitHubSkillSourceResolver,
    fetcher: gitHubSkillFetcher,
  );
  await artifactFileStorageService.ensureReady();
  final artifactRepository = ArtifactRepository(storage);
  final createArtifactGuidelineHandler = CreateArtifactGuidelineToolHandler(
    activeThemeSpecProvider: () {
      final storedThemeId = settingsRepository.getThemeIdSync();
      return AppThemeSpec.resolveById(storedThemeId ?? '') ??
          AppThemeSpec.claude();
    },
  );
  final createArtifactHandler = CreateArtifactToolHandler(
    artifactRepository: artifactRepository,
    fileStorageService: artifactFileStorageService,
  );
  late final ProviderContainer container;
  final chatAttachmentPickerService = ImagePickerChatAttachmentPickerService();
  final chatAttachmentStorageService = ChatAttachmentStorageService(
    resolveRootDirectory: () async => agentRootDirectory,
    resolveWorkspaceId: () async {
      return container.read(currentGroupProvider)?.workspaceId;
    },
  );
  final runtimeAwareWorkspaceService = WorkspaceRuntimeService(
    storage: storage,
    currentGroupReader: () => container.read(currentGroupProvider),
    currentGroupWriter: (group) {
      container.read(currentGroupProvider.notifier).state = group;
    },
    groupsReader: () => container.read(groupsProvider),
    groupsWriter: (groups) {
      container.read(groupsProvider.notifier).setGroups(groups);
    },
  );
  final tavilyWebSearcher = buildTavilyWebSearcher();
  final toolExecutor = ToolExecutor(
    chatStorage: storage,
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
      return tavilyWebSearcher(
        query: query,
        maxResults: maxResults,
        apiKey: config.additionalConfig['web_search.tavily_api_key'] as String?,
        baseUrl: config.additionalConfig['web_search.tavily_base_url'] as String?,
      );
    },
    webpageFetcher: buildDefaultWebpageFetcher(sideModelLlm: llm),
    reminderCreator: buildDefaultReminderCreator(),
    calendarEventCreator: buildDefaultCalendarEventCreator(),
    resultSharer: buildDefaultResultSharer(),
    imageGenerator: buildOpenAIImageGenerator(),
  );
  final runtimeRegistry = buildDefaultToolRuntimeRegistry(
    toolExecutor: toolExecutor,
    skillRuntimeService: skillRuntimeService,
    appSettingsRepository: settingsRepository,
    createArtifactGuidelineHandler: createArtifactGuidelineHandler,
    createArtifactHandler: createArtifactHandler,
  );
  final toolPolicyService = ToolPolicyService(
    repository: settingsRepository,
  );
  final traceRecorder = ChatTraceRecorder();
  final followUpDispatchQueue = FollowUpDispatchQueue();
  final turnRepository = ChatTurnRepository(storage);
  final turnStepRepository = ChatTurnStepRepository(storage);
  final eventRepository = ChatEventRepository(storage);
  final sessionContextService = SessionContextService(
    chatTurnRepository: turnRepository,
    chatEventRepository: eventRepository,
    snapshotRepository: SessionContextSnapshotRepository(storage),
    chatStorage: storage,
    contextProjector: SessionContextProjector(),
    tokenBudgetService: SessionTokenBudgetService(
      modelBudgetRegistry: modelBudgetRegistry,
      modelCapabilityResolver: modelCapabilityResolver,
    ),
    summaryService: SessionSummaryService(chatService: ChatService(
      llm: llm,
      toolCallService: ToolCallService(
        runtimeRegistry: runtimeRegistry,
        traceRecorder: traceRecorder,
        toolExecutor: toolExecutor,
        toolPolicyService: toolPolicyService,
        hostAdapters: ToolHostAdapters(
          fileTools: fileToolAdapters,
          workspace: WorkspaceToolHostAdapters(
            resolveWorkspaceForGroup:
                runtimeAwareWorkspaceService.resolveWorkspaceForGroup,
            ensureWorkspaceForLongLivedOutput:
                runtimeAwareWorkspaceService.ensureWorkspaceForLongLivedOutput,
          ),
        ),
      ),
    )),
    chatService: ChatService(
      llm: llm,
      toolCallService: ToolCallService(
        runtimeRegistry: runtimeRegistry,
        traceRecorder: traceRecorder,
        toolExecutor: toolExecutor,
        toolPolicyService: toolPolicyService,
        hostAdapters: ToolHostAdapters(
          fileTools: fileToolAdapters,
          workspace: WorkspaceToolHostAdapters(
            resolveWorkspaceForGroup:
                runtimeAwareWorkspaceService.resolveWorkspaceForGroup,
            ensureWorkspaceForLongLivedOutput:
                runtimeAwareWorkspaceService.ensureWorkspaceForLongLivedOutput,
          ),
        ),
      ),
    ),
    settingsRepository: settingsRepository,
  );
  final chatService = ChatService(
    llm: llm,
    toolCallService: ToolCallService(
      runtimeRegistry: runtimeRegistry,
      traceRecorder: traceRecorder,
      toolExecutor: toolExecutor,
      toolPolicyService: toolPolicyService,
      hostAdapters: ToolHostAdapters(
        fileTools: fileToolAdapters,
        workspace: WorkspaceToolHostAdapters(
          resolveWorkspaceForGroup:
              runtimeAwareWorkspaceService.resolveWorkspaceForGroup,
          ensureWorkspaceForLongLivedOutput:
              runtimeAwareWorkspaceService.ensureWorkspaceForLongLivedOutput,
        ),
      ),
    ),
  );
  final turnHarness = TurnHarness(
    plannerService: AgentPlannerService(
      llm: llm,
      toolPolicyService: toolPolicyService,
      availableTools: runtimeRegistry.getDefinitionsForPlatform(
        _resolveRuntimePlatform(),
      ),
      onPlannerRetryScheduled: (progress) {
        final reason = progress.error is TimeoutException ? '请求超时' : '请求失败';
        container.read(chatSendStateProvider.notifier).setStatusText(
              '$reason，正在重试 ${progress.attempt}/${progress.maxAttempts}',
            );
      },
      onPlannerRuntimeStream: (entries) {
        unawaited(
          container.read(turnProjectionDispatcherProvider).dispatchPreviewEvent(
                entries,
              ),
        );
      },
      onPlannerRequestTrace: (event) {
        final coordinator =
            container.read(chatSendCoordinatorProvider) as DefaultChatSendCoordinator;
        coordinator.recordPlannerRequestTrace(event);
      },
    ),
    turnRepository: turnRepository,
    turnStepRepository: turnStepRepository,
    eventRepository: eventRepository,
    transcriptBuilderService: TranscriptBuilderService(
      eventRepository: eventRepository,
    ),
    turnVerifier: TurnVerifier(),
    toolCallService: ToolCallService(
      runtimeRegistry: runtimeRegistry,
      traceRecorder: traceRecorder,
      toolExecutor: toolExecutor,
      toolPolicyService: toolPolicyService,
      hostAdapters: ToolHostAdapters(
        fileTools: fileToolAdapters,
        workspace: WorkspaceToolHostAdapters(
          resolveWorkspaceForGroup:
              runtimeAwareWorkspaceService.resolveWorkspaceForGroup,
          ensureWorkspaceForLongLivedOutput:
              runtimeAwareWorkspaceService.ensureWorkspaceForLongLivedOutput,
        ),
      ),
    ),
    chatStorage: storage,
    sessionContextService: sessionContextService,
    followUpDispatchQueue: followUpDispatchQueue,
  );

  container = ProviderContainer();

  return AppRuntime(
    sharedPreferences: preferences,
    appSettingsRepository: settingsRepository,
    chatStorage: storage,
    followUpDispatchQueue: followUpDispatchQueue,
    chatAttachmentPickerService: chatAttachmentPickerService,
    chatAttachmentStorageService: chatAttachmentStorageService,
    artifactFileStorageService: artifactFileStorageService,
    fileToolRootService: fileToolAdapters?.rootService,
    skillStorageService: skillStorageService,
    gitHubSkillSourceResolver: gitHubSkillSourceResolver,
    gitHubSkillFetcher: gitHubSkillFetcher,
    skillIndexService: skillIndexService,
    skillRuntimeService: skillRuntimeService,
    skillInstallerService: skillInstallerService,
    traceRecorder: traceRecorder,
    chatService: chatService,
    turnHarness: turnHarness,
  );
}

ChatStorage _createChatStorage(SharedPreferences preferences) {
  return ChatStorageFactory.create(preferences);
}

class _RootApp extends ConsumerWidget {
  const _RootApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTheme = ref.watch(appThemeControllerProvider);
    return MaterialApp(
      routes: _buildRouteMap(),
      initialRoute: RouteConstant.chatPage,
      title: 'AI Chat',
      theme: AppTheme.fromSpec(activeTheme),
    );
  }

  Map<String, WidgetBuilder> _buildRouteMap() {
    return {
      RouteConstant.chatPage: (context) => const ChatPage(title: 'AI Chat'),
      RouteConstant.settingsPage: (context) => const SettingsPage(),
      RouteConstant.testPage: (context) => const TestPage(),
      RouteConstant.debugHubPage: (context) => const DebugHubPage(),
      RouteConstant.componentMotionDebugPage: (context) =>
          const ComponentMotionDebugPage(),
      RouteConstant.layoutDebugPage: (context) => const LayoutDebugPage(),
      RouteConstant.webviewDebugPage: (context) => const WebviewDebugPage(),
    };
  }
}

String _resolveRuntimePlatform() {
  if (kIsWeb) {
    return 'web';
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'android';
    case TargetPlatform.iOS:
      return 'ios';
    case TargetPlatform.macOS:
      return 'macos';
    case TargetPlatform.windows:
      return 'windows';
    case TargetPlatform.linux:
      return 'linux';
    case TargetPlatform.fuchsia:
      return 'android';
  }
}
