import 'package:ai_chat/models/artifact/artifact_turn_projection.dart';
import 'package:ai_chat/models/chat/assistant_turn_block.dart';
import 'package:ai_chat/models/chat/chat_timeline_projection.dart';
import 'package:ai_chat/models/chat/runtime_assistant_draft.dart';
import 'package:ai_chat/models/chat/runtime_streaming_preview_state.dart';
import 'package:ai_chat/models/chat/tool_presentation_event.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/services/artifact/runtime_artifact_preview_parser.dart';
import 'package:ai_chat/services/artifact/artifact_turn_resolver.dart';
import 'package:ai_chat/services/chat_block_builder.dart';
import 'package:ai_chat/services/tool_presentation_block_projector.dart';

/// Builds one consistent projection snapshot for timeline rendering and
/// waiting-state providers so consumers do not independently rescan messages.
class ChatTimelineProjectionService {
  ChatTimelineProjectionService({
    ChatBlockBuilder? blockBuilder,
    ArtifactTurnResolver? artifactTurnResolver,
    ToolPresentationBlockProjector? toolBlockProjector,
  })  : _blockBuilder = blockBuilder ?? ChatBlockBuilder(),
        _artifactTurnResolver = artifactTurnResolver,
        _runtimeArtifactPreviewParser = const RuntimeArtifactPreviewParser(),
        _toolBlockProjector =
            toolBlockProjector ?? const ToolPresentationBlockProjector();

  final ChatBlockBuilder _blockBuilder;
  final ArtifactTurnResolver? _artifactTurnResolver;
  final RuntimeArtifactPreviewParser _runtimeArtifactPreviewParser;
  final ToolPresentationBlockProjector _toolBlockProjector;

  ChatTimelineProjection build({
    required List<ChatMessage> messages,
    int? groupId,
    RuntimeAssistantDraft? runtimeDraft,
    RuntimeStreamingPreviewState runtimePreviewState =
        const RuntimeStreamingPreviewState(),
  }) {
    final runtimeTurnId = _resolveActiveRuntimeTurnId(
      messages: messages,
      groupId: groupId,
      runtimeDraft: runtimeDraft,
    );
    final toolPresentationEvents = _buildToolPresentationEvents(
      messages: messages,
      groupId: groupId,
    );
    final blocks = _buildNonToolBlocks(
      messages: messages,
      groupId: groupId,
    );
    final toolBlocks = _toolBlockProjector.project(
      events: toolPresentationEvents,
    );
    final artifactBlocks = _buildArtifactBlocks(
      messages: messages,
      groupId: groupId,
    );
    final runtimeDraftBlock = _buildRuntimeDraftBlock(runtimeDraft);
    final runtimeArtifactBlocks = _buildRuntimeArtifactBlocks(
      projectedAssistantBlocks: [
        ...blocks,
        ...toolBlocks,
        if (runtimeDraftBlock != null) runtimeDraftBlock,
      ],
      runtimePreviewState: runtimePreviewState,
      resolvedTurnId: runtimeTurnId,
    );
    return ChatTimelineProjection(
      activeAskUserQuestionMessage: _findActiveAskUserQuestion(messages),
      pendingToolConfirmation: _findPendingConfirmation(messages),
      assistantBlocks: _mergeBlocks(
        baseBlocks: [
          ...blocks,
          ...toolBlocks,
          if (runtimeDraftBlock != null) runtimeDraftBlock,
        ],
        artifactBlocks: [
          ...artifactBlocks,
          ...runtimeArtifactBlocks,
        ],
      ),
      toolPresentationEvents: toolPresentationEvents,
      runtimeAssistantDraft: runtimeDraft,
      runtimePreviewState: runtimePreviewState,
    );
  }

  List<AssistantTurnBlock> _buildNonToolBlocks({
    required List<ChatMessage> messages,
    required int? groupId,
  }) {
    final nonToolMessages = messages
        .where(
          (message) => message.isUser || _belongsToNonToolBlockProjection(message),
        )
        .toList(growable: false);
    return _blockBuilder
        .buildAssistantBlocks(
          messages: nonToolMessages,
          groupId: groupId,
        )
        .toList(growable: false);
  }

  List<ToolPresentationEvent> _buildToolPresentationEvents({
    required List<ChatMessage> messages,
    required int? groupId,
  }) {
    final sortedMessages = [...messages]..sort(compareChatMessagesForTimeline);
    final events = <ToolPresentationEvent>[];
    String? currentTurnId;
    var fallbackUserIndex = 0;

    for (final message in sortedMessages) {
      if (message.isUser) {
        fallbackUserIndex += 1;
        currentTurnId = _buildTurnId(
          groupId: groupId,
          messageId: message.id,
          fallbackIndex: fallbackUserIndex,
        );
        continue;
      }

      currentTurnId ??= _buildTurnId(
        groupId: groupId,
        messageId: message.id,
        fallbackIndex: fallbackUserIndex + 1,
      );

      switch (message.contentType) {
        case MessageContentType.toolInvocation:
        case MessageContentType.actionConfirmation:
          final invocation =
              ToolInvocation.fromJson(message.payloadJson ?? const {});
          events.add(
            ToolPresentationEvent(
              toolName: invocation.toolName,
              phase: _mapInvocationPhase(invocation.status),
              turnId: currentTurnId,
              stepId: _resolveStepId(
                turnId: currentTurnId,
                payload: message.payloadJson,
              ),
                providerCallId: _readProviderCallId(message.payloadJson),
              sourceContentType: message.contentType,
              sourceMessageId: message.id,
              timestamp: message.timestamp,
              data: {
                ...?message.payloadJson,
                'arguments': invocation.arguments,
                'summary': invocation.summary,
                'requiresConfirmation': invocation.requiresConfirmation,
              },
            ),
          );
          break;
        case MessageContentType.toolResult:
          final result = ToolResult.fromJson(message.payloadJson ?? const {});
          if (result.toolName.trim().isEmpty) {
            break;
          }
          events.add(
            ToolPresentationEvent(
              toolName: result.toolName,
              phase: ToolPresentationEventPhase.result,
              turnId: currentTurnId,
              stepId: _resolveStepId(
                turnId: currentTurnId,
                payload: message.payloadJson,
              ),
                providerCallId: _readProviderCallId(message.payloadJson),
              sourceContentType: message.contentType,
              sourceMessageId: message.id,
              timestamp: message.timestamp,
              data: {
                ...?message.payloadJson,
                'summary': result.summary,
                'data': result.data,
              },
            ),
          );
          break;
        case MessageContentType.plainText:
        case MessageContentType.askUserQuestionPrompt:
        case MessageContentType.askUserQuestionResult:
          break;
      }
    }

    return events;
  }

  bool _belongsToNonToolBlockProjection(ChatMessage message) {
    switch (message.contentType) {
      case MessageContentType.toolInvocation:
      case MessageContentType.toolResult:
      case MessageContentType.actionConfirmation:
        return false;
      case MessageContentType.plainText:
      case MessageContentType.askUserQuestionPrompt:
      case MessageContentType.askUserQuestionResult:
        return true;
    }
  }

  List<AssistantTurnBlock> _buildArtifactBlocks({
    required List<ChatMessage> messages,
    required int? groupId,
  }) {
    final resolver = _artifactTurnResolver;
    if (resolver == null) {
      return const <AssistantTurnBlock>[];
    }
    final projections = resolver.resolve(messages: messages, groupId: groupId);
    return projections.map((projection) {
      return AssistantTurnBlock(
        id: '${projection.turnId}-artifact-${projection.artifactId}',
        turnId: projection.turnId,
        type: AssistantTurnBlockType.artifact,
        sequence: 100000,
        createdAt: projection.createdAt,
        updatedAt: projection.updatedAt,
        title: projection.title,
        text: projection.source,
        payload: {
          'sourceMessageId': projection.sourceMessageId,
          'artifactId': projection.artifactId,
          'type': projection.type.name,
          'sourcePath': projection.sourcePath,
          if (projection.source != null) 'source': projection.source,
        },
        artifactProjection: projection,
      );
    }).toList(growable: false);
  }

  List<AssistantTurnBlock> _buildRuntimeArtifactBlocks({
    required List<AssistantTurnBlock> projectedAssistantBlocks,
    required RuntimeStreamingPreviewState runtimePreviewState,
    required String? resolvedTurnId,
  }) {
    if (runtimePreviewState.isEmpty) {
      return const <AssistantTurnBlock>[];
    }

    final runtimeArtifactBlocks = <AssistantTurnBlock>[];
    for (final message in runtimePreviewState.messages) {
      for (final block in message.blocks) {
        final targetTurnId = _resolveProjectedRuntimeTurnId(
          entryTurnId: 'preview:${message.messageId}',
          fallbackTurnId: resolvedTurnId,
        );
        final preview = _runtimeArtifactPreviewParser.parse(
          message: message,
          block: block,
          turnId: targetTurnId,
        );
        if (preview == null) {
          continue;
        }
        final alreadyResolved = projectedAssistantBlocks.any(
          (projectedBlock) =>
              projectedBlock.type == AssistantTurnBlockType.artifact &&
              projectedBlock.turnId == targetTurnId,
        );
        if (alreadyResolved) {
          continue;
        }
        runtimeArtifactBlocks.add(
          AssistantTurnBlock(
            id: preview.entryId,
            turnId: targetTurnId,
            type: AssistantTurnBlockType.artifact,
            sequence: 99998,
            createdAt: preview.createdAt,
            updatedAt: preview.updatedAt,
            title: preview.title,
            text: preview.source,
            payload: const {
              'isRuntimePreview': true,
            },
            artifactProjection: ArtifactTurnProjection(
              artifactId: preview.artifactId,
              turnId: preview.turnId,
              title: preview.title,
              type: preview.type,
              sourcePath: preview.sourcePath,
              source: preview.source,
              createdAt: preview.createdAt,
              updatedAt: preview.updatedAt,
            ),
          ),
        );
      }
    }
    return runtimeArtifactBlocks;
  }

  String? _resolveActiveRuntimeTurnId({
    required List<ChatMessage> messages,
    required int? groupId,
    required RuntimeAssistantDraft? runtimeDraft,
  }) {
    if (runtimeDraft != null && !_isTransientRuntimeTurnId(runtimeDraft.turnId)) {
      return runtimeDraft.turnId;
    }

    var fallbackUserIndex = 0;
    String? latestUserTurnId;
    for (final message in messages) {
      if (!message.isUser) {
        continue;
      }
      fallbackUserIndex += 1;
      latestUserTurnId = _buildTurnId(
        groupId: groupId,
        messageId: message.id,
        fallbackIndex: fallbackUserIndex,
      );
    }
    return latestUserTurnId;
  }

  String _resolveProjectedRuntimeTurnId({
    required String entryTurnId,
    required String? fallbackTurnId,
  }) {
    if (!_isTransientRuntimeTurnId(entryTurnId)) {
      return entryTurnId;
    }
    return fallbackTurnId ?? entryTurnId;
  }

  bool _isTransientRuntimeTurnId(String turnId) {
    return turnId == 'planner_runtime' || turnId.contains('_runtime_');
  }

  List<AssistantTurnBlock> _mergeBlocks({
    required List<AssistantTurnBlock> baseBlocks,
    required List<AssistantTurnBlock> artifactBlocks,
  }) {
    final blocksByTurn = <String, List<AssistantTurnBlock>>{};
    for (final block in baseBlocks) {
      blocksByTurn.putIfAbsent(block.turnId, () => []).add(block);
    }
    for (final artifactBlock in artifactBlocks) {
      final turnBlocks =
          blocksByTurn.putIfAbsent(artifactBlock.turnId, () => <AssistantTurnBlock>[]);
      final finalResponseIndex = turnBlocks.indexWhere(
        (block) => block.type == AssistantTurnBlockType.finalResponse,
      );
      if (finalResponseIndex == -1) {
        turnBlocks.add(artifactBlock);
      } else {
        turnBlocks.insert(finalResponseIndex, artifactBlock);
      }
    }

    final merged = <AssistantTurnBlock>[];
    final seenTurnOrder = <String>[];
    for (final block in baseBlocks) {
      if (!seenTurnOrder.contains(block.turnId)) {
        seenTurnOrder.add(block.turnId);
      }
    }
    for (final artifactBlock in artifactBlocks) {
      if (!seenTurnOrder.contains(artifactBlock.turnId)) {
        seenTurnOrder.add(artifactBlock.turnId);
      }
    }
    for (final turnId in seenTurnOrder) {
      final turnBlocks = [...?blocksByTurn[turnId]];
      turnBlocks.sort(_compareTurnBlocks);
      merged.addAll(turnBlocks);
    }
    return merged;
  }

  AssistantTurnBlock? _buildRuntimeDraftBlock(RuntimeAssistantDraft? draft) {
    if (draft == null) {
      return null;
    }
    return AssistantTurnBlock(
      id: draft.draftId,
      turnId: draft.turnId,
      type: draft.blockType,
      sequence: 99999,
      createdAt: draft.createdAt,
      updatedAt: draft.updatedAt,
      text: draft.text,
      reasoningText: draft.reasoningText,
      payload: draft.payload,
    );
  }

  int _compareTurnBlocks(
    AssistantTurnBlock left,
    AssistantTurnBlock right,
  ) {
    final timeOrder = left.createdAt.compareTo(right.createdAt);
    if (timeOrder != 0) {
      return timeOrder;
    }

    final sequenceOrder = left.sequence.compareTo(right.sequence);
    if (sequenceOrder != 0) {
      return sequenceOrder;
    }

    final typeOrder =
        _turnBlockTypePriority(left.type).compareTo(_turnBlockTypePriority(right.type));
    if (typeOrder != 0) {
      return typeOrder;
    }

    return left.id.compareTo(right.id);
  }

  int _turnBlockTypePriority(AssistantTurnBlockType type) {
    switch (type) {
      case AssistantTurnBlockType.analysis:
        return 0;
      case AssistantTurnBlockType.toolWorkflow:
        return 1;
      case AssistantTurnBlockType.toolResultSummary:
        return 2;
      case AssistantTurnBlockType.artifact:
        return 3;
      case AssistantTurnBlockType.structuredOutput:
        return 4;
      case AssistantTurnBlockType.finalResponse:
        return 5;
    }
  }

  ChatMessage? _findActiveAskUserQuestion(List<ChatMessage> messages) {
    final resolvedTurnIds = <int>{};

    for (final message in messages) {
      if (message.contentType != MessageContentType.askUserQuestionResult) {
        continue;
      }
        final turnId = message.payloadJson?['agentTurnId'];
      if (turnId is int) {
        resolvedTurnIds.add(turnId);
      }
    }

    for (final message in messages.reversed) {
      if (message.contentType != MessageContentType.askUserQuestionPrompt) {
        continue;
      }
        final payload = message.payloadJson;
      final turnId = payload?['agentTurnId'];
      final status = payload?['status'];
      if (turnId is! int || resolvedTurnIds.contains(turnId)) {
        continue;
      }
      if (status is String &&
          status.isNotEmpty &&
          status != 'awaitingResponse') {
        continue;
      }
      return message;
    }

    return null;
  }

  ProjectedPendingToolConfirmation? _findPendingConfirmation(
    List<ChatMessage> messages,
  ) {
    for (final message in messages.reversed) {
      final contentType = message.contentType;
      if (contentType != MessageContentType.actionConfirmation &&
          contentType != MessageContentType.toolInvocation) {
        continue;
      }

        final payload = message.payloadJson;
      if (payload == null) {
        continue;
      }

      final invocation = ToolInvocation.fromJson(payload);
      if (invocation.status != ToolInvocationStatus.awaitingConfirmation ||
          !invocation.requiresConfirmation) {
        continue;
      }

      return ProjectedPendingToolConfirmation(
        message: message,
        invocation: invocation,
      );
    }

    return null;
  }

  ToolPresentationEventPhase _mapInvocationPhase(
    ToolInvocationStatus status,
  ) {
    switch (status) {
      case ToolInvocationStatus.proposed:
        return ToolPresentationEventPhase.proposed;
      case ToolInvocationStatus.awaitingConfirmation:
        return ToolPresentationEventPhase.awaitingConfirmation;
      case ToolInvocationStatus.running:
        return ToolPresentationEventPhase.running;
      case ToolInvocationStatus.cancelled:
        return ToolPresentationEventPhase.result;
    }
  }

  String _buildTurnId({
    required int? groupId,
    required int? messageId,
    required int fallbackIndex,
  }) {
    return '${groupId ?? 0}_${messageId ?? 'user_$fallbackIndex'}';
  }

  String? _resolveStepId({
    required String turnId,
    required Map<String, dynamic>? payload,
  }) {
    final rawStepId = payload?['stepId'];
    if (rawStepId is int) {
      return '$turnId-step-$rawStepId';
    }
    if (rawStepId is String && rawStepId.trim().isNotEmpty) {
      return '$turnId-step-${rawStepId.trim()}';
    }
    return null;
  }

  String? _readProviderCallId(Map<String, dynamic>? payload) {
    final raw = payload?['providerCallId'];
    if (raw is! String) {
      return null;
    }
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
