import '../models/chat_event.dart';
import '../models/chat_message.dart';
import '../models/tool/tool_result.dart';

class SessionContextProjector {
  List<ChatMessage> projectMessagesToContext(
    List<ChatMessage> messages,
  ) {
    return messages
        .where((message) => message.text.trim().isNotEmpty)
        .map(
          (message) => ChatMessage(
            text: message.text,
            role: message.role,
            id: message.id,
            timestamp: message.timestamp,
            status: MessageStatus.completed,
            reasoningContent: message.reasoningContent,
            contentType: message.contentType,
            payloadJson: message.payloadJson,
            referenceJson: message.referenceJson,
          ),
        )
        .toList(growable: false);
  }

  List<ChatMessage> projectEventsToContext(
    List<ChatEvent> events,
  ) {
    return events
        .map(projectEventToContext)
        .whereType<ChatMessage>()
        .toList(growable: false);
  }

  ChatMessage projectSnapshotToContext(
    String summaryText, {
    DateTime? timestamp,
  }) {
    return ChatMessage(
      text: summaryText,
      role: MessageRole.system,
      timestamp: timestamp,
      status: MessageStatus.completed,
    );
  }

  ChatMessage? projectEventToContext(ChatEvent event) {
    final content = _resolveContextContent(event);
    if (content.isEmpty) {
      return null;
    }

    final projectedRole = _projectRole(event);
    if (projectedRole == null) {
      return null;
    }

    return ChatMessage(
      text: content,
      role: projectedRole,
      timestamp: event.createdAt,
      status: MessageStatus.completed,
    );
  }

  String _resolveContextContent(ChatEvent event) {
    final modelContextText = _extractModelContextText(event);
    if (modelContextText != null) {
      return modelContextText;
    }
    final content = event.content?.trim() ?? '';
    return content;
  }

  String? _extractModelContextText(ChatEvent event) {
    if (event.eventType != ChatEventType.toolResult &&
        event.eventType != ChatEventType.toolError) {
      return null;
    }
    final payload = event.payloadJson;
    if (payload == null) {
      return null;
    }
    return ToolResult.fromJson(payload).resolvedToolResultText;
  }

  MessageRole? _projectRole(ChatEvent event) {
    switch (event.eventType) {
      case ChatEventType.userMessage:
        return MessageRole.user;
      case ChatEventType.userInteractionResult:
        return MessageRole.user;
      case ChatEventType.assistantPlannerMessage:
      case ChatEventType.assistantQuestionPrompt:
      case ChatEventType.toolResult:
      case ChatEventType.toolError:
      case ChatEventType.finalAnswer:
        return MessageRole.assistant;
      case ChatEventType.assistantReasoningDelta:
      case ChatEventType.assistantTextDelta:
      case ChatEventType.assistantTextFinal:
      case ChatEventType.assistantToolCall:
      case ChatEventType.assistantToolConfirmation:
      case ChatEventType.toolExecutionStarted:
      case ChatEventType.turnStatus:
      case ChatEventType.error:
        return null;
    }
  }
}
