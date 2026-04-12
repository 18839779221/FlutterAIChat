import 'dart:convert';

import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/models/trace/chat_trace_event.dart';
import 'package:ai_chat/providers/chat_send_state_providers.dart';
import 'package:ai_chat/services/tool_call_service.dart';

/// Snapshot of the local send transaction inputs before tool preparation and
/// model streaming start.
class ChatSendTransactionDraft {
  /// Newly created user message that should appear immediately in the UI.
  final ChatMessage userMessage;

  /// Assistant placeholder inserted once streaming is ready to begin.
  final ChatMessage assistantPlaceholder;

  /// Stable history snapshot restricted to completed user/assistant pairs.
  final List<ChatMessage> historyMessages;

  const ChatSendTransactionDraft({
    required this.userMessage,
    required this.assistantPlaceholder,
    required this.historyMessages,
  });
}

/// Derived result of the tool preparation stage before assistant streaming.
class ToolPreparationDraft {
  /// Whether the current turn must stop and wait for user confirmation.
  final bool requiresConfirmation;

  /// Next send phase implied by the tool preparation result.
  final ChatSendPhase nextPhase;

  /// History snapshot that should be passed into the next model round.
  final List<ChatMessage> toolContextHistory;

  const ToolPreparationDraft({
    required this.requiresConfirmation,
    required this.nextPhase,
    required this.toolContextHistory,
  });
}

/// Derived message mutations produced after a confirmed tool invocation runs.
class ConfirmedToolExecutionDraft {
  /// Replacement for the original confirmation message once execution starts.
  final ChatMessage runningMessage;

  /// Optional tool-result message appended after execution completes.
  final ChatMessage? toolResultMessage;

  const ConfirmedToolExecutionDraft({
    required this.runningMessage,
    required this.toolResultMessage,
  });
}

enum StreamingAssistantDeltaKind {
  content,
  reasoning,
  ignored,
}

/// Parsed semantic delta emitted by the streaming assistant response.
class StreamingAssistantDelta {
  /// Whether this chunk updates visible content, reasoning text, or should be ignored.
  final StreamingAssistantDeltaKind kind;

  /// Normalized textual payload carried by the chunk.
  final String content;

  const StreamingAssistantDelta({
    required this.kind,
    required this.content,
  });
}

/// Structured trace payload resolved before the controller records it.
class ChatSendTraceDraft {
  /// Trace stage represented by the future log entry.
  final ChatTraceStage stage;

  /// Success or failure outcome for the stage.
  final ChatTraceStatus status;

  /// Short operator-facing summary attached to the event.
  final String summary;

  /// Additional structured diagnostic fields.
  final Map<String, dynamic> data;

  const ChatSendTraceDraft({
    required this.stage,
    required this.status,
    required this.summary,
    required this.data,
  });
}

/// Finalization decision for assistant streaming terminal events.
class StreamingAssistantTerminalDraft {
  /// Assistant message id affected by the terminal event.
  final int assistantMessageId;

  /// Message status that should be persisted when requested.
  final MessageStatus nextStatus;

  /// Whether the assistant status should be updated in UI and persistence layers.
  final bool shouldPersistStatusUpdate;

  /// Whether the controller should clear the generating flag.
  final bool shouldStopGenerating;

  /// Whether the controller should return the send phase to idle.
  final bool shouldSetIdlePhase;

  /// Whether the auto summary timer should start after this terminal event.
  final bool shouldScheduleAutoSummary;

  /// Optional trace entry to record for this terminal event.
  final ChatSendTraceDraft? traceEntry;

  const StreamingAssistantTerminalDraft({
    required this.assistantMessageId,
    required this.nextStatus,
    required this.shouldPersistStatusUpdate,
    required this.shouldStopGenerating,
    required this.shouldSetIdlePhase,
    required this.shouldScheduleAutoSummary,
    required this.traceEntry,
  });
}

/// Builds the minimal send transaction snapshot so `sendMessage()` can focus on
/// orchestration instead of inline state assembly details.
ChatSendTransactionDraft buildChatSendTransactionDraft({
  required String text,
  required List<ChatMessage> currentMessages,
}) {
  final userMessage = ChatMessage(
    text: text,
    role: MessageRole.user,
    status: MessageStatus.completed,
  );
  final assistantPlaceholder = ChatMessage(
    text: '',
    role: MessageRole.assistant,
    status: MessageStatus.generating,
  );

  final historyMessages = <ChatMessage>[];
  int index = 0;
  while (index < currentMessages.length - 1) {
    final current = currentMessages[index];
    final next = currentMessages[index + 1];
    if (current.isUser &&
        next.isAssistant &&
        next.status == MessageStatus.completed &&
        current.contentType == MessageContentType.plainText &&
        next.contentType == MessageContentType.plainText) {
      historyMessages.add(current);
      historyMessages.add(next);
    }
    index += 2;
  }

  return ChatSendTransactionDraft(
    userMessage: userMessage,
    assistantPlaceholder: assistantPlaceholder,
    historyMessages: historyMessages,
  );
}

/// Resolves the next send-stage snapshot after tool preparation completes.
ToolPreparationDraft resolveToolPreparationDraft({
  required List<ChatMessage> historyMessages,
  required ToolPreparationResult toolPreparationResult,
}) {
  final toolContextHistory = [
    ...historyMessages,
    ...toolPreparationResult.additionalContextMessages,
  ];
  final requiresConfirmation = toolPreparationResult.toolInvocation != null &&
      toolPreparationResult.toolResult == null;

  return ToolPreparationDraft(
    requiresConfirmation: requiresConfirmation,
    nextPhase: requiresConfirmation
        ? ChatSendPhase.awaitingConfirmation
        : ChatSendPhase.streamingResponse,
    toolContextHistory: toolContextHistory,
  );
}

/// Resolves UI messages that should be written after a confirmed tool
/// invocation transitions into execution.
ConfirmedToolExecutionDraft resolveConfirmedToolExecutionDraft({
  required ChatMessage sourceMessage,
  required ToolInvocation invocation,
  required ToolPreparationResult executionResult,
}) {
  final runningInvocation = executionResult.toolInvocation ??
      invocation.copyWith(
        status: ToolInvocationStatus.running,
        summary: '正在执行工具：${invocation.toolName}',
        requiresConfirmation: false,
      );
  final runningMessage = sourceMessage.copyWith(
    text: runningInvocation.summary,
    contentType: MessageContentType.toolInvocation,
    payloadJson: runningInvocation.toJson(),
  );

  final toolResult = executionResult.toolResult;
  final toolResultMessage = toolResult == null
      ? null
      : ChatMessage(
          text: toolResult.displayText,
          role: MessageRole.assistant,
          status: MessageStatus.completed,
          contentType: MessageContentType.toolResult,
          payloadJson: toolResult.toJson(),
        );

  return ConfirmedToolExecutionDraft(
    runningMessage: runningMessage,
    toolResultMessage: toolResultMessage,
  );
}

/// Parses a raw stream event into a normalized assistant delta shape.
StreamingAssistantDelta resolveStreamingAssistantDelta(String rawEvent) {
  try {
    final decoded = jsonDecode(rawEvent);
    if (decoded is! Map) {
      return const StreamingAssistantDelta(
        kind: StreamingAssistantDeltaKind.ignored,
        content: '',
      );
    }
    final data = decoded.cast<String, dynamic>();
    final type = data['type'];
    final content = data['content'];
    if (content is! String || content.isEmpty) {
      return const StreamingAssistantDelta(
        kind: StreamingAssistantDeltaKind.ignored,
        content: '',
      );
    }
    if (type == 'content') {
      return StreamingAssistantDelta(
        kind: StreamingAssistantDeltaKind.content,
        content: content,
      );
    }
    if (type == 'reasoning') {
      return StreamingAssistantDelta(
        kind: StreamingAssistantDeltaKind.reasoning,
        content: content,
      );
    }
  } catch (_) {
    // Ignore malformed stream chunks and let the controller continue.
  }

  return const StreamingAssistantDelta(
    kind: StreamingAssistantDeltaKind.ignored,
    content: '',
  );
}

/// Resolves the terminal state when assistant streaming fails.
StreamingAssistantTerminalDraft resolveStreamingAssistantFailureDraft({
  required int assistantMessageId,
  required Object error,
}) {
  return StreamingAssistantTerminalDraft(
    assistantMessageId: assistantMessageId,
    nextStatus: MessageStatus.failed,
    shouldPersistStatusUpdate: true,
    shouldStopGenerating: true,
    shouldSetIdlePhase: true,
    shouldScheduleAutoSummary: false,
    traceEntry: ChatSendTraceDraft(
      stage: ChatTraceStage.sendFailed,
      status: ChatTraceStatus.failure,
      summary: 'AI响应出错',
      data: {
        'assistantMessageId': assistantMessageId,
        'error': error.toString(),
      },
    ),
  );
}

/// Resolves the terminal state when assistant streaming finishes normally.
StreamingAssistantTerminalDraft resolveStreamingAssistantCompletionDraft({
  required int assistantMessageId,
  required ChatMessage assistantMessage,
}) {
  if (assistantMessage.status == MessageStatus.interrupted) {
    return StreamingAssistantTerminalDraft(
      assistantMessageId: assistantMessageId,
      nextStatus: MessageStatus.interrupted,
      shouldPersistStatusUpdate: false,
      shouldStopGenerating: false,
      shouldSetIdlePhase: false,
      shouldScheduleAutoSummary: false,
      traceEntry: null,
    );
  }

  return StreamingAssistantTerminalDraft(
    assistantMessageId: assistantMessageId,
    nextStatus: MessageStatus.completed,
    shouldPersistStatusUpdate: true,
    shouldStopGenerating: true,
    shouldSetIdlePhase: true,
    shouldScheduleAutoSummary: true,
    traceEntry: ChatSendTraceDraft(
      stage: ChatTraceStage.sendDone,
      status: ChatTraceStatus.success,
      summary: '发送完成',
      data: {
        'assistantMessageId': assistantMessageId,
        'phase': ChatSendPhase.idle.name,
      },
    ),
  );
}
