import 'package:ai_chat/models/llm/streaming_message_event.dart';

/// Runtime-only read model for in-flight provider preview messages.
///
/// This state is not persisted and only exists to let projection/UI layers
/// render temporary preview content before the final transcript message lands.
class RuntimeStreamingPreviewState {
  const RuntimeStreamingPreviewState({
    this.messages = const <RuntimeStreamingPreviewMessage>[],
  });

  final List<RuntimeStreamingPreviewMessage> messages;

  bool get isEmpty => messages.isEmpty;

  RuntimeStreamingPreviewState copyWith({
    List<RuntimeStreamingPreviewMessage>? messages,
  }) {
    return RuntimeStreamingPreviewState(
      messages: messages ?? this.messages,
    );
  }
}

/// One streamed assistant message preview composed from ordered content blocks.
class RuntimeStreamingPreviewMessage {
  const RuntimeStreamingPreviewMessage({
    required this.messageId,
    required this.createdAt,
    required this.updatedAt,
    this.isCompleted = false,
    this.blocks = const <RuntimeStreamingPreviewBlock>[],
  });

  final String messageId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isCompleted;
  final List<RuntimeStreamingPreviewBlock> blocks;

  RuntimeStreamingPreviewMessage copyWith({
    String? messageId,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isCompleted,
    List<RuntimeStreamingPreviewBlock>? blocks,
  }) {
    return RuntimeStreamingPreviewMessage(
      messageId: messageId ?? this.messageId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isCompleted: isCompleted ?? this.isCompleted,
      blocks: blocks ?? this.blocks,
    );
  }
}

/// One ordered content block inside a runtime preview message.
class RuntimeStreamingPreviewBlock {
  const RuntimeStreamingPreviewBlock({
    required this.contentBlockId,
    required this.blockType,
    required this.createdAt,
    required this.updatedAt,
    this.isCompleted = false,
    this.text = '',
    this.toolUseId,
    this.toolName,
  });

  final String contentBlockId;
  final StreamingContentBlockType blockType;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isCompleted;
  final String text;
  final String? toolUseId;
  final String? toolName;

  RuntimeStreamingPreviewBlock copyWith({
    String? contentBlockId,
    StreamingContentBlockType? blockType,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isCompleted,
    String? text,
    String? toolUseId,
    String? toolName,
  }) {
    return RuntimeStreamingPreviewBlock(
      contentBlockId: contentBlockId ?? this.contentBlockId,
      blockType: blockType ?? this.blockType,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isCompleted: isCompleted ?? this.isCompleted,
      text: text ?? this.text,
      toolUseId: toolUseId ?? this.toolUseId,
      toolName: toolName ?? this.toolName,
    );
  }
}
