class ChatTimelineOrderAnchorStore {
  final Map<String, _OrderAnchor> _anchors = <String, _OrderAnchor>{};

  _OrderAnchor remember({
    required String logicalId,
    required int anchorMicros,
    required int sequence,
  }) {
    return _anchors.putIfAbsent(
      logicalId,
      () => _OrderAnchor(
        anchorMicros: anchorMicros,
        sequence: sequence,
      ),
    );
  }

  void retainLogicalIds(Set<String> logicalIds) {
    _anchors.removeWhere((key, _) => !logicalIds.contains(key));
  }
}

class _OrderAnchor {
  const _OrderAnchor({
    required this.anchorMicros,
    required this.sequence,
  });

  final int anchorMicros;
  final int sequence;
}
