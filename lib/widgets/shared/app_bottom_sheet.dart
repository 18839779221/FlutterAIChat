import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme_spec.dart';

/// Shared height presets for modal bottom sheets in the app.
enum AppBottomSheetMode {
  adaptive,
  fixed80,
}

/// Opens a modal bottom sheet with the app's shared shell and interactions.
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required AppBottomSheetMode mode,
  required Widget body,
  String? title,
  String? subtitle,
  EdgeInsetsGeometry? bodyPadding,
  bool useSafeArea = true,
  bool useRootNavigator = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: useRootNavigator,
    isDismissible: true,
    enableDrag: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AppBottomSheetScaffold(
      mode: mode,
      title: title,
      subtitle: subtitle,
      bodyPadding: bodyPadding,
      useSafeArea: useSafeArea,
      body: body,
    ),
  );
}

/// Shared outer shell that keeps the drag handle fixed above the content area.
class AppBottomSheetScaffold extends StatelessWidget {
  const AppBottomSheetScaffold({
    super.key,
    required this.mode,
    required this.body,
    this.title,
    this.subtitle,
    this.bodyPadding,
    this.useSafeArea = true,
  });

  final AppBottomSheetMode mode;
  final Widget body;
  final String? title;
  final String? subtitle;
  final EdgeInsetsGeometry? bodyPadding;
  final bool useSafeArea;

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final bottomInset = useSafeArea
        ? math.max(viewInsets.bottom, viewPadding.bottom)
        : viewInsets.bottom;
    final hasHeader =
        (title ?? '').trim().isNotEmpty || (subtitle ?? '').trim().isNotEmpty;
    final content = bodyPadding == null
        ? body
        : Padding(
            padding: bodyPadding!,
            child: body,
          );
    final shell = Container(
      key: const ValueKey('app-bottom-sheet'),
      decoration: BoxDecoration(
        color: colors.chatBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(radius.lg)),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: spacing.sm),
            Center(
              child: Container(
                key: const ValueKey('app-bottom-sheet-drag-handle'),
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.secondaryText.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(radius.pill),
                ),
              ),
            ),
            if (hasHeader)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  spacing.lg,
                  spacing.md,
                  spacing.lg,
                  spacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if ((title ?? '').trim().isNotEmpty)
                      Text(
                        title!.trim(),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: colors.primaryText,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    if ((subtitle ?? '').trim().isNotEmpty) ...[
                      SizedBox(height: spacing.xs),
                      Text(
                        subtitle!.trim(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.secondaryText,
                              height: 1.4,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            if (!hasHeader) SizedBox(height: spacing.md),
            Flexible(
              fit: mode == AppBottomSheetMode.fixed80
                  ? FlexFit.tight
                  : FlexFit.loose,
              child: content,
            ),
          ],
        ),
      ),
    );

    final constrainedShell = mode == AppBottomSheetMode.fixed80
        ? FractionallySizedBox(
            heightFactor: 0.8,
            alignment: Alignment.bottomCenter,
            child: shell,
          )
        : ConstrainedBox(
            constraints: BoxConstraints(maxHeight: screenHeight * 0.8),
            child: shell,
          );

    final aligned = Align(
      alignment: Alignment.bottomCenter,
      child: constrainedShell,
    );

    if (!useSafeArea) {
      return aligned;
    }
    return aligned;
  }
}
