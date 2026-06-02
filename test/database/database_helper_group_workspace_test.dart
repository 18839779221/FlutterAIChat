import 'dart:io';

import 'package:ai_chat/database/database_helper.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('new database schema includes nullable chat_groups.workspace_id', () async {
    final helper = DatabaseHelper(
      databaseName: 'database_helper_group_workspace_schema.db',
    );
    final db = await helper.database;
    final tableInfo = await db.rawQuery('PRAGMA table_info(chat_groups)');
    final workspaceColumn = tableInfo.firstWhere(
      (row) => row['name'] == 'workspace_id',
    );

    expect(workspaceColumn['type'], 'TEXT');
    expect(workspaceColumn['notnull'], 0);
  });

  test('group round-trip persists workspace_id when provided', () async {
    final helper = DatabaseHelper(
      databaseName: 'database_helper_group_workspace_roundtrip.db',
    );
    final groupId = await helper.insertGroup(
      ChatGroup(
        title: 'Workspace group',
        lockedProviderStyle: ChatTurnProviderStyle.openaiResponses,
        workspaceId: 'ws_20260602_a3k9qx',
      ),
    );

    final stored = await helper.getGroupById(groupId);
    expect(stored, isNotNull);
    expect(stored!.workspaceId, 'ws_20260602_a3k9qx');
  });

  test('upgrade from v14 adds nullable workspace_id to chat_groups', () async {
    const dbName = 'database_helper_upgrade_v14_to_v15_workspace.db';
    final dbPath = p.join(await getDatabasesPath(), dbName);
    await databaseFactory.deleteDatabase(dbPath);

    final seedDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 14,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE chat_groups (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              last_message_at INTEGER NOT NULL,
              system_prompt TEXT,
              is_summarized INTEGER NOT NULL DEFAULT 0,
              locked_provider_style TEXT NOT NULL
            )
          ''');
          await db.insert('chat_groups', {
            'title': 'Legacy group',
            'created_at': 1,
            'last_message_at': 1,
            'system_prompt': null,
            'is_summarized': 0,
            'locked_provider_style': ChatTurnProviderStyle.openaiResponses.name,
          });
        },
      ),
    );
    await seedDb.close();

    final helper = DatabaseHelper(databaseName: dbName);
    final db = await helper.database;
    final tableInfo = await db.rawQuery('PRAGMA table_info(chat_groups)');
    final workspaceColumn = tableInfo.firstWhere(
      (row) => row['name'] == 'workspace_id',
    );
    final rows = await db.query('chat_groups');

    expect(workspaceColumn['type'], 'TEXT');
    expect(rows.single['workspace_id'], isNull);
  });

  tearDown(() async {
    for (final name in <String>[
      'database_helper_group_workspace_schema.db',
      'database_helper_group_workspace_roundtrip.db',
      'database_helper_upgrade_v14_to_v15_workspace.db',
    ]) {
      final dbPath = p.join(await getDatabasesPath(), name);
      if (File(dbPath).existsSync()) {
        await databaseFactory.deleteDatabase(dbPath);
      }
    }
  });
}
