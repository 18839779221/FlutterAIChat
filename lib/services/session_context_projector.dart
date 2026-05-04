import '../models/chat_event.dart';
import '../models/chat_message.dart';
import '../models/context/model_context_item.dart';
import '../models/tool/tool_result.dart';
import 'model_context_item_encoder.dart';
import 'tool_result_context_projector.dart';

class SessionContextProjector {
  SessionContextProjector({
    ModelContextItemEncoder? contextItemEncoder,
    ToolResultContextProjector? toolResultContextProjector,
  })  : _contextItemEncoder = contextItemEncoder ?? const ModelContextItemEncoder(),
        _toolResultContextProjector =
            toolResultContextProjector ?? const ToolResultContextProjector();

  final ModelContextItemEncoder _contextItemEncoder;
  final ToolResultContextProjector _toolResultContextProjector;

  List<ChatMessage> projectMessagesToContext(
    List<ChatMessage> messages,
  ) {
    return _contextItemEncoder.encodeAll(
      projectMessagesToContextItems(messages),
    );
  }

  List<ChatMessage> projectEventsToContext(
    List<ChatEvent> events,
  ) {
    return encodeContextItems(
      projectEventsToContextItems(events),
    );
  }

  List<ChatMessage> encodeContextItems(
    List<ModelContextItem> items,
  ) {
    return _contextItemEncoder.encodeAll(items);
  }

  List<ModelContextItem> projectMessagesToContextItems(
    List<ChatMessage> messages,
  ) {
    return messages
        .where((message) => message.text.trim().isNotEmpty)
        .map(
          (message) => switch (message.role) {
            MessageRole.system => ModelContextItem.systemMessage(
                message.text,
                timestamp: message.timestamp,
              ),
            MessageRole.user => ModelContextItem.userMessage(
                message.text,
                timestamp: message.timestamp,
              ),
            MessageRole.assistant => ModelContextItem.assistantMessage(
                message.text,
                timestamp: message.timestamp,
              ),
          },
        )
        .toList(growable: false);
  }

  List<ModelContextItem> projectEventsToContextItems(
    List<ChatEvent> events,
  ) {
    return events
        .map(projectEventToContextItem)
        .whereType<ModelContextItem>()
        .toList(growable: false);
  }

  ChatMessage projectSnapshotToContext(
    String summaryText, {
    DateTime? timestamp,
  }) {
    return _contextItemEncoder.encode(
          projectSnapshotToContextItem(
            summaryText,
            timestamp: timestamp,
          ),
        ) ??
        ChatMessage(
          text: summaryText,
          role: MessageRole.system,
          timestamp: timestamp,
          status: MessageStatus.completed,
        );
  }

  ModelContextItem projectSnapshotToContextItem(
    String summaryText, {
    DateTime? timestamp,
  }) {
    return ModelContextItem.systemMessage(
      summaryText,
      timestamp: timestamp,
    );
  }

  ChatMessage? projectEventToContext(ChatEvent event) {
    final item = projectEventToContextItem(event);
    if (item == null) {
      return null;
    }
    return _contextItemEncoder.encode(item);
  }

  ModelContextItem? projectEventToContextItem(ChatEvent event) {
    switch (event.eventType) {
      case ChatEventType.userMessage:
        final content = event.content?.trim() ?? '';
        if (content.isEmpty) {
          return null;
        }
        return ModelContextItem.userMessage(
          content,
          timestamp: event.createdAt,
        );
      case ChatEventType.userInteractionResult:
        final content = event.content?.trim() ?? '';
        if (content.isEmpty) {
          return null;
        }
        return ModelContextItem.userMessage(
          content,
          timestamp: event.createdAt,
        );
      case ChatEventType.assistantPlannerMessage:
      case ChatEventType.assistantQuestionPrompt:
      case ChatEventType.finalAnswer:
        final content = event.content?.trim() ?? '';
        if (content.isEmpty) {
          return null;
        }
        return ModelContextItem.assistantMessage(
          content,
          timestamp: event.createdAt,
        );
      case ChatEventType.assistantToolCall:
      case ChatEventType.assistantToolConfirmation:
        final payload = event.payloadJson;
        final toolName = payload?['toolName']?.toString().trim();
        final summary =
            payload?['summary']?.toString().trim() ?? event.content?.trim() ?? '';
        if (summary.isEmpty && (toolName == null || toolName.isEmpty)) {
          return null;
        }
        return ModelContextItem.assistantToolUse(
          text: summary,
          toolName: toolName,
          providerCallId: payload?['providerCallId']?.toString().trim(),
          arguments: payload?['arguments'] is Map
              ? Map<String, dynamic>.from(
                  payload!['arguments'] as Map<dynamic, dynamic>,
                )
              : null,
          timestamp: event.createdAt,
        );
      case ChatEventType.toolResult:
      case ChatEventType.toolError:
        final payload = event.payloadJson;
        final content = payload == null
            ? ''
            : (_toolResultContextProjector
                    .projectToContextText(ToolResult.fromJson(payload))
                    ?.trim() ??
                '');
        if (content.isEmpty) {
          return null;
        }
        return ModelContextItem.userToolResult(
          text: content,
          toolName: payload?['toolName']?.toString(),
          providerCallId: payload?['providerCallId']?.toString().trim(),
          timestamp: event.createdAt,
        );
      case ChatEventType.assistantReasoningDelta:
      case ChatEventType.assistantTextDelta:
      case ChatEventType.assistantTextFinal:
      case ChatEventType.toolExecutionStarted:
      case ChatEventType.turnStatus:
      case ChatEventType.error:
        return null;
    }
  }
}
