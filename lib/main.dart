import 'package:ai_chat/constants/route_constant.dart';
import 'package:ai_chat/pages/test_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'pages/chat_page.dart';
import 'database/database_helper.dart';
import 'pages/settings_page.dart';
import 'utils/logger.dart';
import 'package:provider/provider.dart';
import 'models/llm/llm_factory.dart';
import 'models/context/context_strategies.dart';
import 'services/chat_service.dart';
import 'providers/chat_state_provider.dart';

void main() async {
  // 确保 Flutter 绑定初始化
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // 初始化数据库工厂
    final dbHelper = DatabaseHelper();
    await dbHelper.testDatabaseConnection();
    
    runApp(const MyApp());
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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ChatService>(
          create: (_) {
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
          },
          // dispose: (_, chatService) => chatService.dispose(),
        ),
        ChangeNotifierProxyProvider<ChatService, ChatStateProvider>(
          create: (context) => ChatStateProvider(
            Provider.of<ChatService>(context, listen: false),
          ),
          update: (context, chatService, previous) => previous!,
        ),
      ],
      child: MaterialApp(
        routes: getRouteMap(),
        initialRoute: RouteConstant.chatPage,
        title: 'AI Chat',
        theme: ThemeData(
          // This is the theme of your application.
          //
          // TRY THIS: Try running your application with "flutter run". You'll see
          // the application has a purple toolbar. Then, without quitting the app,
          // try changing the seedColor in the colorScheme below to Colors.green
          // and then invoke "hot reload" (save your changes or press the "hot
          // reload" button in a Flutter-supported IDE, or press "r" if you used
          // the command line to start the app).
          //
          // Notice that the counter didn't reset back to zero; the application
          // state is not lost during the reload. To reset the state, use hot
          // restart instead.
          //
          // This works for code too, not just values: Most code changes can be
          // tested with just a hot reload.
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        ),
      ),
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

