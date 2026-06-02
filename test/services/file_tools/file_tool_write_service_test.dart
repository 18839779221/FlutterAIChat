import 'dart:io';

import 'package:ai_chat/services/file_tools/file_tool_root_service.dart';
import 'package:ai_chat/services/file_tools/file_tool_session_guard.dart';
import 'package:ai_chat/services/file_tools/file_tool_write_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FileToolWriteService', () {
    late Directory tempDirectory;
    late FileToolRootService rootService;
    late FileToolSessionGuard guard;
    late FileToolWriteService service;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp('file-write-');
      rootService = FileToolRootService(
        rootDirectory: Directory('${tempDirectory.path}/agent'),
      );
      await rootService.ensureReady();
      guard = FileToolSessionGuard();
      service = FileToolWriteService(
        rootService: rootService,
        sessionGuard: guard,
      );
    });

    tearDown(() async {
      if (tempDirectory.existsSync()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('write rejects overwriting an unread existing file', () async {
      final file = File('${rootService.rootPath}/memories/demo.md');
      await file.create(recursive: true);
      await file.writeAsString('old');

      expect(
        () => service.writeFile(
          relativePath: '/memories/demo.md',
          content: 'new',
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

    test('write creates new file and refreshes seen state', () async {
      final outcome = await service.writeFile(
        relativePath: '/artifacts/report.md',
        content: 'hello',
      );

      expect(outcome.filePreviouslyExisted, isFalse);
      expect(outcome.newLength, 5);
      expect(outcome.oldContentPreview, isEmpty);
      expect(outcome.newContentPreview, 'hello');
      expect(outcome.contentPreviewTruncated, isFalse);
      expect(guard.hasSeen('/artifacts/report.md'), isTrue);
    });

    test(
        'edit fails when old_string matches multiple locations without replace_all',
        () async {
      final file = File('${rootService.rootPath}/memories/demo.md');
      await file.create(recursive: true);
      await file.writeAsString('return null;\nreturn null;');
      guard.markRead(
        filePath: '/memories/demo.md',
        version: guard.snapshotForStat(await file.stat()),
      );

      expect(
        () => service.editFile(
          relativePath: '/memories/demo.md',
          oldString: 'return null;',
          newString: 'return value;',
          replaceAll: false,
        ),
        throwsA(
          isA<FileToolWriteException>().having(
            (error) => error.code,
            'code',
            'ambiguous_old_string',
          ),
        ),
      );
    });

    test('edit replaces exact string and refreshes seen version', () async {
      final file = File('${rootService.rootPath}/memories/demo.md');
      await file.create(recursive: true);
      await file.writeAsString('alpha\nbeta\ngamma');
      guard.markRead(
        filePath: '/memories/demo.md',
        version: guard.snapshotForStat(await file.stat()),
      );

      final outcome = await service.editFile(
        relativePath: 'memories/demo.md',
        oldString: 'beta',
        newString: 'delta',
        replaceAll: false,
      );

      expect(outcome.replacementCount, 1);
      expect(outcome.oldContentPreview, 'alpha\nbeta\ngamma');
      expect(outcome.newContentPreview, 'alpha\ndelta\ngamma');
      expect(outcome.contentPreviewTruncated, isFalse);
      expect(await file.readAsString(), contains('delta'));
      expect(guard.hasSeen('/memories/demo.md'), isTrue);
    });
  });
}
