/// Internal normalized planner-stream chunk used only inside the LLM layer.
enum StreamingPlannerChunkType {
  contentDelta,
  reasoningDelta,
  toolCallStarted,
  toolCallArgumentsDelta,
  toolCallCompleted,
  streamCompleted,
}

/// Provider-agnostic planner stream chunk.
///
/// This model intentionally stays generic: it carries tool-call identity,
/// optional tool name, raw argument text deltas, and lightweight provider
/// metadata without encoding any tool-specific field semantics.
class StreamingPlannerChunk {
  final StreamingPlannerChunkType type;
  final String? content;
  final String? providerCallId;
  final String? toolName;
  final String? argumentsTextDelta;
  final Map<String, dynamic>? providerMetadata;

  const StreamingPlannerChunk({
    required this.type,
    this.content,
    this.providerCallId,
    this.toolName,
    this.argumentsTextDelta,
    this.providerMetadata,
  });

  const StreamingPlannerChunk.contentDelta(
    String content, {
    Map<String, dynamic>? providerMetadata,
  })
      : this(
          type: StreamingPlannerChunkType.contentDelta,
          content: content,
          providerMetadata: providerMetadata,
        );

  const StreamingPlannerChunk.reasoningDelta(
    String content, {
    Map<String, dynamic>? providerMetadata,
  })
      : this(
          type: StreamingPlannerChunkType.reasoningDelta,
          content: content,
          providerMetadata: providerMetadata,
        );

  const StreamingPlannerChunk.toolCallStarted({
    String? providerCallId,
    String? toolName,
    Map<String, dynamic>? providerMetadata,
  }) : this(
          type: StreamingPlannerChunkType.toolCallStarted,
          providerCallId: providerCallId,
          toolName: toolName,
          providerMetadata: providerMetadata,
        );

  const StreamingPlannerChunk.toolCallArgumentsDelta({
    String? providerCallId,
    String? toolName,
    required String argumentsTextDelta,
    Map<String, dynamic>? providerMetadata,
  }) : this(
          type: StreamingPlannerChunkType.toolCallArgumentsDelta,
          providerCallId: providerCallId,
          toolName: toolName,
          argumentsTextDelta: argumentsTextDelta,
          providerMetadata: providerMetadata,
        );

  const StreamingPlannerChunk.toolCallCompleted({
    String? providerCallId,
    String? toolName,
    Map<String, dynamic>? providerMetadata,
  }) : this(
          type: StreamingPlannerChunkType.toolCallCompleted,
          providerCallId: providerCallId,
          toolName: toolName,
          providerMetadata: providerMetadata,
        );

  const StreamingPlannerChunk.streamCompleted()
      : this(type: StreamingPlannerChunkType.streamCompleted);
}
