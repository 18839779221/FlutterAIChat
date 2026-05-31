import 'package:ai_chat/models/chat/active_turn_status_presentation.dart';
import 'package:ai_chat/models/chat/chat_timeline_projection.dart';
import 'package:ai_chat/models/chat/tool_presentation_event.dart';
import 'package:ai_chat/providers/chat_send_state_providers.dart';
import 'package:ai_chat/tools/core/tool_display_names.dart';

/// Resolves one unified user-facing active status from timeline projection
/// facts and send-state fallbacks.
class ActiveTurnStatusResolver {
  const ActiveTurnStatusResolver();

  ActiveTurnStatusPresentation? resolve({
    required ChatTimelineProjection projection,
    required ChatSendState sendState,
  }) {
    final statusTextOverride = _normalizeOverride(sendState.statusText);
    final confirmation = projection.pendingToolConfirmation;
    if (confirmation != null) {
      final summary = confirmation.invocation.summary.trim();
      return ActiveTurnStatusPresentation(
        phase: ActiveTurnStatusPhase.awaitingConfirmation,
        text: summary.isNotEmpty ? summary : '等待工具确认',
        turnId: _turnIdForMessageId(confirmation.message.id),
        sourceMessageId: confirmation.message.id,
        toolName: confirmation.invocation.toolName,
        sourceKind: ActiveTurnStatusSourceKind.confirmation,
        allowFloating: true,
      );
    }

    if (sendState.phase == ChatSendPhase.idle) {
      if (statusTextOverride == null) {
        return null;
      }
      return ActiveTurnStatusPresentation(
        phase: ActiveTurnStatusPhase.idle,
        text: statusTextOverride,
        turnId: 'idle_override',
        sourceKind: ActiveTurnStatusSourceKind.sendPhaseFallback,
        allowFloating: true,
      );
    }

    final latestToolEvent = _latestToolEvent(projection.toolPresentationEvents);
    final activeRunningEvents = _activeRunningEvents(
      projection.toolPresentationEvents,
    );
    final latestActiveRunningEvent = activeRunningEvents.isEmpty
        ? null
        : activeRunningEvents.last;
    final hasLatestProposed =
        latestToolEvent?.phase == ToolPresentationEventPhase.proposed;
    if (latestActiveRunningEvent != null) {
      final latestRunningToolName = latestActiveRunningEvent.toolName;
      final runningText = activeRunningEvents.length > 1
          ? '正在执行工具'
          : (_toolStatusText(latestRunningToolName) ?? '正在执行工具');
      return ActiveTurnStatusPresentation(
        phase: ActiveTurnStatusPhase.executingTool,
        text: statusTextOverride ?? runningText,
        turnId: latestActiveRunningEvent.turnId,
        sourceMessageId: latestActiveRunningEvent.sourceMessageId,
        toolName: activeRunningEvents.length == 1 ? latestRunningToolName : null,
        sourceKind: ActiveTurnStatusSourceKind.toolEvent,
        allowFloating: true,
      );
    }

    if (!projection.runtimePreviewState.isEmpty ||
        sendState.phase == ChatSendPhase.streamingResponse) {
      if (!projection.runtimePreviewState.isEmpty ||
          sendState.isGenerating) {
        return ActiveTurnStatusPresentation(
          phase: ActiveTurnStatusPhase.streamingResponse,
          text: statusTextOverride ?? '正在生成回复',
          turnId: _turnIdForPreview(projection),
          sourceKind: projection.runtimePreviewState.isEmpty
              ? ActiveTurnStatusSourceKind.sendPhaseFallback
              : ActiveTurnStatusSourceKind.runtimePreview,
          allowFloating: true,
        );
      }
    }

    final resultEvent = _latestEventForPhase(
      projection.toolPresentationEvents,
      ToolPresentationEventPhase.result,
    );
    if (resultEvent != null ||
        (sendState.phase == ChatSendPhase.preparing && hasLatestProposed)) {
      final planningEvent = resultEvent ?? latestToolEvent;
      return ActiveTurnStatusPresentation(
        phase: ActiveTurnStatusPhase.planning,
        text: statusTextOverride ?? '正在规划下一步',
        turnId: planningEvent?.turnId ?? 'pending',
        sourceMessageId: planningEvent?.sourceMessageId,
        toolName: planningEvent?.toolName,
        sourceKind: ActiveTurnStatusSourceKind.toolEvent,
        allowFloating: true,
      );
    }

    switch (sendState.phase) {
      case ChatSendPhase.idle:
        return null;
      case ChatSendPhase.preparing:
        return ActiveTurnStatusPresentation(
          phase: ActiveTurnStatusPhase.planning,
          text: statusTextOverride ?? '正在请求模型',
          turnId: 'pending',
          sourceKind: ActiveTurnStatusSourceKind.sendPhaseFallback,
          allowFloating: true,
        );
      case ChatSendPhase.awaitingConfirmation:
        return ActiveTurnStatusPresentation(
          phase: ActiveTurnStatusPhase.awaitingConfirmation,
          text: statusTextOverride ?? '等待工具确认',
          turnId: 'pending',
          sourceKind: ActiveTurnStatusSourceKind.sendPhaseFallback,
          allowFloating: true,
        );
      case ChatSendPhase.executingTool:
        return ActiveTurnStatusPresentation(
          phase: ActiveTurnStatusPhase.executingTool,
          text: statusTextOverride ?? '正在执行工具',
          turnId: 'pending',
          sourceKind: ActiveTurnStatusSourceKind.sendPhaseFallback,
          allowFloating: true,
        );
      case ChatSendPhase.streamingResponse:
        return ActiveTurnStatusPresentation(
          phase: ActiveTurnStatusPhase.streamingResponse,
          text: statusTextOverride ?? '正在生成回复',
          turnId: 'pending',
          sourceKind: ActiveTurnStatusSourceKind.sendPhaseFallback,
          allowFloating: true,
        );
    }
  }

  ToolPresentationEvent? _latestEventForPhase(
    List<ToolPresentationEvent> events,
    ToolPresentationEventPhase phase,
  ) {
    for (final event in events.reversed) {
      if (event.phase == phase) {
        return event;
      }
    }
    return null;
  }

  ToolPresentationEvent? _latestToolEvent(List<ToolPresentationEvent> events) {
    if (events.isEmpty) {
      return null;
    }
    return events.last;
  }

  List<ToolPresentationEvent> _activeRunningEvents(
    List<ToolPresentationEvent> events,
  ) {
    if (events.isEmpty) {
      return const <ToolPresentationEvent>[];
    }

    final pendingResultCountByKey = <String, int>{};
    final activeRunningEvents = <ToolPresentationEvent>[];

    for (final event in events.reversed) {
      if (event.phase == ToolPresentationEventPhase.result) {
        final key = _eventMatchKey(event);
        pendingResultCountByKey.update(key, (count) => count + 1,
            ifAbsent: () => 1);
        continue;
      }
      if (event.phase != ToolPresentationEventPhase.running) {
        continue;
      }

      final key = _eventMatchKey(event);
      final pendingCount = pendingResultCountByKey[key] ?? 0;
      if (pendingCount > 0) {
        pendingResultCountByKey[key] = pendingCount - 1;
        continue;
      }
      activeRunningEvents.add(event);
    }

    return activeRunningEvents.reversed.toList(growable: false);
  }

  String _eventMatchKey(ToolPresentationEvent event) {
    final providerCallId = event.providerCallId?.trim();
    if (providerCallId != null && providerCallId.isNotEmpty) {
      return 'provider:$providerCallId';
    }
    final stepId = event.stepId?.trim();
    if (stepId != null && stepId.isNotEmpty) {
      return 'step:$stepId';
    }
    return 'tool:${event.toolName.trim()}';
  }

  String? _normalizeOverride(String? text) {
    final normalized = text?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  String? _toolStatusText(String toolName) {
    switch (toolName.trim()) {
      case 'web_search':
        return '正在联网搜索';
      case 'fetch_webpage':
        return '正在读取网页';
      case 'Read':
        return '正在读取文件';
      case 'LS':
        return '正在列出目录';
      case 'Grep':
        return '正在搜索文件内容';
      case 'Glob':
        return '正在查找文件';
      default:
        final displayName = resolveToolDisplayName(toolName);
        return displayName.trim().isEmpty ? null : '正在$displayName';
    }
  }

  String _turnIdForMessageId(int? messageId) {
    return messageId == null ? 'pending' : 'message_$messageId';
  }

  String _turnIdForPreview(ChatTimelineProjection projection) {
    final previewMessages = projection.runtimePreviewState.messages;
    if (previewMessages.isEmpty) {
      return 'pending';
    }
    return 'preview_${previewMessages.last.messageId}';
  }
}
