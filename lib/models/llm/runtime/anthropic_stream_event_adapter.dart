import 'dart:async';

import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as anthropic;

import '../streaming_planner_chunk.dart';
import 'stream_tool_call_tracker.dart';

/// Converts typed `anthropic_sdk_dart` message stream events into planner
/// chunks consumed by `StreamingDecisionAccumulator`.
class AnthropicStreamEventAdapter {
  const AnthropicStreamEventAdapter();

  Stream<StreamingPlannerChunk> adapt(
    Stream<anthropic.MessageStreamEvent> events,
  ) async* {
    final toolCallTracker = StreamToolCallTracker();

    await for (final event in events) {
      switch (event) {
        case anthropic.ContentBlockStartEvent():
          final block = event.contentBlock;
          if (block is anthropic.ToolUseBlock) {
            yield toolCallTracker.started(
              index: event.index,
              toolName: block.name,
              providerCallId: block.id,
            );
          }
        case anthropic.ContentBlockDeltaEvent():
          final delta = event.delta;
          if (delta is anthropic.TextDelta) {
            yield StreamingPlannerChunk.contentDelta(delta.text);
          } else if (delta is anthropic.ThinkingDelta) {
            yield StreamingPlannerChunk.reasoningDelta(delta.thinking);
          } else if (delta is anthropic.InputJsonDelta) {
            yield toolCallTracker.argumentsDelta(
              index: event.index,
              argumentsTextDelta: delta.partialJson,
            );
          } else if (delta is anthropic.SignatureDelta) {
            yield StreamingPlannerChunk.keepalive(
              providerMetadata: <String, dynamic>{
                'anthropic_thinking_signature': delta.signature,
              },
            );
          }
        case anthropic.ContentBlockStopEvent():
          yield toolCallTracker.completed(
            index: event.index,
          );
        case anthropic.MessageStopEvent():
          yield const StreamingPlannerChunk.streamCompleted();
        case anthropic.PingEvent():
          yield const StreamingPlannerChunk.keepalive(
            providerMetadata: <String, dynamic>{
              'anthropic_event_type': 'ping',
            },
          );
        case anthropic.ErrorEvent():
          throw StateError(
            'Anthropic stream error: ${event.errorType}: ${event.message}',
          );
        case anthropic.MessageStartEvent():
          yield StreamingPlannerChunk.keepalive(
            providerMetadata: <String, dynamic>{
              'message_id': event.message.id,
            },
          );
        case anthropic.MessageDeltaEvent():
          // Extract usage from message delta
          final usage = event.usage;
          if (usage != null) {
            yield StreamingPlannerChunk.keepalive(
              providerMetadata: <String, dynamic>{
                '_usage': <String, dynamic>{
                  'input_tokens': usage.inputTokens,
                  'output_tokens': usage.outputTokens,
                },
              },
            );
          }
          continue;
      }
    }
  }
}
