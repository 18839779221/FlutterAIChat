import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/settings/settings_row.dart';
import 'package:ai_chat/widgets/settings/settings_value_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('settings row prefers value badge over outlined chip styling', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: SettingsRow(
            title: '执行模式',
            subtitle: '当前自动化策略',
            trailing: SettingsValueBadge(label: '平衡'),
          ),
        ),
      ),
    );

    expect(find.text('平衡'), findsOneWidget);
    expect(find.byType(SettingsValueBadge), findsOneWidget);
  });
}
