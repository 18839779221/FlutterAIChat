import 'package:ai_chat/models/chat/assistant_turn_block.dart';
import 'package:ai_chat/models/chat/chat_timeline_projection.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/services/artifact/artifact_turn_resolver.dart';
import 'package:ai_chat/services/chat_block_builder.dart';

/// Builds one consistent projection snapshot for timeline rendering and
/// waiting-state providers so consumers do not independently rescan messages.
class ChatTimelineProjectionService {
  ChatTimelineProjectionService({
    ChatBlockBuilder? blockBuilder,
    ArtifactTurnResolver? artifactTurnResolver,
  })  : _blockBuilder = blockBuilder ?? ChatBlockBuilder(),
        _artifactTurnResolver = artifactTurnResolver;

  final ChatBlockBuilder _blockBuilder;
  final ArtifactTurnResolver? _artifactTurnResolver;

  ChatTimelineProjection build({
    required List<ChatMessage> messages,
    int? groupId,
  }) {
    final blocks = _blockBuilder.buildAssistantBlocks(
      messages: messages,
      groupId: groupId,
    );
    final artifactBlocks = _buildArtifactBlocks(
      messages: messages,
      groupId: groupId,
    );
    return ChatTimelineProjection(
      activeAskUserQuestionMessage: _findActiveAskUserQuestion(messages),
      pendingToolConfirmation: _findPendingConfirmation(messages),
      assistantBlocks: _mergeBlocks(
        baseBlocks: blocks,
        artifactBlocks: artifactBlocks,
      ),
    );
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
        text: projection.isStale ? '已在后续回复中更新' : projection.source,
        payload: {
          'sourceMessageId': projection.sourceMessageId,
          'artifactId': projection.artifactId,
          'type': projection.type.name,
          'sourcePath': projection.sourcePath,
          'isStale': projection.isStale,
          if (projection.source != null) 'source': projection.source,
        },
        artifactProjection: projection,
      );
    }).toList(growable: false);
  }

  List<AssistantTurnBlock> _mergeBlocks({
    required List<AssistantTurnBlock> baseBlocks,
    required List<AssistantTurnBlock> artifactBlocks,
  }) {
    if (artifactBlocks.isEmpty) {
      return baseBlocks;
    }

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
      merged.addAll(blocksByTurn[turnId] ?? const <AssistantTurnBlock>[]);
    }
    return merged;
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
}
