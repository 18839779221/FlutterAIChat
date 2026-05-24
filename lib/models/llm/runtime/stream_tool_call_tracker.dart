import '../streaming_planner_chunk.dart';

typedef StreamToolCallMeta = ({String? providerCallId, String? toolName});

/// Tracks in-flight streamed tool-call metadata keyed by provider-specific
/// stream index so later argument/completion events can reuse the same ids.
class StreamToolCallTracker {
  final Map<int, StreamToolCallMeta> _metaByIndex = <int, StreamToolCallMeta>{};

  void remember(
    int? index, {
    String? providerCallId,
    String? toolName,
  }) {
    if (index == null) {
      return;
    }
    _metaByIndex[index] = (
      providerCallId: providerCallId,
      toolName: toolName,
    );
  }

  StreamToolCallMeta? lookup(int? index) {
    if (index == null) {
      return null;
    }
    return _metaByIndex[index];
  }

  StreamingPlannerChunk started({
    required int? index,
    String? providerCallId,
    String? toolName,
    Map<String, dynamic>? providerMetadata,
  }) {
    remember(
      index,
      providerCallId: providerCallId,
      toolName: toolName,
    );
    return StreamingPlannerChunk.toolCallStarted(
      toolCallIndex: index,
      providerCallId: providerCallId,
      toolName: toolName,
      providerMetadata: providerMetadata,
    );
  }

  StreamingPlannerChunk argumentsDelta({
    required int? index,
    String? providerCallId,
    String? toolName,
    required String argumentsTextDelta,
    Map<String, dynamic>? providerMetadata,
  }) {
    final meta = lookup(index);
    return StreamingPlannerChunk.toolCallArgumentsDelta(
      toolCallIndex: index,
      providerCallId: providerCallId ?? meta?.providerCallId,
      toolName: toolName ?? meta?.toolName,
      argumentsTextDelta: argumentsTextDelta,
      providerMetadata: providerMetadata,
    );
  }

  StreamingPlannerChunk completed({
    required int? index,
    String? providerCallId,
    String? toolName,
    Map<String, dynamic>? providerMetadata,
  }) {
    final meta = lookup(index);
    return StreamingPlannerChunk.toolCallCompleted(
      toolCallIndex: index,
      providerCallId: providerCallId ?? meta?.providerCallId,
      toolName: toolName ?? meta?.toolName,
      providerMetadata: providerMetadata,
    );
  }
}
