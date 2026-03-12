import 'package:ai_chat/constants/route_constant.dart';
import 'package:ai_chat/pages/test_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'pages/chat_page.dart';
import 'database/database_helper.dart';
import 'pages/settings_page.dart';
import 'utils/logger.dart';
import 'providers/chat_providers.dart';
import 'models/llm/llm_factory.dart';
import 'models/context/context_strategies.dart';
import 'services/chat_service.dart';

void main() async {
  // 确保 Flutter 绑定初始化
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // 初始化数据库工厂
    final dbHelper = DatabaseHelper();
    await dbHelper.testDatabaseConnection();
    
    // 创建一个自定义的ProviderContainer来添加覆盖
    final container = ProviderContainer(
      overrides: [
        // 覆盖聊天服务工厂提供者
        chatServiceFactoryProvider.overrideWithValue(_createChatService()),
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
ChatService _createChatService() {
  // 创建混合策略
  final contextStrategy = HybridStrategy(
    strategies: [
      TokenBasedStrategy(),
      SmartSelectionStrategy(),
    ],
    weights: [0.7, 0.3], // 70% token基础，30% 智能选择
  );

  // 创建LLM模型实例
  final llm = LLMFactory.createLLM(LLMType.deepseek);

  // 创建聊天服务
  return ChatService(
    llm: llm,
    contextStrategy: contextStrategy,
    maxTokens: 4000,
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      routes: getRouteMap(),
      initialRoute: RouteConstant.chatPage,
      title: '小晨AI助手',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
    );
  }

  Map<String, WidgetBuilder> getRouteMap() {
    return {
      RouteConstant.chatPage: (context) => const ChatPage(title: '小晨AI助手'),
      RouteConstant.settingsPage: (context) => const SettingsPage(),
      RouteConstant.testPage: (context) => const TestPage()
    };
  }
}
