import 'dart:io';

import 'package:ai_chat/services/file_tools/file_tool_models.dart';
import 'package:ai_chat/services/file_tools/file_tool_session_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FileToolSessionGuard', () {
    late FileToolSessionGuard guard;

    setUp(() {
      guard = FileToolSessionGuard();
    });

    test('existing file cannot be edited before read', () {
      expect(
        () => guard.assertWritable(
          filePath: '/memories/a.md',
          currentVersion: const FileToolVersionSnapshot(
            modifiedAtMillis: 10,
            sizeBytes: 20,
          ),
          fileExists: true,
        ),
        throwsA(
          isA<FileToolGuardException>().having(
            (error) => error.code,
            'code',
            'unread_file',
          ),
        ),
      );
    });

    test('markRead allows write when version is unchanged', () {
      const version = FileToolVersionSnapshot(
        modifiedAtMillis: 10,
        sizeBytes: 20,
      );
      guard.markRead(filePath: '/memories/a.md', version: version);

      expect(
        () => guard.assertWritable(
          filePath: '/memories/a.md',
          currentVersion: version,
          fileExists: true,
        ),
        returnsNormally,
      );
    });

    test('stale file version is rejected', () {
      guard.markRead(
        filePath: '/memories/a.md',
        version: const FileToolVersionSnapshot(
          modifiedAtMillis: 10,
          sizeBytes: 20,
        ),
      );

      expect(
        () => guard.assertWritable(
          filePath: '/memories/a.md',
          currentVersion: const FileToolVersionSnapshot(
            modifiedAtMillis: 11,
            sizeBytes: 20,
          ),
          fileExists: true,
        ),
        throwsA(
          isA<FileToolGuardException>().having(
            (error) => error.code,
            'code',
            'stale_file_version',
          ),
        ),
      );
    });

    test('snapshotForStat keeps modified time and size', () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'file-tool-guard-',
      );
      final file = File('${tempDirectory.path}/demo.txt');
      await file.writeAsString('hello');

      final snapshot = guard.snapshotForStat(await file.stat());

      expect(snapshot.sizeBytes, 5);
      expect(snapshot.modifiedAtMillis, greaterThan(0));

      await tempDirectory.delete(recursive: true);
    });
  });
}
