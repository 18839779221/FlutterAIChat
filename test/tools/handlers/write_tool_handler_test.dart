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
import 'package:ai_chat/tools/handlers/write_tool_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WriteToolHandler', () {
    test('writes a new sandbox file', () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'write-handler-',
      );
      final rootService = FileToolRootService(
        rootDirectory: Directory('${tempDirectory.path}/agent'),
      );
      await rootService.ensureReady();
      final sessionGuard = FileToolSessionGuard();

      final handler = WriteToolHandler();
      final resolution = await handler.normalizeArguments(
        rawArguments: {
          'file_path': 'artifacts/report.md',
          'content': 'hello world',
        },
        userMessage: 'write file',
        history: const [],
        now: DateTime(2026, 4, 13),
      );
      final result = await handler.execute(
        ToolExecutionContext(
          groupId: 1,
          toolName: 'Write',
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
      expect(result.data['filePath'], 'artifacts/report.md');
      expect(
        result.toolResultText,
        '已写入文件：artifacts/report.md',
      );
      expect(
        File('${rootService.rootPath}/artifacts/report.md').existsSync(),
        isTrue,
      );

      await tempDirectory.delete(recursive: true);
    });
  });
}
