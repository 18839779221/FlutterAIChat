import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme_spec.dart';
import '../theme/app_typography.dart';
import '../widgets/home_header_button.dart';

class LiquidGlassLabPage extends StatefulWidget {
  const LiquidGlassLabPage({super.key});

  @override
  State<LiquidGlassLabPage> createState() => _LiquidGlassLabPageState();
}

class _LiquidGlassLabPageState extends State<LiquidGlassLabPage> {
  double _expandX = 1.16;
  double _expandY = 1.06;
  double _edgeBoost = 0.46;
  double _highlightBoost = 0.18;
  double _durationMs = 150;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    final config = LiquidGlassPressConfig(
      expandX: _expandX,
      expandY: _expandY,
      edgeBoost: _edgeBoost,
      highlightBoost: _highlightBoost,
      duration: Duration(milliseconds: _durationMs.round()),
    );

    return Scaffold(
      backgroundColor: colors.chatBackground,
      body: Stack(
        children: [
          const Positioned.fill(child: _LabBackground()),
          SafeArea(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                spacing.lg,
                spacing.lg,
                spacing.lg,
                spacing.xl,
              ),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: _buildTitle(colors),
                  ),
                ),
                SizedBox(height: spacing.lg),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: _HomeSurfacePreview(config: config),
                  ),
                ),
                SizedBox(height: spacing.lg),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: _buildTuningPanel(colors, spacing, radius),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitle(AppThemeSpec colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '首页 Header 按钮调试',
          style: AppTypography.uiStyle(
            color: colors.primaryText,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            height: 1.16,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '直接拿首页按钮的真实实现来调静态材质。关注平面玻璃、边缘折射高光和按压反馈是否成立。',
          style: AppTypography.uiStyle(
            color: colors.secondaryText,
            fontSize: 13,
            height: 1.55,
          ),
        ),
      ],
    );
  }

  Widget _buildTuningPanel(
    AppThemeSpec colors,
    AppSpacing spacing,
    AppRadius radius,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.assistantSurface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(radius.lg + 8),
        border: Border.all(
          color: colors.semantic.text.inverse.withValues(alpha: 0.54),
        ),
        boxShadow: [
          BoxShadow(
            color: colors.primaryText.withValues(alpha: 0.055),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '按压参数',
              style: AppTypography.uiStyle(
                color: colors.primaryText,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            SizedBox(height: spacing.sm),
            _TuningSlider(
              label: '横向扩张',
              value: _expandX,
              min: 1.00,
              max: 1.24,
              divisions: 24,
              formatter: (value) => '${((value - 1) * 100).round()}%',
              onChanged: (value) => setState(() => _expandX = value),
            ),
            _TuningSlider(
              label: '纵向扩张',
              value: _expandY,
              min: 1.00,
              max: 1.12,
              divisions: 12,
              formatter: (value) => '${((value - 1) * 100).round()}%',
              onChanged: (value) => setState(() => _expandY = value),
            ),
            _TuningSlider(
              label: '边缘高光',
              value: _edgeBoost,
              min: 0.0,
              max: 0.7,
              divisions: 14,
              formatter: (value) => value.toStringAsFixed(2),
              onChanged: (value) => setState(() => _edgeBoost = value),
            ),
            _TuningSlider(
              label: '内部亮度',
              value: _highlightBoost,
              min: 0.0,
              max: 0.5,
              divisions: 10,
              formatter: (value) => value.toStringAsFixed(2),
              onChanged: (value) => setState(() => _highlightBoost = value),
            ),
            _TuningSlider(
              label: '动画时长',
              value: _durationMs,
              min: 70,
              max: 220,
              divisions: 15,
              formatter: (value) => '${value.round()}ms',
              onChanged: (value) => setState(() => _durationMs = value),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeSurfacePreview extends StatelessWidget {
  const _HomeSurfacePreview({required this.config});

  final LiquidGlassPressConfig config;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.chatBackground.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(radius.lg + 14),
        border: Border.all(color: colors.primaryText.withValues(alpha: 0.09)),
        boxShadow: [
          BoxShadow(
            color: colors.primaryText.withValues(alpha: 0.055),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius.lg + 14),
        child: SizedBox(
          height: 690,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius.lg + 14),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        colors.chatBackground.withValues(alpha: 0.92),
                        colors.chatBackground.withValues(alpha: 0.56),
                        colors.settingsPanelBackground.withValues(alpha: 0.78),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: -70,
                top: 40,
                child: _SoftAtmosphereBlob(
                  color: colors.workflowRunning.withValues(alpha: 0.12),
                  size: 180,
                ),
              ),
              Positioned(
                right: -100,
                bottom: 110,
                child: _SoftAtmosphereBlob(
                  color: colors.userBubbleSurface.withValues(alpha: 0.55),
                  size: 220,
                ),
              ),
              Padding(
                padding: EdgeInsets.all(spacing.lg + 4),
              child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        HomeHeaderButton(
                          shellKey: const ValueKey('lab-header-menu-button-shell'),
                          buttonKey: const ValueKey('lab-header-menu-button'),
                          icon: Icons.menu,
                          tooltip: '会话列表',
                          onPressed: () {},
                          filled: true,
                        ),
                        const Spacer(),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            HomeHeaderButton(
                              shellKey: const ValueKey(
                                'lab-header-new-chat-button-shell',
                              ),
                              buttonKey: const ValueKey(
                                'lab-header-new-chat-button',
                              ),
                              icon: Icons.add,
                              tooltip: '新建对话',
                              onPressed: () {},
                            ),
                            SizedBox(width: spacing.xxs + 2),
                            HomeHeaderButton(
                              shellKey: const ValueKey(
                                'lab-header-debug-cases-button-shell',
                              ),
                              buttonKey: const ValueKey(
                                'lab-header-debug-cases-button',
                              ),
                              icon: Icons.science_outlined,
                              tooltip: '测试案例',
                              onPressed: () {},
                            ),
                            SizedBox(width: spacing.xxs + 2),
                            HomeHeaderButton(
                              shellKey: const ValueKey(
                                'lab-header-debug-inspector-button-shell',
                              ),
                              buttonKey: const ValueKey(
                                'lab-header-debug-inspector-button',
                              ),
                              icon: Icons.bug_report_outlined,
                              tooltip: '调试检查器',
                              onPressed: () {},
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Spacer(),
                    Align(
                      alignment: Alignment.centerRight,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color:
                              colors.userBubbleSurface.withValues(alpha: 0.82),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(radius.lg + 6),
                            topRight: Radius.circular(radius.lg + 6),
                            bottomLeft: Radius.circular(radius.lg + 6),
                            bottomRight: Radius.circular(radius.sm),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: colors.primaryText.withValues(alpha: 0.04),
                              blurRadius: 12,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: spacing.md,
                            vertical: spacing.sm,
                          ),
                          child: Text(
                            '我希望按钮被挤压变大，但不要出现外包气泡。',
                            style: AppTypography.uiStyle(
                              color: colors.primaryText,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: spacing.lg),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Text(
                          '这个 Lab 使用 Flutter 原生 AnimatedContainer、Transform 和 BackdropFilter。后续确认手感后，可以把 LiquidGlassBar / LiquidGlassButtonSegment 收敛成首页组件。',
                          style: AppTypography.uiStyle(
                            color: colors.primaryText,
                            fontSize: 14,
                            height: 1.65,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    _ComposerPreview(config: config),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComposerPreview extends StatelessWidget {
  const _ComposerPreview({required this.config});

  final LiquidGlassPressConfig config;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius.lg + 12),
        border: Border.all(
          color: colors.semantic.text.inverse.withValues(alpha: 0.62),
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colors.assistantSurface.withValues(alpha: 0.28),
            colors.assistantSurface.withValues(alpha: 0.56),
            colors.assistantSurface.withValues(alpha: 0.72),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: colors.core.elevation.shadowColor.withValues(alpha: 0.12),
            blurRadius: 42,
            spreadRadius: -8,
            offset: const Offset(0, 24),
          ),
          BoxShadow(
            color: colors.semantic.text.inverse.withValues(alpha: 0.28),
            blurRadius: 8,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius.lg + 12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
          child: Padding(
            padding: EdgeInsets.all(spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '继续追问，或补充你的要求',
                  style: AppTypography.uiStyle(
                    color: colors.secondaryText.withValues(alpha: 0.72),
                    fontSize: 13,
                    height: 1.2,
                  ),
                ),
                SizedBox(height: spacing.lg),
                Row(
                  children: [
                    LiquidGlassBar(
                      config: config,
                      children: [
                        LiquidGlassButtonSegment(
                          semanticLabel: '添加图片',
                          icon: Icons.image_outlined,
                          config: config,
                        ),
                      ],
                    ),
                    SizedBox(width: spacing.xs),
                    LiquidGlassBar(
                      config: config,
                      children: [
                        LiquidGlassButtonSegment(
                          semanticLabel: '选择模型',
                          label: 'Claude Sonnet',
                          minWidth: 132,
                          config: config,
                        ),
                      ],
                    ),
                    const Spacer(),
                    LiquidGlassBar(
                      config: config,
                      accent: true,
                      children: [
                        LiquidGlassButtonSegment(
                          semanticLabel: '发送',
                          icon: Icons.arrow_upward_rounded,
                          config: config,
                          accent: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

@immutable
class LiquidGlassPressConfig {
  const LiquidGlassPressConfig({
    required this.expandX,
    required this.expandY,
    required this.edgeBoost,
    required this.highlightBoost,
    required this.duration,
  });

  final double expandX;
  final double expandY;
  final double edgeBoost;
  final double highlightBoost;
  final Duration duration;
}

class LiquidGlassBar extends StatelessWidget {
  const LiquidGlassBar({
    super.key,
    required this.children,
    required this.config,
    this.accent = false,
  });

  final List<Widget> children;
  final LiquidGlassPressConfig config;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius.pill),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: AnimatedContainer(
          duration: config.duration,
          curve: Curves.easeOutCubic,
          height: 52,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius.pill),
            color: colors.semantic.text.inverse.withValues(alpha: 0.08),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      ),
    );
  }
}

class LiquidGlassButtonSegment extends StatefulWidget {
  const LiquidGlassButtonSegment({
    super.key,
    required this.semanticLabel,
    required this.config,
    this.icon,
    this.label,
    this.minWidth = 48,
    this.accent = false,
  }) : assert(icon != null || label != null);

  final String semanticLabel;
  final IconData? icon;
  final String? label;
  final double minWidth;
  final bool accent;
  final LiquidGlassPressConfig config;

  @override
  State<LiquidGlassButtonSegment> createState() =>
      _LiquidGlassButtonSegmentState();
}

class _LiquidGlassButtonSegmentState extends State<LiquidGlassButtonSegment> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) {
      return;
    }
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final motion = Theme.of(context).extension<AppMotion>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final config = widget.config;
    const double baseHeight = 44;
    final double maxWidth = widget.minWidth * config.expandX;
    final double maxHeight = baseHeight * config.expandY;
    final double width = widget.minWidth * (_pressed ? config.expandX : 1);
    final double height = baseHeight * (_pressed ? config.expandY : 1);
    final foreground =
        widget.accent ? colors.workflowRunning : colors.primaryText;
    final edgeAlpha =
        (_pressed ? 0.18 + config.edgeBoost : 0.14).clamp(0.0, 1.0).toDouble();
    final fillAlpha = (_pressed ? 0.20 + config.highlightBoost : 0.10)
        .clamp(0.0, 1.0)
        .toDouble();
    final surfaceTint =
        widget.accent ? colors.workflowRunning : colors.userBubbleSurface;

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _setPressed(true),
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: SizedBox(
          width: maxWidth,
          height: maxHeight,
          child: Center(
            child: AnimatedContainer(
              duration: config.duration,
              curve: _pressed ? motion.easeOut : Curves.easeOutBack,
              width: width,
              height: height,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius.pill),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colors.semantic.text.inverse.withValues(
                      alpha: _pressed ? 0.58 : 0.36,
                    ),
                    surfaceTint.withValues(alpha: fillAlpha),
                    colors.settingsPanelBackground.withValues(
                      alpha: _pressed ? 0.24 : 0.16,
                    ),
                  ],
                ),
                border: Border.all(
                  color: _pressed
                      ? colors.semantic.text.inverse.withValues(
                          alpha: edgeAlpha * 0.74,
                        )
                      : colors.primaryText.withValues(alpha: 0.11),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: colors.primaryText.withValues(
                      alpha: _pressed ? 0.10 : 0.055,
                    ),
                    blurRadius: _pressed ? 18 : 14,
                    spreadRadius: -9,
                    offset: Offset(0, _pressed ? 8 : 6),
                  ),
                  BoxShadow(
                    color: colors.semantic.text.inverse.withValues(
                      alpha: _pressed ? 0.46 : 0.28,
                    ),
                    blurRadius: _pressed ? 9 : 6,
                    spreadRadius: -5,
                    offset: const Offset(-1, -2),
                  ),
                ],
              ),
              child: Center(
                child: AnimatedScale(
                  scale: _pressed ? 0.985 : 1,
                  duration: config.duration,
                  curve: motion.easeOut,
                  child: widget.icon == null
                      ? Text(
                          widget.label!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: AppTypography.uiStyle(
                            color: foreground,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        )
                      : Icon(
                          widget.icon,
                          size: 22,
                          color: foreground.withValues(
                            alpha: _pressed ? 0.98 : 0.84,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TuningSlider extends StatelessWidget {
  const _TuningSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.formatter,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double value) formatter;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTypography.uiStyle(
                  color: colors.secondaryText,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ),
            Text(
              formatter(value),
              style: AppTypography.uiStyle(
                color: colors.primaryText,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: formatter(value),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _SoftAtmosphereBlob extends StatelessWidget {
  const _SoftAtmosphereBlob({
    required this.color,
    required this.size,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
          child: SizedBox.square(dimension: size),
        ),
      ),
    );
  }
}

class _LabBackground extends StatelessWidget {
  const _LabBackground();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colors.chatBackground,
            colors.settingsPanelBackground.withValues(alpha: 0.92),
          ],
        ),
      ),
    );
  }
}
