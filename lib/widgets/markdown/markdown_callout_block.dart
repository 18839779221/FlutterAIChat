import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// Document-style semantic callout rendered from Markdown `[!TYPE]` blocks.
class MarkdownCalloutBlock extends StatelessWidget {
  /// Normalized callout type used for semantic tone selection.
  final String type;

  /// Original author-provided type shown when the normalized type is generic.
  final String rawType;

  /// Optional human-readable title shown beside the type label.
  final String title;

  /// Body content rendered inside the callout surface.
  final Widget child;

  const MarkdownCalloutBlock({
    super.key,
    required this.type,
    required this.rawType,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final tone = _CalloutTone.resolve(context, type);
    final label = _displayLabel;
    final trimmedTitle = title.trim();

    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tone.backgroundColor,
          borderRadius: BorderRadius.circular(9),
          border: Border(
            left: BorderSide(
              color: tone.accentColor,
              width: 1.6,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 11, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    tone.icon,
                    size: 13,
                    color: tone.accentColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: AppTypography.uiStyle(
                      color: tone.headerColor,
                      fontSize: 11.5,
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                  if (trimmedTitle.isNotEmpty) ...[
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        trimmedTitle,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.documentStyle(
                          color: tone.titleColor,
                          fontSize: 12.8,
                          height: 1.2,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ] else
                    const Spacer(),
                ],
              ),
              const SizedBox(height: 7),
              DefaultTextStyle.merge(
                style: AppTypography.documentStyle(
                  color: tone.bodyColor,
                  fontSize: 13,
                  height: 1.5,
                ),
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _displayLabel {
    final normalized = type.trim().toUpperCase();
    final original = rawType.trim().toUpperCase();
    if (normalized == 'CALLOUT' && original.isNotEmpty) {
      return original;
    }
    return normalized.isEmpty ? 'CALLOUT' : normalized;
  }
}

class _CalloutTone {
  final Color backgroundColor;
  final Color accentColor;
  final Color headerColor;
  final Color titleColor;
  final Color bodyColor;
  final IconData icon;

  const _CalloutTone({
    required this.backgroundColor,
    required this.accentColor,
    required this.headerColor,
    required this.titleColor,
    required this.bodyColor,
    required this.icon,
  });

  static _CalloutTone resolve(BuildContext context, String type) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeSpec>()!;
    final isDark = theme.brightness == Brightness.dark;
    final normalized = type.trim().toUpperCase();

    Color mix(Color base, double alpha) => base.withValues(alpha: alpha);

    final bodyColor = colors.primaryText.withValues(alpha: isDark ? 0.9 : 0.86);
    final titleColor =
        colors.primaryText.withValues(alpha: isDark ? 0.94 : 0.9);
    final neutralAccent = colors.workflowRunning;

    switch (normalized) {
      case 'TIP':
        return _CalloutTone(
          backgroundColor: mix(colors.toolOutcomeSurface, isDark ? 0.42 : 0.34),
          accentColor: mix(colors.workflowSuccess, isDark ? 0.76 : 0.62),
          headerColor: mix(colors.workflowSuccess, isDark ? 0.9 : 0.78),
          titleColor: titleColor,
          bodyColor: bodyColor,
          icon: Icons.tips_and_updates_outlined,
        );
      case 'WARNING':
        return _CalloutTone(
          backgroundColor:
              mix(colors.toolExceptionSurface, isDark ? 0.42 : 0.34),
          accentColor: mix(colors.workflowWarning, isDark ? 0.82 : 0.72),
          headerColor: mix(colors.workflowWarning, isDark ? 0.92 : 0.82),
          titleColor: titleColor,
          bodyColor: bodyColor,
          icon: Icons.warning_amber_rounded,
        );
      case 'RESULT':
        return _CalloutTone(
          backgroundColor: mix(colors.toolOutcomeSurface, isDark ? 0.45 : 0.36),
          accentColor: mix(colors.workflowSuccess, isDark ? 0.78 : 0.66),
          headerColor: mix(colors.workflowSuccess, isDark ? 0.92 : 0.8),
          titleColor: titleColor,
          bodyColor: bodyColor,
          icon: Icons.check_circle_outline,
        );
      case 'SOURCES':
        return _CalloutTone(
          backgroundColor: mix(colors.assistantSurface, isDark ? 0.36 : 0.24),
          accentColor: mix(colors.secondaryText, isDark ? 0.54 : 0.42),
          headerColor: mix(colors.secondaryText, isDark ? 0.78 : 0.68),
          titleColor: titleColor,
          bodyColor: bodyColor,
          icon: Icons.link_outlined,
        );
      case 'NOTE':
      case 'CALLOUT':
      default:
        return _CalloutTone(
          backgroundColor: mix(colors.structuredSurface, isDark ? 0.38 : 0.28),
          accentColor: mix(neutralAccent, isDark ? 0.66 : 0.52),
          headerColor: mix(neutralAccent, isDark ? 0.86 : 0.72),
          titleColor: titleColor,
          bodyColor: bodyColor,
          icon: Icons.info_outline,
        );
    }
  }
}
