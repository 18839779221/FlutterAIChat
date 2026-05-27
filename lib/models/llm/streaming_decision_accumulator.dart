import 'dart:convert';

import '../agent/model_tool_call.dart';
import '../agent/model_turn_decision.dart';
import '../../utils/logger.dart';
import 'streaming_message_event.dart';

/// Incrementally assembles a final [ModelTurnDecision] from unified preview
/// events while keeping provider streaming hidden from upper planner layers.
class StreamingDecisionAccumulator {
  static const String _tag = 'StreamingDecisionAccumulator';

  _StreamingMessageDraft? _messageDraft;
  final Map<String, dynamic> _providerState = <String, dynamic>{};
  void consume(StreamingMessageEvent event) {
    _mergeProviderState(event.providerMetadata);

    if (event is StreamingMessageStartEvent) {
      _messageDraft ??= _StreamingMessageDraft(messageId: event.messageId);
      return;
    }
    if (event is StreamingMessageStopEvent) {
      final message = _ensureMessage(event.messageId);
      message.isStopped = true;
      return;
    }
    if (event is StreamingContentBlockStartEvent) {
      final message = _ensureMessage(event.messageId);
      if (message.blockById(event.contentBlockId) != null) {
        Logger.temp(
          _tag,
          'duplicate content block start ignored',
          level: LogLevel.warning,
          reason: 'guard invalid preview event lifecycle',
          data: {
            'messageId': event.messageId,
            'contentBlockId': event.contentBlockId,
          },
        );
        return;
      }
      message.blocks.add(
        _StreamingContentBlockDraft(
          contentBlockId: event.contentBlockId,
          type: event.blockType,
          toolUseId: event.toolUseId,
          toolName: event.toolName,
        ),
      );
      return;
    }
    if (event is StreamingContentBlockDeltaEvent) {
      final block = _messageDraft?.blockById(event.contentBlockId);
      if (block == null) {
        Logger.temp(
          _tag,
          'content block delta ignored without start',
          level: LogLevel.warning,
          reason: 'guard invalid preview event lifecycle',
          data: {
            'messageId': event.messageId,
            'contentBlockId': event.contentBlockId,
            'deltaType': event.deltaType.name,
          },
        );
        return;
      }
      if (event.deltaType == StreamingContentDeltaType.signature) {
        block.metadataBuffer.write(event.value);
      } else {
        block.textBuffer.write(event.value);
      }
      return;
    }
    if (event is StreamingContentBlockStopEvent) {
      final block = _messageDraft?.blockById(event.contentBlockId);
      if (block == null) {
        Logger.temp(
          _tag,
          'content block stop ignored without start',
          level: LogLevel.warning,
          reason: 'guard invalid preview event lifecycle',
          data: {
            'messageId': event.messageId,
            'contentBlockId': event.contentBlockId,
          },
        );
        return;
      }
      block.isStopped = true;
    }
  }

  ModelTurnDecision? buildDecision() {
    final message = _messageDraft;
    if (message == null) {
      return null;
    }

    final assistantBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    final toolCalls = <ModelToolCall>[];
    var droppedInvalidToolCalls = 0;

    for (var i = 0; i < message.blocks.length; i += 1) {
      final block = message.blocks[i];
      if (block.type == StreamingContentBlockType.text) {
        assistantBuffer.write(block.text);
        continue;
      }
      if (block.type == StreamingContentBlockType.thinking) {
        reasoningBuffer.write(block.text);
        continue;
      }

      final toolName = block.toolName;
      if (toolName == null) {
        continue;
      }
      final arguments = _parseArguments(block.text);
      if (arguments == null) {
        Logger.temp(
          _tag,
          'tool call arguments parse failed',
          level: LogLevel.warning,
          reason: 'streaming decision accumulator rejected invalid tool block',
          data: {
            'messageId': message.messageId,
            'contentBlockId': block.contentBlockId,
            'toolName': toolName,
            'toolUseId': block.toolUseId,
            'rawArgumentsLength': block.text.length,
          },
        );
        droppedInvalidToolCalls += 1;
        continue;
      }
      toolCalls.add(
        ModelToolCall(
          providerCallId: block.toolUseId,
          toolName: toolName,
          arguments: arguments,
          sequence: i,
        ),
      );
    }

    final assistantMessage = _normalizeText(assistantBuffer.toString());
    final visibleReasoning = _normalizeText(reasoningBuffer.toString());

    if (toolCalls.isEmpty &&
        assistantMessage == null &&
        visibleReasoning == null &&
        droppedInvalidToolCalls ==
            message.blocks
                .where((block) => block.type == StreamingContentBlockType.toolUse)
                .length) {
      return null;
    }

    final providerState = Map<String, dynamic>.from(_providerState);
    _ensureAnthropicContentBlocks(
      providerState: providerState,
      blocks: message.blocks,
    );
    if ((providerState['message_id'] ?? '').toString().trim().isEmpty) {
      providerState['message_id'] = message.messageId;
    }

    return ModelTurnDecision(
      toolCalls: toolCalls,
      assistantMessage: assistantMessage,
      visibleReasoning: visibleReasoning,
      providerState: providerState,
      isTerminal: toolCalls.isEmpty,
    );
  }

  StreamingDecisionAccumulatorSnapshot currentSnapshot() {
    final message = _messageDraft;
    return StreamingDecisionAccumulatorSnapshot(
      messageId: message?.messageId,
      blocks: [
        if (message != null)
          for (final block in message.blocks)
            StreamingContentBlockSnapshot(
              contentBlockId: block.contentBlockId,
              type: block.type,
              toolUseId: block.toolUseId,
              toolName: block.toolName,
              text: block.text,
              metadataText: block.metadataText,
              isStopped: block.isStopped,
            ),
      ],
      providerState: Map<String, dynamic>.unmodifiable(_providerState),
    );
  }

  Map<String, dynamic> debugSnapshot() {
    final message = _messageDraft;
    final assistantChars = message == null
        ? 0
        : message.blocks
            .where((block) => block.type == StreamingContentBlockType.text)
            .fold<int>(0, (sum, block) => sum + block.text.length);
    final reasoningChars = message == null
        ? 0
        : message.blocks
            .where((block) => block.type == StreamingContentBlockType.thinking)
            .fold<int>(0, (sum, block) => sum + block.text.length);

    return {
      'messageId': message?.messageId,
      'assistantTextLength': assistantChars,
      'reasoningLength': reasoningChars,
      'providerStateKeys': _providerState.keys.toList(growable: false),
      'toolDrafts': [
        if (message != null)
          for (final block in message.blocks.where(
            (block) => block.type == StreamingContentBlockType.toolUse,
          ))
            {
              'contentBlockId': block.contentBlockId,
              'providerCallId': block.toolUseId,
              'toolName': block.toolName,
              'isCompleted': block.isStopped,
              'rawArgumentsLength': block.text.length,
            },
      ],
    };
  }

  _StreamingMessageDraft _ensureMessage(String messageId) {
    final current = _messageDraft;
    if (current != null) {
      return current;
    }
    final created = _StreamingMessageDraft(messageId: messageId);
    _messageDraft = created;
    return created;
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
    required List<_StreamingContentBlockDraft> blocks,
  }) {
    if (providerState.containsKey('content_blocks')) {
      return;
    }
    final contentBlocks = <Map<String, dynamic>>[];
    for (final block in blocks) {
      if (block.type == StreamingContentBlockType.text) {
        if (block.text.isEmpty) {
          continue;
        }
        contentBlocks.add({
          'type': 'text',
          'text': block.text,
        });
        continue;
      }
      if (block.type == StreamingContentBlockType.thinking) {
        if (block.text.isEmpty) {
          continue;
        }
        contentBlocks.add({
          'type': 'thinking',
          'thinking': block.text,
          if (block.metadataText.isNotEmpty) 'signature': block.metadataText,
        });
        continue;
      }
      final arguments = _parseArguments(block.text);
      if (block.toolName == null || arguments == null) {
        continue;
      }
      contentBlocks.add({
        'type': 'tool_use',
        'id': block.toolUseId,
        'name': block.toolName,
        'input': arguments,
      });
    }
    if (contentBlocks.isNotEmpty) {
      providerState['content_blocks'] = contentBlocks;
    }
  }

  Map<String, dynamic>? _parseArguments(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  String? _normalizeText(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : value;
  }

}

class _StreamingMessageDraft {
  _StreamingMessageDraft({
    required this.messageId,
  });

  final String messageId;
  final List<_StreamingContentBlockDraft> blocks = [];
  bool isStopped = false;

  _StreamingContentBlockDraft? blockById(String contentBlockId) {
    for (final block in blocks) {
      if (block.contentBlockId == contentBlockId) {
        return block;
      }
    }
    return null;
  }
}

class _StreamingContentBlockDraft {
  _StreamingContentBlockDraft({
    required this.contentBlockId,
    required this.type,
    this.toolUseId,
    this.toolName,
  });

  final String contentBlockId;
  final StreamingContentBlockType type;
  final String? toolUseId;
  final String? toolName;
  final StringBuffer textBuffer = StringBuffer();
  final StringBuffer metadataBuffer = StringBuffer();
  bool isStopped = false;

  String get text => textBuffer.toString();

  String get metadataText => metadataBuffer.toString();
}

/// Read-only view of one accumulated content block.
class StreamingContentBlockSnapshot {
  const StreamingContentBlockSnapshot({
    required this.contentBlockId,
    required this.type,
    required this.text,
    required this.isStopped,
    this.toolUseId,
    this.toolName,
    this.metadataText,
  });

  /// Stable content block id in provider message scope.
  final String contentBlockId;

  /// Semantic content block type.
  final StreamingContentBlockType type;

  /// Provider tool-use id when this block is a tool use.
  final String? toolUseId;

  /// Provider tool name when this block is a tool use.
  final String? toolName;

  /// Accumulated text/thinking/input_json payload.
  final String text;

  /// Auxiliary metadata such as Anthropic thinking signatures.
  final String? metadataText;

  /// Whether the provider emitted a stop event for this block.
  final bool isStopped;
}

/// Read-only view of the accumulator state at a point in time.
class StreamingDecisionAccumulatorSnapshot {
  const StreamingDecisionAccumulatorSnapshot({
    this.messageId,
    List<StreamingContentBlockSnapshot>? blocks,
    required this.providerState,
    String? text,
    String? reasoning,
    List<StreamingToolCallDraft> toolCalls = const <StreamingToolCallDraft>[],
  })  : _blocks = blocks,
        _text = text,
        _reasoning = reasoning,
        _toolCalls = toolCalls;

  /// Stable message id for the current draft message.
  final String? messageId;

  /// Ordered content blocks in emission order.
  final List<StreamingContentBlockSnapshot>? _blocks;

  /// Provider metadata merged from streaming events.
  final Map<String, dynamic> providerState;

  /// Legacy-compatible aggregated assistant text view.
  final String? _text;

  /// Legacy-compatible aggregated reasoning text view.
  final String? _reasoning;

  /// Legacy-compatible aggregated tool call view.
  final List<StreamingToolCallDraft> _toolCalls;

  List<StreamingContentBlockSnapshot> get blocks {
    final explicitBlocks = _blocks;
    if (explicitBlocks != null) {
      return explicitBlocks;
    }
    final resolvedMessageId = messageId ?? 'snapshot';
    final legacyReasoning = _reasoning;
    final legacyText = _text;
    final legacyToolCalls = _toolCalls;
    return [
      if (legacyReasoning != null)
        StreamingContentBlockSnapshot(
          contentBlockId: '$resolvedMessageId:thinking',
          type: StreamingContentBlockType.thinking,
          text: legacyReasoning,
          isStopped: true,
        ),
      if (legacyText != null)
        StreamingContentBlockSnapshot(
          contentBlockId: '$resolvedMessageId:text',
          type: StreamingContentBlockType.text,
          text: legacyText,
          isStopped: true,
        ),
      for (final toolCall in legacyToolCalls)
        StreamingContentBlockSnapshot(
          contentBlockId: '$resolvedMessageId:tool:${toolCall.sequence}',
          type: StreamingContentBlockType.toolUse,
          toolUseId: toolCall.id,
          toolName: toolCall.toolName,
          text: toolCall.argumentsBuffer,
          isStopped: toolCall.isDone,
        ),
    ];
  }

  String? get text => _text ?? resolvedText;

  String? get reasoning => _reasoning ?? resolvedReasoning;

  List<StreamingToolCallDraft> get toolCalls =>
      _toolCalls.isNotEmpty ? _toolCalls : resolvedToolCalls;

  String? get resolvedText {
    final buffer = StringBuffer();
    for (final block in blocks) {
      if (block.type == StreamingContentBlockType.text) {
        buffer.write(block.text);
      }
    }
    final value = buffer.toString();
    return value.isEmpty ? null : value;
  }

  String? get resolvedReasoning {
    final buffer = StringBuffer();
    for (final block in blocks) {
      if (block.type == StreamingContentBlockType.thinking) {
        buffer.write(block.text);
      }
    }
    final value = buffer.toString();
    return value.isEmpty ? null : value;
  }

  List<StreamingToolCallDraft> get resolvedToolCalls {
    return [
      for (var i = 0; i < blocks.length; i += 1)
        if (blocks[i].type == StreamingContentBlockType.toolUse)
          StreamingToolCallDraft(
            id: blocks[i].toolUseId,
            toolName: blocks[i].toolName,
            argumentsBuffer: blocks[i].text,
            sequence: i,
            isDone: blocks[i].isStopped,
          ),
    ];
  }
}

/// Legacy-compatible read-only view of one in-progress tool call.
class StreamingToolCallDraft {
  const StreamingToolCallDraft({
    required this.id,
    required this.toolName,
    required this.argumentsBuffer,
    required this.sequence,
    required this.isDone,
  });

  final String? id;
  final String? toolName;
  final String argumentsBuffer;
  final int sequence;
  final bool isDone;
}
