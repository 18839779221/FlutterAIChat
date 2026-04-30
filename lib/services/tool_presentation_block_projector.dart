import 'package:ai_chat/models/chat/assistant_turn_block.dart';
import 'package:ai_chat/models/chat/tool_phase_visibility.dart';
import 'package:ai_chat/models/chat/tool_presentation_event.dart';
import 'package:ai_chat/models/chat/tool_workflow_step.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/services/tool_ui_renderer_registry.dart';

/// Projects standardized tool presentation events into timeline blocks.
///
/// This keeps tool workflow/result block construction on the presentation side
/// of the boundary instead of rebuilding those blocks directly from messages.
class ToolPresentationBlockProjector {
  const ToolPresentationBlockProjector({
    this.registry = const ToolUiRendererRegistry(),
  });

  final ToolUiRendererRegistry registry;

  List<AssistantTurnBlock> project({
    required List<ToolPresentationEvent> events,
  }) {
    if (events.isEmpty) {
      return const <AssistantTurnBlock>[];
    }

    final sortedEvents = [...events]
      ..sort((left, right) {
        final turnOrder = left.turnId.compareTo(right.turnId);
        if (turnOrder != 0) {
          return turnOrder;
        }
        final timeOrder = left.timestamp.compareTo(right.timestamp);
        if (timeOrder != 0) {
          return timeOrder;
        }
        return (left.sourceMessageId ?? 0).compareTo(right.sourceMessageId ?? 0);
      });

    final blocks = <AssistantTurnBlock>[];
    final sequenceByTurn = <String, int>{};

    for (final event in sortedEvents) {
      if (registry.visibilityForPhase(event.toolName, event.phase) ==
          ToolPhaseVisibility.hidden) {
        continue;
      }
      final nextSequence = (sequenceByTurn[event.turnId] ?? 0) + 1;
      sequenceByTurn[event.turnId] = nextSequence;
      final block = switch (event.phase) {
        ToolPresentationEventPhase.result => _buildResultBlock(
            event: event,
            sequence: nextSequence,
          ),
        ToolPresentationEventPhase.proposed ||
        ToolPresentationEventPhase.awaitingConfirmation ||
        ToolPresentationEventPhase.running =>
          _buildWorkflowBlock(
            event: event,
            sequence: nextSequence,
          ),
      };
      _appendBlock(blocks, block);
    }

    return blocks;
  }

  AssistantTurnBlock _buildWorkflowBlock({
    required ToolPresentationEvent event,
    required int sequence,
  }) {
    final step = ToolWorkflowStep(
      stepId: event.stepId ?? '${event.turnId}-step-$sequence',
      turnId: event.turnId,
      toolName: event.toolName,
      title: (event.data['summary'] ?? '').toString(),
      summary: (event.data['summary'] ?? '').toString(),
      status: _stepStatusForPhase(event.phase),
      requiresConfirmation: event.data['requiresConfirmation'] == true,
      executionPolicy: event.data['executionPolicy'] as String?,
      toolAccess: event.data['toolAccess'] is Map
          ? Map<String, dynamic>.from(event.data['toolAccess'] as Map)
          : null,
      details: event.data['arguments'] is Map
          ? Map<String, dynamic>.from(event.data['arguments'] as Map)
          : const <String, dynamic>{},
    );

    return AssistantTurnBlock(
      id: '${event.turnId}-workflow-$sequence',
      turnId: event.turnId,
      type: AssistantTurnBlockType.toolWorkflow,
      sequence: sequence,
      createdAt: event.timestamp,
      updatedAt: event.timestamp,
      status: step.status.name,
      title: step.title,
      text: step.summary,
      payload: {
        if (event.sourceMessageId != null) 'sourceMessageId': event.sourceMessageId,
        'steps': [
          {
            ..._stepToJson(step),
            if (event.providerCallId != null)
              'providerCallId': event.providerCallId,
          },
        ],
      },
      workflowSteps: [step],
    );
  }

  AssistantTurnBlock _buildResultBlock({
    required ToolPresentationEvent event,
    required int sequence,
  }) {
    final result = _toolResultFromEvent(event);
    return AssistantTurnBlock(
      id: '${event.turnId}-tool-result-$sequence',
      turnId: event.turnId,
      type: AssistantTurnBlockType.toolResultSummary,
      sequence: sequence,
      createdAt: event.timestamp,
      updatedAt: event.timestamp,
      status: result.status.name,
      title: result.toolName,
      text: result.summary,
      payload: {
        if (event.sourceMessageId != null) 'sourceMessageId': event.sourceMessageId,
        ...result.toJson(),
        if (event.providerCallId != null) 'providerCallId': event.providerCallId,
        if (event.stepId != null) 'stepId': event.stepId,
      },
      toolResult: result,
    );
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

    final previousSteps = _readStepMaps(previous);
    final nextSteps = _readStepMaps(block);
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
    final nextProviderCallId =
        (nextStep['providerCallId'] ?? '').toString().trim();

    final alreadyTracked = previousSteps.any((step) {
      if (step['stepId'] != nextStepId) {
        return false;
      }
      final previousProviderCallId =
          (step['providerCallId'] ?? '').toString().trim();
      if (previousProviderCallId.isEmpty || nextProviderCallId.isEmpty) {
        return previousProviderCallId == nextProviderCallId;
      }
      return previousProviderCallId == nextProviderCallId;
    });
    if (!alreadyTracked) {
      blocks.add(block);
      return;
    }

    final mergedSteps = previousSteps.map((step) {
      if (step['stepId'] != nextStepId) {
        return step;
      }
      final previousProviderCallId =
          (step['providerCallId'] ?? '').toString().trim();
      if (previousProviderCallId != nextProviderCallId) {
        return step;
      }
      return nextStep;
    }).toList();
    final latestStep = mergedSteps.last;

    blocks[blocks.length - 1] = previous.copyWith(
      updatedAt: block.updatedAt,
      status: latestStep['status']?.toString(),
      title: latestStep['title']?.toString() ?? block.title,
      text: latestStep['summary']?.toString() ?? block.text,
      payload: {
        ...?previous.payload,
        ...?block.payload,
        'sourceMessageId': block.payload?['sourceMessageId'] ??
            previous.payload?['sourceMessageId'],
        'steps': mergedSteps,
      },
      workflowSteps: mergedSteps.map(_stepFromJson).toList(growable: false),
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

      final candidateSteps = _readStepMaps(candidate);
      if (candidateSteps.isEmpty) {
        continue;
      }

      final stepIndex = _resolveToolResultStepIndex(
        candidateSteps: candidateSteps,
        toolName: toolName,
        payload: payload,
      );
      if (stepIndex == -1) {
        continue;
      }

      final currentStep = candidateSteps[stepIndex];
      final resultStatus = (payload?['status'] ?? '').toString();
      final workflowStatus = switch (resultStatus) {
        'success' => ToolWorkflowStepStatus.completed.name,
        'failure' => ToolWorkflowStepStatus.failed.name,
        _ => currentStep['status']?.toString() ??
            ToolWorkflowStepStatus.completed.name,
      };
      final mergedStep = {
        ...currentStep,
        'title': payload?['summary'] ?? currentStep['title'],
        'summary': payload?['summary'] ?? currentStep['summary'],
        'status': workflowStatus,
        if (payload?['executionPolicy'] != null)
          'executionPolicy': payload?['executionPolicy'],
        if (payload?['toolAccess'] != null)
          'toolAccess': payload?['toolAccess'],
        'details': {
          ...?(currentStep['details'] is Map
              ? Map<String, dynamic>.from(currentStep['details'] as Map)
              : null),
          if (payload?['data'] is Map)
            ...Map<String, dynamic>.from(payload?['data'] as Map),
        },
      };
      final sameToolStepCount = candidateSteps
          .where((step) => (step['toolName'] ?? '').toString() == toolName)
          .length;
      final shouldReplaceCurrentWorkflow = sameToolStepCount <= 1;

      if (shouldReplaceCurrentWorkflow) {
        blocks[index] = block.copyWith(
          turnId: candidate.turnId,
          sequence: candidate.sequence,
          createdAt: candidate.createdAt,
          updatedAt: block.updatedAt,
          payload: {
            ...?block.payload,
            'sourceMessageId': block.payload?['sourceMessageId'] ??
                candidate.payload?['sourceMessageId'],
          },
          toolResult: block.toolResult ?? _toolResultFromPayload(block.payload),
        );
      } else {
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
          workflowSteps: nextSteps.map(_stepFromJson).toList(growable: false),
        );
      }
      return true;
    }

    return false;
  }

  List<Map<String, dynamic>> _readStepMaps(AssistantTurnBlock block) {
    return (block.payload?['steps'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        const <Map<String, dynamic>>[];
  }

  int _resolveToolResultStepIndex({
    required List<Map<String, dynamic>> candidateSteps,
    required String toolName,
    required Map<String, dynamic>? payload,
  }) {
    final normalizedToolName = toolName.trim();
    final matchingIndexes = <int>[];
    for (var index = 0; index < candidateSteps.length; index += 1) {
      if ((candidateSteps[index]['toolName'] ?? '').toString() ==
          normalizedToolName) {
        matchingIndexes.add(index);
      }
    }
    if (matchingIndexes.isEmpty) {
      return -1;
    }

    final providerCallId = (payload?['providerCallId'] ?? '').toString().trim();
    if (providerCallId.isNotEmpty) {
      final exactIndex = matchingIndexes.lastWhere(
        (index) =>
            (candidateSteps[index]['providerCallId'] ?? '').toString() ==
            providerCallId,
        orElse: () => -1,
      );
      if (exactIndex != -1) {
        return exactIndex;
      }
      return -1;
    }

    final data = payload?['data'];
    if (data is Map) {
      final typedData = Map<String, dynamic>.from(data);
      final logicalResourceId = _firstNonEmptyString([
        typedData['resourceId'],
        typedData['artifactId'],
      ]);
      if (logicalResourceId != null) {
        final exactIndex = matchingIndexes.lastWhere(
          (index) =>
              _stepLogicalResourceId(candidateSteps[index]) == logicalResourceId,
          orElse: () => -1,
        );
        if (exactIndex != -1) {
          return exactIndex;
        }
        return -1;
      }

      final resultPath = _firstNonEmptyString([
        typedData['filePath'],
        typedData['sourcePath'],
        typedData['path'],
      ]);
      if (resultPath != null) {
        final exactIndex = matchingIndexes.lastWhere(
          (index) => _stepPrimaryPath(candidateSteps[index]) == resultPath,
          orElse: () => -1,
        );
        if (exactIndex != -1) {
          return exactIndex;
        }
        return -1;
      }
    }

    if (matchingIndexes.length == 1) {
      return matchingIndexes.single;
    }

    return matchingIndexes.last;
  }

  String? _stepLogicalResourceId(Map<String, dynamic> step) {
    final details = step['details'];
    if (details is! Map) {
      return null;
    }
    final typedDetails = Map<String, dynamic>.from(details);
    return _firstNonEmptyString([
      typedDetails['resourceId'],
      typedDetails['artifactId'],
      typedDetails['id'],
    ]);
  }

  String? _stepPrimaryPath(Map<String, dynamic> step) {
    final details = step['details'];
    if (details is! Map) {
      return null;
    }
    final typedDetails = Map<String, dynamic>.from(details);
    return _firstNonEmptyString([
      typedDetails['file_path'],
      typedDetails['filePath'],
      typedDetails['sourcePath'],
      typedDetails['path'],
    ]);
  }

  String? _firstNonEmptyString(List<Object?> values) {
    for (final value in values) {
      final trimmed = (value ?? '').toString().trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return null;
  }

  ToolWorkflowStepStatus _stepStatusForPhase(ToolPresentationEventPhase phase) {
    switch (phase) {
      case ToolPresentationEventPhase.proposed:
        return ToolWorkflowStepStatus.proposed;
      case ToolPresentationEventPhase.awaitingConfirmation:
        return ToolWorkflowStepStatus.awaitingConfirmation;
      case ToolPresentationEventPhase.running:
        return ToolWorkflowStepStatus.running;
      case ToolPresentationEventPhase.result:
        return ToolWorkflowStepStatus.completed;
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

  ToolWorkflowStep _stepFromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String? ?? 'proposed';
    final status = ToolWorkflowStepStatus.values.firstWhere(
      (value) => value.name == statusName,
      orElse: () => ToolWorkflowStepStatus.proposed,
    );

    return ToolWorkflowStep(
      stepId: json['stepId'] as String? ?? 'unknown-step',
      turnId: json['turnId'] as String? ?? '',
      toolName: json['toolName'] as String? ?? 'unknown_tool',
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      status: status,
      requiresConfirmation: json['requiresConfirmation'] as bool? ?? false,
      executionPolicy: json['executionPolicy'] as String?,
      toolAccess: json['toolAccess'] is Map
          ? Map<String, dynamic>.from(json['toolAccess'] as Map)
          : null,
      details: json['details'] is Map
          ? Map<String, dynamic>.from(json['details'] as Map)
          : const {},
    );
  }

  ToolResult _toolResultFromEvent(ToolPresentationEvent event) {
    return ToolResult.fromJson({
      'toolName': event.toolName,
      'status': event.data['status'] ?? 'success',
      'summary': event.data['summary'] ?? '',
      'data': event.data['data'] ?? const <String, dynamic>{},
      if (event.data['executionPolicy'] != null)
        'executionPolicy': event.data['executionPolicy'],
      if (event.data['toolAccess'] != null) 'toolAccess': event.data['toolAccess'],
      if (event.data['errorMessage'] != null)
        'errorMessage': event.data['errorMessage'],
    });
  }

  ToolResult? _toolResultFromPayload(Map<String, dynamic>? payload) {
    if (payload == null) {
      return null;
    }
    try {
      return ToolResult.fromJson(payload);
    } catch (_) {
      return null;
    }
  }
}
