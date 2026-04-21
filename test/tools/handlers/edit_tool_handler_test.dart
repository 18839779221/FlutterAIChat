import 'dart:io';

import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
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
import 'package:ai_chat/tools/handlers/edit_tool_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EditToolHandler', () {
    test('edits an existing file after it has been read', () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'edit-handler-',
      );
      final rootService = FileToolRootService(
        rootDirectory: Directory('${tempDirectory.path}/agent'),
      );
      await rootService.ensureReady();
      final file = File('${rootService.rootPath}/memories/demo.md');
      await file.create(recursive: true);
      await file.writeAsString('alpha\nbeta\ngamma');
      final sessionGuard = FileToolSessionGuard();
      sessionGuard.markRead(
        filePath: 'memories/demo.md',
        version: sessionGuard.snapshotForStat(await file.stat()),
      );

      final handler = EditToolHandler();
      final resolution = await handler.normalizeArguments(
        rawArguments: {
          'file_path': 'memories/demo.md',
          'old_string': 'beta',
          'new_string': 'delta',
        },
        userMessage: 'edit file',
        history: const [],
        now: DateTime(2026, 4, 13),
      );
      final result = await handler.execute(
        ToolExecutionContext(
          groupId: 1,
          toolName: 'Edit',
          arguments: resolution.normalizedArguments,
          history: const <ChatMessage>[],
          now: DateTime(2026, 4, 13),
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
      expect(result.data['replacementCount'], 1);
      expect(
        result.toolResultText,
        '已编辑文件：memories/demo.md',
      );
      expect(await file.readAsString(), contains('delta'));

      await tempDirectory.delete(recursive: true);
    });

    test('returns structured failure for ambiguous edits', () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'edit-handler-ambiguous-',
      );
      final rootService = FileToolRootService(
        rootDirectory: Directory('${tempDirectory.path}/agent'),
      );
      await rootService.ensureReady();
      final file = File('${rootService.rootPath}/memories/demo.md');
      await file.create(recursive: true);
      await file.writeAsString('return null;\nreturn null;');
      final sessionGuard = FileToolSessionGuard();
      sessionGuard.markRead(
        filePath: 'memories/demo.md',
        version: sessionGuard.snapshotForStat(await file.stat()),
      );

      final handler = EditToolHandler();
      final resolution = await handler.normalizeArguments(
        rawArguments: {
          'file_path': 'memories/demo.md',
          'old_string': 'return null;',
          'new_string': 'return value;',
        },
        userMessage: 'edit file',
        history: const [],
        now: DateTime(2026, 4, 13),
      );
      final result = await handler.execute(
        ToolExecutionContext(
          groupId: 1,
          toolName: 'Edit',
          arguments: resolution.normalizedArguments,
          history: const <ChatMessage>[],
          now: DateTime(2026, 4, 13),
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
      expect(result.errorMessage, 'ambiguous_old_string');
      expect(
        result.toolResultText,
        '编辑文件失败\n实际文件路径：memories/demo.md',
      );

      await tempDirectory.delete(recursive: true);
    });
  });
}
