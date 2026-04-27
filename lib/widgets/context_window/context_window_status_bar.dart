import 'package:flutter/material.dart';

import '../../models/session/context_window_snapshot.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';

class ContextWindowStatusBar extends StatelessWidget {
  const ContextWindowStatusBar({
    super.key,
    required this.snapshot,
    required this.onTap,
  });

  final ContextWindowSnapshot snapshot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final ratio = snapshot.totalWindowUsageRatio.clamp(0.0, 1.0);

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.xs),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('context-window-status-bar'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius.pill),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.xs,
              vertical: spacing.xxs,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius.pill),
              child: LinearProgressIndicator(
                minHeight: 4,
                value: ratio,
                backgroundColor: colors.secondaryText.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(
                  _resolveValueColor(colors, ratio),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _resolveValueColor(AppColors colors, double ratio) {
    if (ratio >= snapshot.compressionTriggerRatio) {
      return colors.workflowWarning.withValues(alpha: 0.72);
    }
    if (ratio >= snapshot.compressionTriggerRatio * 0.85) {
      return colors.workflowRunning.withValues(alpha: 0.64);
    }
    return colors.secondaryText.withValues(alpha: 0.48);
  }
}
