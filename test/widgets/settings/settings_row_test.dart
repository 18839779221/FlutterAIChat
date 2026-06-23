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

  testWidgets('settings row exposes action semantics only when tappable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Column(
            children: [
              const SettingsRow(
                title: '当前 Provider',
                subtitle: '展示项',
                trailing: SettingsValueBadge(label: 'Claude'),
              ),
              SettingsRow(
                title: '执行模式',
                subtitle: '可点击项',
                onTap: () {},
                trailing: const SettingsValueBadge(label: '平衡'),
              ),
            ],
          ),
        ),
      ),
    );

    expect(
        find.byKey(const ValueKey('settings-row-action-执行模式')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-row-display-当前 Provider')),
        findsOneWidget);
  });

  testWidgets('settings row action uses outer interaction shell key', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SettingsRow(
            title: '执行模式',
            subtitle: '当前自动化策略',
            onTap: () {},
            trailing: const Text('平衡'),
          ),
        ),
      ),
    );

    expect(
        find.byKey(const ValueKey('settings-row-shell-执行模式')), findsOneWidget);
  });

  testWidgets('settings row can render leading icon slot', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: SettingsRow(
            title: '当前 Provider',
            leading: Icon(Icons.hub_outlined),
            trailing: Text('Claude'),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.hub_outlined), findsOneWidget);
  });
}
