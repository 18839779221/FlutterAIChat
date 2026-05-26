import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/markdown/markdown_widget_impl.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Markdown rendering regressions', () {
    testWidgets('list items keep the same body font size as normal paragraphs',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: MarkdownWidgetImpl(
              data: 'Paragraph text\n\n- First item\n- Second item',
            ),
          ),
        ),
      );

      final paragraph = tester.widget<RichText>(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText && widget.text.toPlainText() == 'Paragraph text',
        ),
      );
      final listItem = tester.widget<RichText>(
        find.byWidgetPredicate(
          (widget) => widget is RichText && widget.text.toPlainText() == 'First item',
        ),
      );

      expect(paragraph.text.style?.fontSize, isNotNull);
      expect(listItem.text.style?.fontSize, paragraph.text.style?.fontSize);
    });

    testWidgets('table rendering keeps visible outer borders in Claude theme',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: MarkdownWidgetImpl(
              data: '| A | B |\n| --- | --- |\n| 1 | 2 |',
            ),
          ),
        ),
      );

      final table = tester.widget<Table>(find.byType(Table));
      final border = table.border;

      expect(border, isNotNull);
      expect(border!.top.color.opacity, greaterThan(0));
      expect(border.left.color.opacity, greaterThan(0));
      expect(border.right.color.opacity, greaterThan(0));
      expect(border.bottom.color.opacity, greaterThan(0));
    });
  });
}
