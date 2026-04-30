import 'package:flutter/widgets.dart';

import '../models/chat/tool_phase_visibility.dart';
import '../models/chat/tool_presentation_event.dart';
import '../models/chat/tool_workflow_step.dart';
import '../models/chat_message.dart';
import '../models/tool/tool_result.dart';

/// Lightweight extension point that lets specific tools provide custom UI
/// while the timeline keeps a default fallback path.
abstract class ToolUiRenderer {
  const ToolUiRenderer();

  /// Whether this renderer owns workflow-step presentation for [toolName].
  bool supportsWorkflowStep(String toolName);

  /// Whether this renderer owns final-result presentation for [toolName].
  bool supportsResult(String toolName);

  /// Whether this renderer wants the given phase to remain visible in the
  /// default timeline projection.
  ToolPhaseVisibility visibilityForPhase(
    String toolName,
    ToolPresentationEventPhase phase,
  ) {
    return ToolPhaseVisibility.visible;
  }

  /// Builds a custom workflow widget. Return null to let the default card
  /// handle rendering.
  Widget? buildWorkflowStep(
    BuildContext context, {
    /// Full workflow history for the current block, ordered from oldest to
    /// newest step so tool-specific UIs can explain what happened.
    required List<ToolWorkflowStep> steps,
    required ChatMessage? sourceMessage,

    /// Whether the current workflow block is expanded by timeline state.
    required bool isExpanded,

    /// Shared tap handler that toggles the workflow block expansion state.
    required VoidCallback? onTap,
  });

  /// Builds a custom result widget. Return null to let the default card
  /// handle rendering.
  Widget? buildResult(
    BuildContext context, {
    required ToolResult result,
    required ChatMessage? sourceMessage,
  });
}

/// Registry for custom tool UI renderers. Callers should always handle the
/// null case by falling back to the default tool cards.
class ToolUiRendererRegistry {
  const ToolUiRendererRegistry({
    this.renderers = const <ToolUiRenderer>[],
  });

  final List<ToolUiRenderer> renderers;

  ToolUiRenderer? findWorkflowRenderer(String toolName) {
    final normalized = toolName.trim();
    if (normalized.isEmpty) {
      return null;
    }
    for (final renderer in renderers) {
      if (renderer.supportsWorkflowStep(normalized)) {
        return renderer;
      }
    }
    return null;
  }

  ToolUiRenderer? findResultRenderer(String toolName) {
    final normalized = toolName.trim();
    if (normalized.isEmpty) {
      return null;
    }
    for (final renderer in renderers) {
      if (renderer.supportsResult(normalized)) {
        return renderer;
      }
    }
    return null;
  }

  ToolPhaseVisibility visibilityForPhase(
    String toolName,
    ToolPresentationEventPhase phase,
  ) {
    final normalized = toolName.trim();
    if (normalized.isEmpty) {
      return ToolPhaseVisibility.visible;
    }
    for (final renderer in renderers) {
      final supportsTool = renderer.supportsWorkflowStep(normalized) ||
          renderer.supportsResult(normalized);
      if (!supportsTool) {
        continue;
      }
      final visibility = renderer.visibilityForPhase(normalized, phase);
      if (visibility == ToolPhaseVisibility.hidden) {
        return ToolPhaseVisibility.hidden;
      }
    }
    return ToolPhaseVisibility.visible;
  }
}
