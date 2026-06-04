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

    test('deletePath deletes a single file', () async {
      final file =
          File('${rootService.rootPath}/workspaces/ws_1/artifacts/a.txt');
      await file.create(recursive: true);
      await file.writeAsString('hello');
      guard.markRead(
        filePath: '/workspaces/ws_1/artifacts/a.txt',
        version: guard.snapshotForStat(await file.stat()),
      );

      final outcome = await service.deletePath(
        relativePath: 'workspaces/ws_1/artifacts/a.txt',
      );

      expect(outcome.filePath, '/workspaces/ws_1/artifacts/a.txt');
      expect(outcome.deletedType, 'file');
      expect(outcome.deletedFileCount, 1);
      expect(outcome.deletedDirectoryCount, 0);
      expect(outcome.hadChildren, isFalse);
      expect(file.existsSync(), isFalse);
      expect(guard.hasSeen('/workspaces/ws_1/artifacts/a.txt'), isFalse);
    });

    test('deletePath throws file_not_found for missing targets', () async {
      expect(
        () => service.deletePath(relativePath: 'workspaces/ws_1/missing.txt'),
        throwsA(
          isA<FileToolWriteException>().having(
            (error) => error.code,
            'code',
            'file_not_found',
          ),
        ),
      );
    });

    test('deletePath deletes an empty directory', () async {
      final directory = Directory(
        '${rootService.rootPath}/workspaces/ws_1/artifacts/empty',
      );
      await directory.create(recursive: true);

      final outcome = await service.deletePath(
        relativePath: 'workspaces/ws_1/artifacts/empty',
      );

      expect(outcome.filePath, '/workspaces/ws_1/artifacts/empty');
      expect(outcome.deletedType, 'directory');
      expect(outcome.deletedFileCount, 0);
      expect(outcome.deletedDirectoryCount, 1);
      expect(outcome.hadChildren, isFalse);
      expect(directory.existsSync(), isFalse);
    });

    test('deletePath recursively deletes a populated directory', () async {
      final root = Directory(
        '${rootService.rootPath}/workspaces/ws_1/artifacts/tree',
      );
      await Directory('${root.path}/docs').create(recursive: true);
      await File('${root.path}/README.md').writeAsString('root file');
      await File('${root.path}/docs/a.txt').writeAsString('a');
      await File('${root.path}/docs/b.txt').writeAsString('b');

      final outcome = await service.deletePath(
        relativePath: 'workspaces/ws_1/artifacts/tree',
      );

      expect(outcome.filePath, '/workspaces/ws_1/artifacts/tree');
      expect(outcome.deletedType, 'directory');
      expect(outcome.deletedFileCount, 3);
      expect(outcome.deletedDirectoryCount, 2);
      expect(outcome.hadChildren, isTrue);
      expect(root.existsSync(), isFalse);
      expect(guard.hasSeen('/workspaces/ws_1/artifacts/tree'), isFalse);
    });
  });
}
