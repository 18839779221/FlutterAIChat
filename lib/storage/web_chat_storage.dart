import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_group.dart';
import '../models/chat_message.dart';
import '../models/response/message_content_type.dart';
import '../utils/logger.dart';
import 'chat_storage.dart';

class WebChatStorage implements ChatStorage {
  static const String _tag = 'WebChatStorage';
  static const String _groupsKey = 'web.chat_groups';
  static const String _messagesKey = 'web.chat_messages';

  final SharedPreferences _preferences;

  WebChatStorage(this._preferences);

  @override
  Future<int> insertGroup(ChatGroup group) async {
    final groups = await _readGroups();
    final nextId = _nextId(groups.map((item) => item['id'] as int?));
    final storedGroup = group.copyWith(id: nextId);
    groups.add(storedGroup.toMap());
    await _writeGroups(groups);
    return nextId;
  }

  @override
  Future<List<ChatGroup>> getAllGroups() async {
    final groups = await _readGroups();
    final decodedGroups = groups.map(ChatGroup.fromMap).toList();
    decodedGroups.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
    return decodedGroups;
  }

  @override
  Future<ChatGroup?> getLatestGroup() async {
    final groups = await getAllGroups();
    if (groups.isEmpty) {
      return null;
    }
    return groups.first;
  }

  @override
  Future<void> updateGroupLastMessageTime(int groupId) async {
    final groups = await _readGroups();
    final updated = groups.map((group) {
      if (group['id'] != groupId) {
        return group;
      }
      return {
        ...group,
        'last_message_at': DateTime.now().millisecondsSinceEpoch,
      };
    }).toList();
    await _writeGroups(updated);
  }

  @override
  Future<void> updateGroupSystemPrompt(int groupId, String? systemPrompt) async {
    final groups = await _readGroups();
    final updated = groups.map((group) {
      if (group['id'] != groupId) {
        return group;
      }
      return {
        ...group,
        'system_prompt': systemPrompt,
      };
    }).toList();
    await _writeGroups(updated);
  }

  @override
  Future<void> updateGroupTitle(int groupId, String title, {bool isSummarized = true}) async {
    final groups = await _readGroups();
    final updated = groups.map((group) {
      if (group['id'] != groupId) {
        return group;
      }
      return {
        ...group,
        'title': title,
        'is_summarized': isSummarized ? 1 : 0,
      };
    }).toList();
    await _writeGroups(updated);
  }

  @override
  Future<void> deleteGroup(int groupId) async {
    final groups = await _readGroups();
    final messages = await _readMessages();
    await _writeGroups(groups.where((group) => group['id'] != groupId).toList());
    await _writeMessages(messages.where((message) => message['group_id'] != groupId).toList());
  }

  @override
  Future<int> insertMessage(ChatMessage message, int groupId) async {
    final messages = await _readMessages();
    final nextId = _nextId(messages.map((item) => item['id'] as int?));
    final storedMessage = {
      ...message.copyWith(id: nextId).toMap(),
      'group_id': groupId,
    };
    messages.add(storedMessage);
    await _writeMessages(messages);
    await updateGroupLastMessageTime(groupId);
    return nextId;
  }

  @override
  Future<List<ChatMessage>> getMessagesByGroup(int groupId) async {
    final messages = await _groupMessages(groupId);
    messages.sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));
    return messages.map(ChatMessage.fromMap).toList();
  }

  @override
  Future<List<ChatMessage>> getMessagesByGroupWithPagination({
    required int groupId,
    required int limit,
    required int offset,
  }) async {
    final messages = await getMessagesByGroup(groupId);
    if (offset >= messages.length) {
      return [];
    }
    final end = (offset + limit).clamp(0, messages.length);
    return messages.sublist(offset, end);
  }

  @override
  Future<int> getGroupMessageCount(int groupId) async {
    final messages = await _groupMessages(groupId);
    return messages.length;
  }

  @override
  Future<void> deleteGroupMessages(int groupId) async {
    final messages = await _readMessages();
    await _writeMessages(messages.where((message) => message['group_id'] != groupId).toList());
  }

  @override
  Future<void> updateMessage(int id, String newText) async {
    await _updateMessageRecord(id, {'text': newText});
  }

  @override
  Future<void> updateMessageReasoning(int id, String? reasoningContent) async {
    await _updateMessageRecord(id, {'reasoning_content': reasoningContent});
  }

  @override
  Future<bool> testDatabaseConnection() async => true;

  @override
  Future<void> updateMessageStatus(int id, MessageStatus status) async {
    await _updateMessageRecord(id, {'status': status.toString().split('.').last});
  }

  @override
  Future<void> updateStructuredMessage(
    int id, {
    required String text,
    required MessageStatus status,
    required MessageContentType contentType,
    String? payloadJson,
  }) async {
    await _updateMessageRecord(id, {
      'text': text,
      'status': status.toString().split('.').last,
      'content_type': contentType.wireName,
      'payload_json': payloadJson,
    });
  }

  @override
  Future<void> deleteMessage(int id) async {
    final messages = await _readMessages();
    await _writeMessages(messages.where((message) => message['id'] != id).toList());
  }

  Future<void> _updateMessageRecord(int id, Map<String, dynamic> patch) async {
    final messages = await _readMessages();
    final updated = messages.map((message) {
      if (message['id'] != id) {
        return message;
      }
      return {
        ...message,
        ...patch,
      };
    }).toList();
    await _writeMessages(updated);
  }

  Future<List<Map<String, dynamic>>> _groupMessages(int groupId) async {
    final messages = await _readMessages();
    return messages.where((message) => message['group_id'] == groupId).toList();
  }

  Future<List<Map<String, dynamic>>> _readGroups() async {
    return _readList(_groupsKey);
  }

  Future<List<Map<String, dynamic>>> _readMessages() async {
    return _readList(_messagesKey);
  }

  Future<List<Map<String, dynamic>>> _readList(String key) async {
    final raw = _preferences.getString(key);
    if (raw == null || raw.isEmpty) {
      return [];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return [];
      }
      return decoded
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
    } catch (e, stackTrace) {
      Logger.e(_tag, '读取本地存储失败', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      return [];
    }
  }

  Future<void> _writeGroups(List<Map<String, dynamic>> groups) async {
    await _preferences.setString(_groupsKey, jsonEncode(groups));
  }

  Future<void> _writeMessages(List<Map<String, dynamic>> messages) async {
    await _preferences.setString(_messagesKey, jsonEncode(messages));
  }

  int _nextId(Iterable<int?> ids) {
    final values = ids.whereType<int>().toList();
    if (values.isEmpty) {
      return 1;
    }
    values.sort();
    return values.last + 1;
  }
}
