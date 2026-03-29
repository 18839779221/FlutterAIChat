import 'package:ai_chat/models/chat/tool_workflow_step.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  group('tool workflow expansion state', () {
    test('auto expands awaiting or running step when no manual selection exists', () {
      final steps = [
        _step('completed-step', ToolWorkflowStepStatus.completed),
        _step('running-step', ToolWorkflowStepStatus.running),
      ];

      expect(
        resolveWorkflowExpandedStepId(
          turnId: 'turn-1',
          steps: steps,
          manualExpandedStepId: null,
        ),
        'running-step',
      );
    });

    test('failed step stays expanded ahead of manual selection', () {
      final steps = [
        _step('failed-step', ToolWorkflowStepStatus.failed),
        _step('completed-step', ToolWorkflowStepStatus.completed),
      ];

      expect(
        resolveWorkflowExpandedStepId(
          turnId: 'turn-1',
          steps: steps,
          manualExpandedStepId: 'completed-step',
        ),
        'failed-step',
      );
    });

    test('manual selection is used after workflow is completed', () {
      final steps = [
        _step('step-1', ToolWorkflowStepStatus.completed),
        _step('step-2', ToolWorkflowStepStatus.completed),
      ];

      expect(
        resolveWorkflowExpandedStepId(
          turnId: 'turn-1',
          steps: steps,
          manualExpandedStepId: 'step-2',
        ),
        'step-2',
      );
    });

    test('toggle keeps one expanded step per turn and supports collapse', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(toolWorkflowExpansionProvider.notifier);

      notifier.toggleExpandedStep(turnId: 'turn-1', stepId: 'step-1');
      expect(
        container.read(toolWorkflowExpansionProvider)['turn-1'],
        'step-1',
      );

      notifier.toggleExpandedStep(turnId: 'turn-1', stepId: 'step-2');
      expect(
        container.read(toolWorkflowExpansionProvider)['turn-1'],
        'step-2',
      );

      notifier.toggleExpandedStep(turnId: 'turn-1', stepId: 'step-2');
      expect(
        container.read(toolWorkflowExpansionProvider).containsKey('turn-1'),
        isFalse,
      );
    });
  });
}

ToolWorkflowStep _step(String id, ToolWorkflowStepStatus status) {
  return ToolWorkflowStep(
    stepId: id,
    turnId: 'turn-1',
    toolName: id,
    title: id,
    summary: id,
    status: status,
    requiresConfirmation: false,
  );
}
