import '../models/session/session_context_snapshot.dart';
import '../storage/chat_storage.dart';

class SessionContextSnapshotRepository {
  final ChatStorage _storage;

  SessionContextSnapshotRepository(this._storage);

  Future<SessionContextSnapshot?> getLatestByGroup(int groupId) {
    return _storage.getLatestSessionContextSnapshotByGroup(groupId);
  }

  Future<int> upsertLatest(SessionContextSnapshot snapshot) async {
    final existing =
        await _storage.getLatestSessionContextSnapshotByGroup(snapshot.groupId);
    if (existing == null) {
      return _storage.insertSessionContextSnapshot(snapshot);
    }

    final updatedSnapshot = snapshot.copyWith(
      id: existing.id,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now(),
    );
    await _storage.updateSessionContextSnapshot(updatedSnapshot);
    return existing.id!;
  }
}
