import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/chat_event.dart';
import '../models/chat_message.dart';
import '../models/response/message_content_type.dart';
import '../models/chat_group.dart';
import '../models/chat_turn.dart';
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
        version: 7,
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
              is_summarized INTEGER NOT NULL DEFAULT 0
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
          Logger.i(_tag, '数据库表创建成功');
        },
        onUpgrade: (Database db, int oldVersion, int newVersion) async {
          if (oldVersion < 2) {
            await db.execute('''
              ALTER TABLE messages 
              ADD COLUMN status TEXT NOT NULL DEFAULT 'initial'
            ''');
          }
          if (oldVersion < 3) {
            await db.execute('''
              ALTER TABLE messages 
              ADD COLUMN reasoning_content TEXT
            ''');
          }
          if (oldVersion < 4) {
            // 创建新表
            await db.execute('''
              CREATE TABLE chat_groups (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                last_message_at INTEGER NOT NULL,
                system_prompt TEXT,
                is_summarized INTEGER NOT NULL DEFAULT 0
              )
            ''');

            // 创建临时消息表
            await db.execute('''
              CREATE TABLE messages_new (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                group_id INTEGER NOT NULL,
                text TEXT NOT NULL,
                role TEXT NOT NULL,
                timestamp INTEGER NOT NULL,
                status TEXT NOT NULL DEFAULT 'initial',
                reasoning_content TEXT,
                FOREIGN KEY (group_id) REFERENCES chat_groups (id) ON DELETE CASCADE
              )
            ''');

            // 创建默认分组
            final defaultGroupId = await db.insert('chat_groups', {
              'title': '默认对话',
              'created_at': DateTime.now().millisecondsSinceEpoch,
              'last_message_at': DateTime.now().millisecondsSinceEpoch,
            });

            // 迁移现有消息到新表
            await db.execute('''
              INSERT INTO messages_new (group_id, text, role, timestamp, status, reasoning_content)
              SELECT ?, text, role, timestamp, status, reasoning_content FROM messages
            ''', [defaultGroupId]);

            // 删除旧表
            await db.execute('DROP TABLE messages');

            // 重命名新表
            await db.execute('ALTER TABLE messages_new RENAME TO messages');
          }
          if (oldVersion < 5) {
            // 添加 is_summarized 字段
            await db.execute('''
              ALTER TABLE chat_groups
              ADD COLUMN is_summarized INTEGER NOT NULL DEFAULT 0
            ''');
          }
          if (oldVersion < 6) {
            await db.execute('''
              ALTER TABLE messages 
              ADD COLUMN content_type TEXT NOT NULL DEFAULT 'plainText'
            ''');
            await db.execute('''
              ALTER TABLE messages 
              ADD COLUMN payload_json TEXT
            ''');
            await db.execute('''
              ALTER TABLE messages 
              ADD COLUMN reference_json TEXT
            ''');
          }
          if (oldVersion < 7) {
            await _createAgentLoopTables(db);
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
        iteration_count INTEGER NOT NULL DEFAULT 0,
        tool_call_count INTEGER NOT NULL DEFAULT 0,
        stop_reason TEXT,
        error_message TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        completed_at INTEGER,
        FOREIGN KEY (group_id) REFERENCES chat_groups (id) ON DELETE CASCADE
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

  Future<void> updateGroupSystemPrompt(int groupId, String? systemPrompt) async {
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

  Future<void> updateGroupTitle(int groupId, String title, {bool isSummarized = true}) async {
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
        turn.toMap(),
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
      return ChatTurn.fromMap(maps.first);
    } catch (e) {
      Logger.e(_tag, '获取 turn 失败', e);
      rethrow;
    }
  }

  @override
  Future<void> updateTurn(ChatTurn turn) async {
    try {
      final db = await database;
      await db.update(
        'chat_turns',
        turn.toMap(),
        where: 'id = ?',
        whereArgs: [turn.id],
      );
    } catch (e) {
      Logger.e(_tag, '更新 turn 失败', e);
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
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      Logger.e(_tag, '插入 event 失败', e);
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

  // 消息相关操作（更新为支持分组）
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
      final messages =
          List.generate(maps.length, (i) => ChatMessage.fromMap(maps[i]));
      return messages.reversed.toList();
    } catch (e) {
      Logger.e(_tag, '获取分组消息失败', e);
      rethrow;
    }
  }

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
      final messages =
          List.generate(maps.length, (i) => ChatMessage.fromMap(maps[i]));
      return messages.reversed.toList();
    } catch (e) {
      Logger.e(_tag, '分页获取分组消息失败', e);
      rethrow;
    }
  }

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
      final result = await db.rawQuery('SELECT COUNT(*) as count FROM messages');
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
      Logger.d(_tag, '更新消息 ID: $id');
      Logger.d(_tag, '新内容: ${newText.substring(0, newText.length.clamp(0, 50))}...');
      
      final db = await database;
      await db.update(
        'messages',
        {'text': newText},
        where: 'id = ?',
        whereArgs: [id],
      );
      
      Logger.i(_tag, '消息更新成功');
    } catch (e, stackTrace) {
      Logger.e(_tag, '更新消息失败', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      rethrow;
    }
  }

  Future<void> updateMessageReasoning(int id, String? reasoningContent) async {
    try {
      Logger.d(_tag, '更新消息推理内容 ID: $id');
      Logger.d(_tag, '新推理内容: ${reasoningContent?.substring(0, reasoningContent.length.clamp(0, 50))}...');
      
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

  Future<void> updateMessageStatus(int id, MessageStatus status) async {
    try {
      final db = await database;
      Logger.d(_tag, '更新消息状态: ID=$id, 状态=$status');
      
      await db.update(
        'messages',
        {'status': status.toString().split('.').last},
        where: 'id = ?',
        whereArgs: [id],
      );
      
      Logger.i(_tag, '消息状态更新成功');
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
