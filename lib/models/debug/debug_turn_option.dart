/// Lightweight selector entry for one persisted turn in the debug inspector.
class DebugTurnOption {
  final int turnId;
  final String status;
  final DateTime updatedAt;
  final String userInputPreview;

  const DebugTurnOption({
    required this.turnId,
    required this.status,
    required this.updatedAt,
    required this.userInputPreview,
  });
}
