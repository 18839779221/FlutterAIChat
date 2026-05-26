import 'package:flutter/material.dart';

import '../../theme/app_theme_spec.dart';

/// Maps project theme semantics to stable CSS variables for artifact rendering.
class ArtifactThemeTokenMapper {
  const ArtifactThemeTokenMapper();

  static Map<String, String> fromSpec(AppThemeSpec spec) {
    return <String, String>{
      '--app-artifact-page-bg': _hex(spec.artifactPageBackground),
      '--app-artifact-surface': _hex(spec.artifactSurface),
      '--app-artifact-surface-muted': _hex(spec.artifactSurfaceMuted),
      '--app-artifact-text-primary': _hex(spec.artifactTextPrimary),
      '--app-artifact-text-secondary': _hex(spec.artifactTextSecondary),
      '--app-artifact-text-tertiary': _hex(spec.artifactTextTertiary),
      '--app-artifact-border-subtle': _hex(spec.artifactBorderSubtle),
      '--app-artifact-border-strong': _hex(spec.artifactBorderStrong),
      '--app-artifact-accent': _hex(spec.artifactAccent),
      '--app-artifact-success': _hex(spec.workflowSuccess),
      '--app-artifact-warning': _hex(spec.workflowWarning),
      '--app-artifact-error': _hex(spec.semantic.state.error),
      '--app-artifact-info': _hex(spec.semantic.state.info),
      '--app-artifact-chart-1': _hex(spec.artifactChart1),
      '--app-artifact-chart-2': _hex(spec.artifactChart2),
      '--app-artifact-chart-3': _hex(spec.artifactChart3),
      '--app-artifact-chart-4': _hex(spec.artifactChart4),
      '--app-artifact-chart-5': _hex(spec.artifactChart5),
      '--app-artifact-chart-grid': _hex(spec.artifactChartGrid),
      '--app-artifact-chart-axis': _hex(spec.artifactChartAxis),
      '--app-artifact-chart-highlight': _hex(spec.artifactChartHighlight),
      '--app-artifact-space-1': _px(spec.core.spacing.xxs),
      '--app-artifact-space-2': _px(spec.core.spacing.xs),
      '--app-artifact-space-3': _px(spec.core.spacing.sm),
      '--app-artifact-space-4': _px(spec.core.spacing.md),
      '--app-artifact-space-5': _px(spec.core.spacing.lg),
      '--app-artifact-space-6': _px(spec.core.spacing.xl),
      '--app-artifact-radius-sm': _px(spec.core.radius.sm),
      '--app-artifact-radius-md': _px(spec.core.radius.md),
      '--app-artifact-radius-lg': _px(spec.core.radius.lg),
      '--app-artifact-font-ui': _fontStack(
        spec.core.typography.uiFontFamily,
        spec.core.typography.documentFontFallback,
      ),
      '--app-artifact-font-code': _fontStack(
        spec.core.typography.codeFontFamily,
      ),
      '--app-artifact-shadow-soft':
          '0 1px 3px ${_rgba(spec.core.elevation.shadowColor)}',
    };
  }

  static String _hex(Color color) {
    final a = (color.a * 255.0).round() & 0xff;
    if (a == 255) {
      final r = (color.r * 255.0).round() & 0xff;
      final g = (color.g * 255.0).round() & 0xff;
      final b = (color.b * 255.0).round() & 0xff;
      return '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}';
    }
    return _rgba(color);
  }

  static String _rgba(Color color) {
    final alpha = color.a.toStringAsFixed(3);
    final r = (color.r * 255.0).round() & 0xff;
    final g = (color.g * 255.0).round() & 0xff;
    final b = (color.b * 255.0).round() & 0xff;
    return 'rgba($r, $g, $b, $alpha)';
  }

  static String _px(double value) {
    if (value == value.roundToDouble()) {
      return '${value.toInt()}px';
    }
    return '${value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')}px';
  }

  static String _fontStack(String primary, [List<String> fallback = const []]) {
    final stack = <String>[primary, ...fallback];
    return stack.map(_quoteFontIfNeeded).join(', ');
  }

  static String _quoteFontIfNeeded(String name) {
    if (name.contains(' ') && !name.startsWith("'") && !name.startsWith('"')) {
      return "'$name'";
    }
    return name;
  }
}
