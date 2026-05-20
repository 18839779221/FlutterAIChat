import 'package:flutter/material.dart';

import 'app_theme_spec.dart';

/// Convenience accessors for the active app theme spec.
extension AppThemeContext on BuildContext {
  AppThemeSpec get appThemeSpec => AppThemeSpec.of(this);
}
