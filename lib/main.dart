import 'package:ai_chat/constants/route_constant.dart';
import 'package:ai_chat/pages/test_page.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/storage/chat_storage.dart';
import 'package:ai_chat/storage/chat_storage_factory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pages/chat_page.dart';
import 'pages/settings_page.dart';
import 'utils/logger.dart';
import 'providers/chat_providers.dart';
import 'models/llm/llm_factory.dart';
import 'models/context/context_strategies.dart';
import 'services/chat_service.dart';
import 'services/chat_trace_recorder.dart';
import 'services/tool_call_service.dart';
import 'services/default_tool_adapters.dart';
import 'services/tool_executor.dart';
import 'services/tool_policy_service.dart';
import 'services/tool_registry.dart';
import 'tools/default_tool_runtime_registry.dart';
import 'theme/app_theme.dart';

void main() async {
  // 确保 Flutter 绑定初始化
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final preferences = await SharedPreferences.getInstance();
    final settingsRepository = AppSettingsRepository(preferences);
    final storage = _createChatStorage(preferences);
    late final ChatTraceRecorder traceRecorder;
    traceRecorder = ChatTraceRecorder(
      logger: (entry) => Logger.i('ChatTrace', traceRecorder.formatLogLine(entry)),
    );
    await storage.testDatabaseConnection();

    // 创建一个自定义的ProviderContainer来添加覆盖
    final container = ProviderContainer(
      overrides: [
        // 覆盖聊天服务工厂提供者
        appSettingsRepositoryProvider.overrideWithValue(settingsRepository),
        databaseProvider.overrideWithValue(storage),
        traceRecorderProvider.overrideWithValue(traceRecorder),
        chatServiceFactoryProvider.overrideWithValue(
          _createChatService(
            settingsRepository,
            storage,
            preferences,
            traceRecorder,
          ),
        ),
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

// 创建聊天服务的函数
ChatService _createChatService(
  AppSettingsRepository settingsRepository,
  ChatStorage storage,
  SharedPreferences preferences,
  ChatTraceRecorder traceRecorder,
) {
  // 创建混合策略
  final contextStrategy = HybridStrategy(
    strategies: [
      TokenBasedStrategy(),
      SmartSelectionStrategy(),
    ],
    weights: [0.7, 0.3], // 70% token基础，30% 智能选择
  );

  // 创建可配置的 HTTP LLM 实例
  final llm = LLMFactory.createLLM(
    LLMType.configurable,
    settingsRepository: settingsRepository,
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
          (config.additionalConfig['web_search.provider'] as String?)?.trim() ??
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
    webpageFetcher: buildDefaultWebpageFetcher(),
    noteSaver: buildSharedPreferencesNoteSaver(preferences),
    reminderCreator: buildDefaultReminderCreator(),
    calendarEventCreator: buildDefaultCalendarEventCreator(),
    resultSharer: buildDefaultResultSharer(),
  );
  final runtimeRegistry = buildDefaultToolRuntimeRegistry(
    toolExecutor: toolExecutor,
  );
  final toolRegistry = ToolRegistry(
    runtimeRegistry: runtimeRegistry,
  );
  final toolPolicyService = ToolPolicyService(
    repository: settingsRepository,
  );
  final toolCallService = ToolCallService(
    llm: llm,
    toolRegistry: toolRegistry,
    runtimeRegistry: runtimeRegistry,
    traceRecorder: traceRecorder,
    toolExecutor: toolExecutor,
    toolPolicyService: toolPolicyService,
  );

  // 创建聊天服务
  return ChatService(
    llm: llm,
    contextStrategy: contextStrategy,
    toolCallService: toolCallService,
    traceRecorder: traceRecorder,
    maxTokens: 4000,
  );
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
