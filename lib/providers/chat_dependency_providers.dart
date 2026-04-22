import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/chat_trace_recorder.dart';
import 'package:ai_chat/services/model_budget_registry.dart';
import 'package:ai_chat/services/session_context_projector.dart';
import 'package:ai_chat/services/session_context_service.dart';
import 'package:ai_chat/services/session_summary_service.dart';
import 'package:ai_chat/services/session_token_budget_service.dart';
import 'package:ai_chat/services/turn_harness.dart';
import 'package:ai_chat/storage/chat_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ai_chat/repositories/chat_event_repository.dart';
import 'package:ai_chat/repositories/chat_turn_repository.dart';
import 'package:ai_chat/repositories/session_context_snapshot_repository.dart';

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

final chatTurnRepositoryProvider = Provider<ChatTurnRepository>((ref) {
  return ChatTurnRepository(ref.watch(databaseProvider));
});

final chatEventRepositoryProvider = Provider<ChatEventRepository>((ref) {
  return ChatEventRepository(ref.watch(databaseProvider));
});

final sessionContextSnapshotRepositoryProvider =
    Provider<SessionContextSnapshotRepository>((ref) {
  return SessionContextSnapshotRepository(ref.watch(databaseProvider));
});

final sessionContextProjectorProvider =
    Provider<SessionContextProjector>((ref) => SessionContextProjector());

final modelBudgetRegistryProvider =
    Provider<ModelBudgetRegistry>((ref) => ModelBudgetRegistry());

final sessionTokenBudgetServiceProvider = Provider<SessionTokenBudgetService>(
  (ref) => SessionTokenBudgetService(
    modelBudgetRegistry: ref.watch(modelBudgetRegistryProvider),
  ),
);

final sessionSummaryServiceProvider = Provider<SessionSummaryService>((ref) {
  return SessionSummaryService(chatService: ref.watch(chatServiceProvider));
});

final sessionContextServiceProvider = Provider<SessionContextService>((ref) {
  return SessionContextService(
    chatTurnRepository: ref.watch(chatTurnRepositoryProvider),
    chatEventRepository: ref.watch(chatEventRepositoryProvider),
    snapshotRepository: ref.watch(sessionContextSnapshotRepositoryProvider),
    contextProjector: ref.watch(sessionContextProjectorProvider),
    tokenBudgetService: ref.watch(sessionTokenBudgetServiceProvider),
    summaryService: ref.watch(sessionSummaryServiceProvider),
    chatService: ref.watch(chatServiceProvider),
  );
});

final turnHarnessProvider = Provider<TurnHarness?>((ref) => null);
