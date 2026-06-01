import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/markdown/flutter_markdown_impl.dart';
import 'package:ai_chat/widgets/markdown/table_edge_fade_scroll_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('RichTableElementBuilder rendering', () {
    testWidgets('renders a Table inside TableEdgeFadeScrollShell',
        (tester) async {
      const data = '''
| a | b |
|---|---|
| 1 | 2 |
''';

      await tester.pumpWidget(_wrap(const FlutterMarkdownImpl(data: data)));
      await tester.pump();

      expect(find.byType(TableEdgeFadeScrollShell), findsOneWidget);
      expect(find.byType(Table), findsOneWidget);

      final Table table = tester.widget(find.byType(Table));
      expect(table.defaultColumnWidth, isA<TableColumnWidth>());
    });

    testWidgets('cell inline bold renders as a styled span, not literal **',
        (tester) async {
      const data = '''
| h |
|---|
| **bold** |
''';

      await tester.pumpWidget(_wrap(const FlutterMarkdownImpl(data: data)));
      await tester.pump();

      expect(find.textContaining('**bold**'), findsNothing);
      expect(find.textContaining('bold'), findsWidgets);
    });

    testWidgets('cell inline code renders as code (no backticks)',
        (tester) async {
      const data = '''
| h |
|---|
| `x` |
''';

      await tester.pumpWidget(_wrap(const FlutterMarkdownImpl(data: data)));
      await tester.pump();

      expect(find.textContaining('`x`'), findsNothing);
      expect(find.textContaining('x'), findsWidgets);
    });

    testWidgets('alignment attribute reaches a DefaultTextStyle in the cell',
        (tester) async {
      const data = '''
| L | C | R |
|:--|:-:|--:|
| 1 | 2 | 3 |
''';

      await tester.pumpWidget(_wrap(const FlutterMarkdownImpl(data: data)));
      await tester.pump();

      // The builder wraps each cell in a DefaultTextStyle whose textAlign
      // reflects the column alignment. Any DefaultTextStyle inside the
      // tree should report center alignment for the middle column.
      final defaultTextStyles = tester
          .widgetList<DefaultTextStyle>(find.byType(DefaultTextStyle))
          .toList();
      expect(
        defaultTextStyles.any((s) => s.textAlign == TextAlign.center),
        isTrue,
      );
    });

    testWidgets('short content still stays narrower than long content',
        (tester) async {
      const data = '''
| short | long                                              |
|-------|---------------------------------------------------|
| 1     | this is a much longer content cell expected wider |
''';

      await tester.pumpWidget(_wrap(const FlutterMarkdownImpl(data: data)));
      await tester.pump();

      final cells = tester
          .widgetList<TableCell>(find.byType(TableCell))
          .toList();
      expect(cells.length, greaterThanOrEqualTo(4));

      // The last two cells are the body row; the long-content cell width
      // should exceed the short-content cell width by a healthy margin.
      final shortRect = tester.getRect(find.byWidget(cells[2]));
      final longRect = tester.getRect(find.byWidget(cells[3]));
      expect(longRect.width, greaterThan(shortRect.width));
    });

    testWidgets('long cell content wraps at the per-column width cap',
        (tester) async {
      const data = '''
| field | detail |
|-------|--------|
| status | this is a long markdown table cell intended to wrap onto multiple lines when the available width is limited instead of stretching the whole table into one very long row |
''';

      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(
          const SizedBox(
            width: 280,
            child: FlutterMarkdownImpl(data: data),
          ),
        ),
      );
      await tester.pump();

      final cells = tester
          .widgetList<TableCell>(find.byType(TableCell))
          .toList();
      final statusRect = tester.getRect(find.byWidget(cells[2]));
      final detailRect = tester.getRect(find.byWidget(cells[3]));
      expect(detailRect.width, greaterThan(statusRect.width));
      expect(detailRect.width, lessThanOrEqualTo(280 * 0.8 + 40));

      final detailText = tester.widget<RichText>(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              widget.text.toPlainText().contains(
                'this is a long markdown table cell intended to wrap',
              ),
        ).first,
      );
      expect(detailText.maxLines, isNull);
      expect(tester.getSize(find.byWidget(detailText)).height, greaterThan(32));
    });
  });
}
