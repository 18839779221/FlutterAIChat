import 'package:ai_chat/services/file_tools/file_tool_read_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FileToolReadFormatter', () {
    test('read output includes line numbers and offset window metadata', () {
      const formatter = FileToolReadFormatter();

      final result = formatter.format(
        filePath: 'tmp/demo.txt',
        lines: const ['alpha', 'beta'],
        startLine: 3,
        totalLines: 5,
        truncated: false,
      );

      expect(result.content, contains('     3\talpha'));
      expect(result.content, contains('     4\tbeta'));
      expect(result.linesReturned, 2);
      expect(result.startLine, 3);
    });
  });
}
