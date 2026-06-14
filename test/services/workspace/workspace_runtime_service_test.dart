import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_turn.dart';
import 'package:ai_chat/services/workspace/workspace_runtime_service.dart';
import 'package:ai_chat/storage/chat_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkspaceRuntimeService', () {
    test('resolves null group workspace to .default', () async {
      final storage = _FakeChatStorage(
        groups: {
          1: ChatGroup(
            id: 1,
            title: 'Draft',
          ),
        },
      );
      final service = WorkspaceRuntimeService(storage: storage);

      final resolved = await service.resolveWorkspaceForGroup(1);

      expect(resolved.workspaceId, '.default');
      expect(resolved.isDefault, isTrue);
      expect(resolved.fileRoot, '/workspaces/.default');
    });

    test('promotes default workspace and syncs current state', () async {
      final currentGroup = ValueNotifier<ChatGroup?>(
        ChatGroup(
          id: 1,
          title: 'Draft',
        ),
      );
      var groups = <ChatGroup>[
        currentGroup.value!,
      ];
      final storage = _FakeChatStorage(
        groups: {
          1: currentGroup.value!,
        },
      );
      final service = WorkspaceRuntimeService(
        storage: storage,
        nowProvider: () => DateTime(2026, 6, 2, 10),
        currentGroupReader: () => currentGroup.value,
        currentGroupWriter: (group) => currentGroup.value = group,
        groupsReader: () => groups,
        groupsWriter: (next) => groups = next,
      );

      final transition = await service.ensureWorkspaceForLongLivedOutput(1);

      expect(transition.workspaceChanged, isTrue);
      expect(
        transition.workspace.workspaceId,
        matches(r'^ws_20260602_[a-z0-9]{6}$'),
      );
      expect(
        transition.reminderMessage,
        contains('The current chat is now using workspace'),
      );
      expect(storage.groups[1]?.workspaceId, transition.workspace.workspaceId);
      expect(currentGroup.value?.workspaceId, transition.workspace.workspaceId);
      expect(groups.single.workspaceId, transition.workspace.workspaceId);
    });

    test('keeps explicit workspace without promoting again', () async {
      final group = ChatGroup(
        id: 1,
        title: 'Existing',
        workspaceId: 'ws_20260602_a3k9qx',
      );
      final storage = _FakeChatStorage(groups: {1: group});
      final service = WorkspaceRuntimeService(storage: storage);

      final transition = await service.ensureWorkspaceForLongLivedOutput(1);

      expect(transition.workspaceChanged, isFalse);
      expect(transition.workspace.workspaceId, 'ws_20260602_a3k9qx');
      expect(transition.reminderMessage, isNull);
    });
  });
}

class ValueNotifier<T> {
  ValueNotifier(this.value);

  T value;
}

class _FakeChatStorage implements ChatStorage {
  _FakeChatStorage({
    required this.groups,
  });

  final Map<int, ChatGroup> groups;

  @override
  Future<ChatGroup?> getGroupById(int id) async => groups[id];

  @override
  Future<void> updateGroupWorkspaceId(int groupId, String? workspaceId) async {
    final group = groups[groupId];
    if (group == null) {
      return;
    }
    groups[groupId] = group.copyWith(workspaceId: workspaceId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
