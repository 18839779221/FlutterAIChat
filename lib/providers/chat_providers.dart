import 'package:ai_chat/controllers/chat_controller.dart';
import 'package:ai_chat/controllers/chat_send_coordinator.dart';
import 'package:ai_chat/controllers/chat_session_coordinator.dart';
import 'package:ai_chat/controllers/chat_summary_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export '../controllers/chat_controller.dart';
export '../controllers/chat_send_coordinator.dart';
export '../controllers/chat_session_coordinator.dart';
export '../controllers/chat_summary_controller.dart';
export 'chat_collection_providers.dart';
export 'chat_dependency_providers.dart';
export 'chat_send_state_providers.dart';
export 'chat_ui_providers.dart';

final chatSendCoordinatorProvider = Provider<ChatSendCoordinator>((ref) {
  return DefaultChatSendCoordinator(ref);
});

final chatSessionCoordinatorProvider = Provider<ChatSessionCoordinator>((ref) {
  return DefaultChatSessionCoordinator(ref);
});

final chatSummaryControllerProvider = Provider<ChatSummaryController>((ref) {
  return DefaultChatSummaryController(
    ref,
    sessionCoordinator: ref.read(chatSessionCoordinatorProvider),
  );
});

final chatControllerProvider = Provider<ChatController>((ref) {
  return ChatController(
    ref,
    sendCoordinator: ref.read(chatSendCoordinatorProvider),
    sessionCoordinator: ref.read(chatSessionCoordinatorProvider),
    summaryController: ref.read(chatSummaryControllerProvider),
  );
});
