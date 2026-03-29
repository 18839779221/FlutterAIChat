import 'package:ai_chat/models/chat/assistant_turn_block.dart';
import 'package:ai_chat/models/chat/tool_workflow_step.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/models/tool/tool_result.dart';

/// Builds UI-facing assistant turn blocks from existing persisted chat messages.
class ChatBlockBuilder {
  List<AssistantTurnBlock> buildAssistantBlocks({
    required List<ChatMessage> messages,
    int? groupId,
  }) {
    final sortedMessages = [...messages]
      ..sort((left, right) => left.timestamp.compareTo(right.timestamp));

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

      if (block.type == AssistantTurnBlockType.analysis) {
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
      case MessageContentType.structuredCard:
        return AssistantTurnBlock(
          id: '$turnId-structured-$sequence',
          turnId: turnId,
          type: AssistantTurnBlockType.structuredOutput,
          sequence: sequence,
          createdAt: message.timestamp,
          updatedAt: message.timestamp,
          title: message.payloadJson?['title'] as String?,
          text: message.text,
          payload: message.payloadJson,
        );
      case MessageContentType.toolInvocation:
      case MessageContentType.actionConfirmation:
        final invocation = _readToolInvocation(message);
        if (invocation.toolName.isEmpty) {
          return AssistantTurnBlock(
            id: '$turnId-analysis-$sequence',
            turnId: turnId,
            type: AssistantTurnBlockType.analysis,
            sequence: sequence,
            createdAt: message.timestamp,
            updatedAt: message.timestamp,
            text: message.text,
            payload: message.payloadJson,
          );
        }
        final step = ToolWorkflowStep(
          stepId: '$turnId-step-$sequence',
          turnId: turnId,
          toolName: invocation.toolName,
          title: invocation.summary.isEmpty ? invocation.toolName : invocation.summary,
          summary: invocation.summary,
          status: _mapInvocationStatus(invocation.status),
          requiresConfirmation: invocation.requiresConfirmation,
          details: invocation.arguments,
        );
        return AssistantTurnBlock(
          id: '$turnId-workflow-$sequence',
          turnId: turnId,
          type: AssistantTurnBlockType.toolWorkflow,
          sequence: sequence,
          createdAt: message.timestamp,
          updatedAt: message.timestamp,
          status: step.status.name,
          title: step.title,
          text: step.summary,
          payload: {
            'sourceMessageId': message.id,
            'steps': [_stepToJson(step)],
          },
        );
      case MessageContentType.toolResult:
        final result = _readToolResult(message);
        if (result.toolName.isEmpty || result.summary.isEmpty) {
          return AssistantTurnBlock(
            id: '$turnId-analysis-$sequence',
            turnId: turnId,
            type: AssistantTurnBlockType.analysis,
            sequence: sequence,
            createdAt: message.timestamp,
            updatedAt: message.timestamp,
            text: message.text,
            payload: message.payloadJson,
          );
        }
        return AssistantTurnBlock(
          id: '$turnId-tool-result-$sequence',
          turnId: turnId,
          type: AssistantTurnBlockType.toolResultSummary,
          sequence: sequence,
          createdAt: message.timestamp,
          updatedAt: message.timestamp,
          status: result.status.name,
          title: result.toolName,
          text: result.summary,
          payload: {
            'sourceMessageId': message.id,
            ...result.toJson(),
          },
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

  ToolInvocation _readToolInvocation(ChatMessage message) {
    final payload = message.payloadJson;
    if (payload != null) {
      try {
        return ToolInvocation.fromJson(payload);
      } catch (_) {
        return ToolInvocation(
          toolName: '',
          arguments: const {},
          status: ToolInvocationStatus.proposed,
          summary: message.text,
          requiresConfirmation: false,
        );
      }
    }
    return ToolInvocation(
      toolName: '',
      arguments: const {},
      status: ToolInvocationStatus.proposed,
      summary: message.text,
      requiresConfirmation: message.contentType ==
          MessageContentType.actionConfirmation,
    );
  }

  ToolResult _readToolResult(ChatMessage message) {
    final payload = message.payloadJson;
    if (payload != null) {
      try {
        return ToolResult.fromJson(payload);
      } catch (_) {
        return ToolResult(
          toolName: '',
          status: ToolExecutionStatus.failure,
          summary: message.text,
        );
      }
    }
    return ToolResult(
      toolName: '',
      status: ToolExecutionStatus.success,
      summary: message.text,
    );
  }

  ToolWorkflowStepStatus _mapInvocationStatus(ToolInvocationStatus status) {
    switch (status) {
      case ToolInvocationStatus.proposed:
        return ToolWorkflowStepStatus.proposed;
      case ToolInvocationStatus.awaitingConfirmation:
        return ToolWorkflowStepStatus.awaitingConfirmation;
      case ToolInvocationStatus.running:
        return ToolWorkflowStepStatus.running;
      case ToolInvocationStatus.cancelled:
        return ToolWorkflowStepStatus.cancelled;
    }
  }

  Map<String, dynamic> _stepToJson(ToolWorkflowStep step) {
    return {
      'stepId': step.stepId,
      'turnId': step.turnId,
      'toolName': step.toolName,
      'title': step.title,
      'summary': step.summary,
      'status': step.status.name,
      'requiresConfirmation': step.requiresConfirmation,
      'details': step.details,
    };
  }
}
