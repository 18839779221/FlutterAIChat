import '../models/chat/send_message_request.dart';

class PendingFollowUpRequest {
  const PendingFollowUpRequest({
    required this.request,
    required this.dispatchMode,
    required this.sequence,
    this.groupId,
  });

  final int? groupId;
  final SendMessageRequest request;
  final SendMessageDispatchMode dispatchMode;
  final int sequence;
}

/// Runtime-only queue for follow-up user inputs submitted while a turn is
/// still active. Pending entries are intentionally not persisted.
class FollowUpDispatchQueue {
  final Map<int?, List<PendingFollowUpRequest>> _pendingByGroup = {};
  int _nextSequence = 1;

  bool get isEmpty =>
      _pendingByGroup.values.every((entries) => entries.isEmpty);

  int pendingCountForGroup(int? groupId) {
    return _pendingForResolvedGroup(groupId).length;
  }

  void enqueue({
    required int? groupId,
    required SendMessageRequest request,
  }) {
    final entry = PendingFollowUpRequest(
      groupId: groupId,
      request: request,
      dispatchMode: request.dispatchMode,
      sequence: _nextSequence++,
    );
    _pendingByGroup.putIfAbsent(groupId, () => <PendingFollowUpRequest>[]).add(
          entry,
        );
  }

  List<PendingFollowUpRequest> takeSteerForPlanner(int groupId) {
    final pending = _pendingForResolvedGroup(groupId);
    if (pending.isEmpty) {
      return const <PendingFollowUpRequest>[];
    }
    final steer = pending
        .where((entry) => entry.dispatchMode == SendMessageDispatchMode.steer)
        .toList(growable: false);
    if (steer.isEmpty) {
      return const <PendingFollowUpRequest>[];
    }
    _removeEntries(steer);
    return steer;
  }

  List<PendingFollowUpRequest> takeAllForNextTurn(int groupId) {
    final pending = _pendingForResolvedGroup(groupId);
    if (pending.isEmpty) {
      return const <PendingFollowUpRequest>[];
    }
    _removeEntries(pending);
    return pending;
  }

  List<PendingFollowUpRequest> _pendingForResolvedGroup(int? groupId) {
    final combined = <PendingFollowUpRequest>[
      ...?_pendingByGroup[groupId],
      if (groupId != null) ...?_pendingByGroup[null],
    ]..sort((left, right) => left.sequence.compareTo(right.sequence));
    return combined;
  }

  void _removeEntries(List<PendingFollowUpRequest> entries) {
    for (final entry in entries) {
      final list = _pendingByGroup[entry.groupId];
      if (list == null) {
        continue;
      }
      list.removeWhere((candidate) => candidate.sequence == entry.sequence);
      if (list.isEmpty) {
        _pendingByGroup.remove(entry.groupId);
      }
    }
  }
}
