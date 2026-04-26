import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/markdown/markdown_math_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Markdown math widgets', () {
    testWidgets('renders inline math with flutter math', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: MarkdownInlineMath(tex: 'E = mc^2'),
          ),
        ),
      );

      expect(find.byType(Math), findsOneWidget);
      expect(find.text('E = mc^2'), findsNothing);
    });

    testWidgets('renders block math in a horizontal scroll container', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: SizedBox(
              width: 240,
              child: MarkdownBlockMath(
                tex: r'\sum_{i=1}^{n} i = \frac{n(n+1)}{2}',
              ),
            ),
          ),
        ),
      );

      expect(find.byType(Math), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(tester.getSize(find.byType(MarkdownBlockMath)).width, 240);
    });

    testWidgets('falls back to raw inline text for invalid math', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: MarkdownInlineMath(tex: r'\frac{1}'),
          ),
        ),
      );

      expect(find.text(r'\frac{1}'), findsOneWidget);
    });
  });
}
