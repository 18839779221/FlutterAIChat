import 'dart:async';

import 'package:ai_chat/models/chat/assistant_turn_block.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/services/chat_block_builder.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/widgets/chat_empty_state.dart';
import 'package:ai_chat/widgets/chat_timeline/chat_timeline_item.dart';
import 'package:ai_chat/widgets/chat_timeline/chat_timeline_row.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChatMessageList extends ConsumerStatefulWidget {
  const ChatMessageList({super.key});

  @override
  ConsumerState<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends ConsumerState<ChatMessageList> {
  final ChatBlockBuilder _blockBuilder = ChatBlockBuilder();
  static const double _anchorThreshold = 100;
  bool _isLoadingOlderHistory = false;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ref.read(scrollControllerProvider);
    _scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
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
    final sendState = ref.watch(chatSendStateProvider);
    final sendPhase = sendState.phase;
    final timelineProjection = ref.watch(chatTimelineProjectionProvider);
    final hasMoreMessages = ref.watch(hasMoreMessagesProvider);
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final textController = ref.read(textControllerProvider);
    final focusNode = ref.read(focusNodeProvider);

    final timelineItems = _buildTimelineItems(
      messages,
      sendPhase,
      timelineProjection.assistantBlocks,
      sendState.statusText,
    );
    final itemCount = timelineItems.length + (hasMoreMessages ? 1 : 0);
    final currentGroupId = ref.read(currentGroupProvider)?.id;

    if (messages.isEmpty) {
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

    return CustomScrollView(
      controller: _scrollController,
      physics: const ClampingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            spacing.sm,
            spacing.xl * 2 + spacing.xxs,
            spacing.sm,
            spacing.xl * 4.2,
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
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  List<ChatTimelineItem> _buildTimelineItems(
    List<ChatMessage> messages,
    ChatSendPhase sendPhase,
    List<AssistantTurnBlock> projectedAssistantBlocks,
    String? sendStatusText,
  ) {
    if (messages.isEmpty) {
      return const [];
    }

    final currentGroup = ref.read(currentGroupProvider);
    final sortedMessages = [...messages]..sort(compareChatMessagesForTimeline);
    final runningTail = ref
        .read(latestMessageRunningStatusResolverProvider)
        .resolve(
          messages: sortedMessages,
          sendPhase: sendPhase,
          statusTextOverride: sendStatusText,
        );

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
        final hasAssistantOutput = segment.length > 1;
        items.add(
          ChatTimelineItem(
            stableKey: _buildUserItemKey(current),
            type: ChatTimelineItemType.userBubble,
            userMessage: current,
            sourceMessages: segment,
            runningTailText:
                isLatestTurn && !hasAssistantOutput && runningTail != null
                    ? runningTail.text
                    : null,
          ),
        );

        final blocks = _blocksForSegment(
          sourceMessages: segment,
          projectedAssistantBlocks: projectedAssistantBlocks,
          groupId: currentGroup?.id,
          fallbackUserIndex:
              items.where((item) => item.userMessage != null).length,
        );
        items.addAll(
          _buildAssistantItems(
            sourceMessages: segment,
            blocks: blocks,
            runningTailText:
                isLatestTurn && hasAssistantOutput ? runningTail?.text : null,
          ),
        );
        cursor = nextCursor;
        continue;
      }

      final orphanBlocks = _blockBuilder.buildAssistantBlocks(
        messages: [current],
        groupId: currentGroup?.id,
      );
      items.addAll(
        _buildAssistantItems(
          sourceMessages: [current],
          blocks: orphanBlocks,
          runningTailText:
              cursor == sortedMessages.length - 1 ? runningTail?.text : null,
        ),
      );
      cursor += 1;
    }

    return items;
  }

  List<ChatTimelineItem> _buildAssistantItems({
    required List<ChatMessage> sourceMessages,
    required List<AssistantTurnBlock> blocks,
    required String? runningTailText,
  }) {
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
          runningTailText: runningTailText != null && index == blocks.length - 1
              ? runningTailText
              : null,
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
    final blocks = projectedAssistantBlocks
        .where((block) => block.turnId == turnId)
        .toList(growable: false);
    if (blocks.isNotEmpty) {
      return blocks;
    }

    return _blockBuilder.buildAssistantBlocks(
      messages: sourceMessages,
      groupId: groupId,
    );
  }

  String _buildUserItemKey(ChatMessage message) {
    return 'user-${message.id ?? message.timestamp.microsecondsSinceEpoch}';
  }

  String _buildAssistantItemKey(
    AssistantTurnBlock block,
    ChatMessage? sourceMessage,
  ) {
    return block.id;
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
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制到剪贴板')),
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
}
