import 'dart:io';

import 'package:ai_chat/database/database_helper.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('DatabaseHelper schema includes turn and event tables in v7', () {
    final source = File('lib/database/database_helper.dart').readAsStringSync();

    expect(source, contains('version: 7'));
    expect(
      source,
      contains(RegExp(r'CREATE TABLE chat_turns \(')),
    );
    expect(
      source,
      contains(RegExp(r'CREATE TABLE chat_events \(')),
    );
    expect(source, contains(RegExp(r'sequence INTEGER NOT NULL')));
    expect(
      source,
      contains(RegExp(r'CREATE UNIQUE INDEX idx_chat_events_turn_id_sequence')),
    );
    expect(source, contains('if (oldVersion < 7)'));
  });

  test('DatabaseHelper creates turn and event tables with unique sequence per turn', () async {
    final helper = DatabaseHelper(databaseName: 'database_helper_test.db');
    final db = await helper.database;

    final tables = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table' AND name IN ('chat_turns', 'chat_events')
      ORDER BY name
    ''');

    expect(
      tables.map((row) => row['name']).toList(),
      ['chat_events', 'chat_turns'],
    );

    final indexes = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'index' AND name = 'idx_chat_events_turn_id_sequence'
    ''');

    expect(indexes, isNotEmpty);

    final groupId = await helper.insertGroup(ChatGroup(title: 'agent loop schema group'));
    final turnId = await db.insert('chat_turns', {
      'group_id': groupId,
      'status': 'running',
      'user_input': '测试 agent turn',
      'iteration_count': 0,
      'tool_call_count': 0,
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

    await helper.deleteGroup(groupId);
  });
}
