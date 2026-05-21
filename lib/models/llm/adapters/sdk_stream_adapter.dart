import 'package:openai_dart/openai_dart.dart' as oai;

import '../streaming_planner_chunk.dart';

/// Converts `openai_dart` streaming events (`ChatStreamEvent`) into our
/// internal [StreamingPlannerChunk] stream for the existing
/// [StreamingDecisionAccumulator].
class SdkStreamAdapter {
  const SdkStreamAdapter();

  /// Adapt a stream of SDK [oai.ChatStreamEvent] into
  /// [StreamingPlannerChunk] that the accumulator can consume.
  Stream<StreamingPlannerChunk> adapt(
    Stream<oai.ChatStreamEvent> sdkStream,
  ) async* {
    await for (final event in sdkStream) {
      final choice = event.choices?.firstOrNull;
      if (choice == null) continue;

      final delta = choice.delta;

      // Reasoning content (DeepSeek R1 / OpenRouter)
      if (delta.reasoningContent != null &&
          delta.reasoningContent!.isNotEmpty) {
        yield StreamingPlannerChunk.reasoningDelta(delta.reasoningContent!);
      }
      if (delta.reasoning != null && delta.reasoning!.isNotEmpty) {
        yield StreamingPlannerChunk.reasoningDelta(delta.reasoning!);
      }

      // Text content
      if (delta.content != null && delta.content!.isNotEmpty) {
        yield StreamingPlannerChunk.contentDelta(delta.content!);
      }

      // Tool calls
      if (delta.toolCalls != null) {
        for (final tc in delta.toolCalls!) {
          final toolCallIndex = tc.index;
          final providerCallId = tc.id;
          final toolName = tc.function?.name;
          final argumentsDelta = tc.function?.arguments;

          // Emit toolCallStarted when we first see an id or name
          if (providerCallId != null || toolName != null) {
            yield StreamingPlannerChunk.toolCallStarted(
              toolCallIndex: toolCallIndex,
              providerCallId: providerCallId,
              toolName: toolName,
            );
          }

          // Emit argument deltas
          if (argumentsDelta != null && argumentsDelta.isNotEmpty) {
            yield StreamingPlannerChunk.toolCallArgumentsDelta(
              toolCallIndex: toolCallIndex,
              providerCallId: providerCallId,
              toolName: toolName,
              argumentsTextDelta: argumentsDelta,
            );
          }
        }
      }
    }
    yield const StreamingPlannerChunk.streamCompleted();
  }
}
