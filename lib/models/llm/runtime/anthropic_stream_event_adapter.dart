import 'dart:async';

import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as anthropic;

import '../streaming_message_event.dart';

/// Converts typed `anthropic_sdk_dart` message stream events into unified
/// preview events.
class AnthropicStreamEventAdapter {
  const AnthropicStreamEventAdapter();

  Stream<StreamingMessageEvent> adaptPreview(
    Stream<anthropic.MessageStreamEvent> events,
  ) async* {
    String? messageId;
    final blockIdsByKey = <String, String>{};
    var startedMessage = false;

    String blockKey(int index, StreamingContentBlockType type) =>
        '$index:${type.name}';

    await for (final event in events) {
      if (event is anthropic.MessageStartEvent) {
        messageId = event.message.id;
        if (!startedMessage) {
          startedMessage = true;
          yield StreamingMessageStartEvent(
            messageId: messageId!,
            providerMetadata: {'message_id': messageId},
          );
        } else {
          yield StreamingMessageStartEvent(messageId: messageId!);
        }
        continue;
      }

      if (event is anthropic.ContentBlockStartEvent) {
        final currentMessageId = messageId ?? 'anthropic_message';
        if (!startedMessage) {
          startedMessage = true;
          yield StreamingMessageStartEvent(messageId: currentMessageId);
        }
        final block = event.contentBlock;
        final blockType = block is anthropic.ToolUseBlock
            ? StreamingContentBlockType.toolUse
            : block is anthropic.ThinkingBlock
                ? StreamingContentBlockType.thinking
                : StreamingContentBlockType.text;
        final blockId = block is anthropic.ToolUseBlock
            ? '$currentMessageId:tool:${block.id}'
            : '$currentMessageId:block:${event.index}:${blockType.name}';
        blockIdsByKey[blockKey(event.index, blockType)] = blockId;
        if (block is anthropic.ToolUseBlock) {
          yield StreamingContentBlockStartEvent(
            messageId: currentMessageId,
            contentBlockId: blockId,
            blockType: StreamingContentBlockType.toolUse,
            toolUseId: block.id,
            toolName: block.name,
          );
        } else if (block is anthropic.TextBlock) {
          yield StreamingContentBlockStartEvent(
            messageId: currentMessageId,
            contentBlockId: blockId,
            blockType: StreamingContentBlockType.text,
          );
        } else if (block is anthropic.ThinkingBlock) {
          yield StreamingContentBlockStartEvent(
            messageId: currentMessageId,
            contentBlockId: blockId,
            blockType: StreamingContentBlockType.thinking,
          );
        }
        continue;
      }

      if (event is anthropic.ContentBlockDeltaEvent) {
        final currentMessageId = messageId ?? 'anthropic_message';
        final delta = event.delta;
        final inferredType = delta is anthropic.TextDelta
            ? StreamingContentBlockType.text
            : delta is anthropic.ThinkingDelta
                ? StreamingContentBlockType.thinking
                : delta is anthropic.InputJsonDelta
                    ? StreamingContentBlockType.toolUse
                    : delta is anthropic.SignatureDelta
                        ? StreamingContentBlockType.thinking
                    : null;
        if (inferredType == null) {
          continue;
        }
        var blockId = blockIdsByKey[blockKey(event.index, inferredType)];
        if (blockId == null) {
          blockId = inferredType == StreamingContentBlockType.toolUse
              ? '$currentMessageId:tool:index_${event.index}'
              : '$currentMessageId:auto:${event.index}:${inferredType.name}';
          blockIdsByKey[blockKey(event.index, inferredType)] = blockId;
          yield StreamingContentBlockStartEvent(
            messageId: currentMessageId,
            contentBlockId: blockId,
            blockType: inferredType,
          );
        }
        if (delta is anthropic.TextDelta) {
          yield StreamingContentBlockDeltaEvent(
            messageId: currentMessageId,
            contentBlockId: blockId,
            deltaType: StreamingContentDeltaType.text,
            value: delta.text,
          );
        } else if (delta is anthropic.ThinkingDelta) {
          yield StreamingContentBlockDeltaEvent(
            messageId: currentMessageId,
            contentBlockId: blockId,
            deltaType: StreamingContentDeltaType.thinking,
            value: delta.thinking,
          );
        } else if (delta is anthropic.InputJsonDelta) {
          yield StreamingContentBlockDeltaEvent(
            messageId: currentMessageId,
            contentBlockId: blockId,
            deltaType: StreamingContentDeltaType.inputJson,
            value: delta.partialJson,
          );
        } else if (delta is anthropic.SignatureDelta) {
          yield StreamingContentBlockDeltaEvent(
            messageId: currentMessageId,
            contentBlockId: blockId,
            deltaType: StreamingContentDeltaType.signature,
            value: delta.signature,
          );
        }
        continue;
      }

      if (event is anthropic.ContentBlockStopEvent) {
        final currentMessageId = messageId ?? 'anthropic_message';
        for (final type in StreamingContentBlockType.values) {
          final blockId = blockIdsByKey[blockKey(event.index, type)];
          if (blockId == null) {
            continue;
          }
          yield StreamingContentBlockStopEvent(
            messageId: currentMessageId,
            contentBlockId: blockId,
          );
        }
        continue;
      }

      if (event is anthropic.MessageStopEvent) {
        final currentMessageId = messageId ?? 'anthropic_message';
        yield StreamingMessageStopEvent(messageId: currentMessageId);
        continue;
      }

      if (event is anthropic.PingEvent || event is anthropic.MessageDeltaEvent) {
        final currentMessageId = messageId ?? 'anthropic_message';
        if (!startedMessage) {
          startedMessage = true;
          yield StreamingMessageStartEvent(messageId: currentMessageId);
        } else {
          yield StreamingMessageStartEvent(messageId: currentMessageId);
        }
        continue;
      }

      if (event is anthropic.ErrorEvent) {
        throw StateError(
          'Anthropic stream error: ${event.errorType}: ${event.message}',
        );
      }
    }
  }
}
