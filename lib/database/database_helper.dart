import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/agent/chat_turn_step.dart';
import '../models/artifact/artifact_record.dart';
import '../models/chat/chat_attachment.dart';
import '../models/chat_event.dart';
import '../models/chat_message.dart';
import '../models/response/message_content_type.dart';
import '../models/chat_group.dart';
import '../models/chat_turn.dart';
import '../models/session/session_context_snapshot.dart';
import '../models/session/session_runtime_config.dart';
import '../models/session/session_runtime_marker.dart';
import '../storage/chat_storage.dart';
import '../utils/logger.dart';

class DatabaseHelper implements ChatStorage {
  static const String _tag = 'DatabaseHelper';
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  final String _databaseName;
  Database? _database;

  factory DatabaseHelper({String databaseName = 'chat_history.db'}) {
    if (databaseName == 'chat_history.db') {
      return _instance;
    }
    return DatabaseHelper._named(databaseName);
  }

  DatabaseHelper._internal() : _databaseName = 'chat_history.db';

  DatabaseHelper._named(this._databaseName);

  Future<Database> get database async {
    if (_database != null) return _database!;
    Logger.i(_tag, '初始化数据库...');
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    try {
      String path = join(await getDatabasesPath(), _databaseName);
      Logger.d(_tag, '数据库路径: $path');

      return await openDatabase(
        path,
        version: 18,
        onCreate: (Database db, int version) async {
          Logger.i(_tag, '创建数据库表...');
          // 创建分组表
          await db.execute('''
            CREATE TABLE chat_groups (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              last_message_at INTEGER NOT NULL,
              system_prompt TEXT,
              is_summarized INTEGER NOT NULL DEFAULT 0,
              workspace_id TEXT
            )
          ''');

          // 创建消息表，添加group_id字段
          await db.execute('''
            CREATE TABLE messages (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              group_id INTEGER NOT NULL,
              text TEXT NOT NULL,
              role TEXT NOT NULL,
              timestamp INTEGER NOT NULL,
              status TEXT NOT NULL DEFAULT 'initial',
              reasoning_content TEXT,
              content_type TEXT NOT NULL DEFAULT 'plainText',
              payload_json TEXT,
              reference_json TEXT,
              FOREIGN KEY (group_id) REFERENCES chat_groups (id) ON DELETE CASCADE
            )
          ''');
          await _createAgentLoopTables(db);
          await _createArtifactRegistryTable(db);
          await _createSessionContextSnapshotTable(db);
          await _createSessionRuntimeConfigTable(db);
          await _createSessionRuntimeMarkerTable(db);
          await _createMessageAttachmentsTable(db);
          Logger.i(_tag, '数据库表创建成功');
        },
        onUpgrade: (Database db, int oldVersion, int newVersion) async {
          if (oldVersion < 18) {
            await db.execute('DROP TABLE IF EXISTS message_attachments');
            await db.execute('DROP TABLE IF EXISTS session_runtime_markers');
            await db.execute('DROP TABLE IF EXISTS session_runtime_configs');
            await db.execute('DROP TABLE IF EXISTS session_context_snapshots');
            await db.execute('DROP TABLE IF EXISTS artifact_registry');
            await db.execute('DROP TABLE IF EXISTS chat_events');
            await db.execute('DROP TABLE IF EXISTS chat_turn_steps');
            await db.execute('DROP TABLE IF EXISTS chat_turns');
            await db.execute('DROP TABLE IF EXISTS messages');
            await db.execute('DROP TABLE IF EXISTS chat_groups');

            await db.execute('''
              CREATE TABLE chat_groups (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                last_message_at INTEGER NOT NULL,
                system_prompt TEXT,
                is_summarized INTEGER NOT NULL DEFAULT 0,
                workspace_id TEXT
              )
            ''');
            await db.execute('''
              CREATE TABLE messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                group_id INTEGER NOT NULL,
                text TEXT NOT NULL,
                role TEXT NOT NULL,
                timestamp INTEGER NOT NULL,
                status TEXT NOT NULL DEFAULT 'initial',
                reasoning_content TEXT,
                content_type TEXT NOT NULL DEFAULT 'plainText',
                payload_json TEXT,
                reference_json TEXT,
                FOREIGN KEY (group_id) REFERENCES chat_groups (id) ON DELETE CASCADE
              )
            ''');
            await _createAgentLoopTables(db);
            await _createArtifactRegistryTable(db);
            await _createSessionContextSnapshotTable(db);
            await _createSessionRuntimeConfigTable(db);
            await _createSessionRuntimeMarkerTable(db);
            await _createMessageAttachmentsTable(db);
            return;
          }
        },
      );
    } catch (e, stackTrace) {
      Logger.e(_tag, '初始化数据库失败', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      rethrow;
    }
  }

  Future<void> _createAgentLoopTables(Database db) async {
    await db.execute('''
      CREATE TABLE chat_turns (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_id INTEGER NOT NULL,
        status TEXT NOT NULL,
        user_input TEXT NOT NULL,
        goal_summary TEXT,
        iteration_count INTEGER NOT NULL DEFAULT 0,
        tool_call_count INTEGER NOT NULL DEFAULT 0,
        provider_style TEXT,
        model_name TEXT,
        provider_state_json TEXT,
        final_response_text TEXT,
        stop_reason TEXT,
        error_message TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        completed_at INTEGER,
        FOREIGN KEY (group_id) REFERENCES chat_groups (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE chat_turn_steps (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        turn_id INTEGER NOT NULL,
        step_index INTEGER NOT NULL,
        provider_response_id TEXT,
        provider_call_id TEXT,
        tool_name TEXT NOT NULL,
        tool_args_json TEXT NOT NULL,
        status TEXT NOT NULL,
        result_summary TEXT,
        result_json TEXT,
        error_code TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        completed_at INTEGER,
        FOREIGN KEY (turn_id) REFERENCES chat_turns (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE chat_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        turn_id INTEGER NOT NULL,
        group_id INTEGER NOT NULL,
        sequence INTEGER NOT NULL,
        event_type TEXT NOT NULL,
        role TEXT,
        status TEXT,
        content TEXT,
        payload_json TEXT,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (turn_id) REFERENCES chat_turns (id) ON DELETE CASCADE,
        FOREIGN KEY (group_id) REFERENCES chat_groups (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX idx_chat_turn_steps_turn_id_step_index
      ON chat_turn_steps(turn_id, step_index)
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX idx_chat_events_turn_id_sequence
      ON chat_events(turn_id, sequence)
    ''');
    await db.execute('''
      CREATE INDEX idx_chat_turns_group_id_created_at
      ON chat_turns(group_id, created_at DESC)
    ''');
    await db.execute('''
      CREATE INDEX idx_chat_events_group_id_created_at
      ON chat_events(group_id, created_at DESC)
    ''');
  }

  Future<void> _createSessionContextSnapshotTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS session_context_snapshots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_id INTEGER NOT NULL,
        summary_text TEXT NOT NULL,
        covered_until_turn_id INTEGER NOT NULL,
        covered_until_event_id INTEGER,
        estimated_tokens INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (group_id) REFERENCES chat_groups (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_session_context_snapshots_group_id_updated_at
      ON session_context_snapshots(group_id, updated_at DESC)
    ''');
  }

  Future<void> _createSessionRuntimeConfigTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS session_runtime_configs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_id INTEGER NOT NULL UNIQUE,
        provider_id TEXT NOT NULL,
        model_id TEXT NOT NULL,
        provider_style TEXT NOT NULL,
        side_provider_id TEXT,
        side_model_id TEXT,
        side_provider_style TEXT,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (group_id) REFERENCES chat_groups (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_session_runtime_configs_group_id_updated_at
      ON session_runtime_configs(group_id, updated_at DESC)
    ''');
  }

  Future<void> _createArtifactRegistryTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS artifact_registry (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_id INTEGER NOT NULL,
        artifact_id TEXT NOT NULL,
        title TEXT NOT NULL,
        type TEXT NOT NULL,
        source_path TEXT NOT NULL,
        origin_turn_id INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        last_updated_at INTEGER NOT NULL,
        FOREIGN KEY (group_id) REFERENCES chat_groups (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_artifact_registry_group_id_artifact_id
      ON artifact_registry(group_id, artifact_id)
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_artifact_registry_group_id_source_path
      ON artifact_registry(group_id, source_path)
    ''');
  }

  Future<void> _createSessionRuntimeMarkerTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS session_runtime_markers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_id INTEGER NOT NULL,
        last_injected_date TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (group_id) REFERENCES chat_groups (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_session_runtime_markers_group_id_updated_at
      ON session_runtime_markers(group_id, updated_at DESC)
    ''');
  }

  Future<void> _createMessageAttachmentsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS message_attachments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        message_id INTEGER,
        local_attachment_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        source TEXT NOT NULL,
        file_name TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        byte_size INTEGER,
        local_path TEXT,
        thumbnail_path TEXT,
        sha256 TEXT,
        status TEXT NOT NULL,
        error_code TEXT,
        error_message TEXT,
        provider_file_ref_json TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (message_id) REFERENCES messages (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<bool> _tableHasColumn(
    Database db, {
    required String tableName,
    required String columnName,
  }) async {
    final result = await db.rawQuery('PRAGMA table_info($tableName)');
    return result.any((row) => row['name'] == columnName);
  }

  // 分组相关操作
  Future<int> insertGroup(ChatGroup group) async {
    try {
      final db = await database;
      return await db.insert('chat_groups', group.toMap());
    } catch (e) {
      Logger.e(_tag, '插入分组失败', e);
      rethrow;
    }
  }

  Future<List<ChatGroup>> getAllGroups() async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        'chat_groups',
        orderBy: 'last_message_at DESC',
      );
      return List.generate(maps.length, (i) => ChatGroup.fromMap(maps[i]));
    } catch (e) {
      Logger.e(_tag, '获取所有分组失败', e);
      rethrow;
    }
  }

  Future<ChatGroup?> getGroupById(int id) async {
    try {
      final db = await database;
      final maps = await db.query(
        'chat_groups',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (maps.isEmpty) return null;
      return ChatGroup.fromMap(maps.first);
    } catch (e) {
      Logger.e(_tag, '获取分组失败 id=$id', e);
      rethrow;
    }
  }

  Future<ChatGroup?> getLatestGroup() async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        'chat_groups',
        orderBy: 'last_message_at DESC',
        limit: 1,
      );
      if (maps.isEmpty) return null;
      return ChatGroup.fromMap(maps.first);
    } catch (e) {
      Logger.e(_tag, '获取最新分组失败', e);
      rethrow;
    }
  }

  Future<void> updateGroupLastMessageTime(int groupId) async {
    try {
      final db = await database;
      await db.update(
        'chat_groups',
        {'last_message_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [groupId],
      );
    } catch (e) {
      Logger.e(_tag, '更新分组最后消息时间失败', e);
      rethrow;
    }
  }

  @override
  Future<void> updateGroupWorkspaceId(int groupId, String? workspaceId) async {
    try {
      final db = await database;
      await db.update(
        'chat_groups',
        {'workspace_id': workspaceId},
        where: 'id = ?',
        whereArgs: [groupId],
      );
    } catch (e) {
      Logger.e(_tag, '更新分组 workspace_id 失败', e);
      rethrow;
    }
  }

  Future<void> updateGroupSystemPrompt(
      int groupId, String? systemPrompt) async {
    try {
      final db = await database;
      await db.update(
        'chat_groups',
        {'system_prompt': systemPrompt},
        where: 'id = ?',
        whereArgs: [groupId],
      );
    } catch (e) {
      Logger.e(_tag, '更新分组系统提示词失败', e);
      rethrow;
    }
  }

  Future<void> updateGroupTitle(int groupId, String title,
      {bool isSummarized = true}) async {
    try {
      final db = await database;
      await db.update(
        'chat_groups',
        {
          'title': title,
          'is_summarized': isSummarized ? 1 : 0,
        },
        where: 'id = ?',
        whereArgs: [groupId],
      );
      Logger.i(_tag, '更新分组标题成功: $title');
    } catch (e) {
      Logger.e(_tag, '更新分组标题失败', e);
      rethrow;
    }
  }

  Future<void> deleteGroup(int groupId) async {
    try {
      final db = await database;
      await db.delete(
        'chat_groups',
        where: 'id = ?',
        whereArgs: [groupId],
      );
    } catch (e) {
      Logger.e(_tag, '删除分组失败', e);
      rethrow;
    }
  }

  @override
  Future<int> insertTurn(ChatTurn turn) async {
    try {
      final db = await database;
      return await db.insert(
        'chat_turns',
        _encodeTurnMap(turn.toMap()),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      Logger.e(_tag, '插入 turn 失败', e);
      rethrow;
    }
  }

  @override
  Future<ChatTurn?> getTurn(int id) async {
    try {
      final db = await database;
      final maps = await db.query(
        'chat_turns',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (maps.isEmpty) {
        return null;
      }
      return ChatTurn.fromMap(_decodeTurnMap(maps.first));
    } catch (e) {
      Logger.e(_tag, '获取 turn 失败', e);
      rethrow;
    }
  }

  @override
  Future<List<ChatTurn>> getTurnsByGroup(int groupId) async {
    try {
      final db = await database;
      final maps = await db.query(
        'chat_turns',
        where: 'group_id = ?',
        whereArgs: [groupId],
        orderBy: 'created_at ASC, id ASC',
      );
      return maps.map(ChatTurn.fromMap).toList(growable: false);
    } catch (e) {
      Logger.e(_tag, '按分组获取 turns 失败', e);
      rethrow;
    }
  }

  @override
  Future<void> updateTurn(ChatTurn turn) async {
    try {
      final db = await database;
      await db.update(
        'chat_turns',
        _encodeTurnMap(turn.toMap()),
        where: 'id = ?',
        whereArgs: [turn.id],
      );
    } catch (e) {
      Logger.e(_tag, '更新 turn 失败', e);
      rethrow;
    }
  }

  @override
  Future<int> insertTurnStep(ChatTurnStep step) async {
    try {
      final db = await database;
      return await db.insert(
        'chat_turn_steps',
        step.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      Logger.e(_tag, '插入 turn step 失败', e);
      rethrow;
    }
  }

  @override
  Future<ChatTurnStep?> getTurnStep(int id) async {
    try {
      final db = await database;
      final maps = await db.query(
        'chat_turn_steps',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (maps.isEmpty) {
        return null;
      }
      return ChatTurnStep.fromMap(maps.first);
    } catch (e) {
      Logger.e(_tag, '获取 turn step 失败', e);
      rethrow;
    }
  }

  @override
  Future<List<ChatTurnStep>> getTurnSteps(int turnId) async {
    try {
      final db = await database;
      final maps = await db.query(
        'chat_turn_steps',
        where: 'turn_id = ?',
        whereArgs: [turnId],
        orderBy: 'step_index ASC',
      );
      return maps.map(ChatTurnStep.fromMap).toList();
    } catch (e) {
      Logger.e(_tag, '获取 turn steps 失败', e);
      rethrow;
    }
  }

  @override
  Future<void> updateTurnStep(ChatTurnStep step) async {
    try {
      final db = await database;
      await db.update(
        'chat_turn_steps',
        step.toMap(),
        where: 'id = ?',
        whereArgs: [step.id],
      );
    } catch (e) {
      Logger.e(_tag, '更新 turn step 失败', e);
      rethrow;
    }
  }

  @override
  Future<int> insertOrReplaceArtifactRecord(ArtifactRecord record) async {
    try {
      final db = await database;
      return await db.insert(
        'artifact_registry',
        record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      Logger.e(_tag, '插入 artifact registry 失败', e);
      rethrow;
    }
  }

  @override
  Future<ArtifactRecord?> getArtifactRecord({
    required int groupId,
    required String artifactId,
  }) async {
    try {
      final db = await database;
      final maps = await db.query(
        'artifact_registry',
        where: 'group_id = ? AND artifact_id = ?',
        whereArgs: [groupId, artifactId],
        limit: 1,
      );
      if (maps.isEmpty) {
        return null;
      }
      return ArtifactRecord.fromMap(maps.first);
    } catch (e) {
      Logger.e(_tag, '获取 artifact registry 失败', e);
      rethrow;
    }
  }

  @override
  Future<ArtifactRecord?> getArtifactRecordByPath({
    required int groupId,
    required String sourcePath,
  }) async {
    try {
      final db = await database;
      final maps = await db.query(
        'artifact_registry',
        where: 'group_id = ? AND source_path = ?',
        whereArgs: [groupId, sourcePath],
        limit: 1,
      );
      if (maps.isEmpty) {
        return null;
      }
      return ArtifactRecord.fromMap(maps.first);
    } catch (e) {
      Logger.e(_tag, '按路径获取 artifact registry 失败', e);
      rethrow;
    }
  }

  @override
  Future<List<ArtifactRecord>> listArtifactRecordsForGroup(int groupId) async {
    try {
      final db = await database;
      final maps = await db.query(
        'artifact_registry',
        where: 'group_id = ?',
        whereArgs: [groupId],
        orderBy: 'created_at ASC, id ASC',
      );
      return maps.map(ArtifactRecord.fromMap).toList(growable: false);
    } catch (e) {
      Logger.e(_tag, '列出 artifact registry 失败', e);
      rethrow;
    }
  }

  @override
  Future<void> updateArtifactRecord(ArtifactRecord record) async {
    try {
      final db = await database;
      await db.update(
        'artifact_registry',
        record.toMap(),
        where: 'id = ?',
        whereArgs: [record.id],
      );
    } catch (e) {
      Logger.e(_tag, '更新 artifact registry 失败', e);
      rethrow;
    }
  }

  @override
  Future<int> insertEvent(ChatEvent event) async {
    try {
      final db = await database;
      return await db.insert(
        'chat_events',
        event.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    } catch (e) {
      Logger.e(_tag, '插入 event 失败', e);
      rethrow;
    }
  }

  @override
  Future<int> getNextEventSequence(int turnId) async {
    try {
      final db = await database;
      final rows = await db.rawQuery(
        'SELECT COALESCE(MAX(sequence), 0) + 1 AS next FROM chat_events WHERE turn_id = ?',
        [turnId],
      );
      if (rows.isEmpty) {
        return 1;
      }
      final value = rows.first['next'];
      if (value is int) {
        return value;
      }
      return int.tryParse(value?.toString() ?? '') ?? 1;
    } catch (e) {
      Logger.e(_tag, '读取 event sequence 失败', e);
      rethrow;
    }
  }

  @override
  Future<List<ChatEvent>> getEventsByTurn(int turnId) async {
    try {
      final db = await database;
      final maps = await db.query(
        'chat_events',
        where: 'turn_id = ?',
        whereArgs: [turnId],
        orderBy: 'sequence ASC',
      );
      return maps.map(ChatEvent.fromMap).toList();
    } catch (e) {
      Logger.e(_tag, '获取 turn events 失败', e);
      rethrow;
    }
  }

  @override
  Future<List<ChatEvent>> getEventsByGroup(int groupId) async {
    try {
      final db = await database;
      final maps = await db.query(
        'chat_events',
        where: 'group_id = ?',
        whereArgs: [groupId],
        orderBy: 'created_at ASC, sequence ASC, id ASC',
      );
      return maps.map(ChatEvent.fromMap).toList(growable: false);
    } catch (e) {
      Logger.e(_tag, '按分组获取 events 失败', e);
      rethrow;
    }
  }

  // 消息相关操作（更新为支持分组）
  @override
  Future<int> insertMessage(ChatMessage message, int groupId) async {
    try {
      final db = await database;
      final map = message.toMap();
      map['group_id'] = groupId;

      final id = await db.insert(
        'messages',
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 更新分组的最后消息时间
      await updateGroupLastMessageTime(groupId);

      return id;
    } catch (e) {
      Logger.e(_tag, '插入消息失败', e);
      rethrow;
    }
  }

  @override
  Future<void> insertMessageAttachments(
    int messageId,
    List<ChatAttachment> attachments,
  ) async {
    try {
      final db = await database;
      await db.delete(
        'message_attachments',
        where: 'message_id = ?',
        whereArgs: [messageId],
      );
      for (final attachment in attachments) {
        await db.insert(
          'message_attachments',
          attachment.toDatabaseMap(messageId: messageId),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    } catch (e) {
      Logger.e(_tag, '插入消息附件失败', e);
      rethrow;
    }
  }

  @override
  Future<List<ChatAttachment>> getMessageAttachments(int messageId) async {
    try {
      final db = await database;
      final maps = await db.query(
        'message_attachments',
        where: 'message_id = ?',
        whereArgs: [messageId],
        orderBy: 'created_at ASC, id ASC',
      );
      return maps
          .map((map) => ChatAttachment.fromDatabaseMap(map))
          .toList(growable: false);
    } catch (e) {
      Logger.e(_tag, '获取消息附件失败', e);
      rethrow;
    }
  }

  @override
  Future<int> insertSessionContextSnapshot(
      SessionContextSnapshot snapshot) async {
    try {
      final db = await database;
      return await db.insert(
        'session_context_snapshots',
        snapshot.toMap(),
      );
    } catch (e) {
      Logger.e(_tag, '插入 Session 上下文快照失败', e);
      rethrow;
    }
  }

  @override
  Future<SessionContextSnapshot?> getLatestSessionContextSnapshotByGroup(
    int groupId,
  ) async {
    try {
      final db = await database;
      final maps = await db.query(
        'session_context_snapshots',
        where: 'group_id = ?',
        whereArgs: [groupId],
        orderBy: 'updated_at DESC, id DESC',
        limit: 1,
      );
      if (maps.isEmpty) {
        return null;
      }
      return SessionContextSnapshot.fromMap(maps.first);
    } catch (e) {
      Logger.e(_tag, '获取最新 Session 上下文快照失败', e);
      rethrow;
    }
  }

  @override
  Future<void> updateSessionContextSnapshot(
    SessionContextSnapshot snapshot,
  ) async {
    try {
      if (snapshot.id == null) {
        throw ArgumentError('SessionContextSnapshot.id is required for update');
      }
      final db = await database;
      await db.update(
        'session_context_snapshots',
        snapshot.toMap(),
        where: 'id = ?',
        whereArgs: [snapshot.id],
      );
    } catch (e) {
      Logger.e(_tag, '更新 Session 上下文快照失败', e);
      rethrow;
    }
  }

  @override
  Future<int> insertSessionRuntimeConfig(SessionRuntimeConfig config) async {
    try {
      final db = await database;
      return await db.insert(
        'session_runtime_configs',
        config.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      Logger.e(_tag, '插入 Session Runtime Config 失败', e);
      rethrow;
    }
  }

  @override
  Future<SessionRuntimeConfig?> getSessionRuntimeConfigByGroup(
    int groupId,
  ) async {
    try {
      final db = await database;
      final maps = await db.query(
        'session_runtime_configs',
        where: 'group_id = ?',
        whereArgs: [groupId],
        orderBy: 'updated_at DESC, id DESC',
        limit: 1,
      );
      if (maps.isEmpty) {
        return null;
      }
      return SessionRuntimeConfig.fromMap(maps.first);
    } catch (e) {
      Logger.e(_tag, '获取 Session Runtime Config 失败', e);
      rethrow;
    }
  }

  @override
  Future<void> updateSessionRuntimeConfig(SessionRuntimeConfig config) async {
    try {
      if (config.id == null) {
        throw ArgumentError('SessionRuntimeConfig.id is required for update');
      }
      final db = await database;
      await db.update(
        'session_runtime_configs',
        config.toMap(),
        where: 'id = ?',
        whereArgs: [config.id],
      );
    } catch (e) {
      Logger.e(_tag, '更新 Session Runtime Config 失败', e);
      rethrow;
    }
  }

  @override
  Future<int> insertSessionRuntimeMarker(SessionRuntimeMarker marker) async {
    try {
      final db = await database;
      return await db.insert(
        'session_runtime_markers',
        marker.toMap(),
      );
    } catch (e) {
      Logger.e(_tag, '插入 Session 运行时标记失败', e);
      rethrow;
    }
  }

  @override
  Future<SessionRuntimeMarker?> getLatestSessionRuntimeMarkerByGroup(
    int groupId,
  ) async {
    try {
      final db = await database;
      final maps = await db.query(
        'session_runtime_markers',
        where: 'group_id = ?',
        whereArgs: [groupId],
        orderBy: 'updated_at DESC, id DESC',
        limit: 1,
      );
      if (maps.isEmpty) {
        return null;
      }
      return SessionRuntimeMarker.fromMap(maps.first);
    } catch (e) {
      Logger.e(_tag, '获取最新 Session 运行时标记失败', e);
      rethrow;
    }
  }

  @override
  Future<void> updateSessionRuntimeMarker(
    SessionRuntimeMarker marker,
  ) async {
    try {
      if (marker.id == null) {
        throw ArgumentError('SessionRuntimeMarker.id is required for update');
      }
      final db = await database;
      await db.update(
        'session_runtime_markers',
        marker.toMap(),
        where: 'id = ?',
        whereArgs: [marker.id],
      );
    } catch (e) {
      Logger.e(_tag, '更新 Session 运行时标记失败', e);
      rethrow;
    }
  }

  @override
  Future<List<ChatMessage>> getMessagesByGroup(int groupId) async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        'messages',
        where: 'group_id = ?',
        whereArgs: [groupId],
        orderBy: 'timestamp DESC',
        limit: 20,
      );
      final messages = <ChatMessage>[];
      for (final map in maps) {
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
        messages.add(
          message.copyWith(
            attachments: attachments,
            referenceJson: nextReferenceJson.isEmpty ? null : nextReferenceJson,
          ),
        );
      }
      return messages.reversed.toList();
    } catch (e) {
      Logger.e(_tag, '获取分组消息失败', e);
      rethrow;
    }
  }

  @override
  Future<List<ChatMessage>> getMessagesByGroupWithPagination({
    required int groupId,
    required int limit,
    required int offset,
  }) async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        'messages',
        where: 'group_id = ?',
        whereArgs: [groupId],
        orderBy: 'timestamp DESC',
        limit: limit,
        offset: offset,
      );
      final messages = <ChatMessage>[];
      for (final map in maps) {
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
        messages.add(
          message.copyWith(
            attachments: attachments,
            referenceJson: nextReferenceJson.isEmpty ? null : nextReferenceJson,
          ),
        );
      }
      return messages.reversed.toList();
    } catch (e) {
      Logger.e(_tag, '分页获取分组消息失败', e);
      rethrow;
    }
  }

  @override
  Future<int> getGroupMessageCount(int groupId) async {
    try {
      final db = await database;
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM messages WHERE group_id = ?',
        [groupId],
      );
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      Logger.e(_tag, '获取分组消息数量失败', e);
      rethrow;
    }
  }

  @override
  Future<void> deleteGroupMessages(int groupId) async {
    try {
      final db = await database;
      await db.delete(
        'messages',
        where: 'group_id = ?',
        whereArgs: [groupId],
      );
    } catch (e) {
      Logger.e(_tag, '删除分组消息失败', e);
      rethrow;
    }
  }

  Future<List<ChatMessage>> getMessages() async {
    try {
      Logger.d(_tag, '开始加载历史消息...');
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        'messages',
        orderBy: 'timestamp DESC',
        limit: 20, // 默认加载最新的20条消息
      );

      Logger.i(_tag, '成功加载 ${maps.length} 条历史消息');
      return List.generate(maps.length, (i) {
        return ChatMessage.fromMap(maps[i]);
      });
    } catch (e, stackTrace) {
      Logger.e(_tag, '加载历史消息失败', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      rethrow;
    }
  }

  Future<List<ChatMessage>> getMessagesWithPagination({
    required int limit,
    required int offset,
  }) async {
    try {
      Logger.d(_tag, '开始分页加载历史消息...');
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        'messages',
        orderBy: 'timestamp DESC',
        limit: limit,
        offset: offset,
      );

      Logger.i(_tag, '成功加载 ${maps.length} 条历史消息');
      return List.generate(maps.length, (i) {
        return ChatMessage.fromMap(maps[i]);
      });
    } catch (e, stackTrace) {
      Logger.e(_tag, '分页加载历史消息失败', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      rethrow;
    }
  }

  Future<int> getTotalMessageCount() async {
    try {
      final db = await database;
      final result =
          await db.rawQuery('SELECT COUNT(*) as count FROM messages');
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      Logger.e(_tag, '获取消息总数失败', e);
      rethrow;
    }
  }

  Future<void> deleteAllMessages() async {
    try {
      Logger.w(_tag, '开始清除所有消息...');
      final db = await database;
      await db.delete('messages');
      Logger.i(_tag, '所有消息已清除');
    } catch (e, stackTrace) {
      Logger.e(_tag, '清除消息失败', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      rethrow;
    }
  }

  Future<void> updateMessage(int id, String newText) async {
    try {
      final db = await database;
      await db.update(
        'messages',
        {'text': newText},
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e, stackTrace) {
      Logger.e(_tag, '更新消息失败', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      rethrow;
    }
  }

  Future<void> updateMessageReasoning(int id, String? reasoningContent) async {
    try {
      Logger.d(_tag, '更新消息推理内容 ID: $id');
      Logger.d(_tag,
          '新推理内容: ${reasoningContent?.substring(0, reasoningContent.length.clamp(0, 50))}...');

      final db = await database;
      await db.update(
        'messages',
        {'reasoning_content': reasoningContent},
        where: 'id = ?',
        whereArgs: [id],
      );

      Logger.i(_tag, '消息推理内容更新成功');
    } catch (e, stackTrace) {
      Logger.e(_tag, '更新消息推理内容失败', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      rethrow;
    }
  }

  Future<bool> testDatabaseConnection() async {
    try {
      final db = await database;
      await db.rawQuery('SELECT 1');
      Logger.i(_tag, '数据库连接测试成功');
      return true;
    } catch (e) {
      Logger.e(_tag, '数据库连接测试失败', e);
      return false;
    }
  }

  Map<String, dynamic> _encodeTurnMap(Map<String, dynamic> map) {
    final encoded = Map<String, dynamic>.from(map);
    final providerState = encoded['provider_state_json'];
    if (providerState is Map) {
      encoded['provider_state_json'] = jsonEncode(providerState);
    }
    return encoded;
  }

  Map<String, dynamic> _decodeTurnMap(Map<String, dynamic> map) {
    final decoded = Map<String, dynamic>.from(map);
    final providerState = decoded['provider_state_json'];
    if (providerState is String && providerState.trim().isNotEmpty) {
      decoded['provider_state_json'] = jsonDecode(providerState);
    }
    return decoded;
  }

  Future<void> updateMessageStatus(int id, MessageStatus status) async {
    try {
      final db = await database;

      await db.update(
        'messages',
        {'status': status.toString().split('.').last},
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e, stackTrace) {
      Logger.e(_tag, '更新消息状态失败', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      rethrow;
    }
  }

  Future<void> updateStructuredMessage(
    int id, {
    required String text,
    required MessageStatus status,
    required MessageContentType contentType,
    String? payloadJson,
  }) async {
    try {
      final db = await database;
      await db.update(
        'messages',
        {
          'text': text,
          'status': status.toString().split('.').last,
          'content_type': contentType.wireName,
          'payload_json': payloadJson,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e, stackTrace) {
      Logger.e(_tag, '更新结构化消息失败', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      rethrow;
    }
  }

  Future<void> deleteMessage(int id) async {
    try {
      Logger.w(_tag, '删除消息 ID: $id');
      final db = await database;
      await db.delete(
        'messages',
        where: 'id = ?',
        whereArgs: [id],
      );
      Logger.i(_tag, '消息删除成功');
    } catch (e, stackTrace) {
      Logger.e(_tag, '删除消息失败', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      rethrow;
    }
  }
}
