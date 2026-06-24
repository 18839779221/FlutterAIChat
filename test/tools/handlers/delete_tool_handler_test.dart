import 'dart:io';

import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/models/workspace/resolved_workspace.dart';
import 'package:ai_chat/services/file_tools/file_tool_budget_service.dart';
import 'package:ai_chat/services/file_tools/file_tool_discovery_service.dart';
import 'package:ai_chat/services/file_tools/file_tool_host_adapters.dart';
import 'package:ai_chat/services/file_tools/file_tool_path_policy.dart';
import 'package:ai_chat/services/file_tools/file_tool_read_formatter.dart';
import 'package:ai_chat/services/file_tools/file_tool_root_service.dart';
import 'package:ai_chat/services/file_tools/file_tool_session_guard.dart';
import 'package:ai_chat/services/file_tools/file_tool_write_service.dart';
import 'package:ai_chat/tools/adapters/tool_host_adapters.dart';
import 'package:ai_chat/tools/core/tool_execution_context.dart';
import 'package:ai_chat/tools/handlers/delete_tool_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeleteToolHandler', () {
    late Directory tempDirectory;
    late FileToolRootService rootService;
    late FileToolSessionGuard sessionGuard;
    late DeleteToolHandler handler;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp('delete-handler-');
      rootService = FileToolRootService(
        rootDirectory: Directory('${tempDirectory.path}/agent'),
      );
      await rootService.ensureReady();
      sessionGuard = FileToolSessionGuard();
      _DeleteTestRoot.currentRootService = rootService;
      _DeleteTestRoot.currentSessionGuard = sessionGuard;
      handler = DeleteToolHandler();
    });

    tearDown(() async {
      if (tempDirectory.existsSync()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('exposes definition for high-risk workspace-scoped deletion', () {
      final definition = handler.definition;

      expect(definition.name, 'Delete');
      expect(definition.title, 'Delete');
      expect(definition.requiresConfirmation, isTrue);
      expect(definition.isConcurrencySafe, isFalse);
      expect(definition.resolvedArgumentSchema.required, ['file_path']);
      expect(
        definition.localizedDescriptionForModel?.chinese,
        contains('任何删除当前 workspace 之外内容'),
      );
      expect(
        definition.localizedDescriptionForModel?.chinese,
        contains('当前 workspace 根目录本身'),
      );
    });

    test('normalizes file_path by trimming whitespace', () async {
      final resolution = await handler.normalizeArguments(
        rawArguments: {
          'file_path': '  artifacts/old.txt  ',
        },
        userMessage: '删除这个文件',
        history: const [],
        now: DateTime(2026, 6, 4),
      );

      expect(resolution.isValid, isTrue);
      expect(
        resolution.normalizedArguments,
        containsPair('file_path', 'artifacts/old.txt'),
      );
    });

    test('rejects missing file_path', () async {
      final resolution = await handler.normalizeArguments(
        rawArguments: const {},
        userMessage: '删除这个文件',
        history: const [],
        now: DateTime(2026, 6, 4),
      );

      expect(resolution.isValid, isFalse);
      expect(resolution.errorCode, 'invalid_file_path');
      expect(resolution.errorSummary, 'Delete failed: missing file_path');
    });

    test('execute rejects paths outside current workspace', () async {
      final result = await handler.execute(
        ToolExecutionContext(
          groupId: 1,
          toolName: 'Delete',
          arguments: const {
            'file_path': '/workspaces/ws_other/artifacts/old.txt',
          },
          history: const <ChatMessage>[],
          now: DateTime(2026, 6, 4),
          cwd: '/workspaces/ws_current',
          workspace: const ResolvedWorkspace(
            workspaceId: 'ws_current',
            isDefault: false,
            fileRoot: '/workspaces/ws_current',
          ),
          hostAdapters: ToolHostAdapters(
            fileTools: FileToolHostAdapters(
              rootService: rootService,
              pathPolicy: FileToolPathPolicy(rootService: rootService),
              sessionGuard: sessionGuard,
              budgetService: const FileToolBudgetService(),
              readFormatter: const FileToolReadFormatter(),
              discoveryService: FileToolDiscoveryService(
                rootService: rootService,
                pathPolicy: FileToolPathPolicy(rootService: rootService),
              ),
              writeService: FileToolWriteService(
                rootService: rootService,
                sessionGuard: sessionGuard,
              ),
            ),
          ),
        ),
      );

      expect(result.status, ToolExecutionStatus.failure);
      expect(result.errorMessage, 'path_outside_workspace');
    });

    test('execute rejects deleting the current workspace root', () async {
      final result = await handler.execute(
        ToolExecutionContext(
          groupId: 1,
          toolName: 'Delete',
          arguments: const {
            'file_path': '/workspaces/ws_current',
          },
          history: const <ChatMessage>[],
          now: DateTime(2026, 6, 4),
          cwd: '/workspaces/ws_current',
          workspace: const ResolvedWorkspace(
            workspaceId: 'ws_current',
            isDefault: false,
            fileRoot: '/workspaces/ws_current',
          ),
          hostAdapters: ToolHostAdapters(
            fileTools: FileToolHostAdapters(
              rootService: rootService,
              pathPolicy: FileToolPathPolicy(rootService: rootService),
              sessionGuard: sessionGuard,
              budgetService: const FileToolBudgetService(),
              readFormatter: const FileToolReadFormatter(),
              discoveryService: FileToolDiscoveryService(
                rootService: rootService,
                pathPolicy: FileToolPathPolicy(rootService: rootService),
              ),
              writeService: FileToolWriteService(
                rootService: rootService,
                sessionGuard: sessionGuard,
              ),
            ),
          ),
        ),
      );

      expect(result.status, ToolExecutionStatus.failure);
      expect(result.errorMessage, 'cannot_delete_workspace_root');
    });

    test('execute returns structured delete result', () async {
      final root = Directory(
        '${rootService.rootPath}/workspaces/ws_current/artifacts/tree',
      );
      await Directory('${root.path}/docs').create(recursive: true);
      await File('${root.path}/README.md').writeAsString('root file');
      await File('${root.path}/docs/a.txt').writeAsString('a');
      await File('${root.path}/docs/b.txt').writeAsString('b');

      final result = await handler.execute(
        ToolExecutionContext(
          groupId: 1,
          toolName: 'Delete',
          arguments: const {
            'file_path': '/workspaces/ws_current/artifacts/tree',
          },
          history: const <ChatMessage>[],
          now: DateTime(2026, 6, 4),
          cwd: '/workspaces/ws_current',
          workspace: const ResolvedWorkspace(
            workspaceId: 'ws_current',
            isDefault: false,
            fileRoot: '/workspaces/ws_current',
          ),
          hostAdapters: ToolHostAdapters(
            fileTools: FileToolHostAdapters(
              rootService: rootService,
              pathPolicy: FileToolPathPolicy(rootService: rootService),
              sessionGuard: sessionGuard,
              budgetService: const FileToolBudgetService(),
              readFormatter: const FileToolReadFormatter(),
              discoveryService: FileToolDiscoveryService(
                rootService: rootService,
                pathPolicy: FileToolPathPolicy(rootService: rootService),
              ),
              writeService: FileToolWriteService(
                rootService: rootService,
                sessionGuard: sessionGuard,
              ),
            ),
          ),
        ),
      );

      expect(result.status, ToolExecutionStatus.success);
      expect(result.summary, '已删除路径：/workspaces/ws_current/artifacts/tree');
      expect(result.data['deletedType'], 'directory');
      expect(result.data['deletedFileCount'], 3);
      expect(result.data['deletedDirectoryCount'], 2);
    });

    test('execute allows deleting a memory topic file outside workspace',
        () async {
      final memoryFile = File('${rootService.rootPath}/memories/user/style.md');
      await memoryFile.create(recursive: true);
      await memoryFile.writeAsString('memory');

      final result = await handler.execute(
        _contextForDelete('/memories/user/style.md'),
      );

      expect(result.status, ToolExecutionStatus.success);
      expect(result.summary, '已删除路径：/memories/user/style.md');
      expect(memoryFile.existsSync(), isFalse);
    });

    test('execute rejects deleting the memory root', () async {
      final result = await handler.execute(
        _contextForDelete('/memories'),
      );

      expect(result.status, ToolExecutionStatus.failure);
      expect(result.errorMessage, 'cannot_delete_memory_root');
    });

    test('execute rejects deleting the memory root with trailing slash',
        () async {
      final result = await handler.execute(
        _contextForDelete('/memories/'),
      );

      expect(result.status, ToolExecutionStatus.failure);
      expect(result.errorMessage, 'cannot_delete_memory_root');
    });

    test('execute rejects deleting the memory index file', () async {
      final indexFile = File('${rootService.rootPath}/memories/MEMORY.md');
      await indexFile.create(recursive: true);

      final result = await handler.execute(
        _contextForDelete('/memories/MEMORY.md'),
      );

      expect(result.status, ToolExecutionStatus.failure);
      expect(result.errorMessage, 'cannot_delete_memory_index');
      expect(indexFile.existsSync(), isTrue);
    });
  });
}

ToolExecutionContext _contextForDelete(String filePath) {
  final rootService = _DeleteTestRoot.currentRootService;
  final sessionGuard = _DeleteTestRoot.currentSessionGuard;
  return ToolExecutionContext(
    groupId: 1,
    toolName: 'Delete',
    arguments: {'file_path': filePath},
    history: const <ChatMessage>[],
    now: DateTime(2026, 6, 19),
    cwd: '/workspaces/ws_current',
    workspace: const ResolvedWorkspace(
      workspaceId: 'ws_current',
      isDefault: false,
      fileRoot: '/workspaces/ws_current',
    ),
    hostAdapters: ToolHostAdapters(
      fileTools: FileToolHostAdapters(
        rootService: rootService,
        pathPolicy: FileToolPathPolicy(rootService: rootService),
        sessionGuard: sessionGuard,
        budgetService: const FileToolBudgetService(),
        readFormatter: const FileToolReadFormatter(),
        discoveryService: FileToolDiscoveryService(
          rootService: rootService,
          pathPolicy: FileToolPathPolicy(rootService: rootService),
        ),
        writeService: FileToolWriteService(
          rootService: rootService,
          sessionGuard: sessionGuard,
        ),
      ),
    ),
  );
}

class _DeleteTestRoot {
  static late FileToolRootService currentRootService;
  static late FileToolSessionGuard currentSessionGuard;
}
