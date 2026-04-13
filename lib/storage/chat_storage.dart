import '../models/agent/chat_turn_step.dart';
import '../models/chat_group.dart';
import '../models/chat_event.dart';
import '../models/chat_message.dart';
import '../models/chat_turn.dart';
import '../models/response/message_content_type.dart';

abstract class ChatStorage {
  Future<int> insertGroup(ChatGroup group);
  Future<List<ChatGroup>> getAllGroups();
  Future<ChatGroup?> getLatestGroup();
  Future<void> updateGroupLastMessageTime(int groupId);
  Future<void> updateGroupSystemPrompt(int groupId, String? systemPrompt);
  Future<void> updateGroupTitle(int groupId, String title,
      {bool isSummarized = true});
  Future<void> deleteGroup(int groupId);

  Future<int> insertTurn(ChatTurn turn);
  Future<ChatTurn?> getTurn(int id);
  Future<void> updateTurn(ChatTurn turn);
  Future<int> insertTurnStep(ChatTurnStep step);
  Future<ChatTurnStep?> getTurnStep(int id);
  Future<List<ChatTurnStep>> getTurnSteps(int turnId);
  Future<void> updateTurnStep(ChatTurnStep step);

  Future<int> insertEvent(ChatEvent event);
  Future<List<ChatEvent>> getEventsByTurn(int turnId);

  Future<int> insertMessage(ChatMessage message, int groupId);
  Future<List<ChatMessage>> getMessagesByGroup(int groupId);
  Future<List<ChatMessage>> getMessagesByGroupWithPagination({
    required int groupId,
    required int limit,
    required int offset,
  });
  Future<int> getGroupMessageCount(int groupId);
  Future<void> deleteGroupMessages(int groupId);
  Future<void> updateMessage(int id, String newText);
  Future<void> updateMessageReasoning(int id, String? reasoningContent);
  Future<void> updateMessageStatus(int id, MessageStatus status);
  Future<void> updateStructuredMessage(
    int id, {
    required String text,
    required MessageStatus status,
    required MessageContentType contentType,
    String? payloadJson,
  });
  Future<void> deleteMessage(int id);
  Future<bool> testDatabaseConnection();
}
