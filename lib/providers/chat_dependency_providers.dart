import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/services/agent_turn_orchestrator.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/chat_trace_recorder.dart';
import 'package:ai_chat/storage/chat_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 数据库提供者（实际实现在 main.dart 中通过 override 注入）
final databaseProvider = Provider<ChatStorage>((ref) {
  throw UnimplementedError('需要在 main.dart 中覆盖 databaseProvider');
});

final appSettingsRepositoryProvider = Provider<AppSettingsRepository>((ref) {
  throw UnimplementedError('需要在 main.dart 中覆盖 AppSettingsRepository');
});

final traceRecorderProvider = Provider<ChatTraceRecorder>((ref) {
  return ChatTraceRecorder();
});

// 聊天服务提供者
final chatServiceProvider = Provider<ChatService>((ref) {
  return ref.watch(chatServiceFactoryProvider);
});

// 聊天服务工厂提供者
final chatServiceFactoryProvider = Provider<ChatService>((ref) {
  throw UnimplementedError("需要在 main.dart 中覆盖创建 ChatService 的代码");
});

final agentTurnOrchestratorProvider =
    Provider<AgentTurnOrchestrator?>((ref) => null);
