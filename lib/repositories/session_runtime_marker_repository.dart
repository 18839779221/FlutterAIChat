import '../models/session/session_runtime_marker.dart';
import '../storage/chat_storage.dart';

class SessionRuntimeMarkerRepository {
  final ChatStorage _storage;

  SessionRuntimeMarkerRepository(this._storage);

  Future<SessionRuntimeMarker?> getLatestByGroup(int groupId) {
    return _storage.getLatestSessionRuntimeMarkerByGroup(groupId);
  }

  Future<int> upsertLatest(SessionRuntimeMarker marker) async {
    final existing =
        await _storage.getLatestSessionRuntimeMarkerByGroup(marker.groupId);
    if (existing == null) {
      return _storage.insertSessionRuntimeMarker(marker);
    }

    final updatedMarker = marker.copyWith(
      id: existing.id,
      updatedAt: DateTime.now(),
    );
    await _storage.updateSessionRuntimeMarker(updatedMarker);
    return existing.id!;
  }
}
