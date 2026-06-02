/// Runtime-resolved workspace identity and canonical file root.
class ResolvedWorkspace {
  const ResolvedWorkspace({
    required this.workspaceId,
    required this.isDefault,
    required this.fileRoot,
  });

  final String workspaceId;
  final bool isDefault;
  final String fileRoot;
}
