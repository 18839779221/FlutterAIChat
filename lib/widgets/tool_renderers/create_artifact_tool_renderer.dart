import 'package:flutter/widgets.dart';

import '../../models/chat/tool_phase_visibility.dart';
import '../../models/chat/tool_presentation_event.dart';
import '../../models/chat/tool_workflow_step.dart';
import '../../models/chat_message.dart';
import '../../models/tool/tool_result.dart';
import '../../services/tool_ui_renderer_registry.dart';

/// Artifact creation delegates visible delivery to the artifact projection
/// surface, so its transcript phases stay hidden from the default timeline.
class CreateArtifactToolUiRenderer extends ToolUiRenderer {
  const CreateArtifactToolUiRenderer();

  @override
  Widget? buildResult(
    BuildContext context, {
    required ToolResult result,
    required ChatMessage? sourceMessage,
  }) {
    return null;
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
  bool supportsResult(String toolName) => toolName.trim() == 'create_artifact';

  @override
  bool supportsWorkflowStep(String toolName) =>
      toolName.trim() == 'create_artifact';

  @override
  ToolPhaseVisibility visibilityForPhase(
    String toolName,
    ToolPresentationEventPhase phase,
  ) {
    if (toolName.trim() == 'create_artifact') {
      return ToolPhaseVisibility.hidden;
    }
    return ToolPhaseVisibility.visible;
  }
}
