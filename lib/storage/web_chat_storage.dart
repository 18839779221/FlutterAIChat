import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/agent/chat_turn_step.dart';
import '../models/artifact/artifact_record.dart';
import '../models/chat/chat_attachment.dart';
import '../models/chat_group.dart';
import '../models/chat_event.dart';
import '../models/chat_message.dart';
import '../models/chat_turn.dart';
import '../models/response/message_content_type.dart';
import '../models/session/session_context_snapshot.dart';
import '../models/session/session_runtime_marker.dart';
import '../utils/logger.dart';
import 'chat_storage.dart';

class WebChatStorage implements ChatStorage {
  static const String _tag = 'WebChatStorage';
  static const String _eventsKey = 'web.chat_events';
  static const String _groupsKey = 'web.chat_groups';
  static const String _messagesKey = 'web.chat_messages';
  static const String _messageAttachmentsKey = 'web.message_attachments';
  static const String _sessionContextSnapshotsKey =
      'web.session_context_snapshots';
  static const String _sessionRuntimeMarkersKey = 'web.session_runtime_markers';
  static const String _artifactRegistryKey = 'web.artifact_registry';
  static const String _turnsKey = 'web.chat_turns';
  static const String _turnStepsKey = 'web.chat_turn_steps';

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
  Future<ChatGroup?> getGroupById(int id) async {
    final groups = await getAllGroups();
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
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
  Future<void> updateGroupWorkspaceId(int groupId, String? workspaceId) async {
    final groups = await _readGroups();
    final updated = groups.map((group) {
      if (group['id'] != groupId) {
        return group;
      }
      return {
        ...group,
        'workspace_id': workspaceId,
      };
    }).toList();
    await _writeGroups(updated);
  }

  @override
  Future<void> updateGroupSystemPrompt(
      int groupId, String? systemPrompt) async {
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
  Future<void> updateGroupTitle(int groupId, String title,
      {bool isSummarized = true}) async {
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
    final events = await _readEvents();
    final groups = await _readGroups();
    final messages = await _readMessages();
    final attachments = await _readMessageAttachments();
    final snapshots = await _readSessionContextSnapshots();
    final runtimeMarkers = await _readSessionRuntimeMarkers();
    final artifacts = await _readArtifactRegistry();
    final turns = await _readTurns();
    final turnSteps = await _readTurnSteps();
    await _writeEvents(
        events.where((event) => event['group_id'] != groupId).toList());
    await _writeGroups(
        groups.where((group) => group['id'] != groupId).toList());
    await _writeMessages(
        messages.where((message) => message['group_id'] != groupId).toList());
    final deletedMessageIds = messages
        .where((message) => message['group_id'] == groupId)
        .map((message) => message['id'])
        .toSet();
    await _writeMessageAttachments(
      attachments
          .where(
            (attachment) =>
                !deletedMessageIds.contains(attachment['message_id']),
          )
          .toList(),
    );
    await _writeSessionContextSnapshots(
      snapshots.where((snapshot) => snapshot['group_id'] != groupId).toList(),
    );
    await _writeSessionRuntimeMarkers(
      runtimeMarkers.where((marker) => marker['group_id'] != groupId).toList(),
    );
    await _writeArtifactRegistry(
      artifacts.where((artifact) => artifact['group_id'] != groupId).toList(),
    );
    await _writeTurns(
        turns.where((turn) => turn['group_id'] != groupId).toList());
    final deletedTurnIds = turns
        .where((turn) => turn['group_id'] == groupId)
        .map((turn) => turn['id'])
        .toSet();
    await _writeTurnSteps(
      turnSteps
          .where((step) => !deletedTurnIds.contains(step['turn_id']))
          .toList(),
    );
  }

  @override
  Future<int> insertTurn(ChatTurn turn) async {
    final turns = await _readTurns();
    final nextId = _nextId(turns.map((item) => item['id'] as int?));
    turns.add({
      ...turn.toMap(),
      'id': nextId,
    });
    await _writeTurns(turns);
    return nextId;
  }

  @override
  Future<ChatTurn?> getTurn(int id) async {
    final turns = await _readTurns();
    final match = turns.where((turn) => turn['id'] == id);
    if (match.isEmpty) {
      return null;
    }
    return ChatTurn.fromMap(match.first);
  }

  @override
  Future<List<ChatTurn>> getTurnsByGroup(int groupId) async {
    final turns = await _readTurns();
    final filtered = turns.where((turn) => turn['group_id'] == groupId).toList()
      ..sort((a, b) {
        final createdComparison =
            (a['created_at'] as int).compareTo(b['created_at'] as int);
        if (createdComparison != 0) {
          return createdComparison;
        }
        return (a['id'] as int).compareTo(b['id'] as int);
      });
    return filtered.map(ChatTurn.fromMap).toList();
  }

  @override
  Future<void> updateTurn(ChatTurn turn) async {
    final turns = await _readTurns();
    final updated = turns.map((storedTurn) {
      if (storedTurn['id'] != turn.id) {
        return storedTurn;
      }
      return turn.toMap();
    }).toList();
    await _writeTurns(updated);
  }

  @override
  Future<int> insertTurnStep(ChatTurnStep step) async {
    final steps = await _readTurnSteps();
    final nextId = _nextId(steps.map((item) => item['id'] as int?));
    steps.add({
      ...step.toMap(),
      'id': nextId,
    });
    await _writeTurnSteps(steps);
    return nextId;
  }

  @override
  Future<ChatTurnStep?> getTurnStep(int id) async {
    final steps = await _readTurnSteps();
    final match = steps.where((step) => step['id'] == id);
    if (match.isEmpty) {
      return null;
    }
    return ChatTurnStep.fromMap(match.first);
  }

  @override
  Future<List<ChatTurnStep>> getTurnSteps(int turnId) async {
    final steps = await _readTurnSteps();
    final filtered = steps.where((step) => step['turn_id'] == turnId).toList()
      ..sort(
          (a, b) => (a['step_index'] as int).compareTo(b['step_index'] as int));
    return filtered.map(ChatTurnStep.fromMap).toList();
  }

  @override
  Future<void> updateTurnStep(ChatTurnStep step) async {
    final steps = await _readTurnSteps();
    final updated = steps.map((storedStep) {
      if (storedStep['id'] != step.id) {
        return storedStep;
      }
      return step.toMap();
    }).toList();
    await _writeTurnSteps(updated);
  }

  @override
  Future<int> insertOrReplaceArtifactRecord(ArtifactRecord record) async {
    final artifacts = await _readArtifactRegistry();
    final existingIndex = artifacts.indexWhere(
      (item) =>
          item['group_id'] == record.groupId &&
          item['artifact_id'] == record.artifactId,
    );
    if (existingIndex != -1) {
      final existingId = artifacts[existingIndex]['id'] as int?;
      artifacts[existingIndex] = {
        ...record.toMap(),
        'id': existingId ??
            record.id ??
            _nextId(artifacts.map((e) => e['id'] as int?)),
      };
      await _writeArtifactRegistry(artifacts);
      return artifacts[existingIndex]['id'] as int;
    }

    final nextId = _nextId(artifacts.map((item) => item['id'] as int?));
    artifacts.add({
      ...record.toMap(),
      'id': nextId,
    });
    await _writeArtifactRegistry(artifacts);
    return nextId;
  }

  @override
  Future<ArtifactRecord?> getArtifactRecord({
    required int groupId,
    required String artifactId,
  }) async {
    final artifacts = await _readArtifactRegistry();
    final matches = artifacts.where(
      (item) =>
          item['group_id'] == groupId && item['artifact_id'] == artifactId,
    );
    if (matches.isEmpty) {
      return null;
    }
    return ArtifactRecord.fromMap(matches.first);
  }

  @override
  Future<ArtifactRecord?> getArtifactRecordByPath({
    required int groupId,
    required String sourcePath,
  }) async {
    final artifacts = await _readArtifactRegistry();
    final matches = artifacts.where(
      (item) =>
          item['group_id'] == groupId && item['source_path'] == sourcePath,
    );
    if (matches.isEmpty) {
      return null;
    }
    return ArtifactRecord.fromMap(matches.first);
  }

  @override
  Future<List<ArtifactRecord>> listArtifactRecordsForGroup(int groupId) async {
    final artifacts = await _readArtifactRegistry();
    final filtered =
        artifacts.where((item) => item['group_id'] == groupId).toList()
          ..sort((a, b) {
            final createdComparison =
                (a['created_at'] as int).compareTo(b['created_at'] as int);
            if (createdComparison != 0) {
              return createdComparison;
            }
            return (a['id'] as int).compareTo(b['id'] as int);
          });
    return filtered.map(ArtifactRecord.fromMap).toList(growable: false);
  }

  @override
  Future<void> updateArtifactRecord(ArtifactRecord record) async {
    final artifacts = await _readArtifactRegistry();
    final updated = artifacts.map((storedArtifact) {
      if (storedArtifact['id'] != record.id) {
        return storedArtifact;
      }
      return record.toMap();
    }).toList();
    await _writeArtifactRegistry(updated);
  }

  @override
  Future<int> insertEvent(ChatEvent event) async {
    final events = await _readEvents();
    final nextId = _nextId(events.map((item) => item['id'] as int?));
    events.add({
      ...event.toMap(),
      'id': nextId,
    });
    await _writeEvents(events);
    return nextId;
  }

  @override
  Future<int> getNextEventSequence(int turnId) async {
    final events = await _readEvents();
    var maxSequence = 0;
    for (final event in events) {
      if (event['turn_id'] != turnId) continue;
      final sequence = event['sequence'];
      if (sequence is int && sequence > maxSequence) {
        maxSequence = sequence;
      }
    }
    return maxSequence + 1;
  }

  @override
  Future<List<ChatEvent>> getEventsByTurn(int turnId) async {
    final events = await _readEvents();
    final filtered = events
        .where((event) => event['turn_id'] == turnId)
        .toList()
      ..sort((a, b) => (a['sequence'] as int).compareTo(b['sequence'] as int));
    return filtered.map(ChatEvent.fromMap).toList();
  }

  @override
  Future<List<ChatEvent>> getEventsByGroup(int groupId) async {
    final events = await _readEvents();
    final filtered =
        events.where((event) => event['group_id'] == groupId).toList()
          ..sort((a, b) {
            final createdComparison =
                (a['created_at'] as int).compareTo(b['created_at'] as int);
            if (createdComparison != 0) {
              return createdComparison;
            }
            final sequenceComparison =
                (a['sequence'] as int).compareTo(b['sequence'] as int);
            if (sequenceComparison != 0) {
              return sequenceComparison;
            }
            return (a['id'] as int).compareTo(b['id'] as int);
          });
    return filtered.map(ChatEvent.fromMap).toList();
  }

  @override
  Future<int> insertSessionContextSnapshot(
      SessionContextSnapshot snapshot) async {
    final snapshots = await _readSessionContextSnapshots();
    final nextId = _nextId(snapshots.map((item) => item['id'] as int?));
    snapshots.add({
      ...snapshot.toMap(),
      'id': nextId,
    });
    await _writeSessionContextSnapshots(snapshots);
    return nextId;
  }

  @override
  Future<SessionContextSnapshot?> getLatestSessionContextSnapshotByGroup(
    int groupId,
  ) async {
    final snapshots = await _readSessionContextSnapshots();
    final matches = snapshots
        .where((snapshot) => snapshot['group_id'] == groupId)
        .toList()
      ..sort(
        (left, right) =>
            (right['updated_at'] as int).compareTo(left['updated_at'] as int),
      );
    if (matches.isEmpty) {
      return null;
    }
    return SessionContextSnapshot.fromMap(matches.first);
  }

  @override
  Future<void> updateSessionContextSnapshot(
    SessionContextSnapshot snapshot,
  ) async {
    final snapshots = await _readSessionContextSnapshots();
    final updated = snapshots.map((storedSnapshot) {
      if (storedSnapshot['id'] != snapshot.id) {
        return storedSnapshot;
      }
      return snapshot.toMap();
    }).toList();
    await _writeSessionContextSnapshots(updated);
  }

  @override
  Future<int> insertSessionRuntimeMarker(SessionRuntimeMarker marker) async {
    final markers = await _readSessionRuntimeMarkers();
    final nextId = _nextId(markers.map((item) => item['id'] as int?));
    markers.add({
      ...marker.toMap(),
      'id': nextId,
    });
    await _writeSessionRuntimeMarkers(markers);
    return nextId;
  }

  @override
  Future<SessionRuntimeMarker?> getLatestSessionRuntimeMarkerByGroup(
    int groupId,
  ) async {
    final markers = await _readSessionRuntimeMarkers();
    final matches = markers
        .where((marker) => marker['group_id'] == groupId)
        .toList()
      ..sort(
        (left, right) =>
            (right['updated_at'] as int).compareTo(left['updated_at'] as int),
      );
    if (matches.isEmpty) {
      return null;
    }
    return SessionRuntimeMarker.fromMap(matches.first);
  }

  @override
  Future<void> updateSessionRuntimeMarker(SessionRuntimeMarker marker) async {
    final markers = await _readSessionRuntimeMarkers();
    final updated = markers.map((storedMarker) {
      if (storedMarker['id'] != marker.id) {
        return storedMarker;
      }
      return marker.toMap();
    }).toList();
    await _writeSessionRuntimeMarkers(updated);
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
  Future<void> insertMessageAttachments(
    int messageId,
    List<ChatAttachment> attachments,
  ) async {
    final stored = await _readMessageAttachments();
    stored.removeWhere((attachment) => attachment['message_id'] == messageId);
    stored.addAll(
      attachments.map(
        (attachment) => attachment.toDatabaseMap(messageId: messageId),
      ),
    );
    await _writeMessageAttachments(stored);
  }

  @override
  Future<List<ChatAttachment>> getMessageAttachments(int messageId) async {
    final stored = await _readMessageAttachments();
    return stored
        .where((attachment) => attachment['message_id'] == messageId)
        .map(ChatAttachment.fromDatabaseMap)
        .toList(growable: false);
  }

  @override
  Future<List<ChatMessage>> getMessagesByGroup(int groupId) async {
    final decoded = await _getAllMessagesByGroupAscending(groupId);
    if (decoded.length <= 20) {
      return decoded;
    }
    return decoded.sublist(decoded.length - 20);
  }

  Future<List<ChatMessage>> _getAllMessagesByGroupAscending(int groupId) async {
    final messages = await _groupMessages(groupId);
    messages.sort(
        (a, b) => (a['timestamp'] as int).compareTo(b['timestamp'] as int));
    final decoded = <ChatMessage>[];
    for (final map in messages) {
      final message = ChatMessage.fromMap(map);
      final messageId = message.id;
      final attachments = messageId == null
          ? const <ChatAttachment>[]
          : await getMessageAttachments(messageId);
      final nextReferenceJson = <String, dynamic>{
        ...?message.referenceJson,
        if (attachments.isNotEmpty)
          'attachments':
              attachments.map((attachment) => attachment.toJson()).toList(),
      };
      decoded.add(
        message.copyWith(
          attachments: attachments,
          referenceJson: nextReferenceJson.isEmpty ? null : nextReferenceJson,
        ),
      );
    }
    return decoded;
  }

  @override
  Future<List<ChatMessage>> getMessagesByGroupWithPagination({
    required int groupId,
    required int limit,
    required int offset,
  }) async {
    final messages = await _getAllMessagesByGroupAscending(groupId);
    final end = messages.length - offset;
    if (end <= 0) {
      return [];
    }
    final start = (end - limit).clamp(0, messages.length);
    return messages.sublist(start, end);
  }

  @override
  Future<int> getGroupMessageCount(int groupId) async {
    final messages = await _groupMessages(groupId);
    return messages.length;
  }

  @override
  Future<void> deleteGroupMessages(int groupId) async {
    final messages = await _readMessages();
    final deletedIds = messages
        .where((message) => message['group_id'] == groupId)
        .map((message) => message['id'])
        .toSet();
    await _writeMessages(
        messages.where((message) => message['group_id'] != groupId).toList());
    final attachments = await _readMessageAttachments();
    await _writeMessageAttachments(
      attachments
          .where((attachment) => !deletedIds.contains(attachment['message_id']))
          .toList(),
    );
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
    await _updateMessageRecord(
        id, {'status': status.toString().split('.').last});
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
    await _writeMessages(
        messages.where((message) => message['id'] != id).toList());
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

  Future<List<Map<String, dynamic>>> _readTurns() async {
    return _readList(_turnsKey);
  }

  Future<List<Map<String, dynamic>>> _readTurnSteps() async {
    return _readList(_turnStepsKey);
  }

  Future<List<Map<String, dynamic>>> _readEvents() async {
    return _readList(_eventsKey);
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

  Future<List<Map<String, dynamic>>> _readMessageAttachments() async {
    return _readList(_messageAttachmentsKey);
  }

  Future<void> _writeMessageAttachments(
    List<Map<String, dynamic>> attachments,
  ) async {
    await _preferences.setString(
      _messageAttachmentsKey,
      jsonEncode(attachments),
    );
  }

  Future<List<Map<String, dynamic>>> _readSessionContextSnapshots() async {
    final raw = _preferences.getString(_sessionContextSnapshotsKey);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      Logger.w(_tag, 'Invalid stored session context snapshots payload');
      return [];
    }
    return decoded
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
  }

  Future<List<Map<String, dynamic>>> _readSessionRuntimeMarkers() async {
    final raw = _preferences.getString(_sessionRuntimeMarkersKey);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      Logger.w(_tag, 'Invalid stored session runtime markers payload');
      return [];
    }
    return decoded
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
  }

  Future<List<Map<String, dynamic>>> _readArtifactRegistry() async {
    final raw = _preferences.getString(_artifactRegistryKey);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      Logger.w(_tag, 'Invalid stored artifact registry payload');
      return [];
    }
    return decoded
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
  }

  Future<void> _writeSessionContextSnapshots(
    List<Map<String, dynamic>> snapshots,
  ) async {
    await _preferences.setString(
      _sessionContextSnapshotsKey,
      jsonEncode(snapshots),
    );
  }

  Future<void> _writeSessionRuntimeMarkers(
    List<Map<String, dynamic>> markers,
  ) async {
    await _preferences.setString(
      _sessionRuntimeMarkersKey,
      jsonEncode(markers),
    );
  }

  Future<void> _writeArtifactRegistry(
    List<Map<String, dynamic>> artifacts,
  ) async {
    await _preferences.setString(
      _artifactRegistryKey,
      jsonEncode(artifacts),
    );
  }

  Future<void> _writeTurns(List<Map<String, dynamic>> turns) async {
    await _preferences.setString(_turnsKey, jsonEncode(turns));
  }

  Future<void> _writeTurnSteps(List<Map<String, dynamic>> turnSteps) async {
    await _preferences.setString(_turnStepsKey, jsonEncode(turnSteps));
  }

  Future<void> _writeEvents(List<Map<String, dynamic>> events) async {
    await _preferences.setString(_eventsKey, jsonEncode(events));
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
