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
      _appendBlock(blocks, block);

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
      case MessageContentType.askUserQuestionPrompt:
        return AssistantTurnBlock(
          id: '$turnId-question-prompt-$sequence',
          turnId: turnId,
          type: AssistantTurnBlockType.structuredOutput,
          sequence: sequence,
          createdAt: message.timestamp,
          updatedAt: message.timestamp,
          title: 'Question',
          text: message.text,
          payload: message.payloadJson,
        );
      case MessageContentType.askUserQuestionResult:
        return AssistantTurnBlock(
          id: '$turnId-question-result-$sequence',
          turnId: turnId,
          type: AssistantTurnBlockType.structuredOutput,
          sequence: sequence,
          createdAt: message.timestamp,
          updatedAt: message.timestamp,
          title: 'Answer',
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
        final stepId = _resolveWorkflowStepId(
          turnId: turnId,
          payload: message.payloadJson,
          sequence: sequence,
        );
        final step = ToolWorkflowStep(
          stepId: stepId,
          turnId: turnId,
          toolName: invocation.toolName,
          title: invocation.summary.isEmpty
              ? invocation.toolName
              : invocation.summary,
          summary: invocation.summary,
          status: _mapInvocationStatus(invocation.status),
          requiresConfirmation: invocation.requiresConfirmation,
          toolAccess: _readToolAccess(message.payloadJson),
          executionPolicy: _readExecutionPolicy(message.payloadJson),
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
      requiresConfirmation:
          message.contentType == MessageContentType.actionConfirmation,
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
      if (step.resolvedExecutionPolicy != null)
        'executionPolicy': step.resolvedExecutionPolicy,
      if (step.toolAccess != null) 'toolAccess': step.toolAccess,
      'details': step.details,
    };
  }

  String? _readExecutionPolicy(Map<String, dynamic>? payload) {
    final snapshotPolicy = _readToolAccess(payload)?['executionPolicy'];
    if (snapshotPolicy is String) {
      final trimmed = snapshotPolicy.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }

    final raw = payload?['executionPolicy'];
    if (raw is! String) {
      return null;
    }
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Map<String, dynamic>? _readToolAccess(Map<String, dynamic>? payload) {
    final raw = payload?['toolAccess'];
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return raw.cast<String, dynamic>();
    }
    return null;
  }

  String _resolveWorkflowStepId({
    required String turnId,
    required Map<String, dynamic>? payload,
    required int sequence,
  }) {
    final rawStepId = payload?['stepId'];
    if (rawStepId is int) {
      return '$turnId-step-$rawStepId';
    }
    if (rawStepId is String && rawStepId.trim().isNotEmpty) {
      return '$turnId-step-${rawStepId.trim()}';
    }
    return '$turnId-step-$sequence';
  }

  void _appendBlock(
    List<AssistantTurnBlock> blocks,
    AssistantTurnBlock block,
  ) {
    if (block.type == AssistantTurnBlockType.toolResultSummary) {
      final merged = _tryMergeResultIntoWorkflow(blocks, block);
      if (merged) {
        return;
      }
      blocks.add(block);
      return;
    }

    if (block.type != AssistantTurnBlockType.toolWorkflow || blocks.isEmpty) {
      blocks.add(block);
      return;
    }

    final previous = blocks.last;
    if (previous.type != AssistantTurnBlockType.toolWorkflow ||
        previous.turnId != block.turnId) {
      blocks.add(block);
      return;
    }

    final previousSteps = (previous.payload?['steps'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        const <Map<String, dynamic>>[];
    final nextSteps = (block.payload?['steps'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        const <Map<String, dynamic>>[];
    if (previousSteps.isEmpty || nextSteps.isEmpty) {
      blocks.add(block);
      return;
    }

    final previousToolName = (previousSteps.last['toolName'] ?? '').toString();
    final nextToolName = (nextSteps.first['toolName'] ?? '').toString();
    if (previousToolName.isEmpty ||
        nextToolName.isEmpty ||
        previousToolName != nextToolName) {
      blocks.add(block);
      return;
    }

    final nextStep = nextSteps.first;
    final nextStepId = (nextStep['stepId'] ?? '').toString();
    if (nextStepId.isEmpty) {
      blocks.add(block);
      return;
    }

    final replacedSteps = previousSteps
        .map((step) => step['stepId'] == nextStepId ? nextStep : step)
        .toList();
    final alreadyTracked =
        previousSteps.any((step) => step['stepId'] == nextStepId);
    final mergedSteps =
        alreadyTracked ? replacedSteps : [...previousSteps, nextStep];
    final latestStep = mergedSteps.last;

    blocks[blocks.length - 1] = previous.copyWith(
      updatedAt: block.updatedAt,
      status: latestStep['status']?.toString(),
      title: latestStep['title']?.toString() ?? block.title,
      text: latestStep['summary']?.toString() ?? block.text,
      payload: {
        ...?previous.payload,
        ...?block.payload,
        'sourceMessageId':
            block.payload?['sourceMessageId'] ?? previous.payload?['sourceMessageId'],
        'steps': mergedSteps,
      },
    );
  }

  bool _tryMergeResultIntoWorkflow(
    List<AssistantTurnBlock> blocks,
    AssistantTurnBlock block,
  ) {
    if (blocks.isEmpty || block.turnId.isEmpty) {
      return false;
    }

    final payload = block.payload;
    final toolName = (payload?['toolName'] ?? '').toString().trim();
    if (toolName.isEmpty) {
      return false;
    }

    for (var index = blocks.length - 1; index >= 0; index -= 1) {
      final candidate = blocks[index];
      if (candidate.turnId != block.turnId) {
        continue;
      }
      if (candidate.type != AssistantTurnBlockType.toolWorkflow) {
        continue;
      }

      final candidateSteps = (candidate.payload?['steps'] as List?)
              ?.whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList() ??
          const <Map<String, dynamic>>[];
      if (candidateSteps.isEmpty) {
        continue;
      }

      final stepIndex = candidateSteps.lastIndexWhere(
        (step) => (step['toolName'] ?? '').toString() == toolName,
      );
      if (stepIndex == -1) {
        continue;
      }

      final currentStep = candidateSteps[stepIndex];
      final resultStatus = (payload?['status'] ?? '').toString();
      final workflowStatus = switch (resultStatus) {
        'success' => ToolWorkflowStepStatus.completed.name,
        'failure' => ToolWorkflowStepStatus.failed.name,
        _ => currentStep['status']?.toString() ?? ToolWorkflowStepStatus.completed.name,
      };
      final mergedStep = {
        ...currentStep,
        'title': payload?['summary'] ?? currentStep['title'],
        'summary': payload?['summary'] ?? currentStep['summary'],
        'status': workflowStatus,
        if (payload?['executionPolicy'] != null)
          'executionPolicy': payload?['executionPolicy'],
        if (payload?['toolAccess'] != null) 'toolAccess': payload?['toolAccess'],
        'details': {
          ...?(currentStep['details'] is Map
              ? Map<String, dynamic>.from(currentStep['details'] as Map)
              : null),
          if (payload?['data'] is Map)
            ...Map<String, dynamic>.from(payload?['data'] as Map),
        },
      };
      final nextSteps = [...candidateSteps];
      nextSteps[stepIndex] = mergedStep;
      blocks[index] = candidate.copyWith(
        updatedAt: block.updatedAt,
        status: workflowStatus,
        title: mergedStep['title']?.toString(),
        text: mergedStep['summary']?.toString(),
        payload: {
          ...?candidate.payload,
          'steps': nextSteps,
        },
      );
      return true;
    }

    return false;
  }
}
