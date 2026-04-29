import 'package:ai_chat/database/database_helper.dart';
import 'package:ai_chat/models/artifact/artifact_record.dart';
import 'package:ai_chat/models/artifact/artifact_type.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/repositories/artifact_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ArtifactRepository', () {
    test('stores and loads artifact registry by group and artifact id',
        () async {
      final storage =
          DatabaseHelper(databaseName: 'artifact_repository_test_v12.db');
      final repository = ArtifactRepository(storage);
      final groupId =
          await storage.insertGroup(ChatGroup(title: 'artifact repo group'));

      await repository.upsertRecord(
        ArtifactRecord(
          artifactId: 'portfolio-pie',
          groupId: groupId,
          title: '投资组合饼图',
          type: ArtifactType.html,
          sourcePath: 'artifacts/$groupId/portfolio-pie.html',
          originTurnId: 42,
          createdAt: DateTime(2026, 4, 30, 10),
          lastUpdatedAt: DateTime(2026, 4, 30, 10),
        ),
      );

      final record = await repository.findByGroupAndArtifactId(
        groupId: groupId,
        artifactId: 'portfolio-pie',
      );

      expect(record, isNotNull);
      expect(record!.sourcePath, 'artifacts/$groupId/portfolio-pie.html');
      expect(record.originTurnId, 42);

      final byPath = await repository.findByGroupAndSourcePath(
        groupId: groupId,
        sourcePath: 'artifacts/$groupId/portfolio-pie.html',
      );
      expect(byPath, isNotNull);
      expect(byPath!.artifactId, 'portfolio-pie');

      final listed = await repository.listByGroup(groupId);
      expect(listed, hasLength(1));

      await storage.deleteGroup(groupId);
    });
  });
}
