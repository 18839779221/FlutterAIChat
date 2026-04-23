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
    test('buildPlannerContext includes latest tool result and unresolved goal',
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

    test('buildPlannerContext includes attempted tools and latest tool error',
        () async {
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

    test(
        'buildFinalAnswerMessages adds system prompt before transcript-derived messages',
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
      expect(messages[1].role, MessageRole.user);
      expect(messages[1].text, contains('# currentDate'));
      expect(messages.last.text, '[user tool_result] 已找到数据库版本是 7');
    });

    test(
        'buildFinalAnswerMessages keeps intermediate planner assistant messages in transcript order',
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
        messages.map((message) => message.text).join('\n'),
        allOf([
          contains('<system-reminder>'),
          contains('帮我查数据库版本'),
          contains('我先查一下数据库版本。'),
          contains('已找到数据库版本是 7'),
        ]),
      );
    });

    test('buildFinalAnswerMessages keeps tool-use and tool-result transcript structure',
        () async {
      final service = TranscriptBuilderService(
        eventRepository: _FakeChatEventRepository([
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.userMessage,
            role: MessageRole.user,
            content: '请帮我更新爱好笔记',
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 2,
            eventType: ChatEventType.assistantToolCall,
            role: MessageRole.assistant,
            content: '准备执行工具：编辑文件',
            payloadJson: const {
              'toolName': 'Edit',
              'arguments': {
                'file_path': 'my_hobbies.md',
                'old_string': '篮球',
                'new_string': '篮球\n游戏',
              },
            },
          ),
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 3,
            eventType: ChatEventType.toolResult,
            role: MessageRole.system,
            content: '已编辑文件：my_hobbies.md',
            payloadJson: const {
              'toolName': 'Edit',
              'status': 'success',
              'summary': '已编辑文件：my_hobbies.md',
              'toolResultText': 'Successfully edited my_hobbies.md',
              'data': {
                'filePath': 'my_hobbies.md',
              },
            },
          ),
        ]),
      );

      final messages = await service.buildFinalAnswerMessages(
        groupId: 1,
        turn: ChatTurn(
          id: 1,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '请帮我更新爱好笔记',
        ),
        transcript: await service.loadTranscript(1),
        systemPrompt: '',
      );

      final combined =
          messages.map((message) => '${message.role.name}:${message.text}').join('\n');
      expect(combined, contains('assistant:[assistant tool_use]'));
      expect(combined, contains('Edit'));
      expect(combined, contains('my_hobbies.md'));
      expect(
        combined,
        contains('user:[user tool_result] Successfully edited my_hobbies.md'),
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
        messages.map((message) => '${message.role.name}:${message.text}').join('\n'),
        allOf([
          contains('user:<system-reminder>'),
          contains('user:帮我规划本地持久化架构'),
          contains('assistant:我先确认你偏好的存储方案。'),
          contains('assistant:你想用 SQLite 还是别的本地存储？'),
          contains('user:我更偏向 SQLite。'),
          contains('user:[user tool_result] 已记录用户偏好：SQLite'),
        ]),
      );
    });

    test('buildFinalAnswerMessages injects date reminder before transcript messages',
        () async {
      final service = TranscriptBuilderService(
        eventRepository: _FakeChatEventRepository([
          ChatEvent(
            turnId: 1,
            groupId: 1,
            sequence: 1,
            eventType: ChatEventType.userMessage,
            role: MessageRole.user,
            content: '今天的最新新闻是什么',
          ),
        ]),
      );

      final messages = await service.buildFinalAnswerMessages(
        groupId: 1,
        turn: ChatTurn(
          id: 1,
          groupId: 1,
          status: ChatTurnStatus.running,
          userInput: '今天的最新新闻是什么',
          providerStateJson: const {
            'runtime_context': {
              'date_change_reminder':
                  '<system-reminder>\nThe date has changed. Today\'s date is now 2026-04-25.\nDO NOT mention this to the user explicitly because they are already aware.\n</system-reminder>',
            },
          },
        ),
        transcript: await service.loadTranscript(1),
        systemPrompt: '你是一个严谨的助手',
      );

      expect(messages[1].text, contains('# currentDate'));
      expect(messages[2].text, contains('The date has changed.'));
      expect(messages[3].text, '今天的最新新闻是什么');
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
    Map<String, dynamic>? payloadJson,
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

  @override
  Future<List<ChatEvent>> listEventsByGroup(int groupId) async {
    return events.where((event) => event.groupId == groupId).toList();
  }
}
