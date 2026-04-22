import 'package:ai_chat/models/chat/assistant_turn_block.dart';
import 'package:ai_chat/models/chat/tool_card_presentation_variant.dart';
import 'package:ai_chat/models/chat/tool_workflow_step.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/response/structured_summary_card.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/services/chat_block_builder.dart';
import 'package:ai_chat/services/tool_card_presentation_mapper.dart';
import 'package:ai_chat/theme/app_colors.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/widgets/chat_blocks/assistant_doc_block.dart';
import 'package:ai_chat/widgets/chat_blocks/final_response_block.dart';
import 'package:ai_chat/widgets/chat_blocks/streaming_response_block.dart';
import 'package:ai_chat/widgets/chat_blocks/structured_output_block.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_exception_card.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_inline_step_row.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_outcome_card.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_workflow_card.dart';
import 'package:ai_chat/widgets/chat_blocks/user_anchor_bubble.dart';
import 'package:ai_chat/widgets/chat_empty_state.dart';
import 'package:ai_chat/widgets/interaction/ask_user_question_card.dart';
import 'package:ai_chat/widgets/interaction/ask_user_question_result_card.dart';
import 'package:ai_chat/widgets/interaction/ask_user_question_timeline_card.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  bool _isNearBottom = true;
  bool _isLoadingOlderHistory = false;
  GlobalKey? _latestTurnEndKey;
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

    final isNearBottom = _isNearLatestAnchor(scrollController);

    if (_isNearBottom != isNearBottom) {
      setState(() {
        _isNearBottom = isNearBottom;
      });
    }
  }

  void _scrollToBottom() {
    ref.read(autoScrollToBottomProvider.notifier).state = true;
    _scrollToLatestTurn(animated: true);
  }

  bool _isNearLatestAnchor(ScrollController scrollController) {
    final targetOffset = _latestAnchorOffset(scrollController);
    if (targetOffset == null) {
      return true;
    }
    return (scrollController.offset - targetOffset).abs() <= _anchorThreshold;
  }

  bool _shouldLoadOlderHistory(ScrollController scrollController) {
    if (_isLoadingOlderHistory || !ref.read(hasMoreMessagesProvider)) {
      return false;
    }

    final minScroll = scrollController.position.minScrollExtent;
    return scrollController.offset <= minScroll + _anchorThreshold;
  }

  double? _latestAnchorOffset(ScrollController scrollController) {
    if (!scrollController.hasClients) {
      return null;
    }

    final anchorContext = _latestTurnEndKey?.currentContext;
    if (anchorContext == null) {
      return scrollController.position.maxScrollExtent;
    }

    final renderObject = anchorContext.findRenderObject();
    if (renderObject == null || !renderObject.attached) {
      return scrollController.position.maxScrollExtent;
    }

    final viewport = RenderAbstractViewport.maybeOf(renderObject);
    if (viewport == null) {
      return scrollController.position.maxScrollExtent;
    }

    final targetOffset = viewport.getOffsetToReveal(renderObject, 1).offset;
    return targetOffset.clamp(
      scrollController.position.minScrollExtent,
      scrollController.position.maxScrollExtent,
    );
  }

  void _scrollToLatestTurn({required bool animated}) {
    final scrollController = ref.read(scrollControllerProvider);
    final targetOffset = _latestAnchorOffset(scrollController);
    if (targetOffset == null) {
      return;
    }

    if (animated) {
      scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      return;
    }

    scrollController.jumpTo(targetOffset);
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

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(messagesProvider);
    final isGenerating = ref.watch(isGeneratingProvider);
    final autoScrollToBottom = ref.watch(autoScrollToBottomProvider);
    final hasMoreMessages = ref.watch(hasMoreMessagesProvider);
    final scrollController = ref.watch(scrollControllerProvider);
    final colors = Theme.of(context).extension<AppColors>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final textController = ref.read(textControllerProvider);
    final focusNode = ref.read(focusNodeProvider);

    if (autoScrollToBottom && !_isNearBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scrollController.hasClients && mounted) {
          _scrollToLatestTurn(animated: isGenerating);
        }
      });
    }

    final latestUserMessage = _findLatestUserMessage(messages);
    final timelineItems = _buildTimelineItems(
      messages,
      latestUserMessage: latestUserMessage,
    );
    final itemCount = timelineItems.length + (hasMoreMessages ? 1 : 0);

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

    return Stack(
      children: [
        NotificationListener<UserScrollNotification>(
          onNotification: (notification) {
            if (notification.direction == ScrollDirection.idle) {
              return false;
            }
            if (_isNearLatestAnchor(scrollController)) {
              return false;
            }
            ref.read(focusNodeProvider).unfocus();
            ref.read(autoScrollToBottomProvider.notifier).state = false;
            return false;
          },
          child: CustomScrollView(
            controller: scrollController,
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
                          child: item,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        if (!_isNearBottom || !autoScrollToBottom)
          Positioned(
            right: 16,
            bottom: 28,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: colors.assistantSurface.withValues(alpha: 0.9),
              foregroundColor: colors.primaryText.withValues(alpha: 0.88),
              elevation: 0.8,
              onPressed: _scrollToBottom,
              child: const Icon(Icons.keyboard_arrow_down),
            ),
          ),
      ],
    );
  }

  ChatMessage? _findLatestUserMessage(List<ChatMessage> messages) {
    for (var index = messages.length - 1; index >= 0; index -= 1) {
      final message = messages[index];
      if (message.isUser) {
        return message;
      }
    }
    return null;
  }

  List<Widget> _buildTimelineItems(
    List<ChatMessage> messages, {
    required ChatMessage? latestUserMessage,
  }) {
    if (messages.isEmpty) {
      return const [];
    }

    final currentGroup = ref.read(currentGroupProvider);
    final sortedMessages = [...messages]..sort(compareChatMessagesForTimeline);

    final widgets = <Widget>[];
    var cursor = 0;

    while (cursor < sortedMessages.length) {
      final current = sortedMessages[cursor];

      if (current.isUser) {
        widgets.add(
          Padding(
            key: identical(current, latestUserMessage)
                ? (_latestTurnEndKey = GlobalKey(
                    debugLabel: 'latest-turn-fallback-anchor',
                  ))
                : null,
            padding: const EdgeInsets.only(bottom: 2),
            child: GestureDetector(
              onLongPress: () => _showMessageOptionMenu(current),
              child: UserAnchorBubble(text: current.text),
            ),
          ),
        );

        final segment = <ChatMessage>[current];
        var nextCursor = cursor + 1;
        while (nextCursor < sortedMessages.length &&
            !sortedMessages[nextCursor].isUser) {
          segment.add(sortedMessages[nextCursor]);
          nextCursor += 1;
        }

        final blocks = _blockBuilder.buildAssistantBlocks(
          messages: segment,
          groupId: currentGroup?.id,
        );
        widgets.addAll(
          _buildAssistantBlocks(
            segment,
            blocks,
            markLatestTurnEnd: identical(current, latestUserMessage),
          ),
        );
        cursor = nextCursor;
        continue;
      }

      final orphanBlocks = _blockBuilder.buildAssistantBlocks(
        messages: [current],
        groupId: currentGroup?.id,
      );
      widgets.addAll(_buildAssistantBlocks([current], orphanBlocks));
      cursor += 1;
    }

    return widgets;
  }

  List<Widget> _buildAssistantBlocks(
    List<ChatMessage> sourceMessages,
    List<AssistantTurnBlock> blocks, {
    bool markLatestTurnEnd = false,
  }) {
    final widgets = <Widget>[];
    final activeAskUserQuestion =
        ref.read(activeAskUserQuestionMessageProvider);
    final toolUiRegistry = ref.read(toolUiRendererRegistryProvider);

    for (var index = 0; index < blocks.length; index += 1) {
      final block = blocks[index];
      final isLatestTurnEnd = markLatestTurnEnd && index == blocks.length - 1;
      final sourceMessage = _resolveSourceMessage(sourceMessages, block);
      late Widget blockWidget;

      switch (block.type) {
        case AssistantTurnBlockType.analysis:
          blockWidget = GestureDetector(
            onLongPress: sourceMessage == null
                ? null
                : () => _showMessageOptionMenu(sourceMessage),
            child: AssistantDocBlock(
              label: 'Analysis',
              text: block.text ?? '',
            ),
          );
          break;
        case AssistantTurnBlockType.finalResponse:
          blockWidget = GestureDetector(
            onLongPress: sourceMessage == null
                ? null
                : () => _showMessageOptionMenu(sourceMessage),
            child: sourceMessage?.status == MessageStatus.generating
                ? StreamingResponseBlock(
                    text: block.text ?? '',
                  )
                : FinalResponseBlock(
                    title: block.title ?? '最终回答',
                    text: block.text ?? '',
                  ),
          );
          break;
        case AssistantTurnBlockType.structuredOutput:
          if (sourceMessage?.contentType ==
              MessageContentType.askUserQuestionPrompt) {
            final isActivePrompt = activeAskUserQuestion?.id != null &&
                activeAskUserQuestion!.id == sourceMessage?.id;
            blockWidget = isActivePrompt
                ? AskUserQuestionCard(message: sourceMessage!)
                : AskUserQuestionTimelineCard(message: sourceMessage!);
            break;
          }
          if (sourceMessage?.contentType ==
              MessageContentType.askUserQuestionResult) {
            blockWidget = AskUserQuestionResultCard(message: sourceMessage!);
            break;
          }
          blockWidget = GestureDetector(
            onLongPress: sourceMessage == null
                ? null
                : () => _showMessageOptionMenu(sourceMessage),
            child: StructuredOutputBlock(
              title: block.title ?? 'Structured Output',
              fields: _extractStructuredFields(block),
            ),
          );
          break;
        case AssistantTurnBlockType.toolResultSummary:
          final payload = block.payload;
          if (payload == null) {
            blockWidget = AssistantDocBlock(text: block.text ?? '');
            break;
          }
          final result = ToolResult.fromJson(payload);
          final customResultWidget =
              toolUiRegistry.findResultRenderer(result.toolName)?.buildResult(
                    context,
                    result: result,
                    sourceMessage: sourceMessage,
                  );
          if (customResultWidget != null) {
            blockWidget = customResultWidget;
            break;
          }
          final presentation = ToolCardPresentationMapper.mapResult(result);
          switch (presentation.variant) {
            case ToolCardPresentationVariant.outcomeCard:
              blockWidget = ToolOutcomeCard(model: presentation);
              break;
            case ToolCardPresentationVariant.exceptionCard:
              blockWidget = ToolExceptionCard(model: presentation);
              break;
            case ToolCardPresentationVariant.inlineStep:
            case ToolCardPresentationVariant.focusedActiveStep:
            case ToolCardPresentationVariant.confirmationStep:
            case ToolCardPresentationVariant.interactionCard:
              blockWidget = ToolInlineStepRow(model: presentation);
              break;
          }
          break;
        case AssistantTurnBlockType.toolWorkflow:
          final steps = _extractWorkflowSteps(block);
          final manualExpandedStepId =
              ref.watch(toolWorkflowExpansionProvider)[block.turnId];
          final expandedStepId = resolveWorkflowExpandedStepId(
            turnId: block.turnId,
            steps: steps,
            manualExpandedStepId: manualExpandedStepId,
          );
          final latestStep = steps.isEmpty ? null : steps.last;
          final customWorkflowWidget = latestStep == null
              ? null
              : toolUiRegistry
                  .findWorkflowRenderer(latestStep.toolName)
                  ?.buildWorkflowStep(
                  context,
                  steps: steps,
                  sourceMessage: sourceMessage,
                  isExpanded: latestStep.stepId == expandedStepId,
                  onTap: () {
                    ref
                        .read(toolWorkflowExpansionProvider.notifier)
                        .toggleExpandedStep(
                          turnId: block.turnId,
                          stepId: latestStep.stepId,
                        );
                  },
                );
          if (customWorkflowWidget != null) {
            blockWidget = customWorkflowWidget;
            break;
          }
          blockWidget = ToolWorkflowCard(
            title: block.title ?? 'Tool Workflow',
            steps: steps,
            expandedStepId: expandedStepId,
            onStepTapped: (stepId) {
              ref
                  .read(toolWorkflowExpansionProvider.notifier)
                  .toggleExpandedStep(
                    turnId: block.turnId,
                    stepId: stepId,
                  );
            },
          );
          break;
      }
      if (isLatestTurnEnd) {
        blockWidget = KeyedSubtree(
          key: _latestTurnEndKey = GlobalKey(debugLabel: 'latest-turn-end'),
          child: blockWidget,
        );
      }

      widgets.add(blockWidget);
    }

    return widgets;
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

  Map<String, String> _extractStructuredFields(AssistantTurnBlock block) {
    final payload = block.payload;
    if (payload == null) {
      return {
        '内容': block.text ?? '',
      };
    }

    try {
      final card = StructuredSummaryCard.fromJson(payload);
      return {
        '摘要': card.summary,
        if (card.keyPoints.isNotEmpty) '关键点': card.keyPoints.join(' / '),
        if (card.actionItems.isNotEmpty) '行动项': card.actionItems.join(' / '),
        if (card.risks.isNotEmpty) '风险': card.risks.join(' / '),
      };
    } catch (_) {
      return payload.map((key, value) => MapEntry(key, '$value'));
    }
  }

  List<ToolWorkflowStep> _extractWorkflowSteps(AssistantTurnBlock block) {
    final rawSteps = block.payload?['steps'];
    if (rawSteps is! List) {
      return const [];
    }

    return rawSteps.whereType<Map>().map((rawStep) {
      final json = Map<String, dynamic>.from(rawStep.cast<dynamic, dynamic>());
      final statusName = json['status'] as String? ?? 'proposed';
      final status = ToolWorkflowStepStatus.values.firstWhere(
        (value) => value.name == statusName,
        orElse: () => ToolWorkflowStepStatus.proposed,
      );

      return ToolWorkflowStep(
        stepId: json['stepId'] as String? ?? 'unknown-step',
        turnId: json['turnId'] as String? ?? block.turnId,
        toolName: json['toolName'] as String? ?? 'unknown_tool',
        title: json['title'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        status: status,
        requiresConfirmation: json['requiresConfirmation'] as bool? ?? false,
        executionPolicy: json['executionPolicy'] as String?,
        toolAccess: json['toolAccess'] is Map
            ? Map<String, dynamic>.from(json['toolAccess'] as Map)
            : null,
        details: json['details'] is Map
            ? Map<String, dynamic>.from(json['details'] as Map)
            : const {},
      );
    }).toList();
  }

  void _showMessageOptionMenu(ChatMessage message) {
    final messagesNotifier = ref.read(messagesProvider.notifier);
    final shouldShowStructuredDebugAction = kDebugMode &&
        message.isAssistant &&
        message.status == MessageStatus.completed &&
        message.contentType == MessageContentType.plainText;

    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        actions: [
          if (shouldShowStructuredDebugAction)
            CupertinoActionSheetAction(
              child: const Text('结构化整理（调试）'),
              onPressed: () async {
                Navigator.pop(context);
                await ref
                    .read(chatControllerProvider)
                    .structureMessageForDebug(message);
              },
            ),
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
