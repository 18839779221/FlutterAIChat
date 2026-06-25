import 'package:ai_chat/pages/home_top_buttons_lab_page.dart';
import 'package:ai_chat/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'lab page exposes top chrome buttons and a scroll-driven state surface',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const HomeTopButtonsLabPage(),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('home-top-buttons-lab-scroll-view')),
          findsOneWidget);
      expect(
          find.byKey(const ValueKey('top-chrome-motion-host')), findsOneWidget);
      expect(find.byKey(const ValueKey('header-menu-button-shell')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('header-workspace-button-shell')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('header-new-chat-button-shell')),
          findsOneWidget);

      final leftBefore =
          tester.getCenter(find.byKey(const ValueKey('header-left-cluster')));
      final rightBefore =
          tester.getCenter(find.byKey(const ValueKey('header-right-cluster')));

      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      scrollable.position.jumpTo(220);
      await tester.pumpAndSettle();

      final leftAfter =
          tester.getCenter(find.byKey(const ValueKey('header-left-cluster')));
      final rightAfter =
          tester.getCenter(find.byKey(const ValueKey('header-right-cluster')));

      expect(leftAfter.dx, greaterThan(leftBefore.dx));
      expect(rightAfter.dx, lessThan(rightBefore.dx));
    },
  );

  testWidgets('lab page scroll view responds to direct drag gestures',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const HomeTopButtonsLabPage(),
      ),
    );
    await tester.pump();

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.pixels, 0);

    await tester.drag(
      find.byKey(const ValueKey('home-top-buttons-lab-scroll-view')),
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();

    expect(scrollable.position.pixels, greaterThan(0));
  });
}
