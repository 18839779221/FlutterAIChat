import 'dart:io';

import 'package:ai_chat/services/file_tools/file_tool_path_policy.dart';
import 'package:ai_chat/services/file_tools/file_tool_root_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FileToolPathPolicy', () {
    late Directory tempDirectory;
    late FileToolPathPolicy policy;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp(
        'file-tool-path-policy-',
      );
      final rootService = FileToolRootService(
        rootDirectory: Directory('${tempDirectory.path}/agent'),
      );
      await rootService.ensureReady();
      policy = FileToolPathPolicy(rootService: rootService);
    });

    tearDown(() async {
      if (tempDirectory.existsSync()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('rejects parent directory traversal', () {
      final result = policy.normalizeSandboxPath('../secrets.txt', cwd: '/');

      expect(result.isValid, isFalse);
      expect(result.errorCode, 'path_outside_sandbox');
    });

    test('accepts agent absolute path', () {
      final result = policy.normalizeSandboxPath(
        '/memories/user/profile.md',
        cwd: '/',
      );

      expect(result.isValid, isTrue);
      expect(result.relativePath, 'memories/user/profile.md');
      expect(result.absolutePath, endsWith('agent/memories/user/profile.md'));
      expect(result.agentPath, '/memories/user/profile.md');
    });

    test('accepts agent-relative path against cwd', () {
      final result = policy.normalizeSandboxPath(
        './profile.md',
        cwd: '/memories/user',
      );

      expect(result.isValid, isTrue);
      expect(result.relativePath, 'memories/user/profile.md');
      expect(result.agentPath, '/memories/user/profile.md');
    });

    test('normalizes root directory path', () {
      final result = policy.normalizeDirectoryPath('.', cwd: '/');

      expect(result.isValid, isTrue);
      expect(result.relativePath, '');
      expect(result.agentPath, '/');
    });
  });
}
