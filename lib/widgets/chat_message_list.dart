import 'dart:async';

import 'package:ai_chat/models/chat/active_turn_status_presentation.dart';
import 'package:ai_chat/models/chat/assistant_turn_block.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/llm/llm_provider_config.dart';
import 'package:ai_chat/models/llm/llm_selection_state.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/tool/tool_invocation.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/pages/model_management_page.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/repositories/app_settings_repository.dart';
import 'package:ai_chat/services/chat_block_builder.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/utils/logger.dart';
import 'package:ai_chat/widgets/chat_empty_state.dart';
import 'package:ai_chat/widgets/chat_timeline/chat_timeline_item.dart';
import 'package:ai_chat/widgets/chat_timeline/chat_timeline_row.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChatMessageList extends ConsumerStatefulWidget {
  const ChatMessageList({
    super.key,
    this.onLongPressRunningTail,
  });

  final VoidCallback? onLongPressRunningTail;

  @override
  ConsumerState<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends ConsumerState<ChatMessageList> {
  final ChatBlockBuilder _blockBuilder = ChatBlockBuilder();
  static const double _anchorThreshold = 100;
  static const double _scrollToBottomVisibilityThreshold = 56;
  static const double _floatingEnterViewportMargin = 12;
  static const double _floatingExitViewportMargin = 4;
  static const Duration _floatingVisibilityExitGrace =
      Duration(milliseconds: 180);
  static const double _ghostHeaderHeight = 56;
  bool _isLoadingOlderHistory = false;
  late final ScrollController _scrollController;
  final GlobalKey _activeStatusAnchorKey = GlobalKey(
    debugLabel: 'active-turn-status-anchor',
  );
  final GlobalKey _latestUserRowAnchorKey = GlobalKey(
    debugLabel: 'latest-user-row-anchor',
  );
  final GlobalKey _latestTimelineTailAnchorKey = GlobalKey(
    debugLabel: 'latest-timeline-tail-anchor',
  );
  int _previousItemCount = 0;
  bool _pendingVisibilityCheck = false;
  int _visibilityCheckGeneration = 0;
  Timer? _floatingVisibilityGraceTimer;
  bool _pendingDynamicInsetSync = false;
  bool _hasPositionedInitialHistory = false;
  int? _pendingInitialHistoryGroupId;
  List<ChatMessage>? _groupSwitchStaleMessages;
  String? _lastPinnedLatestUserStableKey;
  double? _cachedMinBottomInset;
  double? _cachedTopTargetInset;
  String? _cachedLatestUserStableKey;
  String? _cachedLatestTailStableKey;
  String? _cachedPendingPinnedUserStableKey;
  ChatSendPhase? _cachedSendPhase;

  @override
  void initState() {
    super.initState();
    _scrollController = ref.read(scrollControllerProvider);
    _scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _floatingVisibilityGraceTimer?.cancel();
    _visibilityCheckGeneration += 1;
    super.dispose();
  }

  void _scrollListener() {
    final scrollController = ref.read(scrollControllerProvider);
    if (!scrollController.hasClients) {
      return;
    }

    if (_shouldLoadOlderHistory(scrollController)) {
      _loadOlderHistoryPreservingAnchor();
    }

    _scheduleActiveStatusVisibilitySync();
    _syncScrollToBottomButtonVisibility();
    _scheduleDynamicInsetSync();
  }

  void _syncScrollToBottomButtonVisibility() {
    final controller = ref.read(scrollControllerProvider);
    if (!controller.hasClients) {
      return;
    }
    final distanceToBottom =
        controller.position.maxScrollExtent - controller.offset;
    final shouldShow = distanceToBottom > _scrollToBottomVisibilityThreshold;
    final notifier = ref.read(scrollToBottomButtonVisibleProvider.notifier);
    if (notifier.state == shouldShow) {
      return;
    }
    notifier.state = shouldShow;
  }

  bool _shouldLoadOlderHistory(ScrollController scrollController) {
    if (_isLoadingOlderHistory || !ref.read(hasMoreMessagesProvider)) {
      return false;
    }

    final minScroll = scrollController.position.minScrollExtent;
    return scrollController.offset <= minScroll + _anchorThreshold;
  }

  Future<void> _loadOlderHistoryPreservingAnchor() async {
    final scrollController = ref.read(scrollControllerProvider);
    if (!scrollController.hasClients) {
      return;
    }

    _isLoadingOlderHistory = true;
    final previousOffset = scrollController.offset;
    final previousMaxScroll = scrollController.position.maxScrollExtent;

    try {
      await ref.read(chatControllerProvider).loadMoreMessages();
      if (!mounted || !scrollController.hasClients) {
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !scrollController.hasClients) {
          return;
        }
        final newMaxScroll = scrollController.position.maxScrollExtent;
        final extentDelta = newMaxScroll - previousMaxScroll;
        if (extentDelta <= 0) {
          return;
        }
        scrollController.jumpTo(previousOffset + extentDelta);
        _scheduleActiveStatusVisibilitySync();
      });
    } finally {
      _isLoadingOlderHistory = false;
    }
  }

  void _scheduleScrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) {
          return;
        }
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      });
    });
  }

  void _resetInitialHistoryPosition({
    int? pendingGroupId,
    List<ChatMessage>? staleMessages,
  }) {
    _hasPositionedInitialHistory = false;
    _pendingInitialHistoryGroupId = pendingGroupId;
    _groupSwitchStaleMessages = staleMessages;
  }

  void _resetDynamicInsetState() {
    _lastPinnedLatestUserStableKey = null;
    _cachedLatestUserStableKey = null;
    _cachedLatestTailStableKey = null;
    _cachedPendingPinnedUserStableKey = null;
    _cachedSendPhase = null;
    ref.read(pendingPinnedUserMessageStableKeyProvider.notifier).state = null;
    final notifier = ref.read(chatMessageListExtraBottomInsetProvider.notifier);
    if (notifier.state == 0) {
      ref.read(scrollToBottomButtonVisibleProvider.notifier).state = false;
      return;
    }
    notifier.state = 0;
    ref.read(scrollToBottomButtonVisibleProvider.notifier).state = false;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ChatGroup?>(currentGroupProvider, (previous, next) {
      if (previous?.id != next?.id) {
        _resetDynamicInsetState();
        _resetInitialHistoryPosition(
          pendingGroupId: next?.id,
          staleMessages: ref.read(messagesProvider),
        );
      }
    });

    final messages = ref.watch(messagesProvider);
    final timelineProjection = ref.watch(chatTimelineProjectionProvider);
    final activeTurnStatus = ref.watch(activeTurnStatusPresentationProvider);
    final shouldFloatActiveStatus =
        ref.watch(activeTurnStatusFloatingVisibilityProvider);
    Logger.temp(
      'ChatMessageList',
      'build called',
      reason: 'diagnose streaming performance',
      data: {
        'assistantBlockCount': timelineProjection.assistantBlocks.length,
        'artifactBlockCount': timelineProjection.assistantBlocks
            .where((b) => b.type == AssistantTurnBlockType.artifact)
            .length,
      },
    );
    final hasMoreMessages = ref.watch(hasMoreMessagesProvider);
    final bottomOverlayHeight = ref.watch(chatBottomOverlayHeightProvider);
    final extraBottomInset = ref.watch(chatMessageListExtraBottomInsetProvider);
    final pendingPinnedUserStableKey =
        ref.watch(pendingPinnedUserMessageStableKeyProvider);
    final sendPhase = ref.watch(sendPhaseProvider);
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final textController = ref.read(textControllerProvider);
    final focusNode = ref.read(focusNodeProvider);
    final topPinnedTargetInset =
        _ghostHeaderHeight + spacing.xxs + MediaQuery.of(context).padding.top;
    final minBottomInset = bottomOverlayHeight > 0
        ? bottomOverlayHeight + spacing.lg
        : spacing.xl * 4.2;
    final bottomTimelineInset = minBottomInset + extraBottomInset;

    final timelineItems = _buildTimelineItems(
      messages,
      timelineProjection.assistantBlocks,
      activeTurnStatus,
      hideInlineActiveStatus: shouldFloatActiveStatus,
    );
    final latestUserStableKey =
        timelineItems.lastOrNull?.type == ChatTimelineItemType.userBubble
            ? timelineItems.last.stableKey
            : null;
    final latestTailStableKey =
        timelineItems.isEmpty ? null : timelineItems.last.stableKey;
    final itemCount = timelineItems.length + 1;
    final currentGroupId = ref.read(currentGroupProvider)?.id;
    // Detect if new items were added (only animate the last item if count increased)
    final previousItemCount = _previousItemCount;
    final hasNewItems = timelineItems.length > previousItemCount;
    _previousItemCount = timelineItems.length;

    final isWaitingForGroupMessageBatch =
        _pendingInitialHistoryGroupId == currentGroupId &&
            identical(messages, _groupSwitchStaleMessages);
    if (_pendingInitialHistoryGroupId != null &&
        _pendingInitialHistoryGroupId != currentGroupId) {
      _pendingInitialHistoryGroupId = null;
      _groupSwitchStaleMessages = null;
    }

    if (sendPhase == ChatSendPhase.idle &&
        timelineItems.length > 1 &&
        (previousItemCount == 0 || _pendingInitialHistoryGroupId != null) &&
        !_hasPositionedInitialHistory &&
        !isWaitingForGroupMessageBatch) {
      _hasPositionedInitialHistory = true;
      _pendingInitialHistoryGroupId = null;
      _groupSwitchStaleMessages = null;
      _scheduleScrollToLatest();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _syncScrollToBottomButtonVisibility();
    });

    if (messages.isEmpty) {
      _resetInitialHistoryPosition();
      _resetDynamicInsetState();
      AppSettingsRepository? repository;
      try {
        repository = ref.read(appSettingsRepositoryProvider);
      } on UnimplementedError {
        repository = null;
      }
      _scheduleActiveStatusVisibilitySync(
        activeStatus: null,
        hasAnchor: false,
      );
      if (repository == null) {
        return ChatEmptyState(
          suggestions: buildChatEmptySuggestionsFromCases(
            ref.watch(featuredDebugTestCasesProvider),
          ),
          onSuggestionSelected: (prompt) {
            textController.value = TextEditingValue(
              text: prompt,
              selection: TextSelection.collapsed(offset: prompt.length),
            );
            focusNode.requestFocus();
          },
        );
      }
      final providerFuture = repository.getProviders();
      final selectionFuture = repository.getSelectionState();
      return FutureBuilder<_EmptyStateModelSetupState>(
        future: _buildEmptyStateModelSetupState(
          providersFuture: providerFuture,
          selectionFuture: selectionFuture,
        ),
        builder: (context, snapshot) {
          final showModelSetupCallout = snapshot.data?.requiresSetup ?? false;
          return ChatEmptyState(
            showModelSetupCallout: showModelSetupCallout,
            onConfigureModel: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ModelManagementPage(repository: repository!),
                ),
              );
            },
            suggestions: buildChatEmptySuggestionsFromCases(
              ref.watch(featuredDebugTestCasesProvider),
            ),
            onSuggestionSelected: (prompt) {
              textController.value = TextEditingValue(
                text: prompt,
                selection: TextSelection.collapsed(offset: prompt.length),
              );
              focusNode.requestFocus();
            },
          );
        },
      );
    }

    _scheduleDynamicInsetSync(
      minBottomInset: minBottomInset,
      topTargetInset: topPinnedTargetInset,
      latestUserStableKey: latestUserStableKey,
      latestTailStableKey: latestTailStableKey,
      pendingPinnedUserStableKey: pendingPinnedUserStableKey,
      sendPhase: sendPhase,
    );

    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _scheduleActiveStatusVisibilitySync();
        _scheduleDynamicInsetSync(
          minBottomInset: minBottomInset,
          topTargetInset: topPinnedTargetInset,
          latestUserStableKey: latestUserStableKey,
          latestTailStableKey: latestTailStableKey,
          pendingPinnedUserStableKey: pendingPinnedUserStableKey,
          sendPhase: sendPhase,
        );
        return false;
      },
      child: CustomScrollView(
        controller: _scrollController,
        physics: const ClampingScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              spacing.sm,
              topPinnedTargetInset,
              spacing.sm,
              bottomTimelineInset,
            ),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index == 0) {
                    return Center(
                      key: const ValueKey('chat-message-list-load-older-slot'),
                      child: hasMoreMessages
                          ? const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: CircularProgressIndicator(
                                key: ValueKey(
                                  'chat-message-list-load-older-indicator',
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    );
                  }

                  final timelineIndex = index - 1;
                  final item = timelineItems[timelineIndex];
                  final isLastItem = timelineIndex == timelineItems.length - 1;
                  final shouldAnimate = hasNewItems && isLastItem;

                  return Align(
                    key: ValueKey('timeline-block-${item.stableKey}'),
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: kIsWeb ? 860 : 720,
                      ),
                      child: Padding(
                        padding: EdgeInsets.only(bottom: spacing.sm),
                        child: _buildRowWithOptionalAnchor(
                          item: item,
                          child: ChatTimelineRow(
                            item: item,
                            blockBuilder: _blockBuilder,
                            currentGroupId: currentGroupId,
                            onLongPressMessage: _showMessageOptionMenu,
                            shouldAnimate: shouldAnimate,
                            onActiveStatusLayoutChanged:
                                _scheduleActiveStatusVisibilitySync,
                          ),
                        ),
                      ),
                    ),
                  );
                },
                childCount: itemCount,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<_EmptyStateModelSetupState> _buildEmptyStateModelSetupState({
    required Future<List<LlmProviderConfig>> providersFuture,
    required Future<LlmSelectionState> selectionFuture,
  }) async {
    final providers = await providersFuture;
    final selection = await selectionFuture;
    if (providers.isEmpty) {
      return const _EmptyStateModelSetupState(requiresSetup: true);
    }
    final selectedProviderId = selection.selectedProviderId;
    final defaultProviderId = selection.defaultProviderId;
    final selectedModelId = selection.selectedModelId;
    final defaultModelId = selection.defaultModelId;

    LlmProviderConfig? provider;
    for (final candidateId in [selectedProviderId, defaultProviderId]) {
      if (candidateId == null) {
        continue;
      }
      for (final item in providers) {
        if (item.id == candidateId) {
          provider = item;
          break;
        }
      }
      if (provider != null) {
        break;
      }
    }
    provider ??= providers.first;
    if (provider.models.isEmpty) {
      return const _EmptyStateModelSetupState(requiresSetup: true);
    }
    for (final candidateId in [selectedModelId, defaultModelId]) {
      if (candidateId == null) {
        continue;
      }
      for (final model in provider.models) {
        if (model.id == candidateId) {
          return const _EmptyStateModelSetupState(requiresSetup: false);
        }
      }
    }
    return const _EmptyStateModelSetupState(requiresSetup: true);
  }

  List<ChatTimelineItem> _buildTimelineItems(
      List<ChatMessage> messages,
      List<AssistantTurnBlock> projectedAssistantBlocks,
      ActiveTurnStatusPresentation? activeTurnStatus,
      {required bool hideInlineActiveStatus}) {
    if (messages.isEmpty) {
      return const [];
    }

    Logger.temp(
      'ChatMessageList',
      '_buildTimelineItems received blocks',
      reason: 'diagnose streaming performance',
      data: {
        'projectedBlockCount': projectedAssistantBlocks.length,
        'projectedBlockTypes':
            projectedAssistantBlocks.map((b) => b.type.name).join(','),
        'projectedArtifactCount': projectedAssistantBlocks
            .where((b) => b.type == AssistantTurnBlockType.artifact)
            .length,
        'allProjectedTurnIds': projectedAssistantBlocks
            .map((b) => '${b.type.name}:${b.turnId}')
            .join(' | '),
      },
    );

    final currentGroup = ref.read(currentGroupProvider);
    final sortedMessages = [...messages]..sort(compareChatMessagesForTimeline);
    final effectiveStatus = activeTurnStatus;

    final items = <ChatTimelineItem>[];
    var cursor = 0;

    while (cursor < sortedMessages.length) {
      final current = sortedMessages[cursor];

      if (current.contentType == MessageContentType.contextBoundary) {
        items.add(
          ChatTimelineItem(
            stableKey:
                'boundary-${current.id ?? current.timestamp.microsecondsSinceEpoch}',
            type: ChatTimelineItemType.contextBoundary,
            boundaryMessage: current,
          ),
        );
        cursor += 1;
        continue;
      }

      if (current.isUser) {
        final segment = <ChatMessage>[current];
        var nextCursor = cursor + 1;
        while (nextCursor < sortedMessages.length &&
            !sortedMessages[nextCursor].isUser) {
          segment.add(sortedMessages[nextCursor]);
          nextCursor += 1;
        }

        final isLatestTurn = nextCursor >= sortedMessages.length;
        final blocks = _blocksForSegment(
          sourceMessages: segment,
          projectedAssistantBlocks: projectedAssistantBlocks,
          groupId: currentGroup?.id,
          fallbackUserIndex:
              items.where((item) => item.userMessage != null).length,
        );
        final hasAssistantOutput = blocks.isNotEmpty;
        items.add(
          ChatTimelineItem(
            stableKey: _buildUserItemKey(current),
            type: ChatTimelineItemType.userBubble,
            userMessage: current,
            sourceMessages: segment,
            rowAnchorKey: isLatestTurn ? _latestUserRowAnchorKey : null,
            activeStatus:
                isLatestTurn && !hasAssistantOutput && effectiveStatus != null
                    ? effectiveStatus
                    : null,
            statusAnchorKey:
                isLatestTurn && !hasAssistantOutput && effectiveStatus != null
                    ? _activeStatusAnchorKey
                    : null,
            hideInlineStatus:
                isLatestTurn && !hasAssistantOutput && effectiveStatus != null
                    ? hideInlineActiveStatus
                    : false,
          ),
        );
        items.addAll(
          _buildAssistantItems(
            sourceMessages: segment,
            blocks: blocks,
            activeStatus:
                isLatestTurn && hasAssistantOutput ? effectiveStatus : null,
            latestTurnHasAssistantOutput: isLatestTurn && hasAssistantOutput,
            hideInlineStatus:
                isLatestTurn && hasAssistantOutput && effectiveStatus != null
                    ? hideInlineActiveStatus
                    : false,
          ),
        );
        cursor = nextCursor;
        continue;
      }

      final orphanBlocks = _blocksForOrphanAssistantMessage(
        sourceMessage: current,
        projectedAssistantBlocks: projectedAssistantBlocks,
        groupId: currentGroup?.id,
        fallbackAssistantIndex: cursor + 1,
      );
      items.addAll(
        _buildAssistantItems(
          sourceMessages: [current],
          blocks: orphanBlocks,
          activeStatus:
              cursor == sortedMessages.length - 1 ? effectiveStatus : null,
          latestTurnHasAssistantOutput: cursor == sortedMessages.length - 1,
          hideInlineStatus:
              cursor == sortedMessages.length - 1 && effectiveStatus != null
                  ? hideInlineActiveStatus
                  : false,
        ),
      );
      cursor += 1;
    }

    _scheduleActiveStatusVisibilitySync(
      activeStatus: effectiveStatus,
      hasAnchor: effectiveStatus != null,
    );

    return items;
  }

  List<AssistantTurnBlock> _blocksForOrphanAssistantMessage({
    required ChatMessage sourceMessage,
    required List<AssistantTurnBlock> projectedAssistantBlocks,
    required int? groupId,
    required int fallbackAssistantIndex,
  }) {
    final projectedBySourceMessage = projectedAssistantBlocks
        .where(
          (block) => block.payload?['sourceMessageId'] == sourceMessage.id,
        )
        .toList(growable: false);
    if (projectedBySourceMessage.isNotEmpty) {
      return projectedBySourceMessage;
    }

    final turnId =
        '${groupId ?? 0}_${sourceMessage.id ?? 'user_$fallbackAssistantIndex'}';
    final projected = projectedAssistantBlocks
        .where((block) => block.turnId == turnId)
        .toList(growable: false);
    if (projected.isNotEmpty) {
      return projected;
    }

    if (_isProjectionOwnedMessage(sourceMessage)) {
      return const <AssistantTurnBlock>[];
    }

    return _blockBuilder.buildAssistantBlocks(
      messages: [sourceMessage],
      groupId: groupId,
    );
  }

  List<ChatTimelineItem> _buildAssistantItems({
    required List<ChatMessage> sourceMessages,
    required List<AssistantTurnBlock> blocks,
    required ActiveTurnStatusPresentation? activeStatus,
    required bool latestTurnHasAssistantOutput,
    required bool hideInlineStatus,
  }) {
    Logger.temp(
      'ChatMessageList',
      '_buildAssistantItems called',
      reason: 'diagnose streaming performance',
      data: {
        'blockCount': blocks.length,
        'blockTypes': blocks.map((b) => b.type.name).join(','),
        'takeoverFocusBlocks': blocks
            .where(
              (block) =>
                  block.type == AssistantTurnBlockType.analysis ||
                  block.type == AssistantTurnBlockType.finalResponse,
            )
            .map((block) => {
                  'type': block.type.name,
                  'id': block.id,
                  'logicalId': block.logicalId,
                  'turnId': block.turnId,
                  'isRuntimePreview':
                      block.payload?['isRuntimePreview'] == true,
                  'previewMessageId': block.payload?['previewMessageId'],
                  'responseId': block.payload?['responseId'],
                  'reasoningScope': block.payload?['reasoningScope'],
                })
            .toList(growable: false),
      },
    );
    final items = <ChatTimelineItem>[];
    for (var index = 0; index < blocks.length; index += 1) {
      final block = blocks[index];
      final sourceMessage = _resolveSourceMessage(sourceMessages, block);
      items.add(
        ChatTimelineItem(
          stableKey: _buildAssistantItemKey(block, sourceMessage),
          type: ChatTimelineItemType.assistantBlock,
          sourceMessage: sourceMessage,
          sourceMessages: sourceMessages,
          block: block,
          rowAnchorKey:
              latestTurnHasAssistantOutput && index == blocks.length - 1
                  ? _latestTimelineTailAnchorKey
                  : null,
          activeStatus: activeStatus != null && index == blocks.length - 1
              ? activeStatus
              : null,
          statusAnchorKey: activeStatus != null && index == blocks.length - 1
              ? _activeStatusAnchorKey
              : null,
          hideInlineStatus: activeStatus != null && index == blocks.length - 1
              ? hideInlineStatus
              : false,
        ),
      );
    }

    return items;
  }

  List<AssistantTurnBlock> _blocksForSegment({
    required List<ChatMessage> sourceMessages,
    required List<AssistantTurnBlock> projectedAssistantBlocks,
    required int? groupId,
    required int fallbackUserIndex,
  }) {
    final userAnchor =
        sourceMessages.where((message) => message.isUser).firstOrNull;
    if (userAnchor == null) {
      return _blockBuilder.buildAssistantBlocks(
        messages: sourceMessages,
        groupId: groupId,
      );
    }

    final turnId =
        '${groupId ?? 0}_${userAnchor.id ?? 'user_$fallbackUserIndex'}';
    Logger.temp(
      'ChatMessageList',
      '_blocksForSegment filtering',
      reason: 'diagnose streaming performance',
      data: {
        'targetTurnId': turnId,
        'projectedBlockCount': projectedAssistantBlocks.length,
        'projectedBlockTypes':
            projectedAssistantBlocks.map((b) => b.type.name).join(','),
        'projectedArtifactCount': projectedAssistantBlocks
            .where((b) => b.type == AssistantTurnBlockType.artifact)
            .length,
        'allBlockTurnIds': projectedAssistantBlocks
            .map((b) => '${b.type.name}:${b.turnId}')
            .join(' | '),
      },
    );
    final blocks = projectedAssistantBlocks
        .where((block) => block.turnId == turnId)
        .toList(growable: false);
    Logger.temp(
      'ChatMessageList',
      '_blocksForSegment filtered result',
      reason: 'diagnose streaming performance',
      data: {
        'filteredBlockCount': blocks.length,
        'filteredBlockTypes': blocks.map((b) => b.type.name).join(','),
        'filteredArtifactCount': blocks
            .where((b) => b.type == AssistantTurnBlockType.artifact)
            .length,
      },
    );
    if (blocks.isNotEmpty) {
      return blocks;
    }

    if (sourceMessages.any(_isProjectionOwnedMessage)) {
      return const <AssistantTurnBlock>[];
    }

    return _blockBuilder.buildAssistantBlocks(
      messages: sourceMessages,
      groupId: groupId,
    );
  }

  bool _isProjectionOwnedMessage(ChatMessage message) {
    switch (message.contentType) {
      case MessageContentType.toolInvocation:
      case MessageContentType.actionConfirmation:
        return _canProjectToolInvocation(message.payloadJson);
      case MessageContentType.toolResult:
        return _canProjectToolResult(message.payloadJson);
      case MessageContentType.contextBoundary:
        return true;
      case MessageContentType.askUserQuestionPrompt:
      case MessageContentType.askUserQuestionResult:
        return true;
      case MessageContentType.plainText:
        return false;
    }
  }

  bool _canProjectToolInvocation(Map<String, dynamic>? payload) {
    if (payload == null) {
      return false;
    }
    try {
      ToolInvocation.fromJson(payload);
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _canProjectToolResult(Map<String, dynamic>? payload) {
    if (payload == null) {
      return false;
    }
    try {
      final result = ToolResult.fromJson(payload);
      return result.toolName.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  String _buildUserItemKey(ChatMessage message) {
    return 'user-${message.timestamp.microsecondsSinceEpoch}';
  }

  String _buildAssistantItemKey(
    AssistantTurnBlock block,
    ChatMessage? sourceMessage,
  ) {
    final logicalId = block.logicalId?.trim();
    final key =
        logicalId != null && logicalId.isNotEmpty ? logicalId : block.id;
    Logger.temp(
      'ChatMessageList',
      'stableKey generated',
      reason: 'diagnose streaming performance',
      data: {
        'blockId': block.id,
        'blockType': block.type.name,
        'updatedAtMicros': block.updatedAt.microsecondsSinceEpoch,
        'stableKey': key,
      },
    );
    return key;
  }

  ChatMessage? _resolveSourceMessage(
    List<ChatMessage> messages,
    AssistantTurnBlock block,
  ) {
    final payload = block.payload;
    final sourceMessageId = payload?['sourceMessageId'];
    if (sourceMessageId is int) {
      return messages
          .where((message) => message.id == sourceMessageId)
          .firstOrNull;
    }

    return messages
        .where((message) => message.timestamp == block.createdAt)
        .firstOrNull;
  }

  Widget _buildRowWithOptionalAnchor({
    required ChatTimelineItem item,
    required Widget child,
  }) {
    final anchorKey = item.rowAnchorKey;
    if (anchorKey == null) {
      return child;
    }

    final alignment = item.type == ChatTimelineItemType.assistantBlock
        ? Alignment.bottomLeft
        : Alignment.topLeft;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: Align(
              alignment: alignment,
              child: SizedBox(
                key: anchorKey,
                width: 0,
                height: 0,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showMessageOptionMenu(ChatMessage message) {
    final messagesNotifier = ref.read(messagesProvider.notifier);

    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            child: const Text('复制'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: message.text));
              final spacing = Theme.of(context).extension<AppSpacing>()!;
              final messenger = ScaffoldMessenger.of(this.context);
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: const Text('已复制到剪贴板'),
                    behavior: SnackBarBehavior.floating,
                    margin: EdgeInsets.fromLTRB(
                      spacing.lg,
                      0,
                      spacing.lg,
                      spacing.xl * 6.2,
                    ),
                    duration: const Duration(milliseconds: 1400),
                  ),
                );
              Navigator.pop(context);
            },
          ),
          CupertinoActionSheetAction(
            child: const Text('删除'),
            onPressed: () {
              final messages = ref.read(messagesProvider);
              final index = messages.indexOf(message);
              if (index != -1) {
                messagesNotifier.deleteMessagePair(index);
              }
              Navigator.pop(context);
            },
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          child: const Text('取消'),
          onPressed: () => Navigator.pop(context),
        ),
      ),
    );
  }

  void _scheduleActiveStatusVisibilitySync({
    ActiveTurnStatusPresentation? activeStatus,
    bool hasAnchor = true,
  }) {
    if (_pendingVisibilityCheck) {
      return;
    }
    _pendingVisibilityCheck = true;
    final generation = ++_visibilityCheckGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingVisibilityCheck = false;
      if (!mounted || generation != _visibilityCheckGeneration) {
        return;
      }
      _syncActiveStatusVisibility(
        activeStatus:
            activeStatus ?? ref.read(activeTurnStatusPresentationProvider),
        hasAnchor: hasAnchor,
      );
    });
  }

  void _scheduleDynamicInsetSync({
    double? minBottomInset,
    double? topTargetInset,
    String? latestUserStableKey,
    String? latestTailStableKey,
    String? pendingPinnedUserStableKey,
    ChatSendPhase? sendPhase,
  }) {
    _cachedMinBottomInset = minBottomInset ?? _cachedMinBottomInset;
    _cachedTopTargetInset = topTargetInset ?? _cachedTopTargetInset;
    _cachedLatestUserStableKey =
        latestUserStableKey ?? _cachedLatestUserStableKey;
    _cachedLatestTailStableKey =
        latestTailStableKey ?? _cachedLatestTailStableKey;
    _cachedPendingPinnedUserStableKey =
        pendingPinnedUserStableKey ?? _cachedPendingPinnedUserStableKey;
    _cachedSendPhase = sendPhase ?? _cachedSendPhase;
    if (_pendingDynamicInsetSync) {
      return;
    }
    _pendingDynamicInsetSync = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingDynamicInsetSync = false;
      if (!mounted) {
        return;
      }
      _syncDynamicInset(
        minBottomInset: _cachedMinBottomInset,
        topTargetInset: _cachedTopTargetInset,
        latestUserStableKey: _cachedLatestUserStableKey,
        latestTailStableKey: _cachedLatestTailStableKey,
        pendingPinnedUserStableKey: _cachedPendingPinnedUserStableKey,
        sendPhase: _cachedSendPhase,
      );
    });
  }

  void _syncDynamicInset({
    double? minBottomInset,
    double? topTargetInset,
    String? latestUserStableKey,
    String? latestTailStableKey,
    String? pendingPinnedUserStableKey,
    ChatSendPhase? sendPhase,
  }) {
    if (!_scrollController.hasClients) {
      return;
    }
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final resolvedMinBottomInset = minBottomInset ??
        (ref.read(chatBottomOverlayHeightProvider) > 0
            ? ref.read(chatBottomOverlayHeightProvider) + spacing.lg
            : spacing.xl * 4.2);
    final resolvedTopTargetInset = topTargetInset ??
        (_ghostHeaderHeight + spacing.xxs + MediaQuery.of(context).padding.top);
    final resolvedSendPhase = sendPhase ?? ref.read(sendPhaseProvider);

    if (latestUserStableKey != null &&
        pendingPinnedUserStableKey == latestUserStableKey &&
        resolvedSendPhase == ChatSendPhase.preparing &&
        latestUserStableKey != _lastPinnedLatestUserStableKey) {
      _initializePinnedLatestUserInset(
        latestUserStableKey: latestUserStableKey,
        topTargetInset: resolvedTopTargetInset,
      );
      return;
    }

    final shouldShrinkExtraInset = latestTailStableKey != null &&
        latestUserStableKey != null &&
        latestTailStableKey != latestUserStableKey;
    if (!shouldShrinkExtraInset) {
      return;
    }

    _shrinkDynamicInsetIfNeeded(minBottomInset: resolvedMinBottomInset);
  }

  void _initializePinnedLatestUserInset({
    required String latestUserStableKey,
    required double topTargetInset,
  }) {
    if (!_scrollController.hasClients) {
      return;
    }

    final rowContext = _latestUserRowAnchorKey.currentContext;
    if (rowContext == null) {
      final nextOffset = _scrollController.position.maxScrollExtent;
      if ((_scrollController.offset - nextOffset).abs() > 0.5) {
        _scrollController.jumpTo(nextOffset);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _scheduleDynamicInsetSync();
      });
      return;
    }

    final listBox = context.findRenderObject() as RenderBox?;
    final userBox = rowContext.findRenderObject() as RenderBox?;
    if (listBox == null || userBox == null) {
      return;
    }

    final listTop = listBox.localToGlobal(Offset.zero).dy;
    final userTop = userBox.localToGlobal(Offset.zero).dy;
    final delta = userTop - (listTop + topTargetInset);
    _lastPinnedLatestUserStableKey = latestUserStableKey;

    if (delta > 1) {
      ref.read(chatMessageListExtraBottomInsetProvider.notifier).state += delta;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) {
          return;
        }
        final nextOffset = (_scrollController.offset + delta).clamp(
          _scrollController.position.minScrollExtent,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.jumpTo(nextOffset);
        ref.read(pendingPinnedUserMessageStableKeyProvider.notifier).state =
            null;
        _cachedPendingPinnedUserStableKey = null;
        _scheduleDynamicInsetSync();
      });
      return;
    }

    ref.read(pendingPinnedUserMessageStableKeyProvider.notifier).state = null;
    _cachedPendingPinnedUserStableKey = null;
    _scheduleDynamicInsetSync();
  }

  void _shrinkDynamicInsetIfNeeded({
    required double minBottomInset,
  }) {
    final listBox = context.findRenderObject() as RenderBox?;
    final tailObject =
        _latestTimelineTailAnchorKey.currentContext?.findRenderObject() ??
            _latestUserRowAnchorKey.currentContext?.findRenderObject();
    final tailBox = tailObject as RenderBox?;
    if (listBox == null || tailBox == null) {
      return;
    }

    final currentExtraInset = ref.read(chatMessageListExtraBottomInsetProvider);
    if (currentExtraInset <= 0) {
      return;
    }

    final listBottom = listBox.localToGlobal(Offset(0, listBox.size.height)).dy;
    final tailBottom = tailBox.localToGlobal(Offset(0, tailBox.size.height)).dy;
    final safeBottom = listBottom - minBottomInset;
    final allowedExtraInset =
        (safeBottom - tailBottom).clamp(0, double.infinity);
    if (allowedExtraInset >= currentExtraInset - 0.5) {
      return;
    }
    ref.read(chatMessageListExtraBottomInsetProvider.notifier).state =
        allowedExtraInset.toDouble();
  }

  void _syncActiveStatusVisibility({
    required ActiveTurnStatusPresentation? activeStatus,
    required bool hasAnchor,
  }) {
    if (activeStatus == null || !hasAnchor) {
      _setActiveStatusFloatingState(
        const ActiveTurnStatusFloatingState(
          turnId: null,
          isFloating: false,
        ),
      );
      return;
    }

    final anchorContext = _activeStatusAnchorKey.currentContext;
    if (anchorContext == null) {
      _setActiveStatusFloatingState(
        ActiveTurnStatusFloatingState(
          turnId: activeStatus.turnId,
          isFloating: true,
        ),
      );
      return;
    }

    final listRenderObject = context.findRenderObject();
    final anchorRenderObject = anchorContext.findRenderObject();
    if (listRenderObject is! RenderBox || anchorRenderObject is! RenderBox) {
      return;
    }
    if (!listRenderObject.hasSize || !anchorRenderObject.hasSize) {
      return;
    }

    final isCurrentlyFloating =
        ref.read(activeTurnStatusFloatingStateProvider).isFloating;
    final viewportMargin = isCurrentlyFloating
        ? _floatingExitViewportMargin
        : _floatingEnterViewportMargin;
    final listRect = MatrixUtils.transformRect(
      listRenderObject.getTransformTo(null),
      Offset.zero & listRenderObject.size,
    );
    final anchorRect = MatrixUtils.transformRect(
      anchorRenderObject.getTransformTo(null),
      Offset.zero & anchorRenderObject.size,
    );
    final isFullyVisible = anchorRect.top >= listRect.top + viewportMargin &&
        anchorRect.bottom <= listRect.bottom - viewportMargin;

    _setActiveStatusFloatingState(
      ActiveTurnStatusFloatingState(
        turnId: activeStatus.turnId,
        isFloating: !isFullyVisible,
        isInVisibilityGrace: _shouldKeepFloatingVisibleDuringExit(
          isFloating: !isFullyVisible,
        ),
      ),
    );
  }

  void _setActiveStatusFloatingState(ActiveTurnStatusFloatingState nextState) {
    final notifier = ref.read(activeTurnStatusFloatingStateProvider.notifier);
    final previous = notifier.state;
    if (previous.turnId == nextState.turnId &&
        previous.isFloating == nextState.isFloating &&
        previous.isInVisibilityGrace == nextState.isInVisibilityGrace) {
      return;
    }
    notifier.state = nextState;
    _scheduleFloatingVisibilityGraceExpiry(nextState);
  }

  bool _shouldKeepFloatingVisibleDuringExit({required bool isFloating}) {
    if (isFloating) {
      return false;
    }
    final wasFloating =
        ref.read(activeTurnStatusFloatingStateProvider).isFloating;
    return wasFloating;
  }

  void _scheduleFloatingVisibilityGraceExpiry(
    ActiveTurnStatusFloatingState state,
  ) {
    _floatingVisibilityGraceTimer?.cancel();
    if (!state.isInVisibilityGrace) {
      _floatingVisibilityGraceTimer = null;
      return;
    }
    _floatingVisibilityGraceTimer = Timer(
      _floatingVisibilityExitGrace,
      () {
        if (!mounted) {
          return;
        }
        final notifier =
            ref.read(activeTurnStatusFloatingStateProvider.notifier);
        final current = notifier.state;
        if (current.turnId == state.turnId &&
            current.isInVisibilityGrace &&
            !current.isFloating) {
          notifier.state = ActiveTurnStatusFloatingState(
            turnId: current.turnId,
            isFloating: false,
          );
        } else {
          _scheduleActiveStatusVisibilitySync();
        }
      },
    );
  }
}

class _EmptyStateModelSetupState {
  const _EmptyStateModelSetupState({required this.requiresSetup});

  final bool requiresSetup;
}
