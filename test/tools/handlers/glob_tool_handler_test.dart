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
import 'package:ai_chat/tools/adapters/tool_host_adapters.dart';
import 'package:ai_chat/tools/core/tool_execution_context.dart';
import 'package:ai_chat/tools/handlers/glob_tool_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GlobToolHandler', () {
    test('returns relative matches', () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'glob-handler-',
      );
      final rootService = FileToolRootService(
        rootDirectory: Directory('${tempDirectory.path}/agent'),
      );
      await rootService.ensureReady();
      await Directory('${rootService.rootPath}/memories/nested').create(
        recursive: true,
      );
      await File('${rootService.rootPath}/memories/nested/today.md')
          .writeAsString('hello');

      final handler = GlobToolHandler();
      final resolution = await handler.normalizeArguments(
        rawArguments: {
          'pattern': '**/*.md',
          'path': 'memories',
        },
        userMessage: 'find markdown files',
        history: const [],
        now: DateTime(2026, 4, 13),
      );
      final result = await handler.execute(
        ToolExecutionContext(
          groupId: 1,
          toolName: 'Glob',
          arguments: resolution.normalizedArguments,
          history: const <ChatMessage>[],
          now: DateTime(2026, 4, 13),
          hostAdapters: ToolHostAdapters(
            fileTools: FileToolHostAdapters(
              rootService: rootService,
              pathPolicy: FileToolPathPolicy(rootService: rootService),
              sessionGuard: FileToolSessionGuard(),
              budgetService: const FileToolBudgetService(),
              readFormatter: const FileToolReadFormatter(),
              discoveryService: FileToolDiscoveryService(
                rootService: rootService,
                pathPolicy: FileToolPathPolicy(rootService: rootService),
              ),
            ),
          ),
        ),
      );

      expect(result.status, ToolExecutionStatus.success);
      expect(result.data['matches'], ['/memories/nested/today.md']);

      await tempDirectory.delete(recursive: true);
    });
  });
}
