import '../../models/workspace/resolved_workspace.dart';
import 'workspace_binding_service.dart';

typedef ResolveWorkspaceForGroup = Future<ResolvedWorkspace> Function(int groupId);
typedef EnsureWorkspaceForLongLivedOutput = Future<WorkspaceTransitionResult>
    Function(int groupId);

class WorkspaceToolHostAdapters {
  const WorkspaceToolHostAdapters({
    required this.resolveWorkspaceForGroup,
    required this.ensureWorkspaceForLongLivedOutput,
  });

  final ResolveWorkspaceForGroup resolveWorkspaceForGroup;
  final EnsureWorkspaceForLongLivedOutput ensureWorkspaceForLongLivedOutput;
}
