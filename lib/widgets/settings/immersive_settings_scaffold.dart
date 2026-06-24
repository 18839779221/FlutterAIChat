import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme_spec.dart';
import '../home_header_button.dart';

enum SettingsHeaderStyle { root, nested, editor }

const settingsFloatingHeaderSurfaceKey = ValueKey(
  'settings-floating-header-surface',
);

/// Shared immersive shell for settings-domain pages with a fixed floating header.
class ImmersiveSettingsScaffold extends StatelessWidget {
  const ImmersiveSettingsScaffold({
    super.key,
    required this.title,
    required this.body,
    this.headerStyle = SettingsHeaderStyle.root,
    this.leading,
    this.trailing,
    this.bodyPadding,
    this.maxContentWidth = 760,
    this.scrollController,
    this.centerTitle = true,
  });

  final String title;
  final Widget body;
  final SettingsHeaderStyle headerStyle;
  final Widget? leading;
  final Widget? trailing;
  final EdgeInsetsGeometry? bodyPadding;
  final double maxContentWidth;
  final ScrollController? scrollController;
  final bool centerTitle;

  static const double headerHeight = 56;
  static const double _headerRegionHeight = 104;

  static double contentStartPadding(
    BuildContext context, {
    required SettingsHeaderStyle headerStyle,
  }) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final topInset = MediaQuery.paddingOf(context).top +
        headerHeight +
        _topGapForStyle(headerStyle);
    switch (headerStyle) {
      case SettingsHeaderStyle.root:
        return topInset + spacing.lg;
      case SettingsHeaderStyle.nested:
      case SettingsHeaderStyle.editor:
        return topInset + spacing.md;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            isDarkTheme ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDarkTheme ? Brightness.dark : Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: colors.chatBackground,
        body: SizedBox.expand(
          child: Stack(
            children: [
              Positioned.fill(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxContentWidth),
                    child: Padding(
                      padding: _resolveBodyPadding(context),
                      child: body,
                    ),
                  ),
                ),
              ),
              const _SettingsTopOverlayVeil(),
              _SettingsFloatingHeader(
                title: title,
                headerStyle: headerStyle,
                leading: leading,
                trailing: trailing,
                centerTitle: centerTitle,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static double _topGapForStyle(SettingsHeaderStyle headerStyle) {
    switch (headerStyle) {
      case SettingsHeaderStyle.root:
        return 10;
      case SettingsHeaderStyle.nested:
      case SettingsHeaderStyle.editor:
        return 8;
    }
  }

  EdgeInsetsGeometry _resolveBodyPadding(BuildContext context) {
    if (bodyPadding != null) {
      return bodyPadding!;
    }
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final topInset =
        MediaQuery.paddingOf(context).top + headerHeight + _topGapForStyle(headerStyle);
    return EdgeInsets.fromLTRB(
      spacing.lg,
      topInset,
      spacing.lg,
      spacing.xl,
    );
  }
}

class _SettingsTopOverlayVeil extends StatelessWidget {
  const _SettingsTopOverlayVeil();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final topPadding = MediaQuery.paddingOf(context).top;
    final totalHeight =
        topPadding + ImmersiveSettingsScaffold._headerRegionHeight;
    final headerBottomFraction =
        ((topPadding + ImmersiveSettingsScaffold.headerHeight) / totalHeight)
            .clamp(0.0, 1.0);

    return IgnorePointer(
      child: SizedBox(
        key: const ValueKey('settings-top-overlay-veil'),
        width: double.infinity,
        height: totalHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colors.chatBackground.withValues(alpha: 0.96),
                colors.chatBackground.withValues(alpha: 0.9),
                colors.chatBackground.withValues(alpha: 0.62),
                colors.chatBackground.withValues(alpha: 0),
              ],
              stops: [
                0,
                headerBottomFraction * 0.55,
                headerBottomFraction,
                1,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsFloatingHeader extends StatelessWidget {
  const _SettingsFloatingHeader({
    required this.title,
    required this.headerStyle,
    required this.leading,
    required this.trailing,
    required this.centerTitle,
  });

  final String title;
  final SettingsHeaderStyle headerStyle;
  final Widget? leading;
  final Widget? trailing;
  final bool centerTitle;

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final resolvedLeading = leading ?? _buildDefaultLeading(context);
    final showsSurface = headerStyle == SettingsHeaderStyle.editor;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          spacing.lg,
          spacing.xs,
          spacing.lg,
          spacing.xs,
        ),
        child: SizedBox(
          key: const ValueKey('settings-floating-header'),
          height: ImmersiveSettingsScaffold.headerHeight,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (showsSurface)
                Positioned.fill(
                  child: IgnorePointer(
                    child: _HeaderSurface(),
                  ),
                ),
              if (centerTitle)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: spacing.xl + 28),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.primaryText,
                        ),
                  ),
                ),
              Row(
                children: [
                  _HeaderSlot(alignment: Alignment.centerLeft, child: resolvedLeading),
                  Expanded(
                    child: centerTitle
                        ? const SizedBox.shrink()
                        : Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: colors.primaryText,
                                ),
                          ),
                  ),
                  _HeaderSlot(alignment: Alignment.centerRight, child: trailing),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _buildDefaultLeading(BuildContext context) {
    switch (headerStyle) {
      case SettingsHeaderStyle.root:
      case SettingsHeaderStyle.nested:
      case SettingsHeaderStyle.editor:
        return HomeHeaderButton(
          tooltip: '返回',
          onPressed: () => Navigator.maybePop(context),
          icon: Icons.arrow_back_rounded,
        );
    }
  }
}

class _HeaderSurface extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final radius = Theme.of(context).extension<AppRadius>()!;
    final colors = Theme.of(context).extension<AppThemeSpec>()!;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius.pill),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          key: settingsFloatingHeaderSurfaceKey,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colors.assistantSurface.withValues(alpha: 0.14),
                colors.assistantSurface.withValues(alpha: 0.24),
                colors.assistantSurface.withValues(alpha: 0.36),
              ],
              stops: const [0, 0.42, 1],
            ),
            borderRadius: BorderRadius.circular(radius.pill),
            border: Border.all(
              color: colors.assistantSurface.withValues(alpha: 0.46),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: colors.core.elevation.shadowColor.withValues(alpha: 0.05),
                blurRadius: 18,
                spreadRadius: -10,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: colors.semantic.text.inverse.withValues(alpha: 0.12),
                blurRadius: 6,
                offset: const Offset(0, -1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderSlot extends StatelessWidget {
  const _HeaderSlot({required this.alignment, this.child});

  final Alignment alignment;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      child: Align(
        alignment: alignment,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
