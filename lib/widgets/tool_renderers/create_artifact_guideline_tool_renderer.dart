import 'package:flutter/widgets.dart';

import '../../models/chat/tool_phase_visibility.dart';
import '../../models/chat/tool_presentation_event.dart';
import '../../models/chat/tool_workflow_step.dart';
import '../../models/chat_message.dart';
import '../../models/tool/tool_result.dart';
import '../../services/tool_ui_renderer_registry.dart';
import 'compact_tool_row_renderer.dart';

/// Keeps the artifact guideline step visible as a minimal timeline hint
/// without surfacing model-facing contract details to the user.
class CreateArtifactGuidelineToolUiRenderer extends ToolUiRenderer {
  const CreateArtifactGuidelineToolUiRenderer();

  static const String _toolName = 'create_artifact__guideline';

  @override
  Widget? buildResult(
    BuildContext context, {
    required ToolResult result,
    required ChatMessage? sourceMessage,
  }) {
    return const CompactToolRow(
      model: CompactToolRowModel(
        actionLabel: '规范',
        primaryText: '已加载可视化规范',
        statusLabel: '完成',
        status: CompactToolRowStatus.success,
      ),
    );
  }

  @override
  Widget? buildWorkflowStep(
    BuildContext context, {
    required List<ToolWorkflowStep> steps,
    required ChatMessage? sourceMessage,
    required bool isExpanded,
    required VoidCallback? onTap,
  }) {
    return null;
  }

  @override
  bool supportsResult(String toolName) => toolName.trim() == _toolName;

  @override
  bool supportsWorkflowStep(String toolName) => toolName.trim() == _toolName;

  @override
  ToolPhaseVisibility visibilityForPhase(
    String toolName,
    ToolPresentationEventPhase phase,
  ) {
    if (toolName.trim() == _toolName && phase != ToolPresentationEventPhase.result) {
      return ToolPhaseVisibility.hidden;
    }
    return ToolPhaseVisibility.visible;
  }
}
