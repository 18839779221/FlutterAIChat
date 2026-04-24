import 'package:ai_chat/controllers/chat_controller.dart';
import 'package:ai_chat/controllers/chat_debug_controller.dart';
import 'package:ai_chat/controllers/chat_interaction_coordinator.dart';
import 'package:ai_chat/controllers/chat_preferences_controller.dart';
import 'package:ai_chat/controllers/chat_send_coordinator.dart';
import 'package:ai_chat/controllers/chat_session_coordinator.dart';
import 'package:ai_chat/controllers/chat_summary_controller.dart';
import 'package:ai_chat/services/tool_ui_renderer_registry.dart';
import 'package:ai_chat/widgets/tool_renderers/edit_tool_workflow_card.dart';
import 'package:ai_chat/widgets/tool_renderers/fetch_webpage_tool_workflow_card.dart';
import 'package:ai_chat/widgets/tool_renderers/read_tool_workflow_card.dart';
import 'package:ai_chat/widgets/tool_renderers/web_search_tool_workflow_card.dart';
import 'package:ai_chat/widgets/tool_renderers/write_tool_workflow_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export '../controllers/chat_controller.dart';
export '../controllers/chat_debug_controller.dart';
export '../controllers/chat_interaction_coordinator.dart';
export '../controllers/chat_preferences_controller.dart';
export '../controllers/chat_send_coordinator.dart';
export '../controllers/chat_session_coordinator.dart';
export '../controllers/chat_summary_controller.dart';
export '../services/tool_ui_renderer_registry.dart';
export 'chat_collection_providers.dart';
export 'chat_dependency_providers.dart';
export 'chat_interaction_providers.dart';
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

final chatDebugControllerProvider = Provider<ChatDebugController>((ref) {
  return DefaultChatDebugController(ref);
});

final chatInteractionCoordinatorProvider =
    Provider<ChatInteractionCoordinator>((ref) {
  return DefaultChatInteractionCoordinator(
    ref,
    sendCoordinator: ref.read(chatSendCoordinatorProvider),
  );
});

final chatPreferencesControllerProvider =
    Provider<ChatPreferencesController>((ref) {
  return DefaultChatPreferencesController(ref);
});

final chatControllerProvider = Provider<ChatController>((ref) {
  return ChatController(
    ref,
    sendCoordinator: ref.read(chatSendCoordinatorProvider),
    sessionCoordinator: ref.read(chatSessionCoordinatorProvider),
    summaryController: ref.read(chatSummaryControllerProvider),
    debugController: ref.read(chatDebugControllerProvider),
    preferencesController: ref.read(chatPreferencesControllerProvider),
  );
});

final toolUiRendererRegistryProvider = Provider<ToolUiRendererRegistry>((ref) {
  return const ToolUiRendererRegistry(
    renderers: [
      ReadToolUiRenderer(),
      WriteToolUiRenderer(),
      EditToolUiRenderer(),
      WebSearchToolUiRenderer(),
      FetchWebpageToolUiRenderer(),
    ],
  );
});
