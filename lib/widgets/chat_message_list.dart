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
  static const double _floatingEnterViewportMargin = 12;
  static const double _floatingExitViewportMargin = 4;
  bool _isLoadingOlderHistory = false;
  late final ScrollController _scrollController;
  final GlobalKey _activeStatusAnchorKey = GlobalKey(
    debugLabel: 'active-turn-status-anchor',
  );
  int _previousItemCount = 0;
  bool _pendingVisibilityCheck = false;
  int _visibilityCheckGeneration = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = ref.read(scrollControllerProvider);
    _scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
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

  void _resetScrollToInitial() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      _scrollController.jumpTo(_scrollController.position.minScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ChatGroup?>(currentGroupProvider, (previous, next) {
      if (previous?.id != next?.id) {
        _resetScrollToInitial();
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
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final textController = ref.read(textControllerProvider);
    final focusNode = ref.read(focusNodeProvider);
    final bottomTimelineInset = bottomOverlayHeight > 0
        ? spacing.sm
        : spacing.xl * 4.2;

    final timelineItems = _buildTimelineItems(
      messages,
      timelineProjection.assistantBlocks,
      activeTurnStatus,
      hideInlineActiveStatus: shouldFloatActiveStatus,
    );
    final itemCount = timelineItems.length + (hasMoreMessages ? 1 : 0);
    final currentGroupId = ref.read(currentGroupProvider)?.id;

    // Detect if new items were added (only animate the last item if count increased)
    final hasNewItems = timelineItems.length > _previousItemCount;
    _previousItemCount = timelineItems.length;

    if (messages.isEmpty) {
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

    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _scheduleActiveStatusVisibilitySync();
        return false;
      },
      child: CustomScrollView(
        controller: _scrollController,
        physics: const ClampingScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              spacing.sm,
              spacing.xl * 2 + spacing.xxs,
              spacing.sm,
              bottomTimelineInset,
            ),
            sliver: SliverList.builder(
              itemCount: itemCount,
              itemBuilder: (context, index) {
                if (hasMoreMessages && index == timelineItems.length) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                final item = timelineItems[index];
                final isLastItem = index == timelineItems.length - 1;
                final shouldAnimate = hasNewItems && isLastItem;

                return Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: kIsWeb ? 860 : 720,
                    ),
                    child: Padding(
                      padding: EdgeInsets.only(bottom: spacing.sm),
                      child: ChatTimelineRow(
                        key: ValueKey('timeline-block-${item.stableKey}'),
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
                );
              },
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
    final selectedProviderId = selection.selectedProviderId as String?;
    final defaultProviderId = selection.defaultProviderId as String?;
    final selectedModelId = selection.selectedModelId as String?;
    final defaultModelId = selection.defaultModelId as String?;

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
    {required bool hideInlineActiveStatus}
  ) {
    if (messages.isEmpty) {
      return const [];
    }

    Logger.temp(
      'ChatMessageList',
      '_buildTimelineItems received blocks',
      reason: 'diagnose streaming performance',
      data: {
        'projectedBlockCount': projectedAssistantBlocks.length,
        'projectedBlockTypes': projectedAssistantBlocks.map((b) => b.type.name).join(','),
        'projectedArtifactCount': projectedAssistantBlocks.where((b) => b.type == AssistantTurnBlockType.artifact).length,
        'allProjectedTurnIds': projectedAssistantBlocks.map((b) => '${b.type.name}:${b.turnId}').join(' | '),
      },
    );

    final currentGroup = ref.read(currentGroupProvider);
    final sortedMessages = [...messages]..sort(compareChatMessagesForTimeline);
    final effectiveStatus = activeTurnStatus;

    final items = <ChatTimelineItem>[];
    var cursor = 0;

    while (cursor < sortedMessages.length) {
      final current = sortedMessages[cursor];

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
    required bool hideInlineStatus,
  }) {
    Logger.temp(
      'ChatMessageList',
      '_buildAssistantItems called',
      reason: 'diagnose streaming performance',
      data: {
        'blockCount': blocks.length,
        'blockTypes': blocks.map((b) => b.type.name).join(','),
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
          activeStatus: activeStatus != null && index == blocks.length - 1
              ? activeStatus
              : null,
          statusAnchorKey: activeStatus != null && index == blocks.length - 1
              ? _activeStatusAnchorKey
              : null,
          hideInlineStatus:
              activeStatus != null && index == blocks.length - 1
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
        'projectedBlockTypes': projectedAssistantBlocks.map((b) => b.type.name).join(','),
        'projectedArtifactCount': projectedAssistantBlocks.where((b) => b.type == AssistantTurnBlockType.artifact).length,
        'allBlockTurnIds': projectedAssistantBlocks.map((b) => '${b.type.name}:${b.turnId}').join(' | '),
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
        'filteredArtifactCount': blocks.where((b) => b.type == AssistantTurnBlockType.artifact).length,
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
    return 'user-${message.id ?? message.timestamp.microsecondsSinceEpoch}';
  }

  String _buildAssistantItemKey(
    AssistantTurnBlock block,
    ChatMessage? sourceMessage,
  ) {
    final key = block.id;
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
        activeStatus: activeStatus ?? ref.read(activeTurnStatusPresentationProvider),
        hasAnchor: hasAnchor,
      );
    });
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
        ref.read(activeTurnStatusFloatingVisibilityProvider);
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
    final isFullyVisible =
        anchorRect.top >= listRect.top + viewportMargin &&
            anchorRect.bottom <= listRect.bottom - viewportMargin;

    _setActiveStatusFloatingState(
      ActiveTurnStatusFloatingState(
        turnId: activeStatus.turnId,
        isFloating: !isFullyVisible,
      ),
    );
  }

  void _setActiveStatusFloatingState(ActiveTurnStatusFloatingState nextState) {
    final notifier = ref.read(activeTurnStatusFloatingStateProvider.notifier);
    final previous = notifier.state;
    if (previous.turnId == nextState.turnId &&
        previous.isFloating == nextState.isFloating) {
      return;
    }
    notifier.state = nextState;
  }
}

class _EmptyStateModelSetupState {
  const _EmptyStateModelSetupState({required this.requiresSetup});

  final bool requiresSetup;
}
