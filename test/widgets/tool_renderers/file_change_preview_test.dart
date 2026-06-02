import 'package:ai_chat/theme/app_theme.dart';
import 'package:ai_chat/widgets/shared/highlighted_code_content.dart';
import 'package:ai_chat/widgets/tool_renderers/file_change_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FileChangePreview', () {
    testWidgets('renders replacement hunks with up to two context lines', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: FileChangePreview(
              filePath: 'lib/main.dart',
              oldContent:
                  'line 0\nline 1\nline 2\nfinal value = old;\nprint(oldValue);\nline 5\nline 6\nline 7',
              newContent:
                  'line 0\nline 1\nline 2\nfinal value = new;\nprint(newValue);\nline 5\nline 6\nline 7',
              truncated: false,
            ),
          ),
        ),
      );

      expect(_findCode('line 0'), findsNothing);
      expect(_findCode('line 1'), findsWidgets);
      expect(_findCode('line 2'), findsWidgets);
      expect(_findCode('final value = old;'), findsOneWidget);
      expect(_findCode('final value = new;'), findsOneWidget);
      expect(_findCode('print(oldValue);'), findsOneWidget);
      expect(_findCode('print(newValue);'), findsOneWidget);
      expect(_findCode('line 5'), findsWidgets);
      expect(_findCode('line 6'), findsWidgets);
      expect(_findCode('line 7'), findsNothing);
      expect(find.text('1'), findsNothing);
      expect(find.text('2'), findsWidgets);
      expect(find.text('4'), findsWidgets);
      expect(find.text('6'), findsWidgets);
    });

    testWidgets('new-file preview does not invent missing context lines', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: FileChangePreview(
              filePath: 'docs/plan.md',
              oldContent: '',
              newContent: 'header 1\nheader 2\nbody 1\nbody 2\nfooter 1\nfooter 2',
              truncated: false,
              forceAdded: true,
            ),
          ),
        ),
      );

      expect(_findCode('header 1'), findsOneWidget);
      expect(_findCode('header 2'), findsOneWidget);
      expect(_findCode('body 1'), findsOneWidget);
      expect(_findCode('body 2'), findsOneWidget);
      expect(_findCode('footer 1'), findsOneWidget);
      expect(_findCode('footer 2'), findsOneWidget);
    });
  });
}

Finder _findCode(String code) {
  return find.byWidgetPredicate(
    (widget) => widget is HighlightedCodeContent && widget.code == code,
  );
}
