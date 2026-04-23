import 'package:ai_chat/models/session/session_runtime_marker.dart';
import 'package:ai_chat/repositories/session_runtime_marker_repository.dart';
import 'package:ai_chat/services/session_runtime_marker_service.dart';
import 'package:ai_chat/storage/chat_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionRuntimeMarkerService', () {
    test('returns no reminder and uses today as initial baseline when marker is missing',
        () async {
      final repository = _FakeSessionRuntimeMarkerRepository();
      final service = SessionRuntimeMarkerService(
        repository: repository,
        nowProvider: () => DateTime(2026, 4, 24, 8),
      );

      final result = await service.prepareForUserMessage(groupId: 1);

      expect(result.currentDate, '2026-04-24');
      expect(result.reminderMessage, isNull);
    });

    test('returns no reminder when stored date matches today', () async {
      final repository = _FakeSessionRuntimeMarkerRepository(
        initialMarker: SessionRuntimeMarker(
          id: 1,
          groupId: 1,
          lastInjectedDate: '2026-04-24',
        ),
      );
      final service = SessionRuntimeMarkerService(
        repository: repository,
        nowProvider: () => DateTime(2026, 4, 24, 21),
      );

      final result = await service.prepareForUserMessage(groupId: 1);

      expect(result.currentDate, '2026-04-24');
      expect(result.reminderMessage, isNull);
    });

    test('returns reminder when stored date differs from today', () async {
      final repository = _FakeSessionRuntimeMarkerRepository(
        initialMarker: SessionRuntimeMarker(
          id: 1,
          groupId: 1,
          lastInjectedDate: '2026-04-24',
        ),
      );
      final service = SessionRuntimeMarkerService(
        repository: repository,
        nowProvider: () => DateTime(2026, 4, 25, 8),
      );

      final result = await service.prepareForUserMessage(groupId: 1);

      expect(result.currentDate, '2026-04-25');
      expect(result.reminderMessage, isNotNull);
      expect(
        result.reminderMessage!.text,
        contains("Today's date is now 2026-04-25"),
      );
    });

    test('persistInjectedDate upserts the latest marker', () async {
      final repository = _FakeSessionRuntimeMarkerRepository();
      final service = SessionRuntimeMarkerService(
        repository: repository,
        nowProvider: () => DateTime(2026, 4, 25, 8),
      );

      await service.persistInjectedDate(
        groupId: 1,
        currentDate: '2026-04-25',
      );

      final stored = await repository.getLatestByGroup(1);
      expect(stored, isNotNull);
      expect(stored!.lastInjectedDate, '2026-04-25');
    });
  });
}

class _FakeSessionRuntimeMarkerRepository
    extends SessionRuntimeMarkerRepository {
  _FakeSessionRuntimeMarkerRepository({
    SessionRuntimeMarker? initialMarker,
  })  : _marker = initialMarker,
        super(_ThrowingChatStorage());

  SessionRuntimeMarker? _marker;

  @override
  Future<SessionRuntimeMarker?> getLatestByGroup(int groupId) async {
    if (_marker?.groupId != groupId) {
      return null;
    }
    return _marker;
  }

  @override
  Future<int> upsertLatest(SessionRuntimeMarker marker) async {
    _marker = marker.copyWith(id: _marker?.id ?? 1);
    return _marker!.id!;
  }
}

class _ThrowingChatStorage extends Fake implements ChatStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('Storage should not be used in this fake');
  }
}
