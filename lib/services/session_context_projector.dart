import '../models/chat_event.dart';
import '../models/chat/chat_attachment.dart';
import '../models/chat_message.dart';
import '../models/context/model_context_item.dart';
import '../models/tool/tool_result.dart';
import '../utils/logger.dart';
import 'model_context_item_encoder.dart';
import 'tool_result_context_projector.dart';

class SessionContextProjector {
  static const _tag = 'SessionContextProjector';

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
            MessageRole.assistant => throw StateError(
                'assistant role unexpected in projectMessagesToContextItems — '
                'round-trip uses assistantTurnSnapshot via buildPlannerCarriers',
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
    final attachments = _attachmentsFromEvent(event);
    if (event.eventType == ChatEventType.userMessage) {
      Logger.temp(
        _tag,
        'attachments.event_projected_to_context',
        reason: 'diagnose_image_attachment_context_chain',
        data: {
          'eventId': event.id,
          'turnId': event.turnId,
          'attachmentCount': attachments.length,
          'localIds': attachments.map((attachment) => attachment.localId).toList(),
          'hasProviderDataUrl': attachments
              .map(
                (attachment) =>
                    attachment.providerFileRefJson?['data_url'] is String &&
                    (attachment.providerFileRefJson?['data_url'] as String)
                        .trim()
                        .isNotEmpty,
              )
              .toList(),
        },
      );
    }
    return _contextItemEncoder.encode(item, attachments: attachments);
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
        final providerCallId =
            event.payloadJson?['providerCallId']?.toString().trim();
        if (providerCallId != null && providerCallId.isNotEmpty) {
          return ModelContextItem.userToolResult(
            text: content,
            providerCallId: providerCallId,
            timestamp: event.createdAt,
          );
        }
        return ModelContextItem.userMessage(
          content,
          timestamp: event.createdAt,
        );
      case ChatEventType.toolResult:
      case ChatEventType.toolError:
        final payload = event.payloadJson;
        final structuredContent = payload == null
            ? null
            : _toolResultContextProjector
                .projectToContextText(ToolResult.fromJson(payload))
                ?.trim();
        final content = structuredContent != null && structuredContent.isNotEmpty
            ? structuredContent
            : (event.content?.trim() ?? '');
        if (content.isEmpty) {
          return null;
        }
        return ModelContextItem.userToolResult(
          text: content,
          toolName: payload?['toolName']?.toString(),
          providerCallId: payload?['providerCallId']?.toString().trim(),
          timestamp: event.createdAt,
        );
      case ChatEventType.assistantPlannerMessage:
      case ChatEventType.assistantQuestionPrompt:
      case ChatEventType.assistantToolCall:
      case ChatEventType.assistantToolConfirmation:
      case ChatEventType.assistantReasoningDelta:
      case ChatEventType.assistantTextDelta:
      case ChatEventType.assistantTextFinal:
      case ChatEventType.assistantTurnSnapshot:
      case ChatEventType.toolExecutionStarted:
      case ChatEventType.turnStatus:
      case ChatEventType.finalAnswer:
      case ChatEventType.error:
        // Assistant-track events live only in the UI rendering pipeline now;
        // round-trip uses assistantTurnSnapshot via SessionContextService
        // .buildPlannerCarriers (spec 2026-05-22).
        return null;
    }
  }

  List<ChatAttachment> _attachmentsFromEvent(ChatEvent event) {
    final raw = event.payloadJson?['attachments'];
    if (raw is! List) {
      return const <ChatAttachment>[];
    }
    return raw
        .whereType<Map>()
        .map((item) => ChatAttachment.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }
}
