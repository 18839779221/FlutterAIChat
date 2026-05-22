import 'dart:io';

import 'package:ai_chat/database/database_helper.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/session/session_context_snapshot.dart';
import 'package:ai_chat/models/session/session_runtime_marker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
      'DatabaseHelper schema includes turn, step, event, snapshot and runtime marker tables in v11',
      () {
    final source = File('lib/database/database_helper.dart').readAsStringSync();

    expect(source, contains('version: 11'));
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
    expect(
      source,
      contains(
          RegExp(r'CREATE TABLE IF NOT EXISTS session_context_snapshots \(')),
    );
    expect(
      source,
      contains(
          RegExp(r'CREATE TABLE IF NOT EXISTS session_runtime_markers \(')),
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
    expect(source, contains('if (oldVersion < 10)'));
    expect(source, contains('if (oldVersion < 11)'));
  });

  test(
      'DatabaseHelper creates turn, step, event, snapshot and runtime marker tables with required indexes',
      () async {
    final helper = DatabaseHelper(databaseName: 'database_helper_test_v11.db');
    final db = await helper.database;

    final tables = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table' AND name IN ('chat_turns', 'chat_turn_steps', 'chat_events', 'session_context_snapshots', 'session_runtime_markers')
      ORDER BY name
    ''');

    expect(
      tables.map((row) => row['name']).toList(),
      [
        'chat_events',
        'chat_turn_steps',
        'chat_turns',
        'session_context_snapshots',
        'session_runtime_markers',
      ],
    );

    final indexes = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'index'
        AND name IN (
          'idx_chat_events_turn_id_sequence',
          'idx_chat_turn_steps_turn_id_step_index',
          'idx_session_context_snapshots_group_id_updated_at',
          'idx_session_runtime_markers_group_id_updated_at'
        )
      ORDER BY name
    ''');

    expect(
      indexes.map((row) => row['name']).toList(),
      [
        'idx_chat_events_turn_id_sequence',
        'idx_chat_turn_steps_turn_id_step_index',
        'idx_session_context_snapshots_group_id_updated_at',
        'idx_session_runtime_markers_group_id_updated_at',
      ],
    );

    final groupId =
        await helper.insertGroup(ChatGroup(title: 'agent loop schema group', lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions));
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
        'tool_name': 'Write',
        'tool_args_json': '{"title":"数据库版本确认"}',
        'status': 'planned',
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }),
      throwsA(isA<Exception>()),
    );

    await helper.deleteGroup(groupId);
  });

  test('DatabaseHelper can persist and update session context snapshots',
      () async {
    final helper =
        DatabaseHelper(databaseName: 'database_helper_snapshot_roundtrip.db');
    final groupId =
        await helper.insertGroup(ChatGroup(title: 'session snapshot group', lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions));

    final snapshotId = await helper.insertSessionContextSnapshot(
      SessionContextSnapshot(
        groupId: groupId,
        summaryText: '当前目标：接入 SessionContextService',
        coveredUntilTurnId: 8,
        estimatedTokens: 90,
      ),
    );

    final created =
        await helper.getLatestSessionContextSnapshotByGroup(groupId);
    expect(created, isNotNull);
    expect(created!.id, snapshotId);
    expect(created.coveredUntilTurnId, 8);

    await helper.updateSessionContextSnapshot(
      created.copyWith(
        summaryText: '当前目标：接入 SessionContextService 并补测试',
        coveredUntilTurnId: 11,
        estimatedTokens: 120,
      ),
    );

    final updated =
        await helper.getLatestSessionContextSnapshotByGroup(groupId);
    expect(updated, isNotNull);
    expect(updated!.summaryText, contains('补测试'));
    expect(updated.coveredUntilTurnId, 11);
    expect(updated.estimatedTokens, 120);

    await helper.deleteGroup(groupId);
  });

  test('DatabaseHelper can persist and update session runtime markers',
      () async {
    final helper =
        DatabaseHelper(databaseName: 'database_helper_runtime_marker.db');
    final groupId =
        await helper.insertGroup(ChatGroup(title: 'runtime marker group', lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions));

    final markerId = await helper.insertSessionRuntimeMarker(
      SessionRuntimeMarker(
        groupId: groupId,
        lastInjectedDate: '2026-04-24',
      ),
    );

    final created = await helper.getLatestSessionRuntimeMarkerByGroup(groupId);
    expect(created, isNotNull);
    expect(created!.id, markerId);
    expect(created.lastInjectedDate, '2026-04-24');

    await helper.updateSessionRuntimeMarker(
      created.copyWith(
        lastInjectedDate: '2026-04-25',
      ),
    );

    final updated = await helper.getLatestSessionRuntimeMarkerByGroup(groupId);
    expect(updated, isNotNull);
    expect(updated!.lastInjectedDate, '2026-04-25');

    await helper.deleteGroup(groupId);
  });

  test(
      'DatabaseHelper upgrades v9 db and adds session context snapshot and runtime marker tables',
      () async {
    const dbName = 'database_helper_upgrade_v9_to_v11.db';
    final dbPath = p.join(await getDatabasesPath(), dbName);
    await databaseFactory.deleteDatabase(dbPath);

    final seedDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 9,
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
          await db.execute('''
            CREATE UNIQUE INDEX idx_chat_turn_steps_turn_id_step_index
            ON chat_turn_steps(turn_id, step_index)
          ''');
          await db.execute('''
            CREATE UNIQUE INDEX idx_chat_events_turn_id_sequence
            ON chat_events(turn_id, sequence)
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
    final snapshotTables = await db.rawQuery("""
      SELECT name FROM sqlite_master
      WHERE type = 'table' AND name = 'session_context_snapshots'
    """);
    expect(snapshotTables, hasLength(1));
    final runtimeMarkerTables = await db.rawQuery("""
      SELECT name FROM sqlite_master
      WHERE type = 'table' AND name = 'session_runtime_markers'
    """);
    expect(runtimeMarkerTables, hasLength(1));
  });
}
