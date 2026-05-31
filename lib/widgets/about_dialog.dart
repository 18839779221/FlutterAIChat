import 'package:flutter/material.dart';

import '../theme/app_theme_spec.dart';

void showAboutAppDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      final colors = Theme.of(context).extension<AppThemeSpec>()!;
      return AlertDialog(
        title: const Text('关于'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('AI 聊天助手'),
            const SizedBox(height: 8),
            Text(
              '版本: 1.0.0',
              style: TextStyle(color: colors.secondaryText),
            ),
            const SizedBox(height: 16),
            const Text('这是一个基于 Flutter 开发的 AI 聊天应用，集成了多种大语言模型。'),
          ],
        ),
        actions: <Widget>[
          TextButton(
            child: const Text('确定'),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ],
      );
    },
  );
} 