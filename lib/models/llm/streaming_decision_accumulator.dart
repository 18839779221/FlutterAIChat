import 'dart:convert';

import '../agent/model_tool_call.dart';
import '../chat/runtime_stream_entry.dart';
import '../agent/model_turn_decision.dart';
import '../../utils/logger.dart';

import 'streaming_planner_chunk.dart';

/// Incrementally assembles a final [ModelTurnDecision] from provider stream
/// chunks while keeping streaming hidden from upper planner layers.
class StreamingDecisionAccumulator {
  static const String _tag = 'StreamingDecisionAccumulator';

  final StringBuffer _assistantTextBuffer = StringBuffer();
  final StringBuffer _reasoningBuffer = StringBuffer();
  final List<_ToolCallDraft> _toolCallDrafts = <_ToolCallDraft>[];
  final Map<String, dynamic> _providerState = <String, dynamic>{};

  void consume(StreamingPlannerChunk chunk) {
    switch (chunk.type) {
      case StreamingPlannerChunkType.keepalive:
        _mergeProviderState(chunk.providerMetadata);
        return;
      case StreamingPlannerChunkType.contentDelta:
        _mergeProviderState(chunk.providerMetadata);
        final content = _nonEmptyText(chunk.content);
        if (content != null) {
          _assistantTextBuffer.write(content);
        }
        return;
      case StreamingPlannerChunkType.reasoningDelta:
        _mergeProviderState(chunk.providerMetadata);
        final content = _nonEmptyText(chunk.content);
        if (content != null) {
          _reasoningBuffer.write(content);
        }
        return;
      case StreamingPlannerChunkType.toolCallStarted:
        _mergeProviderState(chunk.providerMetadata);
        _resolveDraft(chunk).mergeStarted(
          toolCallIndex: chunk.toolCallIndex,
          providerCallId: chunk.providerCallId,
          toolName: chunk.toolName,
        );
        return;
      case StreamingPlannerChunkType.toolCallArgumentsDelta:
        _mergeProviderState(chunk.providerMetadata);
        _resolveDraft(chunk).appendArgumentsDelta(
          chunk.argumentsTextDelta ?? '',
          toolCallIndex: chunk.toolCallIndex,
          providerCallId: chunk.providerCallId,
          toolName: chunk.toolName,
        );
        return;
      case StreamingPlannerChunkType.toolCallCompleted:
        _mergeProviderState(chunk.providerMetadata);
        final completedDraft = _resolveDraft(chunk);
        completedDraft.markCompleted(
          toolCallIndex: chunk.toolCallIndex,
          providerCallId: chunk.providerCallId,
          toolName: chunk.toolName,
        );
        Logger.temp(
          _tag,
          'tool call draft completed',
          reason: 'diagnose anthropic create_artifact decision null',
          data: {
            'toolName': completedDraft.toolName,
            'providerCallId': completedDraft.providerCallId,
            'toolCallIndex': completedDraft.toolCallIndex,
            'rawArgumentsLength': completedDraft.rawArgumentsLength,
            'rawArgumentsHead': completedDraft.debugHeadPreview(),
            'rawArgumentsTail': completedDraft.debugTailPreview(),
          },
        );
        return;
      case StreamingPlannerChunkType.streamCompleted:
        _mergeProviderState(chunk.providerMetadata);
        for (final draft in _toolCallDrafts) {
          if (!draft.isCompleted && draft.canFinalizeOnStreamCompleted) {
            draft.isCompleted = true;
          }
        }
        return;
    }
  }

  ModelTurnDecision? buildDecision() {
    final toolCalls = <ModelToolCall>[];
    var droppedInvalidToolCalls = 0;
    for (final draft in _toolCallDrafts) {
      if (!draft.isCompleted || draft.toolName == null) {
        continue;
      }
      final arguments = draft.parseArguments();
      if (arguments == null) {
        Logger.temp(
          _tag,
          'tool call arguments parse failed',
          level: LogLevel.warning,
          reason: 'diagnose anthropic create_artifact decision null',
          data: {
            'toolName': draft.toolName,
            'providerCallId': draft.providerCallId,
            'toolCallIndex': draft.toolCallIndex,
            'rawArgumentsLength': draft.rawArgumentsLength,
            'rawArgumentsHead': draft.debugHeadPreview(),
            'rawArgumentsTail': draft.debugTailPreview(),
          },
        );
        droppedInvalidToolCalls += 1;
        continue;
      }
      toolCalls.add(
        ModelToolCall(
          providerCallId: draft.providerCallId,
          toolName: draft.toolName!,
          arguments: arguments,
          sequence: draft.sequence,
        ),
      );
    }

    final assistantMessage = _normalizeText(_assistantTextBuffer.toString());
    final visibleReasoning = _normalizeText(_reasoningBuffer.toString());

    if (toolCalls.isEmpty &&
        assistantMessage == null &&
        visibleReasoning == null &&
        droppedInvalidToolCalls == _toolCallDrafts
            .where((draft) => draft.isCompleted && draft.toolName != null)
            .length) {
      return null;
    }

    final providerState = Map<String, dynamic>.from(_providerState);
    _ensureAnthropicContentBlocks(
      providerState: providerState,
      toolCalls: toolCalls,
      assistantMessage: assistantMessage,
      visibleReasoning: visibleReasoning,
    );

    return ModelTurnDecision(
      toolCalls: toolCalls,
      assistantMessage: toolCalls.isNotEmpty ? assistantMessage : assistantMessage,
      visibleReasoning: visibleReasoning,
      providerState: providerState,
      isTerminal: toolCalls.isEmpty,
    );
  }

  /// Snapshot of the current accumulator state, exposed for adapters that
  /// need to assemble a provider-shaped raw assistant message from streamed
  /// fragments (see [ApiStyleAdapter.assembleRawFromStreamingSnapshot]).
  ///
  /// Read-only by design — accumulator continues to be the sole writer.
  StreamingDecisionAccumulatorSnapshot currentSnapshot() {
    final text = _assistantTextBuffer.toString();
    final reasoning = _reasoningBuffer.toString();
    return StreamingDecisionAccumulatorSnapshot(
      text: text.isEmpty ? null : text,
      reasoning: reasoning.isEmpty ? null : reasoning,
      toolCalls: [
        for (final draft in _toolCallDrafts)
          StreamingToolCallDraft(
            id: draft.providerCallId,
            toolName: draft.toolName,
            argumentsBuffer: draft.rawArgumentsText,
            sequence: draft.sequence,
            isDone: draft.isCompleted,
          ),
      ],
      providerState: Map<String, dynamic>.unmodifiable(_providerState),
    );
  }

  /// Returns a compact debug snapshot for logging when stream assembly fails.
  Map<String, dynamic> debugSnapshot() {
    return {
      'assistantTextLength': _assistantTextBuffer.length,
      'reasoningLength': _reasoningBuffer.length,
      'providerStateKeys': _providerState.keys.toList(growable: false),
      'toolDrafts': _toolCallDrafts
          .map(
            (draft) => {
              'sequence': draft.sequence,
              'toolCallIndex': draft.toolCallIndex,
              'providerCallId': draft.providerCallId,
              'toolName': draft.toolName,
              'isCompleted': draft.isCompleted,
              'rawArgumentsLength': draft.rawArgumentsLength,
              'canFinalizeOnStreamCompleted': draft.canFinalizeOnStreamCompleted,
            },
          )
          .toList(growable: false),
    };
  }

  List<RuntimeStreamEntry> runtimeSnapshots({
    required String turnId,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();
    final snapshots = <RuntimeStreamEntry>[];
    final assistantText = _assistantTextBuffer.toString();
    if (assistantText.isNotEmpty) {
      snapshots.add(
        RuntimeStreamEntry(
          turnId: turnId,
          entryId: '$turnId-assistant-text',
          kind: RuntimeStreamEntryKind.assistantText,
          createdAt: timestamp,
          updatedAt: timestamp,
          text: assistantText,
        ),
      );
    }

    final reasoningText = _reasoningBuffer.toString();
    if (reasoningText.isNotEmpty) {
      snapshots.add(
        RuntimeStreamEntry(
          turnId: turnId,
          entryId: '$turnId-reasoning',
          kind: RuntimeStreamEntryKind.reasoning,
          createdAt: timestamp,
          updatedAt: timestamp,
          text: reasoningText,
        ),
      );
    }

    for (final draft in _toolCallDrafts) {
      if (draft.rawArgumentsLength == 0) {
        continue;
      }
      snapshots.add(
        RuntimeStreamEntry(
          turnId: turnId,
          entryId: draft.runtimeEntryId(turnId),
          kind: RuntimeStreamEntryKind.toolCallArguments,
          providerCallId: draft.providerCallId,
          toolName: draft.toolName,
          createdAt: timestamp,
          updatedAt: timestamp,
          text: draft.rawArgumentsText,
          payload: {
            'sequence': draft.sequence,
            if (draft.toolCallIndex != null) 'toolCallIndex': draft.toolCallIndex,
            'isCompleted': draft.isCompleted,
          },
        ),
      );
    }
    return snapshots;
  }

  _ToolCallDraft _resolveDraft(StreamingPlannerChunk chunk) {
    final toolCallIndex = chunk.toolCallIndex;
    if (toolCallIndex != null) {
      for (final draft in _toolCallDrafts) {
        if (draft.toolCallIndex == toolCallIndex) {
          return draft;
        }
      }
    }

    final draft = _ToolCallDraft(sequence: _toolCallDrafts.length);
    _toolCallDrafts.add(draft);
    return draft;
  }

  void _mergeProviderState(Map<String, dynamic>? metadata) {
    if (metadata == null || metadata.isEmpty) {
      return;
    }
    for (final entry in metadata.entries) {
      _providerState[entry.key] = entry.value;
    }
  }

  void _ensureAnthropicContentBlocks({
    required Map<String, dynamic> providerState,
    required List<ModelToolCall> toolCalls,
    required String? assistantMessage,
    required String? visibleReasoning,
  }) {
    if (providerState.containsKey('content_blocks')) {
      return;
    }
    final messageId = providerState['message_id'];
    final hasStructuredAnthropicLikeState = toolCalls.isNotEmpty ||
        assistantMessage != null ||
        visibleReasoning != null;
    if ((messageId is! String || messageId.trim().isEmpty) &&
        !hasStructuredAnthropicLikeState) {
      return;
    }

    final contentBlocks = <Map<String, dynamic>>[];
    if (visibleReasoning != null) {
      contentBlocks.add({
        'type': 'thinking',
        'thinking': visibleReasoning,
      });
    }
    for (final toolCall in toolCalls) {
      contentBlocks.add({
        'type': 'tool_use',
        'id': toolCall.providerCallId,
        'name': toolCall.toolName,
        'input': toolCall.arguments,
      });
    }
    if (assistantMessage != null) {
      contentBlocks.add({
        'type': 'text',
        'text': assistantMessage,
      });
    }
    if (contentBlocks.isNotEmpty) {
      providerState['content_blocks'] = contentBlocks;
    }
  }

  String? _normalizeText(String? value) {
    if (value == null) {
      return null;
    }
    if (value.isEmpty) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : value;
  }

  String? _nonEmptyText(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }
}

class _ToolCallDraft {
  _ToolCallDraft({
    required this.sequence,
  });

  final int sequence;
  String? providerCallId;
  String? toolName;
  bool isCompleted = false;
  int? toolCallIndex;
  final StringBuffer _rawArgumentsBuffer = StringBuffer();

  int get rawArgumentsLength => _rawArgumentsBuffer.length;
  String get rawArgumentsText => _rawArgumentsBuffer.toString();

  bool get canFinalizeOnStreamCompleted =>
      toolCallIndex != null || toolName != null || _rawArgumentsBuffer.isNotEmpty;

  void mergeStarted({
    int? toolCallIndex,
    String? providerCallId,
    String? toolName,
  }) {
    this.toolCallIndex = toolCallIndex ?? this.toolCallIndex;
    this.providerCallId = providerCallId ?? this.providerCallId;
    this.toolName = toolName ?? this.toolName;
  }

  void appendArgumentsDelta(
    String delta, {
    int? toolCallIndex,
    String? providerCallId,
    String? toolName,
  }) {
    if (delta.isEmpty) {
      return;
    }
    this.toolCallIndex = toolCallIndex ?? this.toolCallIndex;
    this.providerCallId = providerCallId ?? this.providerCallId;
    this.toolName = toolName ?? this.toolName;
    _rawArgumentsBuffer.write(delta);
  }

  void markCompleted({
    int? toolCallIndex,
    String? providerCallId,
    String? toolName,
  }) {
    mergeStarted(
      toolCallIndex: toolCallIndex,
      providerCallId: providerCallId,
      toolName: toolName,
    );
    isCompleted = true;
  }

  String runtimeEntryId(String turnId) {
    final normalizedProviderCallId = providerCallId?.trim();
    if (normalizedProviderCallId != null && normalizedProviderCallId.isNotEmpty) {
      return '$turnId-tool-$normalizedProviderCallId';
    }
    return '$turnId-tool-$sequence';
  }

  Map<String, dynamic>? parseArguments() {
    final raw = _rawArgumentsBuffer.toString().trim();
    if (raw.isEmpty) {
      return const <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  String debugHeadPreview([int maxChars = 200]) {
    final raw = _rawArgumentsBuffer.toString();
    if (raw.length <= maxChars) {
      return raw;
    }
    return raw.substring(0, maxChars);
  }

  String debugTailPreview([int maxChars = 200]) {
    final raw = _rawArgumentsBuffer.toString();
    if (raw.length <= maxChars) {
      return raw;
    }
    return raw.substring(raw.length - maxChars);
  }
}

/// Read-only view of the accumulator state at a point in time.
class StreamingDecisionAccumulatorSnapshot {
  final String? text;
  final String? reasoning;
  final List<StreamingToolCallDraft> toolCalls;
  final Map<String, dynamic> providerState;

  const StreamingDecisionAccumulatorSnapshot({
    required this.text,
    required this.reasoning,
    required this.toolCalls,
    required this.providerState,
  });
}

/// Read-only view of one in-progress tool call.
class StreamingToolCallDraft {
  final String? id;
  final String? toolName;
  final String argumentsBuffer;
  final int sequence;
  final bool isDone;

  const StreamingToolCallDraft({
    required this.id,
    required this.toolName,
    required this.argumentsBuffer,
    required this.sequence,
    required this.isDone,
  });
}
