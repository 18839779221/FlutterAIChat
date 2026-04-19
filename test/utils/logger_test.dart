import 'package:ai_chat/utils/logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Logger', () {
    test('formats local timestamps with explicit timezone offset', () {
      final timestamp = DateTime.parse('2026-04-18T18:01:27.417336+08:00');

      expect(
        Logger.formatTimestampForLog(timestamp),
        '2026-04-18T18:01:27.417336+08:00',
      );
    });
  });
}
