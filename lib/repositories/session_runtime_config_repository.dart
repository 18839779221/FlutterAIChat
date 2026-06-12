import '../models/session/session_runtime_config.dart';
import '../storage/chat_storage.dart';

class SessionRuntimeConfigRepository {
  final ChatStorage _storage;

  SessionRuntimeConfigRepository(this._storage);

  Future<SessionRuntimeConfig?> getByGroup(int groupId) {
    return _storage.getSessionRuntimeConfigByGroup(groupId);
  }

  Future<int> upsert(SessionRuntimeConfig config) async {
    final existing = await _storage.getSessionRuntimeConfigByGroup(config.groupId);
    if (existing == null) {
      return _storage.insertSessionRuntimeConfig(config);
    }

    final updated = config.copyWith(
      id: existing.id,
      updatedAt: DateTime.now(),
    );
    await _storage.updateSessionRuntimeConfig(updated);
    return existing.id!;
  }
}
