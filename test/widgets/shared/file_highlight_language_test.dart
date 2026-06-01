import 'package:ai_chat/widgets/shared/file_highlight_language.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fileHighlightLanguageForPath', () {
    test('maps common file extensions to flutter_highlight language ids', () {
      expect(fileHighlightLanguageForPath('lib/main.dart'), 'dart');
      expect(fileHighlightLanguageForPath('docs/plan.md'), 'markdown');
      expect(fileHighlightLanguageForPath('config/app.yaml'), 'yaml');
      expect(fileHighlightLanguageForPath('scripts/run.sh'), 'bash');
    });

    test('falls back to plaintext for unsupported or missing extensions', () {
      expect(fileHighlightLanguageForPath('README'), 'plaintext');
      expect(fileHighlightLanguageForPath('tmp/data.unknownext'), 'plaintext');
    });
  });
}
