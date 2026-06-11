import 'package:flutter/material.dart';

import '../../models/session/context_window_snapshot.dart';
import '../../theme/app_theme_spec.dart';
import '../../theme/app_typography.dart';
import 'context_window_usage_color.dart';

/// Inline context usage affordance shown on the second row of the composer.
///
/// The UI keeps a very light visual footprint while still exposing the current
/// fill percentage directly to the user and preserving tap access to details.
class ContextWindowUsageIndicator extends StatelessWidget {
  const ContextWindowUsageIndicator({
    super.key,
    required this.snapshot,
    required this.onTap,
  });

  /// Snapshot that drives the visible percentage and progress ring.
  final ContextWindowSnapshot snapshot;

  /// Triggered when the user opens the detailed context window breakdown.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final visibleRatio = snapshot.plannerInputUsageRatio.clamp(0.0, 1.0);
    final percent = (snapshot.plannerInputUsageRatio * 100).round();
    final accent = resolveContextWindowUsageColor(colors, snapshot);

    return Semantics(
      container: true,
      button: true,
      excludeSemantics: true,
      label: 'Planner 输入使用率 $percent%',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('context-window-usage-indicator'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      value: visibleRatio,
                      strokeWidth: 2,
                      backgroundColor:
                          colors.secondaryText.withValues(alpha: 0.12),
                      valueColor: AlwaysStoppedAnimation<Color>(accent),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$percent%',
                    style: AppTypography.uiStyle(
                      color: accent,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      height: 1.0,
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
