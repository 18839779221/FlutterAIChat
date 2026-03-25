import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DatabaseHelper schema includes typed message columns and v6 upgrade path', () {
    final source = File('lib/database/database_helper.dart').readAsStringSync();

    expect(source, contains('version: 6'));
    expect(
      source,
      contains(RegExp(r"content_type\s+TEXT\s+NOT\s+NULL\s+DEFAULT\s+'plainText'")),
    );
    expect(source, contains(RegExp(r'payload_json\s+TEXT')));
    expect(source, contains(RegExp(r'reference_json\s+TEXT')));
    expect(source, contains('if (oldVersion < 6)'));
    expect(
      source,
      contains(
        RegExp(
          r"ALTER\s+TABLE\s+messages\s+ADD\s+COLUMN\s+content_type\s+TEXT\s+NOT\s+NULL\s+DEFAULT\s+'plainText'",
        ),
      ),
    );
    expect(
      source,
      contains(
        RegExp(
          r'ALTER\s+TABLE\s+messages\s+ADD\s+COLUMN\s+payload_json\s+TEXT',
        ),
      ),
    );
    expect(
      source,
      contains(
        RegExp(
          r'ALTER\s+TABLE\s+messages\s+ADD\s+COLUMN\s+reference_json\s+TEXT',
        ),
      ),
    );
  });
}
