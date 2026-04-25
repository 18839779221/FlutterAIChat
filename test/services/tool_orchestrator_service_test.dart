import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/trace/chat_trace_event.dart';
import 'package:ai_chat/models/tool/tool_definition.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/models/tool/tool_policy.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/services/chat_trace_recorder.dart';
import 'package:ai_chat/services/file_tools/file_tool_budget_service.dart';
import 'package:ai_chat/services/file_tools/file_tool_discovery_service.dart';
import 'package:ai_chat/services/file_tools/file_tool_host_adapters.dart';
import 'package:ai_chat/services/file_tools/file_tool_path_policy.dart';
import 'package:ai_chat/services/file_tools/file_tool_read_formatter.dart';
import 'package:ai_chat/services/file_tools/file_tool_root_service.dart';
import 'package:ai_chat/services/file_tools/file_tool_session_guard.dart';
import 'package:ai_chat/services/tool_orchestrator_service.dart';
import 'package:ai_chat/services/tool_policy_service.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/tools/adapters/tool_host_adapters.dart';
import 'package:ai_chat/tools/core/tool_argument_resolution.dart';
import 'package:ai_chat/tools/core/tool_execution_context.dart';
import 'package:ai_chat/tools/core/tool_handler.dart';
import 'package:ai_chat/tools/core/tool_runtime_registry.dart';
import 'package:ai_chat/tools/handlers/read_tool_handler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

void main() {
  group('ToolOrchestratorService.executeToolInvocation', () {
    test('returns confirmation request before running high-risk tool',
        () async {
      final service = await _createService(
        runtimeRegistry: ToolRuntimeRegistry(
          handlers: [
            _FakeShareToolHandler(),
          ],
        ),
      );

      final result = await service.executeToolInvocation(
        groupId: 1,
        invocation: const ToolInvocation(
          toolName: 'share_result',
          arguments: {
            'text': '这是一段要分享的内容',
            'subject': '分享标题',
          },
          status: ToolInvocationStatus.running,
          summary: '准备执行工具：分享结果',
          requiresConfirmation: false,
        ),
      );

      expect(result.toolResult, isNull);
      expect(result.additionalContextMessages, isEmpty);
      expect(result.toolInvocation, isNotNull);
      expect(
        result.toolInvocation!.status,
        ToolInvocationStatus.awaitingConfirmation,
      );
      expect(result.toolInvocation!.requiresConfirmation, isTrue);
      expect(result.toolAccess, isNotNull);
      expect(result.toolAccess!.executionPolicyLabel, 'require_confirmation');
    });

    test('returns blocked result with shared policy metadata', () async {
      final service = await _createService(
        runtimeRegistry: ToolRuntimeRegistry(
          handlers: [
            _FakeReminderToolHandler(),
          ],
        ),
        blockedToolNames: const {'create_reminder'},
      );

      final result = await service.executeToolInvocation(
        groupId: 1,
        invocation: const ToolInvocation(
          toolName: 'create_reminder',
          arguments: {
            'title': '交周报',
            'dueAt': '2026-03-31T20:00:00+08:00',
          },
          status: ToolInvocationStatus.running,
          summary: '准备执行工具：创建提醒',
          requiresConfirmation: false,
        ),
      );

      expect(result.toolAccess, isNotNull);
      expect(result.toolAccess!.executionDecision, ToolPolicyDecision.blocked);
      expect(result.toolAccess!.isVisibleToPlanner, isFalse);
      expect(result.toolResult, isNotNull);
      expect(result.toolResult!.status, ToolExecutionStatus.failure);
      expect(result.toolResult!.executionPolicy, 'blocked');
      expect(
        result.toolResult!.toolAccess?['executionPolicy'],
        'blocked',
      );
      expect(result.toolInvocation!.status, ToolInvocationStatus.cancelled);
    });

    test('rejects user interaction tools from the immediate execution path',
        () async {
      final service = await _createService(
        runtimeRegistry: ToolRuntimeRegistry(
          handlers: [
            _FakeAskUserQuestionToolHandler(),
          ],
        ),
      );

      expect(
        () => service.executeToolInvocation(
          groupId: 1,
          invocation: const ToolInvocation(
            toolName: 'ask_user_question',
            arguments: {
              'questions': [],
            },
            status: ToolInvocationStatus.running,
            summary: '请先回答几个问题',
            requiresConfirmation: false,
          ),
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('executes runtime handler and builds structured context', () async {
      final traceRecorder = ChatTraceRecorder();
      final service = await _createService(
        traceRecorder: traceRecorder,
        runtimeRegistry: ToolRuntimeRegistry(
          handlers: [
            _FakeShareToolHandler(),
          ],
        ),
      );

      final result = await service.executeToolInvocation(
        groupId: 1,
        invocation: const ToolInvocation(
          toolName: 'share_result',
          arguments: {
            'text': '这是一段要分享的内容',
            'subject': '分享标题',
          },
          status: ToolInvocationStatus.awaitingConfirmation,
          summary: '准备执行工具：分享结果',
          requiresConfirmation: true,
        ),
        turnId: 'turn-tool-1',
      );

      expect(result.toolResult, isNotNull);
      expect(result.toolResult!.toolName, 'share_result');
      expect(result.toolResult!.executionPolicy, 'require_confirmation');
      expect(
        result.toolResult!.toolAccess?['executionPolicy'],
        'require_confirmation',
      );
      expect(result.additionalContextMessages.single.text,
          contains('分享状态：success'));

      final stages = traceRecorder
          .eventsForTurn('turn-tool-1')
          .map((event) => event.stage)
          .toList();
      expect(
        stages,
        containsAllInOrder([
          ChatTraceStage.toolExecuteDone,
          ChatTraceStage.toolContextBuilt,
        ]),
      );
    });

    test('trustTool flag persists trust before execution', () async {
      final service = await _createService(
        runtimeRegistry: ToolRuntimeRegistry(
          handlers: [
            _FakeReminderToolHandler(),
          ],
        ),
      );

      await service.executeToolInvocation(
        groupId: 1,
        invocation: const ToolInvocation(
          toolName: 'create_reminder',
          arguments: {
            'title': '交周报',
            'dueAt': '2026-03-31T20:00:00+08:00',
          },
          status: ToolInvocationStatus.awaitingConfirmation,
          summary: '准备执行工具：创建提醒',
          requiresConfirmation: true,
        ),
        trustTool: true,
      );

      final second = await service.executeToolInvocation(
        groupId: 1,
        invocation: const ToolInvocation(
          toolName: 'create_reminder',
          arguments: {
            'title': '再次交周报',
            'dueAt': '2026-04-01T20:00:00+08:00',
          },
          status: ToolInvocationStatus.awaitingConfirmation,
          summary: '准备执行工具：创建提醒',
          requiresConfirmation: true,
        ),
      );

      expect(second.toolResult, isNotNull);
      expect(second.toolResult!.toolName, 'create_reminder');
    });

    test('normalizes arguments before executing runtime handler', () async {
      final handler = _RecordingNormalizeToolHandler();
      final service = await _createService(
        runtimeRegistry: ToolRuntimeRegistry(
          handlers: [handler],
        ),
      );

      final result = await service.executeToolInvocation(
        groupId: 1,
        invocation: const ToolInvocation(
          toolName: 'web_search',
          arguments: {
            'query': 'OpenAI latest news',
            'top_k': 4,
          },
          status: ToolInvocationStatus.running,
          summary: '准备执行工具：联网搜索',
          requiresConfirmation: false,
        ),
      );

      expect(handler.seenRawArguments, containsPair('top_k', 4));
      expect(handler.executedArguments, isNotNull);
      expect(handler.executedArguments, isNot(contains('top_k')));
      expect(handler.executedArguments, containsPair('maxResults', 4));
      expect(result.toolResult, isNotNull);
      expect(result.toolResult!.status, ToolExecutionStatus.success);
    });

    test('returns failure result when normalized arguments are invalid',
        () async {
      final service = await _createService(
        runtimeRegistry: ToolRuntimeRegistry(
          handlers: [_InvalidNormalizeToolHandler()],
        ),
      );

      final result = await service.executeToolInvocation(
        groupId: 1,
        invocation: const ToolInvocation(
          toolName: 'web_search',
          arguments: {},
          status: ToolInvocationStatus.running,
          summary: '准备执行工具：联网搜索',
          requiresConfirmation: false,
        ),
      );

      expect(result.toolResult, isNotNull);
      expect(result.toolResult!.status, ToolExecutionStatus.failure);
      expect(result.toolResult!.errorMessage, 'invalid_query');
      expect(result.additionalContextMessages, isEmpty);
    });

    test('fires execution-started callback before runtime handler executes',
        () async {
      final handler = _ExecutionStartedProbeToolHandler();
      final service = await _createService(
        runtimeRegistry: ToolRuntimeRegistry(
          handlers: [handler],
        ),
      );
      var callbackCalled = false;

      final result = await service.executeToolInvocation(
        groupId: 1,
        invocation: const ToolInvocation(
          toolName: 'web_search',
          arguments: {'query': 'tool state timing'},
          status: ToolInvocationStatus.running,
          summary: '准备执行工具：联网搜索',
          requiresConfirmation: false,
        ),
        onExecutionStarted: ({required invocation, required toolAccess}) {
          callbackCalled = true;
          handler.executionStarted = true;
        },
      );

      expect(callbackCalled, isTrue);
      expect(handler.sawExecutionStartedBeforeExecute, isTrue);
      expect(result.executionStarted, isTrue);
    });

    test('passes host adapters through execution context for file tools',
        () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'tool-orchestrator-read-',
      );
      final rootService = FileToolRootService(
        rootDirectory: Directory('${tempDirectory.path}/agent'),
      );
      await rootService.ensureReady();
      await rootService.resolveDirectory('memories').create(recursive: true);
      await File('${rootService.rootPath}/memories/demo.md')
          .writeAsString('alpha\nbeta');

      final service = await _createService(
        runtimeRegistry: ToolRuntimeRegistry(
          handlers: [ReadToolHandler()],
        ),
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
      );

      final result = await service.executeToolInvocation(
        groupId: 1,
        invocation: const ToolInvocation(
          toolName: 'Read',
          arguments: {'file_path': 'memories/demo.md'},
          status: ToolInvocationStatus.running,
          summary: '准备执行工具：读取文件',
          requiresConfirmation: false,
        ),
      );

      expect(result.toolResult?.status, ToolExecutionStatus.success);
      expect(result.toolResult?.data['content'], contains('alpha'));

      await tempDirectory.delete(recursive: true);
    });

    test('requires tool policy service before resolving runtime tool access',
        () async {
      final service = ToolOrchestratorService(
        runtimeRegistry: ToolRuntimeRegistry(
          handlers: [
            _FakeShareToolHandler(),
          ],
        ),
      );

      await expectLater(
        () => service.executeToolInvocation(
          groupId: 1,
          invocation: const ToolInvocation(
            toolName: 'share_result',
            arguments: {
              'text': '这是一段要分享的内容',
              'subject': '分享标题',
            },
            status: ToolInvocationStatus.running,
            summary: '准备执行工具：分享结果',
            requiresConfirmation: false,
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('toolPolicyService is required'),
          ),
        ),
      );
    });
  });
}

Future<ToolOrchestratorService> _createService({
  required ToolRuntimeRegistry runtimeRegistry,
  ChatTraceRecorder? traceRecorder,
  ToolHostAdapters hostAdapters = const ToolHostAdapters(),
  Set<String> blockedToolNames = const {},
}) async {
  SharedPreferences.setMockInitialValues({
    if (blockedToolNames.isNotEmpty) 'tool.blocked_names': blockedToolNames.toList(),
  });
  final preferences = await SharedPreferences.getInstance();
  return ToolOrchestratorService(
    runtimeRegistry: runtimeRegistry,
    traceRecorder: traceRecorder,
    hostAdapters: hostAdapters,
    toolPolicyService: ToolPolicyService(
      repository: AppSettingsRepository(
        preferences,
        localDefaultsLoader: () async => null,
      ),
    ),
  );
}

class _FakeShareToolHandler implements ToolHandler {
  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'share_result',
        title: '分享结果',
        parameters: {
          'text': 'string',
          'subject': 'string',
        },
        requiresConfirmation: true,
      );

  @override
  List<ChatMessage> buildContextMessages({
    required ToolResult result,
    required ToolExecutionContext context,
  }) {
    return [
      ChatMessage(
        text: '分享状态：success',
        role: MessageRole.system,
        status: MessageStatus.completed,
      ),
    ];
  }

  @override
  Future<ToolResult> execute(ToolExecutionContext context) async {
    return ToolResult(
      toolName: 'share_result',
      status: ToolExecutionStatus.success,
      summary: '已发起分享',
      data: {
        'text': context.arguments['text'],
        'subject': context.arguments['subject'],
        'shareStatus': 'success',
      },
    );
  }

  @override
  Future<ToolArgumentResolution> normalizeArguments({
    required Map<String, dynamic> rawArguments,
    required String userMessage,
    required List<ChatMessage> history,
    required DateTime now,
  }) async {
    return ToolArgumentResolution.valid(rawArguments);
  }
}

class _FakeReminderToolHandler implements ToolHandler {
  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'create_reminder',
        title: '创建提醒',
        parameters: {
          'title': 'string',
          'dueAt': 'string',
        },
        requiresConfirmation: true,
      );

  @override
  List<ChatMessage> buildContextMessages({
    required ToolResult result,
    required ToolExecutionContext context,
  }) {
    return [
      ChatMessage(
        text: '已创建提醒：${context.arguments['title']}',
        role: MessageRole.system,
        status: MessageStatus.completed,
      ),
    ];
  }

  @override
  Future<ToolResult> execute(ToolExecutionContext context) async {
    return ToolResult(
      toolName: 'create_reminder',
      status: ToolExecutionStatus.success,
      summary: '已创建提醒：${context.arguments['title']}',
      data: {
        'title': context.arguments['title'],
        'dueAt': context.arguments['dueAt'],
      },
    );
  }

  @override
  Future<ToolArgumentResolution> normalizeArguments({
    required Map<String, dynamic> rawArguments,
    required String userMessage,
    required List<ChatMessage> history,
    required DateTime now,
  }) async {
    return ToolArgumentResolution.valid(rawArguments);
  }
}

class _FakeAskUserQuestionToolHandler implements ToolHandler {
  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'ask_user_question',
        title: '向用户提问',
        runtimeKind: ToolRuntimeKind.userInteraction,
      );

  @override
  Future<ToolResult> execute(ToolExecutionContext context) async {
    throw StateError('interaction tools should not execute via orchestrator');
  }

  @override
  List<ChatMessage> buildContextMessages({
    required ToolResult result,
    required ToolExecutionContext context,
  }) {
    return const [];
  }

  @override
  Future<ToolArgumentResolution> normalizeArguments({
    required Map<String, dynamic> rawArguments,
    required String userMessage,
    required List<ChatMessage> history,
    required DateTime now,
  }) async {
    return ToolArgumentResolution.valid(rawArguments);
  }
}

class _RecordingNormalizeToolHandler implements ToolHandler {
  Map<String, dynamic>? seenRawArguments;
  Map<String, dynamic>? executedArguments;

  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'web_search',
        title: '联网搜索',
        parameters: {
          'query': 'string',
          'maxResults': 'int?',
        },
      );

  @override
  List<ChatMessage> buildContextMessages({
    required ToolResult result,
    required ToolExecutionContext context,
  }) {
    return [
      ChatMessage(
        text: '已归一化 maxResults=${context.arguments['maxResults']}',
        role: MessageRole.system,
        status: MessageStatus.completed,
      ),
    ];
  }

  @override
  Future<ToolResult> execute(ToolExecutionContext context) async {
    executedArguments = Map<String, dynamic>.from(context.arguments);
    return ToolResult(
      toolName: 'web_search',
      status: ToolExecutionStatus.success,
      summary: '联网搜索成功',
      data: Map<String, dynamic>.from(context.arguments),
    );
  }

  @override
  Future<ToolArgumentResolution> normalizeArguments({
    required Map<String, dynamic> rawArguments,
    required String userMessage,
    required List<ChatMessage> history,
    required DateTime now,
  }) async {
    seenRawArguments = Map<String, dynamic>.from(rawArguments);
    return ToolArgumentResolution.valid({
      'query': rawArguments['query'],
      'maxResults': rawArguments['top_k'],
    });
  }
}

class _InvalidNormalizeToolHandler implements ToolHandler {
  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'web_search',
        title: '联网搜索',
        parameters: {
          'query': 'string',
        },
      );

  @override
  List<ChatMessage> buildContextMessages({
    required ToolResult result,
    required ToolExecutionContext context,
  }) {
    return const [];
  }

  @override
  Future<ToolResult> execute(ToolExecutionContext context) async {
    throw UnimplementedError('invalid arguments should not execute');
  }

  @override
  Future<ToolArgumentResolution> normalizeArguments({
    required Map<String, dynamic> rawArguments,
    required String userMessage,
    required List<ChatMessage> history,
    required DateTime now,
  }) async {
    return ToolArgumentResolution.invalid(
      errorCode: 'invalid_query',
      errorSummary: '联网搜索失败：缺少有效查询词',
    );
  }
}

class _ExecutionStartedProbeToolHandler implements ToolHandler {
  bool executionStarted = false;
  bool sawExecutionStartedBeforeExecute = false;

  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'web_search',
        title: '联网搜索',
        parameters: {
          'query': 'string',
        },
      );

  @override
  List<ChatMessage> buildContextMessages({
    required ToolResult result,
    required ToolExecutionContext context,
  }) {
    return const [];
  }

  @override
  Future<ToolResult> execute(ToolExecutionContext context) async {
    sawExecutionStartedBeforeExecute = executionStarted;
    return const ToolResult(
      toolName: 'web_search',
      status: ToolExecutionStatus.success,
      summary: '联网搜索成功',
    );
  }

  @override
  Future<ToolArgumentResolution> normalizeArguments({
    required Map<String, dynamic> rawArguments,
    required String userMessage,
    required List<ChatMessage> history,
    required DateTime now,
  }) async {
    return ToolArgumentResolution.valid(rawArguments);
  }
}
