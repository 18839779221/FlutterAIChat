import 'package:ai_chat/models/chat/assistant_turn_block.dart';
import 'package:ai_chat/models/chat/chat_timeline_projection.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/services/chat_block_builder.dart';

/// Builds one consistent projection snapshot for timeline rendering and
/// waiting-state providers so consumers do not independently rescan messages.
class ChatTimelineProjectionService {
  ChatTimelineProjectionService({
    ChatBlockBuilder? blockBuilder,
  }) : _blockBuilder = blockBuilder ?? ChatBlockBuilder();

  final ChatBlockBuilder _blockBuilder;

  ChatTimelineProjection build({
    required List<ChatMessage> messages,
    int? groupId,
  }) {
    final blocks = _blockBuilder.buildAssistantBlocks(
      messages: messages,
      groupId: groupId,
    );
    return ChatTimelineProjection(
      activeAskUserQuestionMessage: _findActiveAskUserQuestion(messages),
      pendingToolConfirmation: _findPendingConfirmation(messages),
      assistantBlocks: blocks,
    );
  }

  ChatMessage? _findActiveAskUserQuestion(List<ChatMessage> messages) {
    final resolvedTurnIds = <int>{};

    for (final message in messages) {
      if (message.contentType != MessageContentType.askUserQuestionResult) {
        continue;
      }
      final turnId = message.payloadJson?['agentTurnId'];
      if (turnId is int) {
        resolvedTurnIds.add(turnId);
      }
    }

    for (final message in messages.reversed) {
      if (message.contentType != MessageContentType.askUserQuestionPrompt) {
        continue;
      }
      final payload = message.payloadJson;
      final turnId = payload?['agentTurnId'];
      final status = payload?['status'];
      if (turnId is! int || resolvedTurnIds.contains(turnId)) {
        continue;
      }
      if (status is String &&
          status.isNotEmpty &&
          status != 'awaitingResponse') {
        continue;
      }
      return message;
    }

    return null;
  }

  ProjectedPendingToolConfirmation? _findPendingConfirmation(
    List<ChatMessage> messages,
  ) {
    for (final message in messages.reversed) {
      final contentType = message.contentType;
      if (contentType != MessageContentType.actionConfirmation &&
          contentType != MessageContentType.toolInvocation) {
        continue;
      }

      final payload = message.payloadJson;
      if (payload == null) {
        continue;
      }

      final invocation = ToolInvocation.fromJson(payload);
      if (invocation.status != ToolInvocationStatus.awaitingConfirmation ||
          !invocation.requiresConfirmation) {
        continue;
      }

      return ProjectedPendingToolConfirmation(
        message: message,
        invocation: invocation,
      );
    }

    return null;
  }
}
