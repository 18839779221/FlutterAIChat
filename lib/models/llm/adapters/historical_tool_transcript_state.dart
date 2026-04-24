/// Reassigns synthetic tool-call ids for historical messages that preserved
/// `modelContextType` semantics but lost their provider-side call ids.
///
/// Each adapter keeps its own instance (with its own id prefix) because the
/// generated ids are scoped to a single outgoing request payload.
class HistoricalToolTranscriptState {
  HistoricalToolTranscriptState(this._idPrefix);

  final String _idPrefix;
  final List<HistoricalToolInvocation> _pendingInvocations =
      <HistoricalToolInvocation>[];
  int _nextId = 0;

  String register(String toolName) {
    _nextId += 1;
    final invocation = HistoricalToolInvocation(
      id: '$_idPrefix$_nextId',
      toolName: toolName,
    );
    _pendingInvocations.add(invocation);
    return invocation.id;
  }

  HistoricalToolInvocation? consume({String? preferredToolName}) {
    if (_pendingInvocations.isEmpty) {
      return null;
    }
    if (preferredToolName != null) {
      for (var index = 0; index < _pendingInvocations.length; index += 1) {
        final invocation = _pendingInvocations[index];
        if (invocation.toolName == preferredToolName) {
          _pendingInvocations.removeAt(index);
          return invocation;
        }
      }
    }
    return _pendingInvocations.removeAt(0);
  }
}

class HistoricalToolInvocation {
  const HistoricalToolInvocation({
    required this.id,
    required this.toolName,
  });

  final String id;
  final String toolName;
}
