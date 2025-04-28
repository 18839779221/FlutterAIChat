import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/chat_message.dart';
import '../utils/logger.dart';

class DatabaseHelper {
  static const String _tag = 'DatabaseHelper';
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    Logger.i(_tag, '初始化数据库...');
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    try {
      String path = join(await getDatabasesPath(), 'chat_history.db');
      Logger.d(_tag, '数据库路径: $path');
      
      return await openDatabase(
        path,
        version: 2,
        onCreate: (Database db, int version) async {
          Logger.i(_tag, '创建数据库表...');
          await db.execute('''
            CREATE TABLE messages (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              text TEXT NOT NULL,
              role TEXT NOT NULL,
              timestamp INTEGER NOT NULL,
              status TEXT NOT NULL DEFAULT 'initial'
            )
          ''');
          Logger.i(_tag, '数据库表创建成功');
        },
        onUpgrade: (Database db, int oldVersion, int newVersion) async {
          if (oldVersion < 2) {
            await db.execute('''
              ALTER TABLE messages 
              ADD COLUMN status TEXT NOT NULL DEFAULT 'initial'
            ''');
          }
        },
      );
    } catch (e, stackTrace) {
      Logger.e(_tag, '初始化数据库失败', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
      rethrow;
    }
  }

  Future<int> insertMessage(ChatMessage message) async {
    try {
      final db = await database;
      Logger.d(_tag, '插入消息: ${message.text.substring(0, message.text.length.clamp(0, 50))}...');
      
      final id = await db.insert(
        'messages',
        message.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      Logger.i(_tag, '消息插入成功，ID: $id');
      return id;
    } catch (e, stackTrace) {
      Logger.e(_tag, '插入消息失败', e);
      Logger.e(_tag, '堆栈跟踪', stackTrace);
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
      }); // 反转列表以保持时间顺序
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
} 