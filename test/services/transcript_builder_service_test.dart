import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/interaction/ask_user_question_request.dart';
import 'package:ai_chat/models/interaction/ask_user_question_response.dart';
import 'package:ai_chat/repositories/chat_event_repository.dart';
import 'package:ai_chat/services/transcript_builder_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TranscriptBuilderService', () {
    test('buildPlannerContext includes latest tool result and unresolved goal', () async {
      final service = TranscriptBuilderService(
        eventRepository: _FakeChatEventRepository([
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.userMessage,
            role: MessageRole.user,
            content: '帮我查数据库版本',
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.toolResult,
            role: MessageRole.system,
            content: '已找到数据库版本是 7',
          ),
        ]),
      );

      final context = await service.buildPlannerContext(
        turn: ChatTurn(
          id: 1,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '帮我查数据库版本',
        ),
        transcript: await service.loadTranscript(1),
      );

      expect(context, contains('用户目标：帮我查数据库版本'));
      expect(context, contains('最近一次工具结果：已找到数据库版本是 7'));
    });

    test('buildPlannerContext includes attempted tools and latest tool error', () async {
      final service = TranscriptBuilderService(
        eventRepository: _FakeChatEventRepository([
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.userMessage,
            role: MessageRole.user,
            content: '帮我安排提醒',
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.assistantToolCall,
            role: MessageRole.assistant,
            content: '准备执行工具：web_search',
            payloadJson: {
              'toolName': 'web_search',
              'arguments': {'query': '提醒时间格式'},
            },
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 3,
            eventType: ChatEventType.assistantToolCall,
            role: MessageRole.assistant,
            content: '准备执行工具：fetch_webpage',
            payloadJson: {
              'toolName': 'fetch_webpage',
              'arguments': {'url': 'https://example.com'},
            },
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 4,
            eventType: ChatEventType.toolError,
            role: MessageRole.system,
            content: '创建提醒失败：时间格式无效',
            status: 'invalid_due_at',
          ),
        ]),
      );

      final context = await service.buildPlannerContext(
        turn: ChatTurn(
          id: 1,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '帮我安排提醒',
        ),
        transcript: await service.loadTranscript(1),
      );

      expect(context, contains('已尝试工具：web_search, fetch_webpage'));
      expect(context, contains('最近一次工具失败：invalid_due_at'));
    });

    test('buildFinalAnswerMessages adds system prompt before transcript-derived messages', () async {
      final service = TranscriptBuilderService(
        eventRepository: _FakeChatEventRepository([
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.userMessage,
            role: MessageRole.user,
            content: '帮我查数据库版本',
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.toolResult,
            role: MessageRole.system,
            content: '已找到数据库版本是 7',
          ),
        ]),
      );

      final messages = await service.buildFinalAnswerMessages(
        groupId: 1,
        turn: ChatTurn(
          id: 1,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '帮我查数据库版本',
        ),
        transcript: await service.loadTranscript(1),
        systemPrompt: '你是一个严谨的助手',
      );

      expect(messages.first.role, MessageRole.system);
      expect(messages.first.text, '你是一个严谨的助手');
      expect(messages.last.text, '已找到数据库版本是 7');
    });

    test('buildFinalAnswerMessages keeps intermediate planner assistant messages in transcript order',
        () async {
      final service = TranscriptBuilderService(
        eventRepository: _FakeChatEventRepository([
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.userMessage,
            role: MessageRole.user,
            content: '帮我查数据库版本',
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.assistantPlannerMessage,
            role: MessageRole.assistant,
            content: '我先查一下数据库版本。',
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 3,
            eventType: ChatEventType.toolResult,
            role: MessageRole.system,
            content: '已找到数据库版本是 7',
          ),
        ]),
      );

      final messages = await service.buildFinalAnswerMessages(
        groupId: 1,
        turn: ChatTurn(
          id: 1,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '帮我查数据库版本',
        ),
        transcript: await service.loadTranscript(1),
        systemPrompt: '',
      );

      expect(
        messages.map((message) => message.text),
        containsAllInOrder([
          '帮我查数据库版本',
          '我先查一下数据库版本。',
          '已找到数据库版本是 7',
        ]),
      );
    });

    test(
        'buildFinalAnswerMessages excludes internal runtime events and keeps user-facing context roles',
        () async {
      final service = TranscriptBuilderService(
        eventRepository: _FakeChatEventRepository([
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.userMessage,
            role: MessageRole.user,
            content: '帮我规划本地持久化架构',
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.assistantPlannerMessage,
            role: MessageRole.assistant,
            content: '我先确认你偏好的存储方案。',
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 3,
            eventType: ChatEventType.toolExecutionStarted,
            role: MessageRole.system,
            content: 'tool_started:ask_user_question',
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 4,
            eventType: ChatEventType.assistantQuestionPrompt,
            role: MessageRole.assistant,
            content: '你想用 SQLite 还是别的本地存储？',
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 5,
            eventType: ChatEventType.userInteractionResult,
            role: MessageRole.system,
            content: '我更偏向 SQLite。',
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 6,
            eventType: ChatEventType.turnStatus,
            role: MessageRole.system,
            content: 'planner_action_respond',
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 7,
            eventType: ChatEventType.toolResult,
            role: MessageRole.system,
            content: '已记录用户偏好：SQLite',
          ),
        ]),
      );

      final messages = await service.buildFinalAnswerMessages(
        groupId: 1,
        turn: ChatTurn(
          id: 1,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '帮我规划本地持久化架构',
        ),
        transcript: await service.loadTranscript(1),
        systemPrompt: '',
      );

      expect(
        messages.map((message) => '${message.role.name}:${message.text}'),
        [
          'user:帮我规划本地持久化架构',
          'assistant:我先确认你偏好的存储方案。',
          'assistant:你想用 SQLite 还是别的本地存储？',
          'user:我更偏向 SQLite。',
          'assistant:已记录用户偏好：SQLite',
        ],
      );
    });
  });
}

class _FakeChatEventRepository implements ChatEventRepository {
  final List<ChatEvent> events;

  _FakeChatEventRepository(this.events);

  @override
  Future<int> appendToolResult({
    required int turnId,
    required int groupId,
    required String content,
    Map<String, dynamic>? payloadJson,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<int> appendAssistantTextDelta({
    required int turnId,
    required int groupId,
    required String content,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<int> appendAssistantTextFinal({
    required int turnId,
      required int groupId,
      required String content,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<int> appendAssistantPlannerMessage({
    required int turnId,
    required int groupId,
    required String content,
    Map<String, dynamic>? payloadJson,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<int> appendFinalAnswer({
    required int turnId,
    required int groupId,
    required String content,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<int> appendToolCall({
    required int turnId,
    required int groupId,
    required String toolName,
    required Map<String, dynamic> arguments,
    required String summary,
    Map<String, dynamic>? payloadJson,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<int> appendToolConfirmation({
    required int turnId,
    required int groupId,
    required String toolName,
    required Map<String, dynamic> arguments,
    required String summary,
    Map<String, dynamic>? payloadJson,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<int> appendAssistantQuestionPrompt({
    required int turnId,
    required int groupId,
    required AskUserQuestionRequest request,
    required String content,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<int> appendUserInteractionResult({
    required int turnId,
    required int groupId,
    required AskUserQuestionResponse response,
    required String content,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<int> appendToolError({
    required int turnId,
    required int groupId,
    required String content,
    String? errorCode,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<int> appendToolExecutionStarted({
    required int turnId,
    required int groupId,
    required String content,
    Map<String, dynamic>? payloadJson,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<int> appendTurnStatus({
    required int turnId,
    required int groupId,
    required String content,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<int> appendUserMessage({
    required int turnId,
    required int groupId,
    required String content,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ChatEvent>> listEventsByTurn(int turnId) async {
    return events.where((event) => event.turnId == turnId).toList();
  }
}
