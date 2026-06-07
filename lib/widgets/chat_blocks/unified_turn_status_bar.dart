import 'package:ai_chat/models/chat/active_turn_status_presentation.dart';
import 'package:ai_chat/theme/app_motion.dart';
import 'package:ai_chat/theme/app_radius.dart';
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
    this.variant = UnifiedTurnStatusBarVariant.inline,
    this.isRunning = true,
    this.textSweepDuration = const Duration(milliseconds: 2500),
  });

  final ActiveTurnStatusPresentation status;
  final UnifiedTurnStatusBarVariant variant;
  final bool isRunning;
  final Duration textSweepDuration;

  bool get _isFloating => variant == UnifiedTurnStatusBarVariant.floating;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final motion = Theme.of(context).extension<AppMotion>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;

    final borderRadius =
        BorderRadius.circular(_isFloating ? radius.lg + 8 : 999);
    final padding = _isFloating
        ? EdgeInsets.fromLTRB(
            spacing.sm,
            spacing.xs,
            spacing.sm + 1,
            spacing.xs,
          )
        : EdgeInsets.symmetric(
            horizontal: spacing.xs + 1,
            vertical: spacing.xxs + 1,
          );
    final textStyle = AppTypography.uiStyle(
      color: (_isFloating ? colors.primaryText : colors.secondaryText)
          .withValues(alpha: _isFloating ? 0.84 : 0.88),
      fontSize: _isFloating ? 12 : 11.5,
      fontWeight: FontWeight.w700,
      height: 1.18,
    );

    return AnimatedOpacity(
      duration: motion.quick,
      curve: motion.easeOut,
      opacity: 1,
      child: Padding(
        padding: EdgeInsets.only(top: spacing.xs),
        child: DecoratedBox(
          decoration: _isFloating
              ? BoxDecoration(
                  borderRadius: borderRadius,
                  boxShadow: [
                    BoxShadow(
                      color: colors.primaryText.withValues(alpha: 0.055),
                      blurRadius: 18,
                      offset: const Offset(0, 9),
                    ),
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.36),
                      blurRadius: 1,
                      offset: const Offset(0, -1),
                    ),
                  ],
                )
              : const BoxDecoration(),
          child: RunningSweepSurface(
            isRunning: isRunning,
            duration: const Duration(milliseconds: 2600),
            showBorder: false,
            sweepOpacity: _isFloating ? 0.42 : 0.58,
            borderRadius: borderRadius,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.assistantSurface.withValues(
                  alpha: _isFloating ? 0.96 : 0.11,
                ),
                borderRadius: borderRadius,
                border: _isFloating
                    ? Border.all(
                        color: colors.divider.withValues(alpha: 0.55),
                      )
                    : null,
              ),
              child: Padding(
                key: const ValueKey('latest-message-running-tail'),
                padding: padding,
                child: RunningSweepStatusLine(
                  text: status.text,
                  style: textStyle,
                  dotColor: colors.workflowRunning,
                  isRunning: isRunning,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  visibleSweepDuration: textSweepDuration,
                  dotSize: _isFloating ? 7 : 6.5,
                  dotSpacing: spacing.xs,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum UnifiedTurnStatusBarVariant {
  inline,
  floating,
}
