import 'package:openai_dart/openai_dart.dart' as oai;

import '../streaming_planner_chunk.dart';
import 'stream_tool_call_tracker.dart';

/// Converts `openai_dart` responses stream events into planner chunks.
class ResponsesStreamEventAdapter {
  const ResponsesStreamEventAdapter();

  Stream<StreamingPlannerChunk> adapt(
    Stream<oai.ResponseStreamEvent> events,
  ) async* {
    final emittedReasoningChunks = <String>{};
    final toolCallTracker = StreamToolCallTracker();

    await for (final event in events) {
      yield* adaptEvent(
        event,
        emittedReasoningChunks: emittedReasoningChunks,
        toolCallTracker: toolCallTracker,
      );
    }
    yield const StreamingPlannerChunk.streamCompleted();
  }

  Stream<StreamingPlannerChunk> adaptEvent(
    oai.ResponseStreamEvent event, {
    Set<String>? emittedReasoningChunks,
    StreamToolCallTracker? toolCallTracker,
  }) async* {
    final localReasoningChunks = emittedReasoningChunks ?? <String>{};
    final localToolCallTracker = toolCallTracker ?? StreamToolCallTracker();
    final data = event.toJson();
    final type = data['type'];
    final delta = data['delta'];
    final providerMetadata = _extractProviderMetadata(data);

    if (type == 'response.output_text.delta' &&
        delta is String &&
        delta.isNotEmpty) {
      yield StreamingPlannerChunk.contentDelta(
        delta,
        providerMetadata: providerMetadata,
      );
      return;
    }

    if ((type == 'response.reasoning.delta' ||
            type == 'response.reasoning_summary_text.delta') &&
        delta is String &&
        delta.isNotEmpty) {
      yield StreamingPlannerChunk.reasoningDelta(
        delta,
        providerMetadata: providerMetadata,
      );
      return;
    }

    if (type == 'response.output_item.added') {
      final item = data['item'];
      if (item is! Map<String, dynamic>) {
        return;
      }
      if (item['type'] == 'function_call') {
        final outputIndex = _normalizeInt(data['output_index']);
        yield localToolCallTracker.started(
          index: outputIndex,
          providerCallId: _normalizeText(item['call_id'] ?? item['id']),
          toolName: _normalizeText(item['name']),
          providerMetadata: providerMetadata,
        );
        return;
      }
      final reasoningChunks = _extractReasoningSummaries(item);
      for (final chunk in reasoningChunks) {
        final dedupeKey = '${item['id'] ?? ''}:$chunk';
        if (localReasoningChunks.add(dedupeKey)) {
          yield StreamingPlannerChunk.reasoningDelta(chunk);
        }
      }
      return;
    }

    if (type == 'response.function_call_arguments.delta' &&
        delta is String &&
        delta.isNotEmpty) {
      final outputIndex = _normalizeInt(data['output_index']);
      yield localToolCallTracker.argumentsDelta(
        index: outputIndex,
        providerCallId:
            _normalizeText(data['call_id'] ?? data['item_id'] ?? data['id']),
        toolName: _normalizeText(data['name']),
        argumentsTextDelta: delta,
        providerMetadata: providerMetadata,
      );
      return;
    }

    if (type == 'response.function_call_arguments.done') {
      final outputIndex = _normalizeInt(data['output_index']);
      yield localToolCallTracker.completed(
        index: outputIndex,
        providerCallId:
            _normalizeText(data['call_id'] ?? data['item_id'] ?? data['id']),
        toolName: _normalizeText(data['name']),
        providerMetadata: providerMetadata,
      );
    }
  }

  List<String> _extractReasoningSummaries(Map<String, dynamic> item) {
    if (item['type'] != 'reasoning') return const [];
    final summaries = item['summary'];
    if (summaries is! List) return const [];
    final chunks = <String>[];
    for (final entry in summaries) {
      if (entry is! Map) continue;
      final text = _normalizeText(entry['text'] ?? entry['summary_text']);
      if (text != null) {
        chunks.add(text);
      }
    }
    return chunks;
  }

  int? _normalizeInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  String? _normalizeText(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Map<String, dynamic>? _extractProviderMetadata(Map<String, dynamic> data) {
    final response = data['response'];
    if (response is Map<String, dynamic>) {
      final responseId = _normalizeText(response['id']);
      if (responseId != null) {
        return <String, dynamic>{'response_id': responseId};
      }
    }
    final responseId = _normalizeText(data['response_id'] ?? data['id']);
    if (responseId == null) {
      return null;
    }
    return <String, dynamic>{'response_id': responseId};
  }
}
