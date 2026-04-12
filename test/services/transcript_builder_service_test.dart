import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
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
      expect(context, contains('最新工具结果：已找到数据库版本是 7'));
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
