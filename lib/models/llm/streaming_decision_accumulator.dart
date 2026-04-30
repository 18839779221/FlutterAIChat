import 'dart:convert';

import '../agent/model_tool_call.dart';
import '../agent/model_turn_decision.dart';

import 'streaming_planner_chunk.dart';

/// Incrementally assembles a final [ModelTurnDecision] from provider stream
/// chunks while keeping streaming hidden from upper planner layers.
class StreamingDecisionAccumulator {
  final StringBuffer _assistantTextBuffer = StringBuffer();
  final StringBuffer _reasoningBuffer = StringBuffer();
  final List<_ToolCallDraft> _toolCallDrafts = <_ToolCallDraft>[];
  final Map<String, dynamic> _providerState = <String, dynamic>{};

  void consume(StreamingPlannerChunk chunk) {
    switch (chunk.type) {
      case StreamingPlannerChunkType.contentDelta:
        _mergeProviderState(chunk.providerMetadata);
        final content = _normalizeText(chunk.content);
        if (content != null) {
          _assistantTextBuffer.write(content);
        }
        return;
      case StreamingPlannerChunkType.reasoningDelta:
        _mergeProviderState(chunk.providerMetadata);
        final content = _normalizeText(chunk.content);
        if (content != null) {
          _reasoningBuffer.write(content);
        }
        return;
      case StreamingPlannerChunkType.toolCallStarted:
        _mergeProviderState(chunk.providerMetadata);
        _resolveDraft(chunk).mergeStarted(
          providerCallId: chunk.providerCallId,
          toolName: chunk.toolName,
        );
        return;
      case StreamingPlannerChunkType.toolCallArgumentsDelta:
        _mergeProviderState(chunk.providerMetadata);
        _resolveDraft(chunk).appendArgumentsDelta(
          chunk.argumentsTextDelta ?? '',
        );
        return;
      case StreamingPlannerChunkType.toolCallCompleted:
        _mergeProviderState(chunk.providerMetadata);
        _resolveDraft(chunk).markCompleted(
          providerCallId: chunk.providerCallId,
          toolName: chunk.toolName,
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
    for (final draft in _toolCallDrafts) {
      if (!draft.isCompleted || draft.toolName == null) {
        continue;
      }
      final arguments = draft.parseArguments();
      if (arguments == null) {
        return null;
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

    if (toolCalls.isEmpty && assistantMessage == null && visibleReasoning == null) {
      return null;
    }

    return ModelTurnDecision(
      toolCalls: toolCalls,
      assistantMessage: toolCalls.isNotEmpty ? assistantMessage : assistantMessage,
      visibleReasoning: visibleReasoning,
      providerState: Map<String, dynamic>.from(_providerState),
      isTerminal: toolCalls.isEmpty,
    );
  }

  _ToolCallDraft _resolveDraft(StreamingPlannerChunk chunk) {
    final providerCallId = _normalizeText(chunk.providerCallId);
    if (providerCallId != null) {
      final byId = _toolCallDrafts.where((draft) => draft.providerCallId == providerCallId);
      if (byId.isNotEmpty) {
        return byId.first;
      }
    }

    final toolName = _normalizeText(chunk.toolName);
    if (providerCallId == null && toolName != null) {
      final byName = _toolCallDrafts.where(
        (draft) => draft.providerCallId == null && draft.toolName == toolName && !draft.isCompleted,
      );
      if (byName.isNotEmpty) {
        return byName.first;
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
}

class _ToolCallDraft {
  _ToolCallDraft({
    required this.sequence,
  });

  final int sequence;
  String? providerCallId;
  String? toolName;
  bool isCompleted = false;
  final StringBuffer _rawArgumentsBuffer = StringBuffer();

  bool get canFinalizeOnStreamCompleted =>
      toolName != null || providerCallId != null || _rawArgumentsBuffer.isNotEmpty;

  void mergeStarted({
    String? providerCallId,
    String? toolName,
  }) {
    this.providerCallId = providerCallId ?? this.providerCallId;
    this.toolName = toolName ?? this.toolName;
  }

  void appendArgumentsDelta(String delta) {
    if (delta.isEmpty) {
      return;
    }
    _rawArgumentsBuffer.write(delta);
  }

  void markCompleted({
    String? providerCallId,
    String? toolName,
  }) {
    mergeStarted(providerCallId: providerCallId, toolName: toolName);
    isCompleted = true;
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
}
