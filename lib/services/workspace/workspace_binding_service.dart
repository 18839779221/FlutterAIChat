import '../../models/workspace/resolved_workspace.dart';
import 'workspace_id_generator.dart';

class WorkspaceTransitionResult {
  const WorkspaceTransitionResult({
    required this.workspace,
    required this.workspaceChanged,
    this.reminderMessage,
  });

  final ResolvedWorkspace workspace;
  final bool workspaceChanged;
  final String? reminderMessage;
}

class WorkspaceBindingService {
  WorkspaceBindingService({
    WorkspaceIdGenerator? idGenerator,
  }) : _idGenerator = idGenerator ?? WorkspaceIdGenerator();

  final WorkspaceIdGenerator _idGenerator;

  String get defaultWorkspaceId => WorkspaceIdGenerator.defaultWorkspaceId;

  ResolvedWorkspace resolveWorkspaceId(String? workspaceId) {
    final resolvedId = (workspaceId == null || workspaceId.trim().isEmpty)
        ? defaultWorkspaceId
        : workspaceId.trim();
    return ResolvedWorkspace(
      workspaceId: resolvedId,
      isDefault: resolvedId == defaultWorkspaceId,
      fileRoot: '/workspaces/$resolvedId',
    );
  }

  String createAutoWorkspaceId({DateTime? now}) {
    return _idGenerator.generateAutoWorkspaceId(now: now);
  }

  String buildWorkspaceChangeReminder(ResolvedWorkspace workspace) {
    return '<system-reminder>\n'
        'The current chat is now using workspace ${workspace.workspaceId}.\n'
        'New files for this chat should be created under ${workspace.fileRoot}.\n'
        '</system-reminder>';
  }
}
