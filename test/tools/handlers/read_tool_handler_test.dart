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
import 'package:ai_chat/tools/handlers/read_tool_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReadToolHandler', () {
    late Directory tempDirectory;
    late FileToolSessionGuard guard;
    late FileToolRootService rootService;
    late ReadToolHandler handler;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp('read-handler-');
      rootService = FileToolRootService(
        rootDirectory: Directory('${tempDirectory.path}/agent'),
      );
      await rootService.ensureReady();
      await Directory('${rootService.rootPath}/memories')
          .create(recursive: true);
      await File('${rootService.rootPath}/memories/demo.md').writeAsString(
        'alpha\nbeta\ngamma',
      );
      guard = FileToolSessionGuard();
      handler = ReadToolHandler();
    });

    tearDown(() async {
      if (tempDirectory.existsSync()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('read returns numbered content and registers file version', () async {
      final resolution = await handler.normalizeArguments(
        rawArguments: {
          'file_path': 'memories/demo.md',
          'offset': 1,
          'limit': 2,
        },
        userMessage: 'read the file',
        history: const [],
        now: DateTime(2026, 4, 13),
      );

      final result = await handler.execute(
        ToolExecutionContext(
          groupId: 1,
          toolName: 'Read',
          arguments: resolution.normalizedArguments,
          history: const <ChatMessage>[],
          now: DateTime(2026, 4, 13),
          hostAdapters: ToolHostAdapters(
            fileTools: FileToolHostAdapters(
              rootService: rootService,
              pathPolicy: FileToolPathPolicy(rootService: rootService),
              sessionGuard: guard,
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
      expect(result.data['content'], contains('     2\tbeta'));
      expect(result.data['content'], contains('     3\tgamma'));
      expect(result.data['linesReturned'], 2);
      expect(result.data['fileVersion'], isA<Map<String, dynamic>>());
      expect(guard.hasSeen('memories/demo.md'), isTrue);
    });
  });
}
