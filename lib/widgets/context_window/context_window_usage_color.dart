import 'package:flutter/material.dart';

import '../../models/session/context_window_snapshot.dart';
import '../../theme/app_colors.dart';

/// Returns the semantic usage accent color for the current context window fill.
Color resolveContextWindowUsageColor(
  AppColors colors,
  ContextWindowSnapshot snapshot,
) {
  final ratio = snapshot.totalWindowUsageRatio.clamp(0.0, 1.0);
  final trigger = snapshot.compressionTriggerRatio;
  if (ratio >= trigger) {
    return colors.workflowWarning.withValues(alpha: 0.72);
  }
  if (ratio >= trigger * 0.85) {
    return colors.workflowRunning.withValues(alpha: 0.64);
  }
  return colors.secondaryText.withValues(alpha: 0.48);
}
