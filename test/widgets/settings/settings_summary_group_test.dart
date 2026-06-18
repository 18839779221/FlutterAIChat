import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/settings/settings_row.dart';
import 'package:ai_chat/widgets/settings/settings_summary_group.dart';
import 'package:ai_chat/widgets/settings/settings_value_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('settings summary group renders title, summary and action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SettingsSummaryGroup(
            title: '模型与运行时',
            summary: '当前模型可用',
            actionLabel: '进入管理',
            onActionPressed: () {},
            children: const [
              SettingsRow(
                title: '当前 Provider',
                subtitle: '用于主对话的默认来源',
                trailing: SettingsValueBadge(label: 'Claude'),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('模型与运行时'), findsOneWidget);
    expect(find.text('当前模型可用'), findsOneWidget);
    expect(find.text('进入管理'), findsOneWidget);
    expect(find.text('Claude'), findsOneWidget);
  });
}
