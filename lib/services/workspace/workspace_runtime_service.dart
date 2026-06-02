import '../../models/chat_group.dart';
import '../../models/workspace/resolved_workspace.dart';
import '../../storage/chat_storage.dart';
import 'workspace_binding_service.dart';

typedef CurrentGroupReader = ChatGroup? Function();
typedef CurrentGroupWriter = void Function(ChatGroup group);
typedef GroupsReader = List<ChatGroup> Function();
typedef GroupsWriter = void Function(List<ChatGroup> groups);

/// Coordinates runtime workspace resolution and promotion for the active chat.
class WorkspaceRuntimeService {
  WorkspaceRuntimeService({
    required ChatStorage storage,
    WorkspaceBindingService? workspaceBindingService,
    DateTime Function()? nowProvider,
    CurrentGroupReader? currentGroupReader,
    CurrentGroupWriter? currentGroupWriter,
    GroupsReader? groupsReader,
    GroupsWriter? groupsWriter,
  })  : _storage = storage,
        _workspaceBindingService =
            workspaceBindingService ?? WorkspaceBindingService(),
        _nowProvider = nowProvider ?? DateTime.now,
        _currentGroupReader = currentGroupReader,
        _currentGroupWriter = currentGroupWriter,
        _groupsReader = groupsReader,
        _groupsWriter = groupsWriter;

  final ChatStorage _storage;
  final WorkspaceBindingService _workspaceBindingService;
  final DateTime Function() _nowProvider;
  final CurrentGroupReader? _currentGroupReader;
  final CurrentGroupWriter? _currentGroupWriter;
  final GroupsReader? _groupsReader;
  final GroupsWriter? _groupsWriter;

  Future<ResolvedWorkspace> resolveWorkspaceForGroup(int groupId) async {
    final group = await _storage.getGroupById(groupId);
    return _workspaceBindingService.resolveWorkspaceId(group?.workspaceId);
  }

  Future<WorkspaceTransitionResult> ensureWorkspaceForLongLivedOutput(
    int groupId,
  ) async {
    final group = await _storage.getGroupById(groupId);
    if (group == null) {
      throw StateError('Chat group $groupId not found');
    }

    final currentWorkspace =
        _workspaceBindingService.resolveWorkspaceId(group.workspaceId);
    if (!currentWorkspace.isDefault) {
      return WorkspaceTransitionResult(
        workspace: currentWorkspace,
        workspaceChanged: false,
      );
    }

    final nextWorkspaceId = _workspaceBindingService.createAutoWorkspaceId(
      now: _nowProvider(),
    );
    await _storage.updateGroupWorkspaceId(groupId, nextWorkspaceId);
    final nextWorkspace =
        _workspaceBindingService.resolveWorkspaceId(nextWorkspaceId);
    _syncCurrentGroup(groupId, nextWorkspaceId);
    _syncGroups(groupId, nextWorkspaceId);
    return WorkspaceTransitionResult(
      workspace: nextWorkspace,
      workspaceChanged: true,
      reminderMessage:
          _workspaceBindingService.buildWorkspaceChangeReminder(nextWorkspace),
    );
  }

  void _syncCurrentGroup(int groupId, String workspaceId) {
    final reader = _currentGroupReader;
    final writer = _currentGroupWriter;
    if (reader == null || writer == null) {
      return;
    }
    final currentGroup = reader();
    if (currentGroup?.id != groupId || currentGroup?.workspaceId == workspaceId) {
      return;
    }
    writer(currentGroup!.copyWith(workspaceId: workspaceId));
  }

  void _syncGroups(int groupId, String workspaceId) {
    final reader = _groupsReader;
    final writer = _groupsWriter;
    if (reader == null || writer == null) {
      return;
    }
    final groups = reader();
    final nextGroups = groups
        .map(
          (group) => group.id == groupId
              ? group.copyWith(workspaceId: workspaceId)
              : group,
        )
        .toList(growable: false);
    writer(nextGroups);
  }
}
