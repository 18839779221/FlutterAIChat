import 'package:ai_chat/models/chat/active_turn_status_presentation.dart';
import 'package:ai_chat/theme/app_motion.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_typography.dart';
import 'package:ai_chat/widgets/tool_renderers/tool_running_effects.dart';
import 'package:flutter/material.dart';

/// Shared primary running-status surface used by both inline and floating hosts.
class UnifiedTurnStatusBar extends StatelessWidget {
  const UnifiedTurnStatusBar({
    super.key,
    required this.status,
  });

  final ActiveTurnStatusPresentation status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final motion = Theme.of(context).extension<AppMotion>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;

    return AnimatedOpacity(
      duration: motion.quick,
      curve: motion.easeOut,
      opacity: 1,
      child: Padding(
        padding: EdgeInsets.only(top: spacing.xs),
        child: RunningSweepSurface(
          isRunning: true,
          duration: const Duration(milliseconds: 2600),
          showBorder: false,
          sweepOpacity: 0.58,
          borderRadius: BorderRadius.circular(999),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.assistantSurface.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Padding(
              key: const ValueKey('latest-message-running-tail'),
              padding: EdgeInsets.symmetric(
                horizontal: spacing.xs + 1,
                vertical: spacing.xxs + 1,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RunningStatusDot(
                    color: colors.workflowRunning,
                    isRunning: true,
                    size: 6.5,
                    margin: EdgeInsets.only(right: spacing.xs),
                  ),
                  Flexible(
                    child: Text(
                      status.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.uiStyle(
                        color: colors.secondaryText.withValues(alpha: 0.88),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        height: 1.18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
