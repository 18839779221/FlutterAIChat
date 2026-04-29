import '../models/artifact/artifact_record.dart';
import '../storage/chat_storage.dart';

class ArtifactRepository {
  final ChatStorage _storage;

  ArtifactRepository(this._storage);

  Future<int> upsertRecord(ArtifactRecord record) {
    return _storage.insertOrReplaceArtifactRecord(record);
  }

  Future<ArtifactRecord?> findByGroupAndArtifactId({
    required int groupId,
    required String artifactId,
  }) {
    return _storage.getArtifactRecord(
      groupId: groupId,
      artifactId: artifactId,
    );
  }

  Future<ArtifactRecord?> findByGroupAndSourcePath({
    required int groupId,
    required String sourcePath,
  }) {
    return _storage.getArtifactRecordByPath(
      groupId: groupId,
      sourcePath: sourcePath,
    );
  }

  Future<List<ArtifactRecord>> listByGroup(int groupId) {
    return _storage.listArtifactRecordsForGroup(groupId);
  }

  Future<void> updateRecord(ArtifactRecord record) {
    return _storage.updateArtifactRecord(record);
  }
}
