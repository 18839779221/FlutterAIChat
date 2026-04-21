import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/agent/chat_turn_step.dart';
import 'package:ai_chat/models/chat_event.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/session/session_context_snapshot.dart';
import 'package:ai_chat/services/tool_executor.dart';
import 'package:ai_chat/storage/chat_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolExecutor.executeSearchChatHistory', () {
    test('当前分组存在匹配消息时返回稳定结果对象', () async {
      final executor = ToolExecutor(
        chatStorage: _FakeChatStorage(
          messages: [
            ChatMessage(
              id: 101,
              text: '数据库版本已经升级到 6',
              role: MessageRole.assistant,
              timestamp: DateTime(2026, 3, 27, 10, 0),
              status: MessageStatus.completed,
            ),
            ChatMessage(
              id: 102,
              text: '数据库 schema 已经补了 content_type 字段',
              role: MessageRole.user,
              timestamp: DateTime(2026, 3, 27, 9, 59),
              status: MessageStatus.completed,
            ),
            ChatMessage(
              id: 103,
              text: '这条消息和查询无关',
              role: MessageRole.user,
              timestamp: DateTime(2026, 3, 27, 9, 58),
              status: MessageStatus.completed,
            ),
          ],
        ),
      );

      final result = await executor.executeSearchChatHistory(
        groupId: 1,
        query: '数据库',
        maxResults: 2,
      );

      expect(result.status, ToolExecutionStatus.success);
      expect(result.displayText, '已执行：搜索历史记录');
      expect(result.payload['query'], '数据库');
      expect(result.payload['matchCount'], 2);
      expect(result.payload['matches'], hasLength(2));
      expect((result.payload['matches'] as List).first['id'], 101);
      expect((result.payload['matches'] as List).last['id'], 102);
    });

    test('查询为空时返回失败结果而不是抛异常', () async {
      final executor =
          ToolExecutor(chatStorage: const _FakeChatStorage(messages: []));

      final result = await executor.executeSearchChatHistory(
        groupId: 1,
        query: '   ',
      );

      expect(result.status, ToolExecutionStatus.failure);
      expect(result.displayText, contains('搜索失败'));
      expect(result.payload['reason'], 'empty_query');
    });

    test('无匹配结果时返回成功且结果列表为空', () async {
      final executor = ToolExecutor(
        chatStorage: _FakeChatStorage(
          messages: [
            ChatMessage(
              id: 201,
              text: '这里只有结构化输出相关内容',
              role: MessageRole.assistant,
              timestamp: DateTime(2026, 3, 27, 8, 0),
              status: MessageStatus.completed,
            ),
          ],
        ),
      );

      final result = await executor.executeSearchChatHistory(
        groupId: 1,
        query: '工具调用',
      );

      expect(result.status, ToolExecutionStatus.success);
      expect(result.displayText, '已执行：搜索历史记录');
      expect(result.payload['matchCount'], 0);
      expect(result.payload['matches'], isEmpty);
    });
  });

  group('ToolExecutor first-wave tool adapters', () {
    test('web_search returns structured success with stub adapter', () async {
      final executor = ToolExecutor(
        chatStorage: const _FakeChatStorage(messages: []),
        webSearcher: ({required query, maxResults}) async => const ToolResult(
          toolName: 'web_search',
          status: ToolExecutionStatus.success,
          summary: '已执行联网搜索',
          data: {
            'query': 'OpenAI 最新消息',
            'provider': 'tavily',
            'results': [
              {
                'title': 'OpenAI launches new feature',
                'url': 'https://example.com/openai',
                'snippet': 'Latest OpenAI update.',
                'source': 'example.com',
              },
            ],
          },
        ),
      );

      final result = await executor.executeWebSearch(
        query: 'OpenAI 最新消息',
        maxResults: 3,
      );

      expect(result.status, ToolExecutionStatus.success);
      expect(result.summary, '已执行联网搜索');
      expect(result.data['provider'], 'tavily');
      expect((result.data['results'] as List).single['source'], 'example.com');
    });

    test('fetch_webpage returns structured success with stub fetcher',
        () async {
      final executor = ToolExecutor(
        chatStorage: const _FakeChatStorage(messages: []),
        webpageFetcher: ({required url, extractMode}) async => const ToolResult(
          toolName: 'fetch_webpage',
          status: ToolExecutionStatus.success,
          summary: '已读取网页',
          data: {
            'url': 'https://example.com',
            'title': 'Example',
            'content': '网页正文',
          },
        ),
      );

      final result = await executor.executeFetchWebpage(
        url: 'https://example.com',
      );

      expect(result.status, ToolExecutionStatus.success);
      expect(result.summary, '已读取网页');
      expect(result.data['content'], '网页正文');
    });

    test('create_reminder returns failure when adapter is unavailable',
        () async {
      final executor = ToolExecutor(
        chatStorage: const _FakeChatStorage(messages: []),
      );

      final result = await executor.executeCreateReminder(
        title: '交周报',
      );

      expect(result.status, ToolExecutionStatus.failure);
      expect(result.errorMessage, 'unsupported_tool');
    });

    test('web_search returns failure when adapter is unavailable', () async {
      final executor = ToolExecutor(
        chatStorage: const _FakeChatStorage(messages: []),
      );

      final result = await executor.executeWebSearch(
        query: 'OpenAI 最新消息',
      );

      expect(result.status, ToolExecutionStatus.failure);
      expect(result.errorMessage, 'unsupported_tool');
    });

    test('create_calendar_event returns success with stub adapter', () async {
      final executor = ToolExecutor(
        chatStorage: const _FakeChatStorage(messages: []),
        calendarEventCreator: ({
          required title,
          required startAt,
          endAt,
          location,
          notes,
        }) async =>
            ToolResult(
          toolName: 'create_calendar_event',
          status: ToolExecutionStatus.success,
          summary: '已创建日历事件：$title',
          data: {
            'title': title,
            'startAt': startAt,
            'endAt': endAt,
            'location': location,
            'notes': notes,
          },
        ),
      );

      final result = await executor.executeCreateCalendarEvent(
        title: '项目评审',
        startAt: '2026-03-31T15:00:00+08:00',
      );

      expect(result.status, ToolExecutionStatus.success);
      expect(result.summary, contains('项目评审'));
    });

    test('share_result returns success with stub adapter', () async {
      final executor = ToolExecutor(
        chatStorage: const _FakeChatStorage(messages: []),
        resultSharer: ({required text, subject}) async => ToolResult(
          toolName: 'share_result',
          status: ToolExecutionStatus.success,
          summary: '已发起分享',
          data: {
            'text': text,
            'subject': subject,
          },
        ),
      );

      final result = await executor.executeShareResult(
        text: '这是一段要分享的内容',
        subject: '分享标题',
      );

      expect(result.status, ToolExecutionStatus.success);
      expect(result.summary, '已发起分享');
      expect(result.data['subject'], '分享标题');
    });
  });
}

class _FakeChatStorage implements ChatStorage {
  final List<ChatMessage> messages;

  const _FakeChatStorage({required this.messages});

  @override
  Future<List<ChatMessage>> getMessagesByGroup(int groupId) async => messages;

  @override
  Future<int> insertGroup(ChatGroup group) => throw UnimplementedError();

  @override
  Future<List<ChatGroup>> getAllGroups() => throw UnimplementedError();

  @override
  Future<ChatGroup?> getLatestGroup() => throw UnimplementedError();

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
  Future<void> deleteGroup(int groupId) => throw UnimplementedError();

  @override
  Future<int> insertTurn(ChatTurn turn) => throw UnimplementedError();

  @override
  Future<ChatTurn?> getTurn(int id) => throw UnimplementedError();

  @override
  Future<List<ChatTurn>> getTurnsByGroup(int groupId) =>
      throw UnimplementedError();

  @override
  Future<ChatTurnStep?> getTurnStep(int id) => throw UnimplementedError();

  @override
  Future<List<ChatTurnStep>> getTurnSteps(int turnId) =>
      throw UnimplementedError();

  @override
  Future<void> updateTurn(ChatTurn turn) => throw UnimplementedError();

  @override
  Future<int> insertTurnStep(ChatTurnStep step) => throw UnimplementedError();

  @override
  Future<void> updateTurnStep(ChatTurnStep step) => throw UnimplementedError();

  @override
  Future<int> insertEvent(ChatEvent event) => throw UnimplementedError();

  @override
  Future<List<ChatEvent>> getEventsByTurn(int turnId) =>
      throw UnimplementedError();

  @override
  Future<List<ChatEvent>> getEventsByGroup(int groupId) =>
      throw UnimplementedError();

  @override
  Future<int> insertMessage(ChatMessage message, int groupId) =>
      throw UnimplementedError();

  @override
  Future<int> insertSessionContextSnapshot(SessionContextSnapshot snapshot) =>
      throw UnimplementedError();

  @override
  Future<SessionContextSnapshot?> getLatestSessionContextSnapshotByGroup(
    int groupId,
  ) =>
      throw UnimplementedError();

  @override
  Future<List<ChatMessage>> getMessagesByGroupWithPagination({
    required int groupId,
    required int limit,
    required int offset,
  }) =>
      throw UnimplementedError();

  @override
  Future<int> getGroupMessageCount(int groupId) => throw UnimplementedError();

  @override
  Future<void> deleteGroupMessages(int groupId) => throw UnimplementedError();

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
  Future<void> deleteMessage(int id) => throw UnimplementedError();

  @override
  Future<bool> testDatabaseConnection() => throw UnimplementedError();

  @override
  Future<void> updateSessionContextSnapshot(
    SessionContextSnapshot snapshot,
  ) =>
      throw UnimplementedError();
}
