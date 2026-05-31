/// Runtime-only streaming preview event model.
///
/// These events describe one provider message and its ordered content blocks.
/// They are consumed by the streaming accumulator and preview projection
/// pipeline, but are not persisted as transcript truth.
abstract class StreamingMessageEvent {
  const StreamingMessageEvent({
    required this.messageId,
    this.providerMetadata,
    this.runtimeMetadata,
  });

  /// Stable provider-scoped message id for one streamed assistant message.
  final String messageId;

  /// Optional provider metadata merged into downstream provider state.
  final Map<String, dynamic>? providerMetadata;

  /// Optional runtime-only metadata for UI/debug projection.
  ///
  /// Unlike [providerMetadata], this map must not be folded into provider truth
  /// or persisted provider continuation state.
  final Map<String, dynamic>? runtimeMetadata;

  /// Returns a copy of this event with runtime-only metadata merged in.
  StreamingMessageEvent copyWithMergedRuntimeMetadata(
    Map<String, dynamic> metadata,
  );
}

enum StreamingContentBlockType {
  text,
  thinking,
  toolUse,
}

enum StreamingContentDeltaType {
  text,
  thinking,
  inputJson,
  signature,
}

class StreamingMessageStartEvent extends StreamingMessageEvent {
  const StreamingMessageStartEvent({
    required super.messageId,
    super.providerMetadata,
    super.runtimeMetadata,
  });

  @override
  StreamingMessageStartEvent copyWithMergedRuntimeMetadata(
    Map<String, dynamic> metadata,
  ) {
    return StreamingMessageStartEvent(
      messageId: messageId,
      providerMetadata: providerMetadata,
      runtimeMetadata: {
        ...?runtimeMetadata,
        ...metadata,
      },
    );
  }
}

class StreamingMessageStopEvent extends StreamingMessageEvent {
  const StreamingMessageStopEvent({
    required super.messageId,
    super.providerMetadata,
    super.runtimeMetadata,
  });

  @override
  StreamingMessageStopEvent copyWithMergedRuntimeMetadata(
    Map<String, dynamic> metadata,
  ) {
    return StreamingMessageStopEvent(
      messageId: messageId,
      providerMetadata: providerMetadata,
      runtimeMetadata: {
        ...?runtimeMetadata,
        ...metadata,
      },
    );
  }
}

class StreamingContentBlockStartEvent extends StreamingMessageEvent {
  const StreamingContentBlockStartEvent({
    required super.messageId,
    required this.contentBlockId,
    required this.blockType,
    this.toolUseId,
    this.toolName,
    super.providerMetadata,
    super.runtimeMetadata,
  });

  /// Stable id for one content block within a streamed message.
  final String contentBlockId;

  /// Semantic type of the block.
  final StreamingContentBlockType blockType;

  /// Stable provider tool-use id when the block is a tool use.
  final String? toolUseId;

  /// Provider tool name when the block is a tool use.
  final String? toolName;

  @override
  StreamingContentBlockStartEvent copyWithMergedRuntimeMetadata(
    Map<String, dynamic> metadata,
  ) {
    return StreamingContentBlockStartEvent(
      messageId: messageId,
      contentBlockId: contentBlockId,
      blockType: blockType,
      toolUseId: toolUseId,
      toolName: toolName,
      providerMetadata: providerMetadata,
      runtimeMetadata: {
        ...?runtimeMetadata,
        ...metadata,
      },
    );
  }
}

class StreamingContentBlockDeltaEvent extends StreamingMessageEvent {
  const StreamingContentBlockDeltaEvent({
    required super.messageId,
    required this.contentBlockId,
    required this.deltaType,
    required this.value,
    super.providerMetadata,
    super.runtimeMetadata,
  });

  /// Target content block id for this delta.
  final String contentBlockId;

  /// Delta semantic type.
  final StreamingContentDeltaType deltaType;

  /// Raw delta payload. Text/thinking/input_json/signature all use this field.
  final String value;

  @override
  StreamingContentBlockDeltaEvent copyWithMergedRuntimeMetadata(
    Map<String, dynamic> metadata,
  ) {
    return StreamingContentBlockDeltaEvent(
      messageId: messageId,
      contentBlockId: contentBlockId,
      deltaType: deltaType,
      value: value,
      providerMetadata: providerMetadata,
      runtimeMetadata: {
        ...?runtimeMetadata,
        ...metadata,
      },
    );
  }
}

class StreamingContentBlockStopEvent extends StreamingMessageEvent {
  const StreamingContentBlockStopEvent({
    required super.messageId,
    required this.contentBlockId,
    super.providerMetadata,
    super.runtimeMetadata,
  });

  /// Target content block id to stop.
  final String contentBlockId;

  @override
  StreamingContentBlockStopEvent copyWithMergedRuntimeMetadata(
    Map<String, dynamic> metadata,
  ) {
    return StreamingContentBlockStopEvent(
      messageId: messageId,
      contentBlockId: contentBlockId,
      providerMetadata: providerMetadata,
      runtimeMetadata: {
        ...?runtimeMetadata,
        ...metadata,
      },
    );
  }
}
