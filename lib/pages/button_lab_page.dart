import 'package:flutter/material.dart';

import '../theme/app_theme_spec.dart';

class ButtonLabPage extends StatelessWidget {
  const ButtonLabPage({super.key});

  @override
  Widget build(BuildContext context) {
    const pageBackground = Color(0xFFFFFFFF);
    const panelBorder = Color(0xFFE5E7EB);
    const panelMuted = Color(0xFF6B7280);

    return Scaffold(
      backgroundColor: pageBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 40, 32, 48),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Button Reference Lab',
                    style: TextStyle(
                      fontSize: 30,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.8,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '先不考虑项目适配，直接按参考按钮的视觉和状态去复刻。当前只保留最核心的 default 与 outline。',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.6,
                      color: panelMuted,
                    ),
                  ),
                  const SizedBox(height: 32),
                  const _ReferenceSurface(
                    title: 'Default',
                    subtitle: '参考 shadcn 的默认黑底按钮：小圆角、紧凑高度、强对比、非常克制。',
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        _ReferenceButton(
                          label: 'Button',
                          variant: _ReferenceButtonVariant.defaultButton,
                        ),
                        _ReferenceButton(
                          label: 'Button',
                          variant: _ReferenceButtonVariant.outline,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const _ReferenceSurface(
                    title: 'States',
                    subtitle: '用同一套按钮骨架检查 icon、disabled 和长文案。',
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        _ReferenceButton(
                          label: 'Continue',
                          variant: _ReferenceButtonVariant.defaultButton,
                          leading: Icons.arrow_forward_rounded,
                        ),
                        _ReferenceButton(
                          label: 'Manage models',
                          variant: _ReferenceButtonVariant.outline,
                          trailing: Icons.arrow_outward_rounded,
                        ),
                        _ReferenceButton(
                          label: 'Disabled',
                          variant: _ReferenceButtonVariant.defaultButton,
                          enabled: false,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const _ReferenceSurface(
                    title: 'Claude Theme Adaptation',
                    subtitle: '保持和参考相同的按钮骨架，只替换成当前主题的色彩与表面语义。',
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        _ReferenceButton(
                          label: '新建对话',
                          variant: _ReferenceButtonVariant.themedPrimary,
                        ),
                        _ReferenceButton(
                          label: '管理模型',
                          variant: _ReferenceButtonVariant.themedOutline,
                        ),
                        _ReferenceButton(
                          label: '继续',
                          variant: _ReferenceButtonVariant.themedPrimary,
                          leading: Icons.arrow_forward_rounded,
                        ),
                        _ReferenceButton(
                          label: '结构化摘要',
                          variant: _ReferenceButtonVariant.themedOutline,
                          trailing: Icons.arrow_outward_rounded,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: panelBorder),
                      color: const Color(0xFFFAFAFA),
                    ),
                    child: const Text(
                      '当前刻意不做项目化改造：不引入玻璃、暖色、品牌语义，也不对齐首页按钮。这里只验证参考按钮本体是否复刻准确。',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: panelMuted,
                      ),
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

class _ReferenceSurface extends StatelessWidget {
  const _ReferenceSurface({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 14,
              height: 1.55,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

enum _ReferenceButtonVariant {
  defaultButton,
  outline,
  themedPrimary,
  themedOutline,
}

class _ReferenceButton extends StatefulWidget {
  const _ReferenceButton({
    required this.label,
    required this.variant,
    this.leading,
    this.trailing,
    this.enabled = true,
  });

  final String label;
  final _ReferenceButtonVariant variant;
  final IconData? leading;
  final IconData? trailing;
  final bool enabled;

  @override
  State<_ReferenceButton> createState() => _ReferenceButtonState();
}

class _ReferenceButtonState extends State<_ReferenceButton> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final themeSpec = Theme.of(context).extension<AppThemeSpec>()!;
    final isThemed = widget.variant == _ReferenceButtonVariant.themedPrimary ||
        widget.variant == _ReferenceButtonVariant.themedOutline;
    final isDefault = widget.variant == _ReferenceButtonVariant.defaultButton ||
        widget.variant == _ReferenceButtonVariant.themedPrimary;
    final isEnabled = widget.enabled;
    final isPressed = _pressed && isEnabled;
    final isHovered = _hovered && isEnabled;

    final palette = _resolvePalette(
      themeSpec: themeSpec,
      isThemed: isThemed,
      isDefault: isDefault,
      isPressed: isPressed,
      isHovered: isHovered,
    );
    final shadow = _resolveShadow(
      isDefault: isDefault,
      isPressed: isPressed,
      isHovered: isHovered,
      isEnabled: isEnabled,
      isThemed: isThemed,
      themeSpec: themeSpec,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedSlide(
        offset: Offset(0, isPressed ? 0.045 : 0),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: isEnabled ? 1 : 0.5,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isEnabled ? () {} : null,
              onHighlightChanged: (value) {
                if (_pressed != value) {
                  setState(() {
                    _pressed = value;
                  });
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOutCubic,
                constraints: const BoxConstraints(minHeight: 36),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: palette.backgroundColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: palette.borderColor),
                  boxShadow: shadow,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.leading != null) ...[
                      Icon(
                        widget.leading,
                        size: 16,
                        color: palette.foregroundColor,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                        color: palette.foregroundColor,
                      ),
                    ),
                    if (widget.trailing != null) ...[
                      const SizedBox(width: 8),
                      Icon(
                        widget.trailing,
                        size: 16,
                        color: palette.foregroundColor,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<BoxShadow> _resolveShadow({
    required bool isDefault,
    required bool isPressed,
    required bool isHovered,
    required bool isEnabled,
    required bool isThemed,
    required AppThemeSpec themeSpec,
  }) {
    if (!isEnabled) {
      return const [];
    }

    if (!isThemed) {
      if (isDefault) {
        return [
          BoxShadow(
            color: const Color(0x14000000),
            blurRadius: isPressed ? 2 : 4,
            offset: Offset(0, isPressed ? 1 : 2),
          ),
        ];
      }
      return [
        BoxShadow(
          color: const Color(0x08000000),
          blurRadius: isPressed ? 1 : 2,
          offset: Offset(0, isPressed ? 1 : 1.5),
        ),
      ];
    }

    if (isDefault) {
      return [
        BoxShadow(
          color: themeSpec.workflowRunning.withValues(
            alpha: isPressed ? 0.12 : (isHovered ? 0.18 : 0.16),
          ),
          blurRadius: isPressed ? 3 : 6,
          offset: Offset(0, isPressed ? 1 : 3),
        ),
      ];
    }

    return [
      BoxShadow(
        color: themeSpec.core.elevation.shadowColor.withValues(
          alpha: isPressed ? 0.04 : 0.08,
        ),
        blurRadius: isPressed ? 1 : 3,
        offset: Offset(0, isPressed ? 1 : 2),
      ),
    ];
  }

  _ButtonPalette _resolvePalette({
    required AppThemeSpec themeSpec,
    required bool isThemed,
    required bool isDefault,
    required bool isPressed,
    required bool isHovered,
  }) {
    if (!isThemed) {
      return _ButtonPalette(
        backgroundColor: isDefault
            ? _resolveDefaultBackground(
                isPressed: isPressed,
                isHovered: isHovered,
              )
            : _resolveOutlineBackground(
                isPressed: isPressed,
                isHovered: isHovered,
              ),
        foregroundColor:
            isDefault ? const Color(0xFFF9FAFB) : const Color(0xFF111827),
        borderColor: isDefault ? Colors.transparent : const Color(0xFFE5E7EB),
      );
    }

    if (isDefault) {
      return _ButtonPalette(
        backgroundColor: _resolveThemePrimaryBackground(
          themeSpec: themeSpec,
          isPressed: isPressed,
          isHovered: isHovered,
        ),
        foregroundColor: themeSpec.semantic.text.inverse,
        borderColor: Colors.transparent,
      );
    }

    return _ButtonPalette(
      backgroundColor: _resolveThemeOutlineBackground(
        themeSpec: themeSpec,
        isPressed: isPressed,
        isHovered: isHovered,
      ),
      foregroundColor: themeSpec.primaryText,
      borderColor: themeSpec.divider,
    );
  }

  Color _resolveDefaultBackground({
    required bool isPressed,
    required bool isHovered,
  }) {
    if (!widget.enabled) {
      return const Color(0xFF111827);
    }
    if (isPressed) {
      return const Color(0xFF030712);
    }
    if (isHovered) {
      return const Color(0xFF1F2937);
    }
    return const Color(0xFF111827);
  }

  Color _resolveOutlineBackground({
    required bool isPressed,
    required bool isHovered,
  }) {
    if (!widget.enabled) {
      return const Color(0xFFFFFFFF);
    }
    if (isPressed || isHovered) {
      return const Color(0xFFF3F4F6);
    }
    return const Color(0xFFFFFFFF);
  }

  Color _resolveThemePrimaryBackground({
    required AppThemeSpec themeSpec,
    required bool isPressed,
    required bool isHovered,
  }) {
    if (!widget.enabled) {
      return themeSpec.workflowRunning.withValues(alpha: 0.45);
    }
    if (isPressed) {
      return const Color(0xFFB45232);
    }
    if (isHovered) {
      return const Color(0xFFD36F4D);
    }
    return themeSpec.workflowRunning;
  }

  Color _resolveThemeOutlineBackground({
    required AppThemeSpec themeSpec,
    required bool isPressed,
    required bool isHovered,
  }) {
    if (!widget.enabled) {
      return themeSpec.assistantSurface.withValues(alpha: 0.76);
    }
    if (isPressed || isHovered) {
      return themeSpec.settingsPanelBackground.withValues(alpha: 0.92);
    }
    return themeSpec.assistantSurface;
  }
}

class _ButtonPalette {
  const _ButtonPalette({
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderColor,
  });

  final Color backgroundColor;
  final Color foregroundColor;
  final Color borderColor;
}
