import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';
import '../../theme/app_theme_spec.dart';

/// 工具卡片右侧的状态徽标：小型状态 icon + 文字。
///
/// 与传统"彩色药丸"不同的是，这里不会用状态色填充背景；状态信息由
/// icon 形态 + 文字 label 承担，色彩只在 icon / label 上以低权重出现。
///
/// 当 [isRunning] 为 true 时，文字直接采用 [statusColor]，并对整个 badge
/// 施加柔和 opacity 呼吸动效（1.4s easeInOut），表达"还在进行中"。
/// 完成态（默认）文字使用 `secondaryText` 灰，色彩仅在 icon 上出现。
class ToolStatusBadge extends StatefulWidget {
  const ToolStatusBadge({
    super.key,
    required this.label,
    this.statusColor,
    this.icon,
    this.isRunning = false,
  });

  /// 状态文字 (e.g. "完成"、"执行中"、"失败")。
  final String label;

  /// 与状态语义匹配的 token 色。
  /// - 完成态：仅作用于 icon
  /// - 执行中：同时作用于 icon 和 label
  final Color? statusColor;

  /// 状态 icon。null 时不渲染 icon，仅显示文字。
  final IconData? icon;

  /// 是否处于进行中/未终结状态。true 时启用呼吸动效 + 着色文字。
  final bool isRunning;

  @override
  State<ToolStatusBadge> createState() => _ToolStatusBadgeState();
}

class _ToolStatusBadgeState extends State<ToolStatusBadge>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _opacity;

  @override
  void initState() {
    super.initState();
    if (widget.isRunning) {
      _startPulse();
    }
  }

  @override
  void didUpdateWidget(ToolStatusBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRunning && _controller == null) {
      _startPulse();
    } else if (!widget.isRunning && _controller != null) {
      _stopPulse();
    }
  }

  void _startPulse() {
    final controller = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    );
    _opacity = Tween<double>(begin: 0.62, end: 1.0).animate(
      CurvedAnimation(parent: controller, curve: Curves.easeInOut),
    );
    controller.repeat(reverse: true);
    _controller = controller;
  }

  void _stopPulse() {
    _controller?.dispose();
    _controller = null;
    _opacity = null;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;

    final labelColor = widget.isRunning && widget.statusColor != null
        ? widget.statusColor!
        : colors.secondaryText;

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, size: 11, color: widget.statusColor),
          SizedBox(width: spacing.xxs),
        ],
        Text(
          widget.label,
          style: TextStyle(
            color: labelColor,
            fontSize: 9.5,
            fontWeight: widget.isRunning ? FontWeight.w700 : FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );

    final opacityAnim = _opacity;
    if (widget.isRunning && opacityAnim != null) {
      return AnimatedBuilder(
        animation: opacityAnim,
        builder: (context, child) => Opacity(
          opacity: opacityAnim.value,
          child: child,
        ),
        child: row,
      );
    }
    return row;
  }
}

/// 给一个 token 状态色匹配 [ToolStatusBadge] 应该用的 icon。
///
/// success 用勾号，warning/failed 用空心警示号；running / 待确认这类
/// 没有终态语义的状态返回 null（badge 只出文字，由调用方左侧指示器
/// 表达"进行中"）。
IconData? toolStatusIconFor(BuildContext context, Color statusColor) {
  final colors = Theme.of(context).extension<AppThemeSpec>()!;
  if (statusColor == colors.workflowSuccess) {
    return Icons.check_rounded;
  }
  if (statusColor == colors.workflowWarning) {
    return Icons.error_outline_rounded;
  }
  return null;
}
