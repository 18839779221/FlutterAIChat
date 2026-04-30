import 'dart:async';

import 'package:ai_chat/models/agent/agent_loop_limits.dart';
import 'package:ai_chat/models/agent/chat_turn_step.dart';
import 'package:ai_chat/models/agent/model_tool_call.dart';
import 'package:ai_chat/models/agent/model_turn_decision.dart';
import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/interaction/ask_user_question_request.dart';
import 'package:ai_chat/models/interaction/ask_user_question_response.dart';
import 'package:ai_chat/models/tool/tool_access_snapshot.dart';
import 'package:ai_chat/models/tool/tool_definition.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/models/tool/tool_policy.dart';
import 'package:ai_chat/repositories/chat_event_repository.dart';
import 'package:ai_chat/repositories/chat_turn_repository.dart';
import 'package:ai_chat/repositories/chat_turn_step_repository.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/decision_tool_call_executor.dart';
import 'package:ai_chat/services/tool_call_service.dart';
import 'package:ai_chat/services/tool_executor.dart';
import 'package:ai_chat/storage/chat_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DefaultDecisionToolCallExecutor', () {
    test('limits concurrent execution within one concurrency-safe batch',
        () async {
      final turnRepository = _InMemoryChatTurnRepository();
      final stepRepository = _InMemoryChatTurnStepRepository();
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          id: 1,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '并发读取',
        ),
      );
      final turn = (await turnRepository.getTurn(turnId))!;
      final toolCallService = _TrackingToolCallService(
        definitionsByName: {
          'Read': const ToolDefinition(
            name: 'Read',
            title: '读取文件',
            isConcurrencySafe: true,
          ),
        },
        handlersByKey: {
          'a.txt': () => _delayedSuccess('Read', 'a.txt'),
          'b.txt': () => _delayedSuccess('Read', 'b.txt'),
          'c.txt': () => _delayedSuccess('Read', 'c.txt'),
          'd.txt': () => _delayedSuccess('Read', 'd.txt'),
          'e.txt': () => _delayedSuccess('Read', 'e.txt'),
        },
      );
      final executor = DefaultDecisionToolCallExecutor(
        turnRepository: turnRepository,
        stepRepository: stepRepository,
        eventRepository: _InMemoryChatEventRepository(),
        toolCallService: toolCallService,
        limits: const AgentLoopLimits(),
        maxConcurrentExecutions: 2,
      );

      final updates = await executor
          .executeDecisionToolCalls(
            turn: turn,
            decision: ModelTurnDecision(
              toolCalls: _readCalls(['a.txt', 'b.txt', 'c.txt', 'd.txt', 'e.txt']),
              assistantMessage: null,
              providerState: const {'response_id': 'resp_parallel'},
              isTerminal: false,
            ),
            config: ChatConfig(systemPrompt: ''),
            consecutiveFailures: 0,
          )
          .toList();

      final summary = updates.last.summary!;
      expect(toolCallService.maxActiveInvocations, 2);
      expect(toolCallService.executedKeys,
          ['a.txt', 'b.txt', 'c.txt', 'd.txt', 'e.txt']);
      expect(summary.executedToolCount, 5);
      expect(summary.shouldStopFurtherExecution, isFalse);
      final steps = await stepRepository.listSteps(turnId);
      expect(steps, hasLength(5));
      expect(
        steps.every((step) => step.status == ChatTurnStepStatus.completed),
        isTrue,
      );
    });

    test('waits for all tasks in a concurrent batch before stopping on failure',
        () async {
      final turnRepository = _InMemoryChatTurnRepository();
      final stepRepository = _InMemoryChatTurnStepRepository();
      final eventRepository = _InMemoryChatEventRepository();
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          id: 2,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '批内失败',
        ),
      );
      final turn = (await turnRepository.getTurn(turnId))!;
      final toolCallService = _TrackingToolCallService(
        definitionsByName: {
          'Read': const ToolDefinition(
            name: 'Read',
            title: '读取文件',
            isConcurrencySafe: true,
          ),
        },
        handlersByKey: {
          'ok-a.txt': () => _delayedSuccess('Read', 'ok-a.txt',
              delay: const Duration(milliseconds: 35)),
          'bad.txt': () => _delayedFailure('Read', 'bad.txt',
              delay: const Duration(milliseconds: 5)),
          'ok-c.txt': () => _delayedSuccess('Read', 'ok-c.txt',
              delay: const Duration(milliseconds: 20)),
        },
      );
      final executor = DefaultDecisionToolCallExecutor(
        turnRepository: turnRepository,
        stepRepository: stepRepository,
        eventRepository: eventRepository,
        toolCallService: toolCallService,
        limits: const AgentLoopLimits(),
        maxConcurrentExecutions: 3,
      );

      final updates = await executor
          .executeDecisionToolCalls(
            turn: turn,
            decision: ModelTurnDecision(
              toolCalls: _readCalls(['ok-a.txt', 'bad.txt', 'ok-c.txt']),
              assistantMessage: null,
              providerState: const {'response_id': 'resp_failure'},
              isTerminal: false,
            ),
            config: ChatConfig(systemPrompt: ''),
            consecutiveFailures: 0,
          )
          .toList();

      final summary = updates.last.summary!;
      expect(toolCallService.executedKeys,
          ['ok-a.txt', 'bad.txt', 'ok-c.txt']);
      expect(summary.executedToolCount, 3);
      expect(summary.hasFailedStep, isTrue);
      expect(summary.shouldStopFurtherExecution, isTrue);
      final steps = await stepRepository.listSteps(turnId);
      expect(
        steps.map((step) => step.status).toList(),
        containsAll([
          ChatTurnStepStatus.completed,
          ChatTurnStepStatus.failed,
          ChatTurnStepStatus.completed,
        ]),
      );
      final eventTypes = updates
          .where((update) => update.event != null)
          .map((update) => update.event!.eventType)
          .toList();
      expect(eventTypes.where((type) => type == ChatEventType.toolResult).length,
          2);
      expect(eventTypes.where((type) => type == ChatEventType.toolError).length,
          1);
    });

    test('preserves provider response id on concurrent assistant tool calls',
        () async {
      final turnRepository = _InMemoryChatTurnRepository();
      final stepRepository = _InMemoryChatTurnStepRepository();
      final eventRepository = _InMemoryChatEventRepository();
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          id: 21,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '并发继续执行 provider tool loop',
        ),
      );
      final turn = (await turnRepository.getTurn(turnId))!;
      final toolCallService = _TrackingToolCallService(
        definitionsByName: {
          'Read': const ToolDefinition(
            name: 'Read',
            title: '读取文件',
            isConcurrencySafe: true,
          ),
        },
        handlersByKey: {
          'alpha.txt': () => _delayedSuccess('Read', 'alpha.txt'),
          'beta.txt': () => _delayedSuccess('Read', 'beta.txt'),
        },
      );
      final executor = DefaultDecisionToolCallExecutor(
        turnRepository: turnRepository,
        stepRepository: stepRepository,
        eventRepository: eventRepository,
        toolCallService: toolCallService,
        limits: const AgentLoopLimits(),
        maxConcurrentExecutions: 2,
      );

      await executor
          .executeDecisionToolCalls(
            turn: turn,
            decision: ModelTurnDecision(
              toolCalls: const [
                ModelToolCall(
                  providerCallId: 'call_alpha',
                  toolName: 'Read',
                  arguments: {'file_path': 'alpha.txt'},
                  sequence: 1,
                ),
                ModelToolCall(
                  providerCallId: 'call_beta',
                  toolName: 'Read',
                  arguments: {'file_path': 'beta.txt'},
                  sequence: 2,
                ),
              ],
              assistantMessage: null,
              providerState: const {'response_id': 'resp_parallel_calls'},
              isTerminal: false,
            ),
            config: ChatConfig(systemPrompt: ''),
            consecutiveFailures: 0,
          )
          .toList();

      final toolCallEvents = eventRepository.events
          .where((event) => event.eventType == ChatEventType.assistantToolCall)
          .toList(growable: false);
      expect(toolCallEvents, hasLength(2));
      expect(
        toolCallEvents
            .map((event) => event.payloadJson?['providerResponseId'])
            .toSet(),
        {'resp_parallel_calls'},
      );
      expect(
        toolCallEvents.map((event) => event.payloadJson?['providerCallId']).toSet(),
        {'call_alpha', 'call_beta'},
      );
    });

    test('preserves provider call id from proposed to running and result',
        () async {
      final turnRepository = _InMemoryChatTurnRepository();
      final stepRepository = _InMemoryChatTurnStepRepository();
      final eventRepository = _InMemoryChatEventRepository();
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          id: 22,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '检查 provider call id 贯穿',
        ),
      );
      final turn = (await turnRepository.getTurn(turnId))!;
      final toolCallService = _TrackingToolCallService(
        definitionsByName: {
          'Read': const ToolDefinition(
            name: 'Read',
            title: '读取文件',
            isConcurrencySafe: true,
          ),
        },
        handlersByKey: {
          'alpha.txt': () => _delayedSuccess('Read', 'alpha.txt'),
        },
      );
      final executor = DefaultDecisionToolCallExecutor(
        turnRepository: turnRepository,
        stepRepository: stepRepository,
        eventRepository: eventRepository,
        toolCallService: toolCallService,
        limits: const AgentLoopLimits(),
        maxConcurrentExecutions: 1,
      );

      await executor
          .executeDecisionToolCalls(
            turn: turn,
            decision: const ModelTurnDecision(
              toolCalls: [
                ModelToolCall(
                  providerCallId: 'call_alpha',
                  toolName: 'Read',
                  arguments: {'file_path': 'alpha.txt'},
                  sequence: 1,
                ),
              ],
              assistantMessage: null,
              providerState: {'response_id': 'resp_provider_call_chain'},
              isTerminal: false,
            ),
            config: ChatConfig(systemPrompt: ''),
            consecutiveFailures: 0,
          )
          .toList();

      final proposedEvents = eventRepository.events
          .where((event) => event.eventType == ChatEventType.assistantToolCall)
          .toList(growable: false);
      final runningEvents = eventRepository.events
          .where((event) => event.eventType == ChatEventType.toolExecutionStarted)
          .toList(growable: false);
      final toolResultEvents = eventRepository.events
          .where((event) => event.eventType == ChatEventType.toolResult)
          .toList(growable: false);

      expect(proposedEvents, hasLength(1));
      expect(runningEvents, hasLength(1));
      expect(
        proposedEvents.single.payloadJson?['providerCallId'],
        'call_alpha',
      );
      expect(
        runningEvents.single.payloadJson?['providerCallId'],
        'call_alpha',
      );
      expect(toolResultEvents, hasLength(1));
      expect(toolResultEvents.single.payloadJson?['providerCallId'], 'call_alpha');
    });

    test('emits tool execution started once even when service reports pre-start',
        () async {
      final turnRepository = _InMemoryChatTurnRepository();
      final stepRepository = _InMemoryChatTurnStepRepository();
      final eventRepository = _InMemoryChatEventRepository();
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          id: 20,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '检查工具状态',
        ),
      );
      final turn = (await turnRepository.getTurn(turnId))!;
      final toolCallService = _TrackingToolCallService(
        definitionsByName: {
          'Read': const ToolDefinition(
            name: 'Read',
            title: '读取文件',
            isConcurrencySafe: true,
          ),
        },
        handlersByKey: {
          'probe.txt': () => _delayedSuccess('Read', 'probe.txt'),
        },
      );
      final executor = DefaultDecisionToolCallExecutor(
        turnRepository: turnRepository,
        stepRepository: stepRepository,
        eventRepository: eventRepository,
        toolCallService: toolCallService,
        limits: const AgentLoopLimits(),
        maxConcurrentExecutions: 1,
      );

      final updates = await executor
          .executeDecisionToolCalls(
            turn: turn,
            decision: ModelTurnDecision(
              toolCalls: _readCalls(['probe.txt']),
              assistantMessage: null,
              providerState: const {'response_id': 'resp_started_once'},
              isTerminal: false,
            ),
            config: ChatConfig(systemPrompt: ''),
            consecutiveFailures: 0,
          )
          .toList();

      final startedEvents = updates
          .where((update) =>
              update.event?.eventType == ChatEventType.assistantToolCall)
          .toList();
      expect(startedEvents, hasLength(1));
    });

    test('keeps write tools isolated between concurrent read batches', () async {
      final turnRepository = _InMemoryChatTurnRepository();
      final stepRepository = _InMemoryChatTurnStepRepository();
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          id: 3,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '读写混合',
        ),
      );
      final turn = (await turnRepository.getTurn(turnId))!;
      final toolCallService = _TrackingToolCallService(
        definitionsByName: {
          'Read': const ToolDefinition(
            name: 'Read',
            title: '读取文件',
            isConcurrencySafe: true,
          ),
          'Write': const ToolDefinition(
            name: 'Write',
            title: '写入文件',
            isConcurrencySafe: false,
          ),
        },
      );
      toolCallService.handlersByKey.addAll({
        'read-a.txt': () => toolCallService.pending('read-a.txt'),
        'read-b.txt': () => toolCallService.pending('read-b.txt'),
        'write-c.txt': () => toolCallService.pending('write-c.txt'),
        'read-d.txt': () => toolCallService.pending('read-d.txt'),
        'read-e.txt': () => toolCallService.pending('read-e.txt'),
      });
      final executor = DefaultDecisionToolCallExecutor(
        turnRepository: turnRepository,
        stepRepository: stepRepository,
        eventRepository: _InMemoryChatEventRepository(),
        toolCallService: toolCallService,
        limits: const AgentLoopLimits(),
        maxConcurrentExecutions: 10,
      );

      final collected = <DecisionToolExecutionUpdate>[];
      final done = Completer<void>();
      executor
          .executeDecisionToolCalls(
            turn: turn,
            decision: const ModelTurnDecision(
              toolCalls: [
                ModelToolCall(
                  toolName: 'Read',
                  arguments: {'file_path': 'read-a.txt'},
                  sequence: 1,
                ),
                ModelToolCall(
                  toolName: 'Read',
                  arguments: {'file_path': 'read-b.txt'},
                  sequence: 2,
                ),
                ModelToolCall(
                  toolName: 'Write',
                  arguments: {'file_path': 'write-c.txt', 'content': 'x'},
                  sequence: 3,
                ),
                ModelToolCall(
                  toolName: 'Read',
                  arguments: {'file_path': 'read-d.txt'},
                  sequence: 4,
                ),
                ModelToolCall(
                  toolName: 'Read',
                  arguments: {'file_path': 'read-e.txt'},
                  sequence: 5,
                ),
              ],
              assistantMessage: null,
              providerState: {'response_id': 'resp_mixed'},
              isTerminal: false,
            ),
            config: ChatConfig(systemPrompt: ''),
            consecutiveFailures: 0,
          )
          .listen(
        collected.add,
        onError: done.completeError,
        onDone: done.complete,
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(toolCallService.startedKeys, ['read-a.txt', 'read-b.txt']);

      toolCallService.completePending('read-a.txt');
      toolCallService.completePending('read-b.txt');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(toolCallService.startedKeys,
          ['read-a.txt', 'read-b.txt', 'write-c.txt']);

      toolCallService.completePending('write-c.txt');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(toolCallService.startedKeys, [
        'read-a.txt',
        'read-b.txt',
        'write-c.txt',
        'read-d.txt',
        'read-e.txt',
      ]);

      toolCallService.completePending('read-d.txt');
      toolCallService.completePending('read-e.txt');
      await done.future;

      final summary = collected.last.summary!;
      expect(summary.executedToolCount, 5);
      expect(summary.shouldStopFurtherExecution, isFalse);
      final steps = await stepRepository.listSteps(turnId);
      expect(
        steps.every((step) => step.status == ChatTurnStepStatus.completed),
        isTrue,
      );
    });

    test('skips later batches after a concurrent batch finishes with failure',
        () async {
      final turnRepository = _InMemoryChatTurnRepository();
      final stepRepository = _InMemoryChatTurnStepRepository();
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          id: 4,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '失败后停止后续批次',
        ),
      );
      final turn = (await turnRepository.getTurn(turnId))!;
      final toolCallService = _TrackingToolCallService(
        definitionsByName: {
          'Read': const ToolDefinition(
            name: 'Read',
            title: '读取文件',
            isConcurrencySafe: true,
          ),
          'Write': const ToolDefinition(
            name: 'Write',
            title: '写入文件',
            isConcurrencySafe: false,
          ),
        },
        handlersByKey: {
          'ok.txt': () => _delayedSuccess('Read', 'ok.txt',
              delay: const Duration(milliseconds: 20)),
          'bad.txt': () => _delayedFailure('Read', 'bad.txt',
              delay: const Duration(milliseconds: 5)),
          'write-later.txt': () => _delayedSuccess('Write', 'write-later.txt'),
        },
      );
      final executor = DefaultDecisionToolCallExecutor(
        turnRepository: turnRepository,
        stepRepository: stepRepository,
        eventRepository: _InMemoryChatEventRepository(),
        toolCallService: toolCallService,
        limits: const AgentLoopLimits(),
        maxConcurrentExecutions: 2,
      );

      final updates = await executor
          .executeDecisionToolCalls(
            turn: turn,
            decision: const ModelTurnDecision(
              toolCalls: [
                ModelToolCall(
                  toolName: 'Read',
                  arguments: {'file_path': 'ok.txt'},
                  sequence: 1,
                ),
                ModelToolCall(
                  toolName: 'Read',
                  arguments: {'file_path': 'bad.txt'},
                  sequence: 2,
                ),
                ModelToolCall(
                  toolName: 'Write',
                  arguments: {'file_path': 'write-later.txt', 'content': 'x'},
                  sequence: 3,
                ),
              ],
              assistantMessage: null,
              providerState: {'response_id': 'resp_stop'},
              isTerminal: false,
            ),
            config: ChatConfig(systemPrompt: ''),
            consecutiveFailures: 0,
          )
          .toList();

      final summary = updates.last.summary!;
      expect(toolCallService.executedKeys, ['ok.txt', 'bad.txt']);
      expect(summary.executedToolCount, 2);
      expect(summary.hasFailedStep, isTrue);
      expect(summary.shouldStopFurtherExecution, isTrue);
      final steps = await stepRepository.listSteps(turnId);
      expect(steps, hasLength(2));
    });
  });
}

List<ModelToolCall> _readCalls(List<String> filePaths) {
  return [
    for (var index = 0; index < filePaths.length; index += 1)
      ModelToolCall(
        toolName: 'Read',
        arguments: {'file_path': filePaths[index]},
        sequence: index + 1,
      ),
  ];
}

Future<ToolPreparationResult> _delayedSuccess(
  String toolName,
  String key, {
  Duration delay = const Duration(milliseconds: 25),
}) async {
  await Future<void>.delayed(delay);
  return ToolPreparationResult(
    toolInvocation: ToolInvocation(
      toolName: toolName,
      arguments: {'file_path': key},
      status: ToolInvocationStatus.running,
      summary: '正在执行工具：$toolName',
      requiresConfirmation: false,
    ),
    toolResult: ToolResult(
      toolName: toolName,
      status: ToolExecutionStatus.success,
      summary: '$key ok',
      data: {'filePath': key},
    ),
    additionalContextMessages: const [],
  );
}

Future<ToolPreparationResult> _delayedFailure(
  String toolName,
  String key, {
  Duration delay = const Duration(milliseconds: 25),
}) async {
  await Future<void>.delayed(delay);
  return ToolPreparationResult(
    toolInvocation: ToolInvocation(
      toolName: toolName,
      arguments: {'file_path': key},
      status: ToolInvocationStatus.running,
      summary: '正在执行工具：$toolName',
      requiresConfirmation: false,
    ),
    toolResult: ToolResult(
      toolName: toolName,
      status: ToolExecutionStatus.failure,
      summary: '$key failed',
      errorMessage: 'failed_$key',
      data: {'filePath': key},
    ),
    additionalContextMessages: const [],
  );
}

class _TrackingToolCallService extends ToolCallService {
  final Map<String, ToolDefinition> definitionsByName;
  final Map<String, Future<ToolPreparationResult> Function()> handlersByKey;
  final Map<String, Completer<ToolPreparationResult>> _pendingCompleters = {};
  final List<String> startedKeys = [];
  final List<String> executedKeys = [];
  int activeInvocations = 0;
  int maxActiveInvocations = 0;

  _TrackingToolCallService({
    required this.definitionsByName,
    Map<String, Future<ToolPreparationResult> Function()>? handlersByKey,
  })  : handlersByKey = handlersByKey ?? {},
        super(
          toolExecutor: ToolExecutor(chatStorage: _NoopChatStorage()),
        );

  @override
  ToolDefinition? findDefinition(String toolName) {
    return definitionsByName[toolName] ?? super.findDefinition(toolName);
  }

  @override
  Future<ToolPreparationResult> executeToolInvocation({
    required int groupId,
    required ToolInvocation invocation,
    bool trustTool = false,
    String? turnId,
    ToolExecutionStartedCallback? onExecutionStarted,
  }) async {
    final key =
        (invocation.arguments['file_path'] ?? invocation.arguments['url'])
            .toString();
    startedKeys.add(key);
    executedKeys.add(key);
    activeInvocations += 1;
    if (activeInvocations > maxActiveInvocations) {
      maxActiveInvocations = activeInvocations;
    }
    try {
      final handler = handlersByKey[key];
      if (handler == null) {
        throw StateError('Missing test handler for $key');
      }
      if (onExecutionStarted != null) {
        await onExecutionStarted(
          invocation: invocation,
          toolAccess: ToolAccessSnapshot(
            definition: definitionsByName[invocation.toolName] ??
                ToolDefinition(
                  name: invocation.toolName,
                  title: invocation.toolName,
                ),
            executionDecision: ToolPolicyDecision.autoRun,
            executionPolicyLabel: 'auto_run',
            isVisibleToPlanner: true,
          ),
        );
      }
      final result = await handler();
      return ToolPreparationResult(
        toolInvocation: result.toolInvocation,
        toolAccess: result.toolAccess,
        toolResult: result.toolResult,
        additionalContextMessages: result.additionalContextMessages,
        executionStarted: onExecutionStarted != null,
      );
    } finally {
      activeInvocations -= 1;
    }
  }

  Future<ToolPreparationResult> pending(String key) {
    final completer = Completer<ToolPreparationResult>();
    _pendingCompleters[key] = completer;
    return completer.future;
  }

  void completePending(String key) {
    final completer = _pendingCompleters.remove(key);
    if (completer == null || completer.isCompleted) {
      return;
    }
    completer.complete(
      ToolPreparationResult(
        toolInvocation: ToolInvocation(
          toolName: key.startsWith('write') ? 'Write' : 'Read',
          arguments: {'file_path': key},
          status: ToolInvocationStatus.running,
          summary: '正在执行工具：$key',
          requiresConfirmation: false,
        ),
        toolResult: ToolResult(
          toolName: key.startsWith('write') ? 'Write' : 'Read',
          status: ToolExecutionStatus.success,
          summary: '$key done',
          data: {'filePath': key},
        ),
        additionalContextMessages: const [],
      ),
    );
  }
}

class _InMemoryChatTurnRepository extends ChatTurnRepository {
  final Map<int, ChatTurn> turns = {};

  _InMemoryChatTurnRepository() : super(_NoopChatStorage());

  @override
  Future<int> createTurn(ChatTurn turn) async {
    final id = turn.id ?? turns.length + 1;
    turns[id] = turn.copyWith(id: id);
    return id;
  }

  @override
  Future<ChatTurn?> getTurn(int id) async => turns[id];

  @override
  Future<void> markAwaitingToolConfirmation(int turnId) async {
    final turn = turns[turnId]!;
    turns[turnId] = turn.copyWith(status: ChatTurnStatus.awaitingToolConfirmation);
  }

  @override
  Future<void> markAwaitingUserInteraction(int turnId) async {
    final turn = turns[turnId]!;
    turns[turnId] = turn.copyWith(status: ChatTurnStatus.awaitingUserInteraction);
  }

  @override
  Future<void> markRunning(int turnId) async {
    final turn = turns[turnId]!;
    turns[turnId] = turn.copyWith(status: ChatTurnStatus.running);
  }

  @override
  Future<void> incrementIterationAndToolCount(int turnId) async {
    final turn = turns[turnId]!;
    turns[turnId] = turn.copyWith(
      iterationCount: turn.iterationCount + 1,
      toolCallCount: turn.toolCallCount + 1,
    );
  }

  @override
  Future<void> incrementToolCallCount(int turnId, {int by = 1}) async {
    final turn = turns[turnId]!;
    turns[turnId] = turn.copyWith(toolCallCount: turn.toolCallCount + by);
  }

  @override
  Future<void> markCompleted(
    int turnId, {
    String? stopReason,
    String? finalResponseText,
  }) async {
    final turn = turns[turnId]!;
    turns[turnId] = turn.copyWith(
      status: ChatTurnStatus.completed,
      stopReason: stopReason,
      finalResponseText: finalResponseText,
      completedAt: DateTime.now(),
    );
  }

  @override
  Future<void> markFailed(int turnId, {String? errorMessage}) async {
    final turn = turns[turnId]!;
    turns[turnId] = turn.copyWith(
      status: ChatTurnStatus.failed,
      errorMessage: errorMessage,
    );
  }

  @override
  Future<void> incrementIteration(int turnId) async {
    final turn = turns[turnId]!;
    turns[turnId] = turn.copyWith(iterationCount: turn.iterationCount + 1);
  }

  @override
  Future<void> updateRuntimeState(
    int turnId, {
    ChatTurnProviderStyle? providerStyle,
    String? modelName,
    Map<String, dynamic>? providerStateJson,
  }) async {
    final turn = turns[turnId]!;
    turns[turnId] = turn.copyWith(
      providerStyle: providerStyle ?? turn.providerStyle,
      modelName: modelName ?? turn.modelName,
      providerStateJson: providerStateJson ?? turn.providerStateJson,
    );
  }
}

class _InMemoryChatTurnStepRepository extends ChatTurnStepRepository {
  final Map<int, ChatTurnStep> steps = {};

  _InMemoryChatTurnStepRepository() : super(_NoopChatStorage());

  @override
  Future<int> createStep(ChatTurnStep step) async {
    final id = step.id ?? steps.length + 1;
    steps[id] = step.copyWith(id: id);
    return id;
  }

  @override
  Future<List<ChatTurnStep>> listSteps(int turnId) async {
    final result = steps.values.where((step) => step.turnId == turnId).toList();
    result.sort((left, right) => left.stepIndex.compareTo(right.stepIndex));
    return result;
  }

  @override
  Future<ChatTurnStep?> getStep(int id) async => steps[id];

  @override
  Future<void> markRunning(int stepId) async {
    final step = steps[stepId]!;
    steps[stepId] = step.copyWith(status: ChatTurnStepStatus.running);
  }

  @override
  Future<void> markCompleted(
    int stepId, {
    required String resultSummary,
    Map<String, dynamic>? resultJson,
  }) async {
    final step = steps[stepId]!;
    steps[stepId] = step.copyWith(
      status: ChatTurnStepStatus.completed,
      resultSummary: resultSummary,
      resultJson: resultJson ?? step.resultJson,
      completedAt: DateTime.now(),
    );
  }

  @override
  Future<void> markFailed(
    int stepId, {
    required String errorCode,
    String? resultSummary,
    Map<String, dynamic>? resultJson,
  }) async {
    final step = steps[stepId]!;
    steps[stepId] = step.copyWith(
      status: ChatTurnStepStatus.failed,
      errorCode: errorCode,
      resultSummary: resultSummary ?? step.resultSummary,
      resultJson: resultJson ?? step.resultJson,
      completedAt: DateTime.now(),
    );
  }
}

class _InMemoryChatEventRepository extends ChatEventRepository {
  final List<ChatEvent> events = [];

  _InMemoryChatEventRepository() : super(_NoopChatStorage());

  @override
  Future<ChatEvent> appendUserMessage({
    required int turnId,
    required int groupId,
    required String content,
  }) async {
    return _append(turnId, groupId, ChatEventType.userMessage, content);
  }

  @override
  Future<ChatEvent> appendToolResult({
    required int turnId,
    required int groupId,
    required String content,
    Map<String, dynamic>? payloadJson,
  }) async {
    return _append(
      turnId,
      groupId,
      ChatEventType.toolResult,
      content,
      payloadJson: payloadJson,
    );
  }

  @override
  Future<ChatEvent> appendToolCall({
    required int turnId,
    required int groupId,
    required String toolName,
    required Map<String, dynamic> arguments,
    required String summary,
    Map<String, dynamic>? payloadJson,
  }) async {
    return _append(
      turnId,
      groupId,
      ChatEventType.assistantToolCall,
      summary,
      payloadJson: payloadJson,
    );
  }

  @override
  Future<ChatEvent> appendToolConfirmation({
    required int turnId,
    required int groupId,
    required String toolName,
    required Map<String, dynamic> arguments,
    required String summary,
    Map<String, dynamic>? payloadJson,
  }) async {
    return _append(
      turnId,
      groupId,
      ChatEventType.assistantToolConfirmation,
      summary,
      payloadJson: payloadJson,
    );
  }

  @override
  Future<ChatEvent> appendToolExecutionStarted({
    required int turnId,
    required int groupId,
    required String content,
    Map<String, dynamic>? payloadJson,
  }) async {
    return _append(
      turnId,
      groupId,
      ChatEventType.toolExecutionStarted,
      content,
      payloadJson: payloadJson,
    );
  }

  @override
  Future<ChatEvent> appendAssistantQuestionPrompt({
    required int turnId,
    required int groupId,
    required AskUserQuestionRequest request,
    required String content,
    Map<String, dynamic>? payloadJson,
  }) async {
    return _append(
      turnId,
      groupId,
      ChatEventType.assistantQuestionPrompt,
      content,
      payloadJson: payloadJson ?? request.toJson(),
    );
  }

  @override
  Future<ChatEvent> appendUserInteractionResult({
    required int turnId,
    required int groupId,
    required AskUserQuestionResponse response,
    required String content,
    Map<String, dynamic>? payloadJson,
  }) async {
    return _append(
      turnId,
      groupId,
      ChatEventType.userInteractionResult,
      content,
      payloadJson: payloadJson ?? response.toJson(),
    );
  }

  @override
  Future<ChatEvent> appendToolError({
    required int turnId,
    required int groupId,
    required String content,
    String? errorCode,
    Map<String, dynamic>? payloadJson,
  }) async {
    return _append(
      turnId,
      groupId,
      ChatEventType.toolError,
      content,
      payloadJson: payloadJson,
      status: errorCode,
    );
  }

  @override
  Future<ChatEvent> appendAssistantTextDelta({
    required int turnId,
    required int groupId,
    required String content,
  }) async {
    return _append(turnId, groupId, ChatEventType.assistantTextDelta, content);
  }

  @override
  Future<ChatEvent> appendAssistantPlannerMessage({
    required int turnId,
    required int groupId,
    required String content,
    Map<String, dynamic>? payloadJson,
  }) async {
    return _append(
      turnId,
      groupId,
      ChatEventType.assistantPlannerMessage,
      content,
      payloadJson: payloadJson,
    );
  }

  @override
  Future<ChatEvent> appendAssistantTextFinal({
    required int turnId,
    required int groupId,
    required String content,
  }) async {
    return _append(turnId, groupId, ChatEventType.assistantTextFinal, content);
  }

  @override
  Future<ChatEvent> appendFinalAnswer({
    required int turnId,
    required int groupId,
    required String content,
  }) async {
    return _append(turnId, groupId, ChatEventType.finalAnswer, content);
  }

  @override
  Future<ChatEvent> appendTurnStatus({
    required int turnId,
    required int groupId,
    required String content,
  }) async {
    return _append(turnId, groupId, ChatEventType.turnStatus, content);
  }

  @override
  Future<List<ChatEvent>> listEventsByTurn(int turnId) async {
    return events.where((event) => event.turnId == turnId).toList();
  }

  Future<ChatEvent> _append(
    int turnId,
    int groupId,
    ChatEventType eventType,
    String? content, {
    Map<String, dynamic>? payloadJson,
    String? status,
  }) async {
    final event = ChatEvent(
      id: events.length + 1,
      turnId: turnId,
      groupId: groupId,
      sequence: events.where((event) => event.turnId == turnId).length + 1,
      eventType: eventType,
      role: MessageRole.system,
      content: content,
      payloadJson: payloadJson,
      status: status,
    );
    events.add(event);
    return event;
  }
}

class _NoopChatStorage implements ChatStorage {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
