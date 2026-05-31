import 'package:ai_chat/models/artifact/artifact_turn_projection.dart';
import 'package:ai_chat/models/chat/assistant_turn_block.dart';
import 'package:ai_chat/models/chat/chat_timeline_projection.dart';
import 'package:ai_chat/models/chat/runtime_assistant_draft.dart';
import 'package:ai_chat/models/chat/runtime_streaming_preview_state.dart';
import 'package:ai_chat/models/llm/streaming_message_event.dart';
import 'package:ai_chat/utils/logger.dart';
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
    Logger.temp(
      'ChatTimelineProjectionService',
      'build called',
      reason: 'diagnose streaming performance',
      data: {
        'messageCount': messages.length,
        'previewMessageCount': runtimePreviewState.messages.length,
        'previewBlockCount': runtimePreviewState.messages.fold<int>(
          0,
          (sum, msg) => sum + msg.blocks.length,
        ),
      },
    );
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
    final resolvedArtifactProviderCallIds = artifactBlocks
        .map((block) => block.artifactProjection?.providerCallId?.trim())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet();
    final runtimeDraftBlock = _buildRuntimeDraftBlock(runtimeDraft);
    final runtimePreviewBlocks = _buildRuntimePreviewBlocks(
      runtimePreviewState: runtimePreviewState,
      resolvedTurnId: runtimeTurnId,
    );
    final runtimeArtifactBlocks = _buildRuntimeArtifactBlocks(
      runtimePreviewState: runtimePreviewState,
      resolvedTurnId: runtimeTurnId,
      resolvedArtifactProviderCallIds: resolvedArtifactProviderCallIds,
    );
    final mergedBlocks = _mergeBlocks(
      baseBlocks: [
        ...blocks,
        ...toolBlocks,
        ...runtimePreviewBlocks,
        if (runtimeDraftBlock != null) runtimeDraftBlock,
      ],
      artifactBlocks: [
        ...artifactBlocks,
        ...runtimeArtifactBlocks,
      ],
    );
    Logger.temp(
      'ChatTimelineProjectionService',
      'build completed',
      reason: 'diagnose streaming performance',
      data: {
        'totalAssistantBlocks': mergedBlocks.length,
        'runtimePreviewBlockCount': runtimePreviewBlocks.length,
        'runtimeArtifactBlockCount': runtimeArtifactBlocks.length,
        'artifactBlockCount': artifactBlocks.length,
        'finalMergedBlockTypes': mergedBlocks.map((b) => b.type.name).join(','),
        'finalMergedTurnIds': mergedBlocks.map((b) => '${b.type.name}:${b.turnId}').join(' | '),
      },
    );
    return ChatTimelineProjection(
      activeAskUserQuestionMessage: _findActiveAskUserQuestion(messages),
      pendingToolConfirmation: _findPendingConfirmation(messages),
      assistantBlocks: mergedBlocks,
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
          if ((projection.providerCallId ?? '').trim().isNotEmpty)
            'providerCallId': projection.providerCallId,
          if (projection.source != null) 'source': projection.source,
        },
        artifactProjection: projection,
      );
    }).toList(growable: false);
  }

  List<AssistantTurnBlock> _buildRuntimePreviewBlocks({
    required RuntimeStreamingPreviewState runtimePreviewState,
    required String? resolvedTurnId,
  }) {
    if (runtimePreviewState.isEmpty) {
      return const <AssistantTurnBlock>[];
    }

    final runtimePreviewBlocks = <AssistantTurnBlock>[];
    for (final message in runtimePreviewState.messages) {
      var sequence = 90000;
      for (final block in message.blocks) {
        final targetTurnId = _resolveProjectedRuntimeTurnId(
          entryTurnId: 'preview:${message.messageId}',
          fallbackTurnId: resolvedTurnId,
        );
        final projected = _buildRuntimePreviewBlock(
          message: message,
          block: block,
          turnId: targetTurnId,
          sequence: sequence,
        );
        if (projected != null) {
          runtimePreviewBlocks.add(projected);
          sequence += 1;
        }
      }
    }
    return runtimePreviewBlocks;
  }

  List<AssistantTurnBlock> _buildRuntimeArtifactBlocks({
    required RuntimeStreamingPreviewState runtimePreviewState,
    required String? resolvedTurnId,
    required Set<String> resolvedArtifactProviderCallIds,
  }) {
    if (runtimePreviewState.isEmpty) {
      return const <AssistantTurnBlock>[];
    }

    Logger.temp(
      'ChatTimelineProjectionService',
      'building runtime artifact blocks',
      reason: 'diagnose streaming performance',
      data: {
        'messageCount': runtimePreviewState.messages.length,
      },
    );

    final runtimeArtifactBlocks = <AssistantTurnBlock>[];
    for (final message in runtimePreviewState.messages) {
      for (final block in message.blocks) {
        Logger.temp(
          'ChatTimelineProjectionService',
          'processing preview block',
          reason: 'diagnose streaming performance',
          data: {
            'blockType': block.blockType.name,
            'toolName': block.toolName,
            'textLength': block.text.length,
          },
        );

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
          Logger.temp(
            'ChatTimelineProjectionService',
            'preview parse returned null',
            reason: 'diagnose streaming performance',
            data: {
              'blockType': block.blockType.name,
              'toolName': block.toolName,
            },
          );
          continue;
        }

        Logger.temp(
          'ChatTimelineProjectionService',
          'preview parsed successfully',
          reason: 'diagnose streaming performance',
          data: {
            'artifactId': preview.artifactId,
            'sourceLength': preview.source?.length ?? 0,
          },
        );
        final providerCallId = preview.providerCallId?.trim();
        if (providerCallId != null &&
            providerCallId.isNotEmpty &&
            resolvedArtifactProviderCallIds.contains(providerCallId)) {
          Logger.temp(
            'ChatTimelineProjectionService',
            'runtime artifact hidden after persisted takeover',
            reason: 'diagnose streaming performance',
            data: {
              'providerCallId': providerCallId,
              'artifactId': preview.artifactId,
              'turnId': targetTurnId,
            },
          );
          continue;
        }
        final artifactBlock = AssistantTurnBlock(
          id: preview.entryId,
          turnId: targetTurnId,
          type: AssistantTurnBlockType.artifact,
          sequence: 99998,
          createdAt: preview.createdAt,
          updatedAt: preview.updatedAt,
          title: preview.title,
          text: preview.source,
          payload: {
            'isRuntimePreview': true,
            if (providerCallId != null && providerCallId.isNotEmpty)
              'providerCallId': providerCallId,
          },
          artifactProjection: ArtifactTurnProjection(
            artifactId: preview.artifactId,
            turnId: preview.turnId,
            title: preview.title,
            type: preview.type,
            providerCallId: providerCallId,
            isRuntimePreview: true,
            sourcePath: preview.sourcePath,
            source: preview.source,
            createdAt: preview.createdAt,
            updatedAt: preview.updatedAt,
          ),
        );
        Logger.temp(
          'ChatTimelineProjectionService',
          'artifact block created',
          reason: 'diagnose streaming performance',
          data: {
            'blockId': artifactBlock.id,
            'blockTurnId': artifactBlock.turnId,
            'updatedAtMicros': artifactBlock.updatedAt.microsecondsSinceEpoch,
            'artifactId': preview.artifactId,
          },
        );
        runtimeArtifactBlocks.add(artifactBlock);
      }
    }
    return runtimeArtifactBlocks;
  }

  AssistantTurnBlock? _buildRuntimePreviewBlock({
    required RuntimeStreamingPreviewMessage message,
    required RuntimeStreamingPreviewBlock block,
    required String turnId,
    required int sequence,
  }) {
    if (block.blockType == StreamingContentBlockType.text) {
      if (block.text.isEmpty) {
        return null;
      }
      return AssistantTurnBlock(
        id: block.contentBlockId,
        turnId: turnId,
        type: AssistantTurnBlockType.finalResponse,
        sequence: sequence,
        createdAt: block.createdAt,
        updatedAt: block.updatedAt,
        logicalId: 'final:$turnId',
        text: block.text,
        payload: _runtimePreviewPayload(
          message: message,
          messageId: message.messageId,
          block: block,
        ),
      );
    }

    if (block.blockType == StreamingContentBlockType.thinking) {
      if (block.text.isEmpty) {
        return null;
      }
      return AssistantTurnBlock(
        id: block.contentBlockId,
        turnId: turnId,
        type: AssistantTurnBlockType.analysis,
        sequence: sequence,
        createdAt: block.createdAt,
        updatedAt: block.updatedAt,
        reasoningText: block.text,
        payload: _runtimePreviewPayload(
          message: message,
          messageId: message.messageId,
          block: block,
        ),
      );
    }

    // Default: do NOT emit a generic streaming tool_use workflow card.
    //
    // A bare "正在执行工具：xxx" card adds no information for the user — the
    // persisted truth `toolInvocation` message lands seconds later carrying
    // the actual arguments and renders the proper card. Most tools
    // (web_search, file tools, etc.) should skip the streaming preview.
    //
    // Tools that genuinely benefit from a live streaming view render
    // through a dedicated pipeline:
    //   - `create_artifact` is projected by `_buildRuntimeArtifactBlocks`
    //   - future opt-in tools can branch on `block.toolName` here and
    //     return their own typed runtime preview block
    return null;
  }

  Map<String, dynamic> _runtimePreviewPayload({
    required RuntimeStreamingPreviewMessage message,
    required String messageId,
    required RuntimeStreamingPreviewBlock block,
  }) {
    return {
      'isRuntimePreview': true,
      'previewMessageId': messageId,
      'previewContentBlockId': block.contentBlockId,
      'previewBlockType': block.blockType.name,
      if (message.streamTraceId?.trim().isNotEmpty == true)
        'streamTraceId': message.streamTraceId!.trim(),
      if (message.streamTurnId?.trim().isNotEmpty == true)
        'streamTurnId': message.streamTurnId!.trim(),
      if (block.toolUseId?.trim().isNotEmpty == true)
        'providerCallId': block.toolUseId!.trim(),
    };
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
    final result = !_isTransientRuntimeTurnId(entryTurnId)
        ? entryTurnId
        : (fallbackTurnId ?? entryTurnId);
    Logger.temp(
      'ChatTimelineProjectionService',
      '_resolveProjectedRuntimeTurnId',
      reason: 'diagnose streaming performance',
      data: {
        'entryTurnId': entryTurnId,
        'fallbackTurnId': fallbackTurnId ?? 'null',
        'resolvedTurnId': result,
      },
    );
    return result;
  }

  bool _isTransientRuntimeTurnId(String turnId) {
    return turnId == 'planner_runtime' ||
           turnId.contains('_runtime_') ||
           turnId.startsWith('preview:');
  }

  List<AssistantTurnBlock> _mergeBlocks({
    required List<AssistantTurnBlock> baseBlocks,
    required List<AssistantTurnBlock> artifactBlocks,
  }) {
    final filteredBaseBlocks = _dropPreviewBlocksSupersededByTruth(baseBlocks);

    final blocksByTurn = <String, List<AssistantTurnBlock>>{};
    for (final block in filteredBaseBlocks) {
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
    for (final block in filteredBaseBlocks) {
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
    Logger.temp(
      'ChatTimelineProjectionService',
      '_mergeBlocks result',
      reason: 'diagnose streaming performance',
      data: {
        'baseBlockCount': baseBlocks.length,
        'artifactBlockCount': artifactBlocks.length,
        'mergedBlockCount': merged.length,
        'mergedBlockTypes': merged.map((b) => b.type.name).join(','),
        'mergedArtifactCount': merged.where((b) => b.type == AssistantTurnBlockType.artifact).length,
        'allMergedTurnIds': merged.map((b) => '${b.type.name}:${b.turnId}').join(' | '),
      },
    );
    return merged;
  }

  /// Drops preview-origin blocks whose [AssistantTurnBlock.logicalId] is
  /// already represented by a truth-origin block.
  ///
  /// Implements the per-entity preview-takeover contract: once the persisted
  /// truth ledger emits a block with the same logical identity (matching
  /// `tool:<providerCallId>` or `final:<turnId>`), the corresponding runtime
  /// preview block is hidden so the timeline stops rendering duplicates while
  /// the SSE stream continues. Generalizes the artifact dedup applied at
  /// [_buildRuntimeArtifactBlocks].
  List<AssistantTurnBlock> _dropPreviewBlocksSupersededByTruth(
    List<AssistantTurnBlock> blocks,
  ) {
    final truthLogicalIds = <String>{};
    for (final block in blocks) {
      if (block.payload?['isRuntimePreview'] == true) {
        continue;
      }
      final logicalId = block.logicalId?.trim();
      if (logicalId == null || logicalId.isEmpty) {
        continue;
      }
      truthLogicalIds.add(logicalId);
    }
    if (truthLogicalIds.isEmpty) {
      return blocks;
    }
    final filtered = <AssistantTurnBlock>[];
    for (final block in blocks) {
      final logicalId = block.logicalId?.trim();
      final isPreview = block.payload?['isRuntimePreview'] == true;
      if (isPreview &&
          logicalId != null &&
          logicalId.isNotEmpty &&
          truthLogicalIds.contains(logicalId)) {
        Logger.temp(
          'ChatTimelineProjectionService',
          'preview block superseded by truth',
          reason: 'per-entity preview takeover',
          data: {
            'logicalId': logicalId,
            'blockType': block.type.name,
            'turnId': block.turnId,
          },
        );
        continue;
      }
      filtered.add(block);
    }
    return filtered;
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
