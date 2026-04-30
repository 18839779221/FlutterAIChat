import 'package:ai_chat/models/chat/assistant_turn_block.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/interaction/ask_user_question_request.dart';
import 'package:ai_chat/models/interaction/ask_user_question_response.dart';
import 'package:ai_chat/models/response/message_content_type.dart';

/// Builds UI-facing assistant turn blocks from existing persisted chat messages.
class ChatBlockBuilder {
  List<AssistantTurnBlock> buildAssistantBlocks({
    required List<ChatMessage> messages,
    int? groupId,
  }) {
    final sortedMessages = [...messages]..sort(compareChatMessagesForTimeline);

    final blocks = <AssistantTurnBlock>[];
    String? currentTurnId;
    var fallbackUserIndex = 0;
    final lastAnalysisIndexByTurn = <String, int>{};
    final sequenceByTurn = <String, int>{};

    for (final message in sortedMessages) {
      if (message.isUser) {
        fallbackUserIndex += 1;
        currentTurnId = _buildTurnId(
          groupId: groupId,
          messageId: message.id,
          fallbackIndex: fallbackUserIndex,
        );
        continue;
      }

      currentTurnId ??= _buildTurnId(
        groupId: groupId,
        messageId: message.id,
        fallbackIndex: fallbackUserIndex + 1,
      );

      final nextSequence = (sequenceByTurn[currentTurnId] ?? 0) + 1;
      sequenceByTurn[currentTurnId] = nextSequence;
      final block = _mapMessageToBlock(
        message: message,
        turnId: currentTurnId,
        sequence: nextSequence,
      );
      blocks.add(block);

      if (block.type == AssistantTurnBlockType.analysis &&
          !_isToolUseReasoningBlock(block)) {
        lastAnalysisIndexByTurn[currentTurnId] = blocks.length - 1;
      }
    }

    for (final entry in lastAnalysisIndexByTurn.entries) {
      final index = entry.value;
      blocks[index] = blocks[index].copyWith(
        type: AssistantTurnBlockType.finalResponse,
      );
    }

    return blocks;
  }

  AssistantTurnBlock _mapMessageToBlock({
    required ChatMessage message,
    required String turnId,
    required int sequence,
  }) {
    switch (message.contentType) {
      case MessageContentType.askUserQuestionPrompt:
        final request = _readAskUserQuestionRequest(message.payloadJson);
        return AssistantTurnBlock(
          id: '$turnId-question-prompt-$sequence',
          turnId: turnId,
          type: AssistantTurnBlockType.structuredOutput,
          sequence: sequence,
          createdAt: message.timestamp,
          updatedAt: message.timestamp,
          title: 'Question',
          text: message.text,
          reasoningText: message.reasoningContent,
          payload: message.payloadJson,
          askUserQuestionRequest: request,
        );
      case MessageContentType.askUserQuestionResult:
        final response = _readAskUserQuestionResponse(message.payloadJson);
        return AssistantTurnBlock(
          id: '$turnId-question-result-$sequence',
          turnId: turnId,
          type: AssistantTurnBlockType.structuredOutput,
          sequence: sequence,
          createdAt: message.timestamp,
          updatedAt: message.timestamp,
          title: 'Answer',
          text: message.text,
          reasoningText: message.reasoningContent,
          payload: message.payloadJson,
          askUserQuestionResponse: response,
        );
      case MessageContentType.toolInvocation:
      case MessageContentType.actionConfirmation:
        return AssistantTurnBlock(
          id: '$turnId-analysis-$sequence',
          turnId: turnId,
          type: AssistantTurnBlockType.analysis,
          sequence: sequence,
          createdAt: message.timestamp,
          updatedAt: message.timestamp,
          text: message.text,
          reasoningText: message.reasoningContent,
          payload: message.payloadJson,
        );
      case MessageContentType.toolResult:
        return AssistantTurnBlock(
          id: '$turnId-analysis-$sequence',
          turnId: turnId,
          type: AssistantTurnBlockType.analysis,
          sequence: sequence,
          createdAt: message.timestamp,
          updatedAt: message.timestamp,
          text: message.text,
          reasoningText: message.reasoningContent,
          payload: message.payloadJson,
        );
      case MessageContentType.plainText:
        return AssistantTurnBlock(
          id: '$turnId-analysis-$sequence',
          turnId: turnId,
          type: AssistantTurnBlockType.analysis,
          sequence: sequence,
          createdAt: message.timestamp,
          updatedAt: message.timestamp,
          text: message.text,
          reasoningText: message.reasoningContent,
          payload: message.payloadJson,
        );
    }
  }

  String _buildTurnId({
    required int? groupId,
    required int? messageId,
    required int fallbackIndex,
  }) {
    return '${groupId ?? 0}_${messageId ?? 'user_$fallbackIndex'}';
  }

  bool _isToolUseReasoningBlock(AssistantTurnBlock block) {
    return block.payload?['reasoningScope'] == 'tool_use' &&
        (block.reasoningText ?? '').trim().isNotEmpty &&
        (block.text ?? '').trim().isEmpty;
  }

  AskUserQuestionRequest? _readAskUserQuestionRequest(
    Map<String, dynamic>? payload,
  ) {
    if (payload == null) {
      return null;
    }
    try {
      return AskUserQuestionRequest.fromJson(payload);
    } catch (_) {
      return null;
    }
  }

  AskUserQuestionResponse? _readAskUserQuestionResponse(
    Map<String, dynamic>? payload,
  ) {
    if (payload == null) {
      return null;
    }
    final submittedAnswers = payload['submittedAnswers'];
    if (submittedAnswers is Map<String, dynamic>) {
      return AskUserQuestionResponse.fromJson(submittedAnswers);
    }
    if (submittedAnswers is Map) {
      return AskUserQuestionResponse.fromJson(
        Map<String, dynamic>.from(submittedAnswers),
      );
    }
    try {
      return AskUserQuestionResponse.fromJson(payload);
    } catch (_) {
      return null;
    }
  }

}
