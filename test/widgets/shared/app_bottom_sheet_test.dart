import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/shared/app_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppBottomSheet', () {
    testWidgets('sheet extends through the bottom safe area', (tester) async {
      const simulatedBottomInset = 34.0;

      await tester.pumpWidget(
        _Harness(
          mode: AppBottomSheetMode.fixed80,
          mediaQueryData: const MediaQueryData(
            size: Size(390, 844),
            viewPadding: EdgeInsets.only(bottom: simulatedBottomInset),
          ),
          body: const SizedBox.expand(
            child: Text('long content'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final windowHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final sheetBottom = tester
          .getBottomRight(find.byKey(const ValueKey('app-bottom-sheet')))
          .dy;
      expect(sheetBottom, closeTo(windowHeight, 1));
    });

    testWidgets('adaptive sheet keeps short content below the 80 percent cap', (
      tester,
    ) async {
      await tester.pumpWidget(
        _Harness(
          mode: AppBottomSheetMode.adaptive,
          body: const SizedBox(
            height: 120,
            child: Text('short content'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final windowHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final sheetHeight = tester
          .getSize(find.byKey(const ValueKey('app-bottom-sheet')))
          .height;

      expect(sheetHeight, lessThan(windowHeight * 0.8));
    });

    testWidgets('fixed80 sheet takes 80 percent of the viewport height', (
      tester,
    ) async {
      await tester.pumpWidget(
        _Harness(
          mode: AppBottomSheetMode.fixed80,
          body: const SizedBox.expand(
            child: Text('long content'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final windowHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final sheetHeight = tester
          .getSize(find.byKey(const ValueKey('app-bottom-sheet')))
          .height;

      expect(sheetHeight, closeTo(windowHeight * 0.8, 2));
    });

    testWidgets('drag handle stays visible after scrolling long body', (
      tester,
    ) async {
      await tester.pumpWidget(
        _Harness(
          mode: AppBottomSheetMode.fixed80,
          body: ListView.builder(
            itemCount: 40,
            itemBuilder: (_, index) => SizedBox(
              height: 56,
              child: Text('item $index'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final handleFinder = find.byKey(
        const ValueKey('app-bottom-sheet-drag-handle'),
      );
      final before = tester.getTopLeft(handleFinder);

      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pumpAndSettle();

      final after = tester.getTopLeft(handleFinder);
      expect(after.dy, closeTo(before.dy, 1));
    });

    testWidgets(
      'scrollable body keeps spacing below drag handle without title',
      (tester) async {
        await tester.pumpWidget(
          _Harness(
            mode: AppBottomSheetMode.fixed80,
            title: null,
            subtitle: null,
            body: ListView.builder(
              itemCount: 20,
              itemBuilder: (_, index) => SizedBox(
                height: 56,
                child: Text('item $index'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        final handleBottom = tester
            .getBottomLeft(
              find.byKey(const ValueKey('app-bottom-sheet-drag-handle')),
            )
            .dy;
        final firstItemTop = tester.getTopLeft(find.text('item 0')).dy;

        expect(firstItemTop - handleBottom, greaterThan(0));
      },
    );

    testWidgets('tapping barrier dismisses sheet', (tester) async {
      await tester.pumpWidget(
        _Harness(
          mode: AppBottomSheetMode.adaptive,
          body: const SizedBox(height: 120, child: Text('short content')),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('app-bottom-sheet')), findsOneWidget);

      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('app-bottom-sheet')), findsNothing);
    });

    testWidgets('dragging down dismisses sheet', (tester) async {
      await tester.pumpWidget(
        _Harness(
          mode: AppBottomSheetMode.fixed80,
          body: ListView.builder(
            itemCount: 20,
            itemBuilder: (_, index) => SizedBox(
              height: 56,
              child: Text('item $index'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('app-bottom-sheet')), findsOneWidget);

      await tester.drag(
        find.byKey(const ValueKey('app-bottom-sheet-drag-handle')),
        const Offset(0, 400),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('app-bottom-sheet')), findsNothing);
    });
  });
}

class _Harness extends StatelessWidget {
  const _Harness({
    required this.mode,
    required this.body,
    this.title = 'Title',
    this.subtitle = 'Subtitle',
    this.mediaQueryData,
  });

  final AppBottomSheetMode mode;
  final Widget body;
  final String? title;
  final String? subtitle;
  final MediaQueryData? mediaQueryData;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.light(),
      home: MediaQuery(
        data: mediaQueryData ?? const MediaQueryData(),
        child: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () {
                  showAppBottomSheet<void>(
                    context: context,
                    mode: mode,
                    title: title,
                    subtitle: subtitle,
                    body: body,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
