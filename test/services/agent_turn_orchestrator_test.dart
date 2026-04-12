import 'dart:async';
import 'dart:collection';

import 'package:ai_chat/models/agent/agent_action.dart';
import 'package:ai_chat/models/agent/agent_loop_limits.dart';
import 'package:ai_chat/models/agent/stop_verification_result.dart';
import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/llm/base_llm.dart';
import 'package:ai_chat/models/tool/tool_call.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/repositories/chat_event_repository.dart';
import 'package:ai_chat/repositories/chat_turn_repository.dart';
import 'package:ai_chat/services/agent_planner_service.dart';
import 'package:ai_chat/services/agent_turn_orchestrator.dart';
import 'package:ai_chat/services/chat_service.dart';
import 'package:ai_chat/services/stop_verifier_service.dart';
import 'package:ai_chat/services/tool_call_service.dart';
import 'package:ai_chat/services/tool_executor.dart';
import 'package:ai_chat/services/transcript_builder_service.dart';
import 'package:ai_chat/storage/chat_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentTurnOrchestrator', () {
    test('runs tool call, records tool result, then streams final answer', () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final turnId = await turnRepository.createTurn(
        ChatTurn(
          id: 1,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '帮我查数据库版本',
        ),
      );
      final turn = (await turnRepository.getTurn(turnId))!;

      final orchestrator = AgentTurnOrchestrator(
        plannerService: _FakePlannerService([
          const AgentAction.callTool(
            ToolCall(
              toolName: 'search_chat_history',
              arguments: {'query': '数据库'},
            ),
          ),
          const AgentAction.respond('根据工具结果生成最终回答'),
        ]),
        turnRepository: turnRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        stopVerifierService: _AlwaysStopVerifier(),
        chatService: _FakeChatService(
          chunks: const ['最终', '回答'],
        ),
        toolCallService: _FakeToolCallService(
          executeResult: ToolPreparationResult(
            toolInvocation: const ToolInvocation(
              toolName: 'search_chat_history',
              arguments: {'query': '数据库'},
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：搜索历史',
              requiresConfirmation: false,
            ),
            toolResult: const ToolResult(
              toolName: 'search_chat_history',
              status: ToolExecutionStatus.success,
              summary: '已找到数据库版本是 7',
            ),
            additionalContextMessages: [
              ChatMessage(
                text: '已找到数据库版本是 7',
                role: MessageRole.system,
                status: MessageStatus.completed,
              ),
            ],
          ),
        ),
        limits: const AgentLoopLimits(maxIterations: 4),
      );

      final emitted = await orchestrator.runTurn(
        turn: turn,
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
      ).toList();

      expect(
        emitted.map((event) => event.eventType),
        containsAllInOrder([
          ChatEventType.userMessage,
          ChatEventType.assistantToolCall,
          ChatEventType.toolExecutionStarted,
          ChatEventType.toolResult,
          ChatEventType.assistantTextDelta,
          ChatEventType.assistantTextDelta,
          ChatEventType.assistantTextFinal,
          ChatEventType.finalAnswer,
        ]),
      );
      expect((await turnRepository.getTurn(turnId))!.status, ChatTurnStatus.completed);
    });

    test('pauses turn when tool requires confirmation', () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final turn = ChatTurn(
        id: 2,
        groupId: 1,
        status: ChatTurnStatus.running,
        userInput: '提醒我明晚交周报',
      );
      await turnRepository.createTurn(turn);

      final orchestrator = AgentTurnOrchestrator(
        plannerService: _FakePlannerService([
          const AgentAction.callTool(
            ToolCall(
              toolName: 'create_reminder',
              arguments: {'title': '交周报'},
            ),
          ),
        ]),
        turnRepository: turnRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        stopVerifierService: _AlwaysStopVerifier(),
        chatService: _FakeChatService(chunks: const []),
        toolCallService: _FakeToolCallService(
          executeResult: ToolPreparationResult(
            toolInvocation: const ToolInvocation(
              toolName: 'create_reminder',
              arguments: {'title': '交周报'},
              status: ToolInvocationStatus.awaitingConfirmation,
              summary: '准备执行工具：创建提醒',
              requiresConfirmation: true,
            ),
            toolResult: null,
            additionalContextMessages: const [],
          ),
        ),
        limits: const AgentLoopLimits(maxIterations: 4),
      );

      final emitted = await orchestrator.runTurn(
        turn: turn,
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
      ).toList();

      expect(emitted.map((event) => event.eventType), contains(ChatEventType.assistantToolConfirmation));
      expect((await turnRepository.getTurn(2))!.status, ChatTurnStatus.awaitingToolConfirmation);
    });

    test('fails turn when tool execution keeps failing beyond limit', () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final turn = ChatTurn(
        id: 3,
        groupId: 1,
        status: ChatTurnStatus.running,
        userInput: '连续调用失败',
      );
      await turnRepository.createTurn(turn);

      final orchestrator = AgentTurnOrchestrator(
        plannerService: _FakePlannerService([
          const AgentAction.callTool(
            ToolCall(
              toolName: 'search_chat_history',
              arguments: {'query': '数据库'},
            ),
          ),
          const AgentAction.callTool(
            ToolCall(
              toolName: 'search_chat_history',
              arguments: {'query': '数据库'},
            ),
          ),
        ]),
        turnRepository: turnRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        stopVerifierService: _AlwaysStopVerifier(),
        chatService: _FakeChatService(chunks: const []),
        toolCallService: _FakeToolCallService(
          executeResult: ToolPreparationResult(
            toolInvocation: const ToolInvocation(
              toolName: 'search_chat_history',
              arguments: {'query': '数据库'},
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：搜索历史',
              requiresConfirmation: false,
            ),
            toolResult: const ToolResult(
              toolName: 'search_chat_history',
              status: ToolExecutionStatus.failure,
              summary: '搜索失败',
              errorMessage: 'search_failed',
            ),
            additionalContextMessages: const [],
          ),
        ),
        limits: const AgentLoopLimits(maxIterations: 4, maxConsecutiveFailures: 1),
      );

      final emitted = await orchestrator.runTurn(
        turn: turn,
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
      ).toList();

      expect(emitted.map((event) => event.eventType), contains(ChatEventType.toolError));
      expect((await turnRepository.getTurn(3))!.status, ChatTurnStatus.failed);
    });

    test('resumes awaiting confirmation turn, executes tool, then streams final answer',
        () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final turn = ChatTurn(
        id: 4,
        groupId: 1,
        status: ChatTurnStatus.awaitingToolConfirmation,
        userInput: '提醒我明晚交周报',
      );
      await turnRepository.createTurn(turn);
      await eventRepository.appendToolConfirmation(
        turnId: 4,
        groupId: 1,
        toolName: 'create_reminder',
        arguments: const {'title': '交周报'},
        summary: '准备执行工具：创建提醒',
      );

      final orchestrator = AgentTurnOrchestrator(
        plannerService: _FakePlannerService([
          const AgentAction.respond('工具执行后给出最终回答'),
        ]),
        turnRepository: turnRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        stopVerifierService: _AlwaysStopVerifier(),
        chatService: _FakeChatService(
          chunks: const ['提醒', '已创建'],
        ),
        toolCallService: _FakeToolCallService(
          executeResult: ToolPreparationResult(
            toolInvocation: const ToolInvocation(
              toolName: 'create_reminder',
              arguments: {'title': '交周报'},
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：创建提醒',
              requiresConfirmation: false,
            ),
            toolResult: const ToolResult(
              toolName: 'create_reminder',
              status: ToolExecutionStatus.success,
              summary: '已创建提醒：交周报',
            ),
            additionalContextMessages: const [],
          ),
        ),
        limits: const AgentLoopLimits(maxIterations: 4),
      );

      final emitted = await orchestrator
          .resumeAfterConfirmation(
            turnId: 4,
            invocation: const ToolInvocation(
              toolName: 'create_reminder',
              arguments: {'title': '交周报'},
              status: ToolInvocationStatus.awaitingConfirmation,
              summary: '准备执行工具：创建提醒',
              requiresConfirmation: true,
            ),
            config: ChatConfig(useReasoning: false, systemPrompt: ''),
            trustTool: true,
          )
          .toList();

      expect(
        emitted.map((event) => event.eventType),
        containsAllInOrder([
          ChatEventType.toolExecutionStarted,
          ChatEventType.toolResult,
          ChatEventType.assistantTextDelta,
          ChatEventType.assistantTextDelta,
          ChatEventType.assistantTextFinal,
          ChatEventType.finalAnswer,
        ]),
      );
      expect((await turnRepository.getTurn(4))!.status, ChatTurnStatus.completed);
    });

    test('stops turn with max_iterations_reached when stop verifier keeps rejecting',
        () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final turn = ChatTurn(
        id: 5,
        groupId: 1,
        status: ChatTurnStatus.running,
        userInput: '继续完善这个回答直到确认完成',
      );
      await turnRepository.createTurn(turn);

      final orchestrator = AgentTurnOrchestrator(
        plannerService: _FakePlannerService([
          const AgentAction.respond('第一次回答'),
          const AgentAction.respond('第二次回答'),
        ]),
        turnRepository: turnRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        stopVerifierService: _NeverStopVerifier(),
        chatService: _FakeChatService(
          chunks: const ['未完成'],
        ),
        toolCallService: _FakeToolCallService(
          executeResult: const ToolPreparationResult.noTool(),
        ),
        limits: const AgentLoopLimits(maxIterations: 1),
      );

      final emitted = await orchestrator.runTurn(
        turn: turn,
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
      ).toList();

      expect(
        emitted.map((event) => event.eventType),
        containsAllInOrder([
          ChatEventType.userMessage,
          ChatEventType.assistantTextDelta,
          ChatEventType.assistantTextFinal,
          ChatEventType.turnStatus,
        ]),
      );
      expect(
        emitted.last,
        isA<ChatEvent>()
            .having((event) => event.eventType, 'eventType', ChatEventType.turnStatus)
            .having((event) => event.content, 'content', 'max_iterations_reached'),
      );
      expect((await turnRepository.getTurn(5))!.status, ChatTurnStatus.failed);
      expect((await turnRepository.getTurn(5))!.errorMessage, 'max_iterations_reached');
    });

    test('pauses on a later tool after an earlier tool already succeeded', () async {
      final eventRepository = _InMemoryChatEventRepository();
      final turnRepository = _InMemoryChatTurnRepository();
      final turn = ChatTurn(
        id: 6,
        groupId: 1,
        status: ChatTurnStatus.running,
        userInput: '先搜数据库版本，再帮我创建提醒',
      );
      await turnRepository.createTurn(turn);

      final orchestrator = AgentTurnOrchestrator(
        plannerService: _FakePlannerService([
          const AgentAction.callTool(
            ToolCall(
              toolName: 'search_chat_history',
              arguments: {'query': '数据库版本'},
            ),
          ),
          const AgentAction.callTool(
            ToolCall(
              toolName: 'create_reminder',
              arguments: {'title': '同步 schema 变更'},
            ),
          ),
        ]),
        turnRepository: turnRepository,
        eventRepository: eventRepository,
        transcriptBuilderService: TranscriptBuilderService(
          eventRepository: eventRepository,
        ),
        stopVerifierService: _AlwaysStopVerifier(),
        chatService: _FakeChatService(chunks: const []),
        toolCallService: _SequencedToolCallService([
          ToolPreparationResult(
            toolInvocation: const ToolInvocation(
              toolName: 'search_chat_history',
              arguments: {'query': '数据库版本'},
              status: ToolInvocationStatus.running,
              summary: '正在执行工具：搜索历史',
              requiresConfirmation: false,
            ),
            toolResult: const ToolResult(
              toolName: 'search_chat_history',
              status: ToolExecutionStatus.success,
              summary: '数据库版本是 7',
            ),
            additionalContextMessages: [
              ChatMessage(
                text: '数据库版本是 7',
                role: MessageRole.system,
                status: MessageStatus.completed,
              ),
            ],
          ),
          ToolPreparationResult(
            toolInvocation: const ToolInvocation(
              toolName: 'create_reminder',
              arguments: {'title': '同步 schema 变更'},
              status: ToolInvocationStatus.awaitingConfirmation,
              summary: '准备执行工具：创建提醒',
              requiresConfirmation: true,
            ),
            toolResult: null,
            additionalContextMessages: const [],
          ),
        ]),
        limits: const AgentLoopLimits(maxIterations: 4),
      );

      final emitted = await orchestrator.runTurn(
        turn: turn,
        config: ChatConfig(useReasoning: false, systemPrompt: ''),
      ).toList();

      expect(
        emitted.map((event) => event.eventType),
        containsAllInOrder([
          ChatEventType.userMessage,
          ChatEventType.assistantToolCall,
          ChatEventType.toolExecutionStarted,
          ChatEventType.toolResult,
          ChatEventType.assistantToolCall,
          ChatEventType.assistantToolConfirmation,
        ]),
      );
      expect((await turnRepository.getTurn(6))!.status, ChatTurnStatus.awaitingToolConfirmation);
      expect((await turnRepository.getTurn(6))!.toolCallCount, 1);
    });
  });
}

class _FakePlannerService extends AgentPlannerService {
  final Queue<AgentAction> actions;

  _FakePlannerService(List<AgentAction> actions)
      : actions = Queue<AgentAction>.from(actions),
        super(llm: _NoopBaseLLM());

  @override
  Future<AgentAction> planNextAction({
    required ChatTurn turn,
    required List<ChatEvent> transcript,
    required ChatConfig config,
    required AgentLoopLimits limits,
  }) async {
    return actions.removeFirst();
  }
}

class _AlwaysStopVerifier extends StopVerifierService {
  @override
  Future<StopVerificationResult> verifyCanStop({
    required ChatTurn turn,
    required List<ChatEvent> transcript,
    required String latestAssistantText,
    required AgentLoopLimits limits,
  }) async {
    return const StopVerificationResult(canStop: true, reason: 'done');
  }
}

class _NeverStopVerifier extends StopVerifierService {
  @override
  Future<StopVerificationResult> verifyCanStop({
    required ChatTurn turn,
    required List<ChatEvent> transcript,
    required String latestAssistantText,
    required AgentLoopLimits limits,
  }) async {
    return const StopVerificationResult(
      canStop: false,
      reason: 'needs_more_work',
    );
  }
}

class _FakeChatService extends ChatService {
  final List<String> chunks;

  _FakeChatService({required this.chunks}) : super(llm: _NoopBaseLLM());

  @override
  Stream<String> streamFinalAnswer({
    required List<ChatMessage> messages,
    required ChatConfig config,
  }) async* {
    for (final chunk in chunks) {
      yield chunk;
    }
  }
}

class _FakeToolCallService extends ToolCallService {
  final ToolPreparationResult executeResult;

  _FakeToolCallService({required this.executeResult})
      : super(
          toolExecutor: ToolExecutor(chatStorage: _NoopChatStorage()),
        );

  @override
  Future<ToolPreparationResult> executeToolInvocation({
    required int groupId,
    required ToolInvocation invocation,
    bool trustTool = false,
    String? turnId,
  }) async {
    return executeResult;
  }
}

class _SequencedToolCallService extends ToolCallService {
  final Queue<ToolPreparationResult> executeResults;

  _SequencedToolCallService(List<ToolPreparationResult> executeResults)
      : executeResults = Queue<ToolPreparationResult>.from(executeResults),
        super(
          toolExecutor: ToolExecutor(chatStorage: _NoopChatStorage()),
        );

  @override
  Future<ToolPreparationResult> executeToolInvocation({
    required int groupId,
    required ToolInvocation invocation,
    bool trustTool = false,
    String? turnId,
  }) async {
    return executeResults.removeFirst();
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
    turns[turnId] = turn.copyWith(
      status: ChatTurnStatus.awaitingToolConfirmation,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> incrementIterationAndToolCount(int turnId) async {
    final turn = turns[turnId]!;
    turns[turnId] = turn.copyWith(
      iterationCount: turn.iterationCount + 1,
      toolCallCount: turn.toolCallCount + 1,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> markCompleted(int turnId, {String? stopReason}) async {
    final turn = turns[turnId]!;
    turns[turnId] = turn.copyWith(
      status: ChatTurnStatus.completed,
      stopReason: stopReason,
      completedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> markFailed(int turnId, {String? errorMessage}) async {
    final turn = turns[turnId]!;
    turns[turnId] = turn.copyWith(
      status: ChatTurnStatus.failed,
      errorMessage: errorMessage,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> incrementIteration(int turnId) async {
    final turn = turns[turnId]!;
    turns[turnId] = turn.copyWith(
      iterationCount: turn.iterationCount + 1,
      updatedAt: DateTime.now(),
    );
  }
}

class _InMemoryChatEventRepository extends ChatEventRepository {
  final List<ChatEvent> events = [];

  _InMemoryChatEventRepository() : super(_NoopChatStorage());

  @override
  Future<int> appendUserMessage({
    required int turnId,
    required int groupId,
    required String content,
  }) async {
    return _append(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.userMessage,
      role: MessageRole.user,
      content: content,
    );
  }

  @override
  Future<int> appendToolResult({
    required int turnId,
    required int groupId,
    required String content,
    Map<String, dynamic>? payloadJson,
  }) async {
    return _append(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.toolResult,
      role: MessageRole.system,
      content: content,
      payloadJson: payloadJson,
    );
  }

  @override
  Future<int> appendToolCall({
    required int turnId,
    required int groupId,
    required String toolName,
    required Map<String, dynamic> arguments,
    required String summary,
  }) async {
    return _append(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.assistantToolCall,
      role: MessageRole.assistant,
      content: summary,
      payloadJson: {
        'toolName': toolName,
        'arguments': arguments,
      },
    );
  }

  @override
  Future<int> appendToolConfirmation({
    required int turnId,
    required int groupId,
    required String toolName,
    required Map<String, dynamic> arguments,
    required String summary,
  }) async {
    return _append(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.assistantToolConfirmation,
      role: MessageRole.assistant,
      content: summary,
      payloadJson: {
        'toolName': toolName,
        'arguments': arguments,
      },
    );
  }

  @override
  Future<int> appendToolExecutionStarted({
    required int turnId,
    required int groupId,
    required String content,
  }) async {
    return _append(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.toolExecutionStarted,
      role: MessageRole.system,
      content: content,
    );
  }

  @override
  Future<int> appendToolError({
    required int turnId,
    required int groupId,
    required String content,
    String? errorCode,
  }) async {
    return _append(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.toolError,
      role: MessageRole.system,
      content: content,
      status: errorCode,
    );
  }

  @override
  Future<int> appendAssistantTextDelta({
    required int turnId,
    required int groupId,
    required String content,
  }) async {
    return _append(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.assistantTextDelta,
      role: MessageRole.assistant,
      content: content,
    );
  }

  @override
  Future<int> appendAssistantTextFinal({
    required int turnId,
    required int groupId,
    required String content,
  }) async {
    return _append(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.assistantTextFinal,
      role: MessageRole.assistant,
      content: content,
    );
  }

  @override
  Future<int> appendFinalAnswer({
    required int turnId,
    required int groupId,
    required String content,
  }) async {
    return _append(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.finalAnswer,
      role: MessageRole.assistant,
      content: content,
    );
  }

  @override
  Future<int> appendTurnStatus({
    required int turnId,
    required int groupId,
    required String content,
  }) async {
    return _append(
      turnId: turnId,
      groupId: groupId,
      eventType: ChatEventType.turnStatus,
      role: MessageRole.system,
      content: content,
    );
  }

  @override
  Future<List<ChatEvent>> listEventsByTurn(int turnId) async {
    return events.where((event) => event.turnId == turnId).toList();
  }

  Future<int> appendEvent(ChatEvent event) async {
    events.add(event);
    return events.length;
  }

  Future<int> _append({
    required int turnId,
    required int groupId,
    required ChatEventType eventType,
    MessageRole? role,
    String? content,
    Map<String, dynamic>? payloadJson,
    String? status,
  }) async {
    final event = ChatEvent(
      turnId: turnId,
      groupId: groupId,
      sequence: events.where((item) => item.turnId == turnId).length + 1,
      eventType: eventType,
      role: role,
      content: content,
      payloadJson: payloadJson,
      status: status,
    );
    events.add(event);
    return events.length;
  }
}

class _NoopBaseLLM implements BaseLLM {
  @override
  Map<String, dynamic> get config => const {};

  @override
  Stream<String> chatStream(List<ChatMessage> messages, ChatConfig config) async* {}

  @override
  String getModelName(ChatConfig config) => 'noop';

  @override
  Future<String> planNextAction({
    required List<ChatMessage> messages,
    required ChatConfig config,
  }) async => '{"action":"respond","response":"noop"}';

  @override
  Future<String> structureSummaryCard(String sourceText) async => '{}';

  @override
  Future<String> summarizeConversation(List<ChatMessage> messages) async => '';

  @override
  Future<bool> validateApiKey(ChatConfig config) async => true;
}

class _NoopChatStorage implements ChatStorage {
  @override
  Future<void> deleteGroup(int groupId) => throw UnimplementedError();

  @override
  Future<void> deleteGroupMessages(int groupId) => throw UnimplementedError();

  @override
  Future<void> deleteMessage(int id) => throw UnimplementedError();

  @override
  Future<List<ChatEvent>> getEventsByTurn(int turnId) async => const [];

  @override
  Future<List<ChatGroup>> getAllGroups() => throw UnimplementedError();

  @override
  Future<int> getGroupMessageCount(int groupId) => throw UnimplementedError();

  @override
  Future<ChatGroup?> getLatestGroup() => throw UnimplementedError();

  @override
  Future<List<ChatMessage>> getMessagesByGroup(int groupId) async => const [];

  @override
  Future<List<ChatMessage>> getMessagesByGroupWithPagination({
    required int groupId,
    required int limit,
    required int offset,
  }) =>
      throw UnimplementedError();

  @override
  Future<ChatTurn?> getTurn(int id) async => null;

  @override
  Future<int> insertEvent(ChatEvent event) => throw UnimplementedError();

  @override
  Future<int> insertGroup(ChatGroup group) => throw UnimplementedError();

  @override
  Future<int> insertMessage(ChatMessage message, int groupId) =>
      throw UnimplementedError();

  @override
  Future<int> insertTurn(ChatTurn turn) => throw UnimplementedError();

  @override
  Future<bool> testDatabaseConnection() async => true;

  @override
  Future<void> updateGroupLastMessageTime(int groupId) =>
      throw UnimplementedError();

  @override
  Future<void> updateGroupSystemPrompt(int groupId, String? systemPrompt) =>
      throw UnimplementedError();

  @override
  Future<void> updateGroupTitle(int groupId, String title,
          {bool isSummarized = true}) =>
      throw UnimplementedError();

  @override
  Future<void> updateMessage(int id, String newText) =>
      throw UnimplementedError();

  @override
  Future<void> updateMessageReasoning(int id, String? reasoningContent) =>
      throw UnimplementedError();

  @override
  Future<void> updateMessageStatus(int id, MessageStatus status) =>
      throw UnimplementedError();

  @override
  Future<void> updateStructuredMessage(
    int id, {
    required String text,
    required MessageStatus status,
    required contentType,
    String? payloadJson,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> updateTurn(ChatTurn turn) => throw UnimplementedError();
}
