/// Runtime-only streaming preview event model.
///
/// These events describe one provider message and its ordered content blocks.
/// They are consumed by the streaming accumulator and preview projection
/// pipeline, but are not persisted as transcript truth.
abstract class StreamingMessageEvent {
  const StreamingMessageEvent({
    required this.messageId,
    this.providerMetadata,
  });

  /// Stable provider-scoped message id for one streamed assistant message.
  final String messageId;

  /// Optional provider metadata merged into downstream provider state.
  final Map<String, dynamic>? providerMetadata;
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
  });
}

class StreamingMessageStopEvent extends StreamingMessageEvent {
  const StreamingMessageStopEvent({
    required super.messageId,
    super.providerMetadata,
  });
}

class StreamingContentBlockStartEvent extends StreamingMessageEvent {
  const StreamingContentBlockStartEvent({
    required super.messageId,
    required this.contentBlockId,
    required this.blockType,
    this.toolUseId,
    this.toolName,
    super.providerMetadata,
  });

  /// Stable id for one content block within a streamed message.
  final String contentBlockId;

  /// Semantic type of the block.
  final StreamingContentBlockType blockType;

  /// Stable provider tool-use id when the block is a tool use.
  final String? toolUseId;

  /// Provider tool name when the block is a tool use.
  final String? toolName;
}

class StreamingContentBlockDeltaEvent extends StreamingMessageEvent {
  const StreamingContentBlockDeltaEvent({
    required super.messageId,
    required this.contentBlockId,
    required this.deltaType,
    required this.value,
    super.providerMetadata,
  });

  /// Target content block id for this delta.
  final String contentBlockId;

  /// Delta semantic type.
  final StreamingContentDeltaType deltaType;

  /// Raw delta payload. Text/thinking/input_json/signature all use this field.
  final String value;
}

class StreamingContentBlockStopEvent extends StreamingMessageEvent {
  const StreamingContentBlockStopEvent({
    required super.messageId,
    required this.contentBlockId,
    super.providerMetadata,
  });

  /// Target content block id to stop.
  final String contentBlockId;
}
