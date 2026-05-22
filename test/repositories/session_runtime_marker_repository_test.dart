import 'package:ai_chat/database/database_helper.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/models/session/session_runtime_marker.dart';
import 'package:ai_chat/repositories/session_runtime_marker_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SessionRuntimeMarkerRepository', () {
    test('persists and reloads latest injected date for a group', () async {
      final storage = DatabaseHelper(
        databaseName: 'session_runtime_marker_repository_test.db',
      );
      final repository = SessionRuntimeMarkerRepository(storage);
      final groupId = await storage.insertGroup(
        ChatGroup(title: 'Date Aware Session', lockedProviderStyle: ChatTurnProviderStyle.openaiChatCompletions),
      );

      await repository.upsertLatest(
        SessionRuntimeMarker(
          groupId: groupId,
          lastInjectedDate: '2026-04-24',
        ),
      );

      final marker = await repository.getLatestByGroup(groupId);

      expect(marker, isNotNull);
      expect(marker!.lastInjectedDate, '2026-04-24');

      await storage.deleteGroup(groupId);
    });
  });
}
