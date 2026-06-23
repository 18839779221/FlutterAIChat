import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/settings/settings_row.dart';
import 'package:ai_chat/widgets/settings/settings_summary_group.dart';
import 'package:ai_chat/widgets/settings/settings_value_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('settings summary group renders section title above panel', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: SettingsSummaryGroup(
            title: '模型与运行时',
            children: [
              SettingsRow(
                title: '当前 Provider',
                trailing: SettingsValueBadge(label: 'Claude'),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('模型与运行时'), findsOneWidget);
    expect(find.text('Claude'), findsOneWidget);
  });

  testWidgets('settings summary group does not require summary copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: SettingsSummaryGroup(
            title: '工具与安全',
            children: [
              SettingsRow(
                title: '执行模式',
                trailing: SettingsValueBadge(label: '平衡'),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('工具与安全'), findsOneWidget);
    expect(find.text('进入管理'), findsNothing);
    expect(find.text('读取类工具自动执行，副作用工具默认先确认。'), findsNothing);
  });
}
