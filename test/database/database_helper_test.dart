import 'dart:io';

import 'package:ai_chat/database/database_helper.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('DatabaseHelper schema includes turn, step and event tables in v9', () {
    final source = File('lib/database/database_helper.dart').readAsStringSync();

    expect(source, contains('version: 9'));
    expect(
      source,
      contains(RegExp(r'CREATE TABLE chat_turns \(')),
    );
    expect(
      source,
      contains(RegExp(r'CREATE TABLE chat_turn_steps \(')),
    );
    expect(
      source,
      contains(RegExp(r'CREATE TABLE chat_events \(')),
    );
    expect(source, contains(RegExp(r'sequence INTEGER NOT NULL')));
    expect(source, contains(RegExp(r'provider_style TEXT')));
    expect(source, contains(RegExp(r'provider_state_json TEXT')));
    expect(source, contains(RegExp(r'provider_response_id TEXT')));
    expect(
      source,
      contains(
        RegExp(
            r'CREATE (UNIQUE )?INDEX idx_chat_turn_steps_turn_id_step_index'),
      ),
    );
    expect(
      source,
      contains(RegExp(r'CREATE UNIQUE INDEX idx_chat_events_turn_id_sequence')),
    );
    expect(source, contains('if (oldVersion < 9)'));
  });

  test(
      'DatabaseHelper creates turn, step and event tables with required indexes',
      () async {
    final helper = DatabaseHelper(databaseName: 'database_helper_test_v9.db');
    final db = await helper.database;

    final tables = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table' AND name IN ('chat_turns', 'chat_turn_steps', 'chat_events')
      ORDER BY name
    ''');

    expect(
      tables.map((row) => row['name']).toList(),
      ['chat_events', 'chat_turn_steps', 'chat_turns'],
    );

    final indexes = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'index'
        AND name IN (
          'idx_chat_events_turn_id_sequence',
          'idx_chat_turn_steps_turn_id_step_index'
        )
      ORDER BY name
    ''');

    expect(
      indexes.map((row) => row['name']).toList(),
      [
        'idx_chat_events_turn_id_sequence',
        'idx_chat_turn_steps_turn_id_step_index'
      ],
    );

    final groupId =
        await helper.insertGroup(ChatGroup(title: 'agent loop schema group'));
    final turnId = await db.insert('chat_turns', {
      'group_id': groupId,
      'status': 'running',
      'user_input': '测试 agent turn',
      'goal_summary': '验证步骤账本',
      'iteration_count': 0,
      'tool_call_count': 0,
      'provider_style': 'openai_responses',
      'model_name': 'gpt-5.4',
      'provider_state_json': '{"response_id":"resp_123"}',
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });

    await db.insert('chat_turn_steps', {
      'turn_id': turnId,
      'step_index': 1,
      'provider_response_id': 'resp_123',
      'tool_name': 'search_chat_history',
      'tool_args_json': '{"query":"数据库版本"}',
      'status': 'planned',
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });

    await db.insert('chat_events', {
      'turn_id': turnId,
      'group_id': groupId,
      'sequence': 1,
      'event_type': 'userMessage',
      'role': 'user',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });

    expect(
      () => db.insert('chat_events', {
        'turn_id': turnId,
        'group_id': groupId,
        'sequence': 1,
        'event_type': 'assistantTextDelta',
        'role': 'assistant',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      }),
      throwsA(isA<Exception>()),
    );

    expect(
      () => db.insert('chat_turn_steps', {
        'turn_id': turnId,
        'step_index': 1,
        'tool_name': 'save_note',
        'tool_args_json': '{"title":"数据库版本确认"}',
        'status': 'planned',
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }),
      throwsA(isA<Exception>()),
    );

    await helper.deleteGroup(groupId);
  });

  test('DatabaseHelper upgrades v8 db without duplicating provider_response_id',
      () async {
    const dbName = 'database_helper_upgrade_v8_to_v9.db';
    final dbPath = p.join(await getDatabasesPath(), dbName);
    await databaseFactory.deleteDatabase(dbPath);

    final seedDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 8,
        onCreate: (db, version) async {
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
              reference_json TEXT
            )
          ''');
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
              completed_at INTEGER
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
              completed_at INTEGER
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
              created_at INTEGER NOT NULL
            )
          ''');
        },
      ),
    );
    await seedDb.close();

    final helper = DatabaseHelper(databaseName: dbName);
    final db = await helper.database;
    final columns = await db.rawQuery('PRAGMA table_info(chat_turn_steps)');
    final providerColumns = columns
        .where((row) => row['name'] == 'provider_response_id')
        .toList(growable: false);

    expect(providerColumns, hasLength(1));
  });
}
