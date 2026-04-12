import 'package:ai_chat/models/chat/assistant_turn_block.dart';
import 'package:ai_chat/models/chat/tool_workflow_step.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/response/structured_summary_card.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/services/chat_block_builder.dart';
import 'package:ai_chat/theme/app_colors.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/widgets/chat_blocks/assistant_doc_block.dart';
import 'package:ai_chat/widgets/chat_blocks/final_response_block.dart';
import 'package:ai_chat/widgets/chat_blocks/structured_output_block.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_result_summary_row.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_workflow_card.dart';
import 'package:ai_chat/widgets/chat_blocks/user_anchor_bubble.dart';
import 'package:ai_chat/widgets/chat_empty_state.dart';
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
  bool _isNearBottom = true;
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

    final maxScroll = scrollController.position.maxScrollExtent;
    final isNearBottom = maxScroll - scrollController.offset <= 100;

    if (_isNearBottom != isNearBottom) {
      setState(() {
        _isNearBottom = isNearBottom;
      });
    }

    final scrollingPosition = scrollController.position;
    if (scrollingPosition.userScrollDirection == ScrollDirection.reverse) {
      ref.read(focusNodeProvider).unfocus();
      ref.read(autoScrollToBottomProvider.notifier).state = false;
    } else if (scrollingPosition.userScrollDirection ==
            ScrollDirection.forward &&
        isNearBottom) {
      ref.read(autoScrollToBottomProvider.notifier).state = true;
    }
  }

  void _scrollToBottom() {
    final scrollController = ref.read(scrollControllerProvider);
    if (!scrollController.hasClients) {
      return;
    }
    scrollController.animateTo(
      scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
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

    if (isGenerating && autoScrollToBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scrollController.hasClients) {
          scrollController.animateTo(
            scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }

    final timelineItems = _buildTimelineItems(messages);
    final itemCount = timelineItems.length + (hasMoreMessages ? 1 : 0);

    if (messages.isEmpty) {
      return const ChatEmptyState();
    }

    return Stack(
      children: [
        ListView.builder(
          controller: scrollController,
          padding: EdgeInsets.fromLTRB(
            spacing.sm,
            spacing.xl * 2.3,
            spacing.sm,
            spacing.xl * 4.2,
          ),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            if (hasMoreMessages && index == 0) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: CircularProgressIndicator(),
                ),
              );
            }

            final item = timelineItems[hasMoreMessages ? index - 1 : index];
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
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
        if (!_isNearBottom)
          Positioned(
            right: 16,
            bottom: 28,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: colors.assistantSurface.withValues(alpha: 0.94),
              foregroundColor: colors.primaryText,
              elevation: 1.5,
              onPressed: _scrollToBottom,
              child: const Icon(Icons.keyboard_arrow_down),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildTimelineItems(List<ChatMessage> messages) {
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
          GestureDetector(
            onLongPress: () => _showMessageOptionMenu(current),
            child: UserAnchorBubble(text: current.text),
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
        widgets.addAll(_buildAssistantBlocks(segment, blocks));
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
    List<AssistantTurnBlock> blocks,
  ) {
    final widgets = <Widget>[];

    for (final block in blocks) {
      final sourceMessage = _resolveSourceMessage(sourceMessages, block);

      switch (block.type) {
        case AssistantTurnBlockType.analysis:
          widgets.add(
            GestureDetector(
              onLongPress: sourceMessage == null
                  ? null
                  : () => _showMessageOptionMenu(sourceMessage),
              child: AssistantDocBlock(
                label: 'Analysis',
                text: block.text ?? '',
              ),
            ),
          );
          break;
        case AssistantTurnBlockType.finalResponse:
          widgets.add(
            GestureDetector(
              onLongPress: sourceMessage == null
                  ? null
                  : () => _showMessageOptionMenu(sourceMessage),
              child: FinalResponseBlock(
                title: block.title ?? 'Final Response',
                text: block.text ?? '',
              ),
            ),
          );
          break;
        case AssistantTurnBlockType.structuredOutput:
          widgets.add(
            GestureDetector(
              onLongPress: sourceMessage == null
                  ? null
                  : () => _showMessageOptionMenu(sourceMessage),
              child: StructuredOutputBlock(
                title: block.title ?? 'Structured Output',
                fields: _extractStructuredFields(block),
              ),
            ),
          );
          break;
        case AssistantTurnBlockType.toolResultSummary:
          final payload = block.payload;
          if (payload == null) {
            widgets.add(AssistantDocBlock(text: block.text ?? ''));
            break;
          }
          widgets
              .add(ToolResultSummaryRow(result: ToolResult.fromJson(payload)));
          break;
        case AssistantTurnBlockType.toolWorkflow:
          final steps = _extractWorkflowSteps(block);
          final manualExpandedStepId =
              ref.watch(toolWorkflowExpansionProvider)[block.turnId];
          widgets.add(
            ToolWorkflowCard(
              title: block.title ?? 'Tool Workflow',
              steps: steps,
              expandedStepId: resolveWorkflowExpandedStepId(
                turnId: block.turnId,
                steps: steps,
                manualExpandedStepId: manualExpandedStepId,
              ),
              onStepTapped: (stepId) {
                ref
                    .read(toolWorkflowExpansionProvider.notifier)
                    .toggleExpandedStep(
                      turnId: block.turnId,
                      stepId: stepId,
                    );
              },
              onContinue: sourceMessage == null
                  ? null
                  : () => ref
                      .read(chatControllerProvider)
                      .confirmToolInvocation(sourceMessage),
              onCancel: sourceMessage == null
                  ? null
                  : () => ref
                      .read(chatControllerProvider)
                      .cancelToolInvocation(sourceMessage),
              onContinueAndTrust: sourceMessage == null
                  ? null
                  : () => ref
                      .read(chatControllerProvider)
                      .confirmToolInvocation(sourceMessage, trustTool: true),
            ),
          );
          break;
      }
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
