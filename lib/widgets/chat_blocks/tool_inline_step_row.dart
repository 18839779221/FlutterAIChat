import 'package:ai_chat/models/chat/tool_card_presentation_model.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/widgets/tool_renderers/tool_running_effects.dart';
import 'package:flutter/material.dart';

/// Compact row used for low-noise context-gathering tool steps and results.
class ToolInlineStepRow extends StatelessWidget {
  final ToolCardPresentationModel model;

  const ToolInlineStepRow({
    super.key,
    required this.model,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return SubtleRunningBreathingSurface(
      isRunning: model.isRunning,
      baseColor: colors.structuredSurface.withValues(alpha: 0.42),
      borderRadius: BorderRadius.circular(radius.sm + 1),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: spacing.xs + spacing.xxs,
          vertical: spacing.xs - 1,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                RunningStatusDot(
                  color: colors.workflowRunning,
                  isRunning: model.isRunning,
                  size: 8,
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: Text(
                    model.title,
                    style: TextStyle(
                      color: colors.primaryText,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if ((model.statusLabel ?? '').isNotEmpty)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: spacing.xs,
                      vertical: spacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: colors.workflowRunning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(radius.pill),
                    ),
                    child: Text(
                      model.statusLabel!,
                      style: TextStyle(
                        color: colors.workflowRunning,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: spacing.xxs),
            Text(
              model.summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.secondaryText,
                fontSize: 10.5,
                height: 1.28,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
