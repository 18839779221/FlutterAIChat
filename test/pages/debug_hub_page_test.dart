import 'package:ai_chat/constants/route_constant.dart';
import 'package:ai_chat/pages/component_motion_debug_page.dart';
import 'package:ai_chat/pages/debug_hub_page.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('debug hub opens component motion debug page', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        routes: {
          RouteConstant.componentMotionDebugPage: (context) =>
              const ComponentMotionDebugPage(),
        },
        home: const DebugHubPage(),
      ),
    );

    expect(find.text('组件与动效调试'), findsOneWidget);

    await tester.tap(find.text('组件与动效调试'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(ComponentMotionDebugPage), findsOneWidget);
  });
}
