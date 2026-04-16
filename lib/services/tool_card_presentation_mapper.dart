import 'package:ai_chat/models/chat/tool_card_presentation_model.dart';
import 'package:ai_chat/models/chat/tool_card_presentation_variant.dart';
import 'package:ai_chat/models/chat/tool_workflow_step.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/tools/core/tool_display_names.dart';

/// Maps raw workflow and result payloads into UI-facing semantic card variants.
class ToolCardPresentationMapper {
  /// Maps a workflow step into its semantic presentation model.
  static ToolCardPresentationModel mapStep(ToolWorkflowStep step) {
    final variant = switch (step.status) {
      ToolWorkflowStepStatus.awaitingConfirmation =>
        ToolCardPresentationVariant.confirmationStep,
      ToolWorkflowStepStatus.running => ToolCardPresentationVariant.focusedActiveStep,
      _ => ToolCardPresentationVariant.inlineStep,
    };

    return ToolCardPresentationModel(
      variant: variant,
      title: step.title.isEmpty ? resolveToolDisplayName(step.toolName) : step.title,
      summary: step.summary,
      primaryFields: _stringFields(step.details),
      statusLabel: _stepStatusLabel(step.status),
    );
  }

  /// Maps a tool result into its semantic presentation model.
  static ToolCardPresentationModel mapResult(ToolResult result) {
    final variant = result.shouldShowExceptionCard
        ? ToolCardPresentationVariant.exceptionCard
        : result.isOutcomeTool
            ? ToolCardPresentationVariant.outcomeCard
            : ToolCardPresentationVariant.inlineStep;

    return ToolCardPresentationModel(
      variant: variant,
      title: resolveToolDisplayName(result.toolName),
      summary: result.summary,
      primaryFields: _stringFields(result.data),
      statusLabel: result.statusLabel,
    );
  }

  static Map<String, String> _stringFields(Map<String, dynamic> data) {
    final fields = <String, String>{};
    for (final entry in data.entries) {
      final value = entry.value;
      if (value == null) {
        continue;
      }
      if (value is String && value.trim().isNotEmpty) {
        fields[entry.key] = value.trim();
        continue;
      }
      if (value is num || value is bool) {
        fields[entry.key] = '$value';
      }
    }
    return fields;
  }

  static String _stepStatusLabel(ToolWorkflowStepStatus status) {
    switch (status) {
      case ToolWorkflowStepStatus.awaitingConfirmation:
        return '待确认';
      case ToolWorkflowStepStatus.running:
        return '执行中';
      case ToolWorkflowStepStatus.completed:
        return '完成';
      case ToolWorkflowStepStatus.failed:
        return '失败';
      case ToolWorkflowStepStatus.cancelled:
        return '已取消';
      case ToolWorkflowStepStatus.proposed:
        return '已提议';
    }
  }
}
