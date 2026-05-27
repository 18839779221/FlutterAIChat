import 'package:ai_chat/models/chat/runtime_streaming_preview_state.dart';
import 'package:ai_chat/models/llm/streaming_message_event.dart';

/// Folds streaming preview events into one runtime-only read model.
class RuntimeStreamingPreviewProjector {
  RuntimeStreamingPreviewProjector({
    RuntimeStreamingPreviewState initialState =
        const RuntimeStreamingPreviewState(),
  }) : _state = initialState;

  RuntimeStreamingPreviewState _state;

  RuntimeStreamingPreviewState currentState() => _state;

  void clear() {
    _state = const RuntimeStreamingPreviewState();
  }

  void consume(
    StreamingMessageEvent event, {
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();
    if (event is StreamingMessageStartEvent) {
      _upsertMessage(
        event.messageId,
        (current) => RuntimeStreamingPreviewMessage(
          messageId: event.messageId,
          createdAt: current?.createdAt ?? timestamp,
          updatedAt: timestamp,
          isCompleted: false,
          blocks: current?.blocks ?? const <RuntimeStreamingPreviewBlock>[],
        ),
      );
      return;
    }
    if (event is StreamingMessageStopEvent) {
      _upsertMessage(
        event.messageId,
        (current) => (current ??
                RuntimeStreamingPreviewMessage(
                  messageId: event.messageId,
                  createdAt: timestamp,
                  updatedAt: timestamp,
                ))
            .copyWith(
          updatedAt: timestamp,
          isCompleted: true,
        ),
      );
      return;
    }
    if (event is StreamingContentBlockStartEvent) {
      _upsertMessage(event.messageId, (current) {
        final base = current ??
            RuntimeStreamingPreviewMessage(
              messageId: event.messageId,
              createdAt: timestamp,
              updatedAt: timestamp,
            );
        final blocks = List<RuntimeStreamingPreviewBlock>.from(base.blocks);
        final existingIndex = blocks.indexWhere(
          (block) => block.contentBlockId == event.contentBlockId,
        );
        final block = RuntimeStreamingPreviewBlock(
          contentBlockId: event.contentBlockId,
          blockType: event.blockType,
          createdAt: existingIndex == -1
              ? timestamp
              : blocks[existingIndex].createdAt,
          updatedAt: timestamp,
          isCompleted: false,
          text: existingIndex == -1 ? '' : blocks[existingIndex].text,
          toolUseId: event.toolUseId,
          toolName: event.toolName,
        );
        if (existingIndex == -1) {
          blocks.add(block);
        } else {
          blocks[existingIndex] = block;
        }
        return base.copyWith(
          updatedAt: timestamp,
          isCompleted: false,
          blocks: blocks,
        );
      });
      return;
    }
    if (event is StreamingContentBlockDeltaEvent) {
      _upsertMessage(event.messageId, (current) {
        final base = current ??
            RuntimeStreamingPreviewMessage(
              messageId: event.messageId,
              createdAt: timestamp,
              updatedAt: timestamp,
            );
        final blocks = List<RuntimeStreamingPreviewBlock>.from(base.blocks);
        final existingIndex = blocks.indexWhere(
          (block) => block.contentBlockId == event.contentBlockId,
        );
        final previous = existingIndex == -1
            ? RuntimeStreamingPreviewBlock(
                contentBlockId: event.contentBlockId,
                blockType: _inferBlockType(event.deltaType),
                createdAt: timestamp,
                updatedAt: timestamp,
              )
            : blocks[existingIndex];
        final nextBlock = previous.copyWith(
          updatedAt: timestamp,
          isCompleted: false,
          text: previous.text + event.value,
        );
        if (existingIndex == -1) {
          blocks.add(nextBlock);
        } else {
          blocks[existingIndex] = nextBlock;
        }
        return base.copyWith(
          updatedAt: timestamp,
          isCompleted: false,
          blocks: blocks,
        );
      });
      return;
    }
    if (event is StreamingContentBlockStopEvent) {
      _upsertMessage(event.messageId, (current) {
        final base = current ??
            RuntimeStreamingPreviewMessage(
              messageId: event.messageId,
              createdAt: timestamp,
              updatedAt: timestamp,
            );
        final blocks = List<RuntimeStreamingPreviewBlock>.from(base.blocks);
        final existingIndex = blocks.indexWhere(
          (block) => block.contentBlockId == event.contentBlockId,
        );
        if (existingIndex == -1) {
          blocks.add(
            RuntimeStreamingPreviewBlock(
              contentBlockId: event.contentBlockId,
              blockType: StreamingContentBlockType.text,
              createdAt: timestamp,
              updatedAt: timestamp,
              isCompleted: true,
            ),
          );
        } else {
          blocks[existingIndex] = blocks[existingIndex].copyWith(
            updatedAt: timestamp,
            isCompleted: true,
          );
        }
        return base.copyWith(
          updatedAt: timestamp,
          blocks: blocks,
        );
      });
    }
  }

  StreamingContentBlockType _inferBlockType(StreamingContentDeltaType deltaType) {
    switch (deltaType) {
      case StreamingContentDeltaType.text:
        return StreamingContentBlockType.text;
      case StreamingContentDeltaType.thinking:
        return StreamingContentBlockType.thinking;
      case StreamingContentDeltaType.inputJson:
      case StreamingContentDeltaType.signature:
        return StreamingContentBlockType.toolUse;
    }
  }

  void _upsertMessage(
    String messageId,
    RuntimeStreamingPreviewMessage Function(
      RuntimeStreamingPreviewMessage? current,
    ) updater,
  ) {
    final messages = List<RuntimeStreamingPreviewMessage>.from(_state.messages);
    final index = messages.indexWhere((message) => message.messageId == messageId);
    final current = index == -1 ? null : messages[index];
    final next = updater(current);
    if (index == -1) {
      messages.add(next);
    } else {
      messages[index] = next;
    }
    _state = _state.copyWith(messages: messages);
  }
}
