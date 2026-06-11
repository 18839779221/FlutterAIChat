import 'package:ai_chat/database/database_helper.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/session/session_context_snapshot.dart';
import 'package:ai_chat/repositories/session_context_snapshot_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SessionContextSnapshotRepository', () {
    test('can persist and reload latest session context snapshot by group',
        () async {
      final storage = DatabaseHelper(
        databaseName: 'session_context_snapshot_repository_test.db',
      );
      final repository = SessionContextSnapshotRepository(storage);
      final groupId = await storage.insertGroup(
        ChatGroup(title: 'Session Context', lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions),
      );

      final id = await repository.upsertLatest(
        SessionContextSnapshot(
          groupId: groupId,
          summaryText: '当前目标：实现 Session 上下文管理',
          coveredUntilTurnId: 12,
          estimatedTokens: 180,
        ),
      );

      final snapshot = await repository.getLatestByGroup(groupId);

      expect(id, greaterThan(0));
      expect(snapshot, isNotNull);
      expect(snapshot!.coveredUntilTurnId, 12);
      expect(snapshot.summaryText, contains('Session 上下文管理'));

      await storage.deleteGroup(groupId);
    });

    test('upsert updates existing latest snapshot for the same group',
        () async {
      final storage = DatabaseHelper(
        databaseName: 'session_context_snapshot_repository_upsert_test.db',
      );
      final repository = SessionContextSnapshotRepository(storage);
      final groupId = await storage.insertGroup(
        ChatGroup(title: 'Session Context Upsert', lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions),
      );

      final firstId = await repository.upsertLatest(
        SessionContextSnapshot(
          groupId: groupId,
          summaryText: '当前目标：先建表',
          coveredUntilTurnId: 5,
          estimatedTokens: 80,
        ),
      );
      final secondId = await repository.upsertLatest(
        SessionContextSnapshot(
          groupId: groupId,
          summaryText: '当前目标：补齐 snapshot repository',
          coveredUntilTurnId: 9,
          estimatedTokens: 120,
        ),
      );

      final snapshot = await repository.getLatestByGroup(groupId);

      expect(secondId, firstId);
      expect(snapshot, isNotNull);
      expect(snapshot!.summaryText, contains('snapshot repository'));
      expect(snapshot.coveredUntilTurnId, 9);

      await storage.deleteGroup(groupId);
    });

    test('persists partial-turn compaction boundary with coveredUntilEventId',
        () async {
      final storage = DatabaseHelper(
        databaseName:
            'session_context_snapshot_repository_partial_turn_test.db',
      );
      final repository = SessionContextSnapshotRepository(storage);
      final groupId = await storage.insertGroup(
        ChatGroup(
            title: 'Session Context Partial Turn',
            lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions),
      );

      final id = await repository.upsertLatest(
        SessionContextSnapshot(
          groupId: groupId,
          summaryText: '当前目标：继续处理 active turn',
          coveredUntilTurnId: 12,
          coveredUntilEventId: 1205,
          estimatedTokens: 180,
        ),
      );

      final snapshot = await repository.getLatestByGroup(groupId);

      expect(id, greaterThan(0));
      expect(snapshot, isNotNull);
      expect(snapshot!.coveredUntilTurnId, 12);
      expect(snapshot.coveredUntilEventId, 1205);

      await storage.deleteGroup(groupId);
    });
  });
}
