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

    final runningEvent = _latestEventForPhase(
      projection.toolPresentationEvents,
      ToolPresentationEventPhase.running,
    );
    if (runningEvent != null) {
      return ActiveTurnStatusPresentation(
        phase: ActiveTurnStatusPhase.executingTool,
        text: _toolStatusText(runningEvent.toolName) ?? '正在执行工具',
        turnId: runningEvent.turnId,
        sourceMessageId: runningEvent.sourceMessageId,
        toolName: runningEvent.toolName,
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
          text: '正在生成回复',
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
    if (resultEvent != null) {
      return ActiveTurnStatusPresentation(
        phase: ActiveTurnStatusPhase.planning,
        text: '正在规划下一步',
        turnId: resultEvent.turnId,
        sourceMessageId: resultEvent.sourceMessageId,
        toolName: resultEvent.toolName,
        sourceKind: ActiveTurnStatusSourceKind.toolEvent,
        allowFloating: true,
      );
    }

    switch (sendState.phase) {
      case ChatSendPhase.idle:
        return null;
      case ChatSendPhase.preparing:
        return const ActiveTurnStatusPresentation(
          phase: ActiveTurnStatusPhase.planning,
          text: '正在请求模型',
          turnId: 'pending',
          sourceKind: ActiveTurnStatusSourceKind.sendPhaseFallback,
          allowFloating: true,
        );
      case ChatSendPhase.awaitingConfirmation:
        return const ActiveTurnStatusPresentation(
          phase: ActiveTurnStatusPhase.awaitingConfirmation,
          text: '等待工具确认',
          turnId: 'pending',
          sourceKind: ActiveTurnStatusSourceKind.sendPhaseFallback,
          allowFloating: true,
        );
      case ChatSendPhase.executingTool:
        return const ActiveTurnStatusPresentation(
          phase: ActiveTurnStatusPhase.executingTool,
          text: '正在执行工具',
          turnId: 'pending',
          sourceKind: ActiveTurnStatusSourceKind.sendPhaseFallback,
          allowFloating: true,
        );
      case ChatSendPhase.streamingResponse:
        return const ActiveTurnStatusPresentation(
          phase: ActiveTurnStatusPhase.streamingResponse,
          text: '正在生成回复',
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
