import 'package:flutter/material.dart';

import '../../models/session/context_window_snapshot.dart';
import '../../theme/app_theme_spec.dart';

/// Returns the semantic usage accent color for the current context window fill.
Color resolveContextWindowUsageColor(
  AppThemeSpec colors,
  ContextWindowSnapshot snapshot,
) {
  final ratio = snapshot.totalWindowUsageRatio;
  if (ratio >= 1.0) {
    return colors.workflowWarning.withValues(alpha: 0.72);
  }
  if (ratio >= 0.85) {
    return colors.workflowRunning.withValues(alpha: 0.64);
  }
  return colors.secondaryText.withValues(alpha: 0.48);
}
