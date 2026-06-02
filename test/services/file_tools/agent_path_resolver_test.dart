import 'dart:io';

import 'package:ai_chat/services/file_tools/agent_path.dart';
import 'package:ai_chat/services/file_tools/agent_path_resolver.dart';
import 'package:ai_chat/services/file_tools/file_tool_root_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentPathResolver', () {
    late Directory tempDirectory;
    late AgentPathResolver resolver;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp(
        'agent-path-resolver-',
      );
      final rootService = FileToolRootService(
        rootDirectory: Directory('${tempDirectory.path}/agent'),
      );
      await rootService.ensureReady();
      resolver = AgentPathResolver(rootService: rootService);
    });

    tearDown(() async {
      if (tempDirectory.existsSync()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('keeps absolute agent path stable', () {
      final result = resolver.resolvePath('/artifacts/42/a.html', cwd: '/');

      expect(result.agentAbsolutePath, '/artifacts/42/a.html');
      expect(result.relativePathFromRoot, 'artifacts/42/a.html');
      expect(result.hostAbsolutePath, endsWith('agent/artifacts/42/a.html'));
    });

    test('resolves root-relative input from cwd', () {
      final result = resolver.resolvePath('artifacts/42/a.html', cwd: '/');

      expect(result.agentAbsolutePath, '/artifacts/42/a.html');
      expect(result.relativePathFromRoot, 'artifacts/42/a.html');
    });

    test('resolves current directory segments', () {
      final result = resolver.resolvePath('./a.html', cwd: '/artifacts/42');

      expect(result.agentAbsolutePath, '/artifacts/42/a.html');
    });

    test('resolves parent directory segments inside sandbox', () {
      final result = resolver.resolvePath('../43/b.html', cwd: '/artifacts/42');

      expect(result.agentAbsolutePath, '/artifacts/43/b.html');
    });

    test('normalizes repeated slashes', () {
      final result = resolver.resolvePath(
        '////artifacts//42///a.html',
        cwd: '/',
      );

      expect(result.agentAbsolutePath, '/artifacts/42/a.html');
    });

    test('rejects escaping sandbox root', () {
      expect(
        () => resolver.resolvePath('../../etc/passwd', cwd: '/'),
        throwsA(isA<AgentPathEscapeException>()),
      );
    });
  });
}
