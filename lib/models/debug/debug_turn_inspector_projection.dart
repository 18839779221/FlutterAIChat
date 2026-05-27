import 'package:ai_chat/models/chat/runtime_assistant_draft.dart';
import 'package:ai_chat/models/chat/runtime_streaming_preview_state.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/chat/tool_presentation_event.dart';

import 'debug_cache_panel_projection.dart';
import 'debug_turn_inspector_context_section.dart';
import 'debug_turn_inspector_timeline_entry.dart';
import 'debug_turn_option.dart';

/// Read-only snapshot used by the debug turn inspector.
class DebugTurnInspectorProjection {
  final List<DebugTurnOption> turnOptions;
  final int? selectedTurnId;
  final DebugTurnOverview? activeTurnOverview;
  final List<DebugTurnTimelineEntry> timelineEntries;
  final List<DebugTurnInspectorContextSection> contextSections;
  final DebugCachePanelProjection? cachePanel;

  const DebugTurnInspectorProjection({
    required this.turnOptions,
    required this.selectedTurnId,
    required this.activeTurnOverview,
    required this.timelineEntries,
    required this.contextSections,
    this.cachePanel,
  });

  DebugTurnInspectorProjection copyWithSelectedTurn(int selectedTurnId) {
    return DebugTurnInspectorProjection(
      turnOptions: turnOptions,
      selectedTurnId: selectedTurnId,
      activeTurnOverview: activeTurnOverview,
      timelineEntries: timelineEntries,
      contextSections: contextSections,
      cachePanel: cachePanel,
    );
  }
}

/// Compact top-level status summary for one turn.
class DebugTurnOverview {
  final int turnId;
  final int groupId;
  final ChatTurnStatus status;
  final String? sendPhase;
  final String? sendStatusText;
  final int iterationCount;
  final int toolCallCount;
  final String? providerStyle;
  final String? modelName;
  final String? diagnosticCode;
  final String? errorMessage;
  final bool hasRuntimeDraft;
  final int runtimePreviewMessageCount;
  final bool hasPendingConfirmation;
  final bool hasActiveQuestion;
  final DateTime startedAt;
  final DateTime updatedAt;
  final int durationMs;

  const DebugTurnOverview({
    required this.turnId,
    required this.groupId,
    required this.status,
    required this.sendPhase,
    this.sendStatusText,
    required this.iterationCount,
    required this.toolCallCount,
    required this.providerStyle,
    required this.modelName,
    required this.diagnosticCode,
    required this.errorMessage,
    required this.hasRuntimeDraft,
    required this.runtimePreviewMessageCount,
    required this.hasPendingConfirmation,
    required this.hasActiveQuestion,
    required this.startedAt,
    required this.updatedAt,
    required this.durationMs,
  });
}

/// Unified debug snapshot for raw runtime values.
class DebugTurnRuntimeSnapshot {
  final ChatMessage? activeAskUserQuestionMessage;
  final RuntimeAssistantDraft? runtimeAssistantDraft;
  final RuntimeStreamingPreviewState runtimePreviewState;
  final List<ToolPresentationEvent> toolPresentationEvents;

  const DebugTurnRuntimeSnapshot({
    required this.activeAskUserQuestionMessage,
    required this.runtimeAssistantDraft,
    required this.runtimePreviewState,
    required this.toolPresentationEvents,
  });
}
