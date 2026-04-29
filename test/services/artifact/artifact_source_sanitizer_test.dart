import 'package:ai_chat/services/artifact/artifact_source_sanitizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArtifactSourceSanitizer', () {
    test('keeps inline style and strips external assets', () {
      const sanitizer = ArtifactSourceSanitizer();

      final result = sanitizer.sanitize('''
<html>
  <head>
    <style>body { color: red; }</style>
    <script src="https://cdn.example.com/app.js"></script>
    <link rel="stylesheet" href="https://cdn.example.com/app.css">
  </head>
  <body>Hello</body>
</html>
''');

      expect(result.isValid, isTrue);
      expect(result.sanitizedSource, contains('<style>body { color: red; }</style>'));
      expect(result.sanitizedSource, isNot(contains('cdn.example.com/app.js')));
      expect(result.sanitizedSource, isNot(contains('cdn.example.com/app.css')));
      expect(result.warnings, contains('removed_external_script'));
      expect(result.warnings, contains('removed_external_stylesheet'));
    });

    test('rejects oversized source', () {
      final sanitizer = ArtifactSourceSanitizer(maxBytes: 8);
      final result = sanitizer.sanitize('0123456789');
      expect(result.isValid, isFalse);
      expect(result.errorCode, 'source_too_large');
    });
  });
}
