import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
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
          ToolExecutor(chatStorage: _FakeChatStorage(messages: const []));

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
  Future<int> insertMessage(ChatMessage message, int groupId) =>
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
}
