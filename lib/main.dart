import 'package:ai_chat/constants/route_constant.dart';
import 'package:ai_chat/pages/test_page.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/repositories/chat_event_repository.dart';
import 'package:ai_chat/repositories/session_context_snapshot_repository.dart';
import 'package:ai_chat/repositories/chat_turn_repository.dart';
import 'package:ai_chat/repositories/chat_turn_step_repository.dart';
import 'package:ai_chat/storage/chat_storage.dart';
import 'package:ai_chat/storage/chat_storage_factory.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pages/chat_page.dart';
import 'pages/settings_page.dart';
import 'utils/logger.dart';
import 'providers/chat_providers.dart';
import 'models/llm/llm_factory.dart';
import 'services/chat_service.dart';
import 'services/chat_trace_recorder.dart';
import 'services/agent_planner_service.dart';
import 'services/default_file_tool_adapters.dart';
import 'services/model_budget_registry.dart';
import 'services/turn_harness.dart';
import 'services/turn_verifier.dart';
import 'services/tool_call_service.dart';
import 'services/default_tool_adapters.dart';
import 'services/transcript_builder_service.dart';
import 'services/tool_executor.dart';
import 'services/tool_policy_service.dart';
import 'services/session_context_projector.dart';
import 'services/session_context_service.dart';
import 'services/session_summary_service.dart';
import 'services/session_token_budget_service.dart';
import 'tools/adapters/tool_host_adapters.dart';
import 'tools/default_tool_runtime_registry.dart';
import 'theme/app_theme.dart';

void main() async {
  // 确保 Flutter 绑定初始化
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Logger.initialize();
    final preferences = await SharedPreferences.getInstance();
    final settingsRepository = AppSettingsRepository(preferences);
    final storage = _createChatStorage(preferences);
    late final ChatTraceRecorder traceRecorder;
    late final ChatService chatService;
    late final TurnHarness turnHarness;
    traceRecorder = ChatTraceRecorder();
    await storage.testDatabaseConnection();
    final llm = LLMFactory.createLLM(
      LLMType.configurable,
      settingsRepository: settingsRepository,
    );
    final modelBudgetRegistry = ModelBudgetRegistry();
    final fileToolAdapters = await buildDefaultFileToolHostAdapters();
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
    chatService = ChatService(
      llm: llm,
      toolCallService: toolCallService,
    );
    final turnRepository = ChatTurnRepository(storage);
    final turnStepRepository = ChatTurnStepRepository(storage);
    final eventRepository = ChatEventRepository(storage);
    final sessionContextService = SessionContextService(
      chatTurnRepository: turnRepository,
      chatEventRepository: eventRepository,
      snapshotRepository: SessionContextSnapshotRepository(storage),
      contextProjector: SessionContextProjector(),
      tokenBudgetService: SessionTokenBudgetService(
        modelBudgetRegistry: modelBudgetRegistry,
      ),
      summaryService: SessionSummaryService(chatService: chatService),
      chatService: chatService,
    );
    turnHarness = TurnHarness(
      plannerService: AgentPlannerService(
        llm: llm,
        toolPolicyService: toolPolicyService,
        availableTools: runtimeRegistry.getDefinitionsForPlatform(
          _resolveRuntimePlatform(),
        ),
      ),
      turnRepository: turnRepository,
      turnStepRepository: turnStepRepository,
      eventRepository: eventRepository,
      transcriptBuilderService: TranscriptBuilderService(
        eventRepository: eventRepository,
      ),
      turnVerifier: TurnVerifier(),
      chatService: chatService,
      toolCallService: toolCallService,
      sessionContextService: sessionContextService,
    );

    // 创建一个自定义的ProviderContainer来添加覆盖
    final container = ProviderContainer(
      overrides: [
        // 覆盖聊天服务工厂提供者
        appSettingsRepositoryProvider.overrideWithValue(settingsRepository),
        databaseProvider.overrideWithValue(storage),
        traceRecorderProvider.overrideWithValue(traceRecorder),
        chatServiceFactoryProvider.overrideWithValue(chatService),
        turnHarnessProvider.overrideWithValue(turnHarness),
      ],
    );

    runApp(UncontrolledProviderScope(
      container: container,
      child: const MyApp(),
    ));
  } catch (e) {
    Logger.e('Main', '应用启动失败', e);
    // 在这里可以显示一个错误界面或者进行其他错误处理
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('应用初始化失败: $e'),
          ),
        ),
      ),
    );
  }
}

ChatStorage _createChatStorage(SharedPreferences preferences) {
  return ChatStorageFactory.create(preferences);
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      routes: getRouteMap(),
      initialRoute: RouteConstant.chatPage,
      title: 'AI Chat',
      theme: AppTheme.light(),
    );
  }

  Map<String, WidgetBuilder> getRouteMap() {
    return {
      RouteConstant.chatPage: (context) => const ChatPage(title: 'AI Chat'),
      RouteConstant.settingsPage: (context) => const SettingsPage(),
      RouteConstant.testPage: (context) => const TestPage()
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
