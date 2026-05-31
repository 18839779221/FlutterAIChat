import 'package:flutter/material.dart';

import '../theme/app_theme_spec.dart';

class ConfirmDialog extends StatelessWidget {
  final String title;
  final String content;
  final String cancelText;
  final String confirmText;
  final VoidCallback? onConfirm;

  /// 确认按钮底色。默认走主题的 `state.error`（破坏性确认场景）。
  /// 调用方需要中性确认时可显式传入 `colors.semantic.state.success` 等 token。
  final Color? confirmColor;

  const ConfirmDialog({
    super.key,
    required this.title,
    required this.content,
    this.cancelText = '取消',
    this.confirmText = '确认',
    this.onConfirm,
    this.confirmColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final resolvedConfirmColor = confirmColor ?? colors.semantic.state.error;
    return AlertDialog(
      title: Text(title),
      content: Text(content),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            cancelText,
            style: TextStyle(color: colors.secondaryText),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop();
            onConfirm?.call();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: resolvedConfirmColor,
            foregroundColor: colors.semantic.text.inverse,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(confirmText),
        ),
      ],
    );
  }
}
