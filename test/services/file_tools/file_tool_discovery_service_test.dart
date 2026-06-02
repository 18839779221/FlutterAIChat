import 'dart:io';

import 'package:ai_chat/services/file_tools/file_tool_budget_service.dart';
import 'package:ai_chat/services/file_tools/file_tool_discovery_service.dart';
import 'package:ai_chat/services/file_tools/file_tool_path_policy.dart';
import 'package:ai_chat/services/file_tools/file_tool_root_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FileToolDiscoveryService', () {
    late Directory tempDirectory;
    late FileToolRootService rootService;
    late FileToolDiscoveryService service;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp(
        'file-tool-discovery-',
      );
      rootService = FileToolRootService(
        rootDirectory: Directory('${tempDirectory.path}/agent'),
      );
      await rootService.ensureReady();
      await Directory('${rootService.rootPath}/memories/nested').create(
        recursive: true,
      );
      await File('${rootService.rootPath}/memories/user.md')
          .writeAsString('hello world\nsecond line');
      await File('${rootService.rootPath}/memories/nested/today.md')
          .writeAsString('nested hello');
      await File('${rootService.rootPath}/artifacts/report.txt')
          .create(recursive: true);
      service = FileToolDiscoveryService(
        rootService: rootService,
        pathPolicy: FileToolPathPolicy(rootService: rootService),
        budgetService: const FileToolBudgetService(maxOutputCharacters: 1000),
      );
    });

    tearDown(() async {
      if (tempDirectory.existsSync()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('list returns direct directory entries', () async {
      final entries = await service.list(pathValue: 'memories', cwd: '/');

      expect(entries.map((item) => item.relativePath).toList(), [
        '/memories/nested',
        '/memories/user.md',
      ]);
    });

    test('glob returns sandbox-relative matches only', () async {
      final result = await service.glob(
        pattern: '**/*.md',
        pathValue: 'memories',
        cwd: '/',
      );

      expect(result, [
        '/memories/nested/today.md',
        '/memories/user.md',
      ]);
    });

    test('grep content mode returns structured matches', () async {
      final result = await service.grep(
        pattern: 'hello',
        pathValue: 'memories',
        cwd: '/',
        outputMode: 'content',
        lineNumbers: true,
      );

      final matches = result['matches'] as List<dynamic>;
      expect(matches, hasLength(2));
      expect(matches.first['filePath'], '/memories/nested/today.md');
      expect(matches.last['lineNumber'], 1);
    });
  });
}
