import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/settings/settings_group_section.dart';
import 'package:ai_chat/widgets/settings/settings_row.dart';
import 'package:ai_chat/widgets/settings/settings_segmented_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('settings group section renders title and child', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: SettingsGroupSection(
            title: '工具设置',
            child: Text('内容'),
          ),
        ),
      ),
    );

    expect(find.text('工具设置'), findsOneWidget);
    expect(find.text('内容'), findsOneWidget);
  });

  testWidgets('settings row renders title and trailing widget', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: SettingsRow(
            title: '深色模式',
            trailing: Switch(value: true, onChanged: null),
          ),
        ),
      ),
    );

    expect(find.text('深色模式'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('segmented control highlights selected option', (tester) async {
    var current = 'balanced';

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return SettingsSegmentedControl<String>(
                value: current,
                options: const {
                  'conservative': '保守',
                  'balanced': '平衡',
                },
                onChanged: (value) {
                  setState(() {
                    current = value;
                  });
                },
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('平衡'), findsOneWidget);
    await tester.tap(find.text('保守'));
    await tester.pumpAndSettle();
    expect(current, 'conservative');
  });
}
