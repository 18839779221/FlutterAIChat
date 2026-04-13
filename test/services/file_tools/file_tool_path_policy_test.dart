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
      final result = policy.normalizeSandboxPath('../secrets.txt');

      expect(result.isValid, isFalse);
      expect(result.errorCode, 'path_outside_sandbox');
    });

    test('accepts sandbox-relative memory path', () {
      final result = policy.normalizeSandboxPath('memories/user/profile.md');

      expect(result.isValid, isTrue);
      expect(result.relativePath, 'memories/user/profile.md');
      expect(result.absolutePath, endsWith('agent/memories/user/profile.md'));
    });

    test('rejects absolute path input', () {
      final result = policy.normalizeSandboxPath('/tmp/demo.txt');

      expect(result.isValid, isFalse);
      expect(result.errorCode, 'absolute_path_not_allowed');
    });
  });
}
