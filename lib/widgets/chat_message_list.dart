import 'dart:async';

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
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/utils/logger.dart';
import 'package:ai_chat/widgets/chat_blocks/assistant_doc_block.dart';
import 'package:ai_chat/widgets/chat_blocks/final_response_block.dart';
import 'package:ai_chat/widgets/chat_blocks/latest_message_running_status_tail.dart';
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
  static const Duration _minRunningVisibleDuration = Duration(seconds: 5);
  static const String _animationDebugTag = 'ToolAnimationDebug';
  bool _isLoadingOlderHistory = false;
  late final ScrollController _scrollController;
  final Set<String> _emittedAnimationDebugKeys = <String>{};

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

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(messagesProvider);
    final sendPhase = ref.watch(sendPhaseProvider);
    final hasMoreMessages = ref.watch(hasMoreMessagesProvider);
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final textController = ref.read(textControllerProvider);
    final focusNode = ref.read(focusNodeProvider);

    final timelineItems = _buildTimelineItems(messages, sendPhase);
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
                    child: item,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  List<Widget> _buildTimelineItems(
    List<ChatMessage> messages,
    ChatSendPhase sendPhase,
  ) {
    if (messages.isEmpty) {
      return const [];
    }

    final currentGroup = ref.read(currentGroupProvider);
    final sortedMessages = [...messages]..sort(compareChatMessagesForTimeline);
    final runningTail = ref
        .read(latestMessageRunningStatusResolverProvider)
        .resolve(messages: sortedMessages, sendPhase: sendPhase);

    final widgets = <Widget>[];
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
        Widget userBubble = Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: GestureDetector(
            onLongPress: () => _showMessageOptionMenu(current),
            child: UserAnchorBubble(text: current.text),
          ),
        );
        if (isLatestTurn && !hasAssistantOutput && runningTail != null) {
          userBubble = _wrapWithLatestRunningTail(
            child: userBubble,
            statusText: runningTail.text,
          );
        }
        widgets.add(userBubble);

        final blocks = _blockBuilder.buildAssistantBlocks(
          messages: segment,
          groupId: currentGroup?.id,
        );
        widgets.addAll(
          _buildAssistantBlocks(
            segment,
            blocks,
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
      widgets.addAll(
        _buildAssistantBlocks(
          [current],
          orphanBlocks,
          runningTailText: cursor == sortedMessages.length - 1
              ? runningTail?.text
              : null,
        ),
      );
      cursor += 1;
    }

    return widgets;
  }

  List<Widget> _buildAssistantBlocks(
    List<ChatMessage> sourceMessages,
    List<AssistantTurnBlock> blocks,
    {
    required String? runningTailText,
  }
  ) {
    final widgets = <Widget>[];
    final activeAskUserQuestion =
        ref.read(activeAskUserQuestionMessageProvider);
    final toolUiRegistry = ref.read(toolUiRendererRegistryProvider);

    for (var index = 0; index < blocks.length; index += 1) {
      final block = blocks[index];
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
          final resultWidget = _buildToolResultBlockWidget(
            block: block,
            result: result,
            sourceMessage: sourceMessage,
            toolUiRegistry: toolUiRegistry,
          );
          final delayedWorkflow = _resolveDelayedWorkflowPreview(
            resultBlock: block,
            result: result,
            sourceMessages: sourceMessages,
            toolUiRegistry: toolUiRegistry,
          );
          if (delayedWorkflow == null) {
            blockWidget = resultWidget;
            break;
          }
          blockWidget = _MinimumVisibleToolStateSwitcher(
            key: ValueKey('${block.id}_${delayedWorkflow.visibleUntil.millisecondsSinceEpoch}'),
            visibleUntil: delayedWorkflow.visibleUntil,
            runningChild: delayedWorkflow.workflowWidget,
            resultChild: resultWidget,
          );
          break;
        case AssistantTurnBlockType.toolWorkflow:
          blockWidget = _buildToolWorkflowBlockWidget(
            block: block,
            sourceMessage: sourceMessage,
            toolUiRegistry: toolUiRegistry,
          );
          break;
      }
      if (runningTailText != null && index == blocks.length - 1) {
        blockWidget = _wrapWithLatestRunningTail(
          child: blockWidget,
          statusText: runningTailText,
        );
      }
      widgets.add(blockWidget);
    }

    return widgets;
  }

  Widget _wrapWithLatestRunningTail({
    required Widget child,
    required String statusText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        child,
        LatestMessageRunningStatusTail(statusText: statusText),
      ],
    );
  }

  Widget _buildToolResultBlockWidget({
    required AssistantTurnBlock block,
    required ToolResult result,
    required ChatMessage? sourceMessage,
    required ToolUiRendererRegistry toolUiRegistry,
  }) {
    final customResultWidget =
        toolUiRegistry.findResultRenderer(result.toolName)?.buildResult(
              context,
              result: result,
              sourceMessage: sourceMessage,
            );
    if (customResultWidget != null) {
      return customResultWidget;
    }
    final presentation = ToolCardPresentationMapper.mapResult(result);
    return switch (presentation.variant) {
      ToolCardPresentationVariant.outcomeCard =>
        ToolOutcomeCard(model: presentation),
      ToolCardPresentationVariant.exceptionCard =>
        ToolExceptionCard(model: presentation),
      ToolCardPresentationVariant.inlineStep ||
      ToolCardPresentationVariant.focusedActiveStep ||
      ToolCardPresentationVariant.confirmationStep ||
      ToolCardPresentationVariant.interactionCard =>
        ToolInlineStepRow(model: presentation),
    };
  }

  Widget _buildToolWorkflowBlockWidget({
    required AssistantTurnBlock block,
    required ChatMessage? sourceMessage,
    required ToolUiRendererRegistry toolUiRegistry,
  }) {
    final steps = _extractWorkflowSteps(block);
    final manualExpandedStepId =
        ref.watch(toolWorkflowExpansionProvider)[block.turnId];
    final expandedStepId = resolveWorkflowExpandedStepId(
      turnId: block.turnId,
      steps: steps,
      manualExpandedStepId: manualExpandedStepId,
    );
    final latestStep = steps.isEmpty ? null : steps.last;
    final workflowDebugKey = 'workflow:${sourceMessage?.id ?? block.id}';
    if (latestStep != null &&
        _emittedAnimationDebugKeys.add(workflowDebugKey)) {
      Logger.temp(
        _animationDebugTag,
        'workflow_widget_built',
        data: {
          'toolName': latestStep.toolName,
          'stepStatus': latestStep.status.name,
          'stepId': latestStep.stepId,
          'sourceMessageId': sourceMessage?.id,
          'expandedStepId': expandedStepId,
          'usesCustomRenderer':
              toolUiRegistry.findWorkflowRenderer(latestStep.toolName) != null,
        },
      );
    }
    final customWorkflowWidget = latestStep == null
        ? null
        : toolUiRegistry.findWorkflowRenderer(latestStep.toolName)?.buildWorkflowStep(
              context,
              steps: steps,
              sourceMessage: sourceMessage,
              isExpanded: latestStep.stepId == expandedStepId,
              onTap: () {
                ref.read(toolWorkflowExpansionProvider.notifier).toggleExpandedStep(
                      turnId: block.turnId,
                      stepId: latestStep.stepId,
                    );
              },
            );
    if (customWorkflowWidget != null) {
      return customWorkflowWidget;
    }
    return ToolWorkflowCard(
      title: block.title ?? 'Tool Workflow',
      steps: steps,
      expandedStepId: expandedStepId,
      onStepTapped: (stepId) {
        ref.read(toolWorkflowExpansionProvider.notifier).toggleExpandedStep(
              turnId: block.turnId,
              stepId: stepId,
            );
      },
    );
  }

  _DelayedWorkflowPreview? _resolveDelayedWorkflowPreview({
    required AssistantTurnBlock resultBlock,
    required ToolResult result,
    required List<ChatMessage> sourceMessages,
    required ToolUiRendererRegistry toolUiRegistry,
  }) {
    final resultMessage = _resolveSourceMessage(sourceMessages, resultBlock);
    if (resultMessage == null) {
      Logger.temp(
        _animationDebugTag,
        'delayed_preview_skipped',
        data: {
          'toolName': result.toolName,
          'reason': 'missing_result_message',
          'blockId': resultBlock.id,
        },
      );
      return null;
    }

    final runningMessage = _findLatestRunningInvocationMessage(
      sourceMessages: sourceMessages,
      resultMessage: resultMessage,
      toolName: result.toolName,
    );
    if (runningMessage == null) {
      Logger.temp(
        _animationDebugTag,
        'delayed_preview_skipped',
        data: {
          'toolName': result.toolName,
          'reason': 'missing_running_message',
          'resultMessageId': resultMessage.id,
        },
      );
      return null;
    }

    final visibleUntil =
        runningMessage.timestamp.add(_minRunningVisibleDuration);
    if (!visibleUntil.isAfter(resultMessage.timestamp)) {
      Logger.temp(
        _animationDebugTag,
        'delayed_preview_skipped',
        data: {
          'toolName': result.toolName,
          'reason': 'duration_already_elapsed',
          'runningMessageId': runningMessage.id,
          'resultMessageId': resultMessage.id,
          'visibleUntil': visibleUntil.toIso8601String(),
          'resultAt': resultMessage.timestamp.toIso8601String(),
        },
      );
      return null;
    }

    final runningWorkflowBlock = _buildRunningWorkflowPreviewBlock(
      sourceMessages: sourceMessages,
      runningMessage: runningMessage,
      turnId: resultBlock.turnId,
    );
    if (runningWorkflowBlock == null) {
      Logger.temp(
        _animationDebugTag,
        'delayed_preview_skipped',
        data: {
          'toolName': result.toolName,
          'reason': 'missing_running_workflow_block',
          'runningMessageId': runningMessage.id,
          'resultMessageId': resultMessage.id,
        },
      );
      return null;
    }

    Logger.temp(
      _animationDebugTag,
      'delayed_preview_active',
      data: {
        'toolName': result.toolName,
        'runningMessageId': runningMessage.id,
        'resultMessageId': resultMessage.id,
        'runningAt': runningMessage.timestamp.toIso8601String(),
        'resultAt': resultMessage.timestamp.toIso8601String(),
        'visibleUntil': visibleUntil.toIso8601String(),
      },
    );

    return _DelayedWorkflowPreview(
      visibleUntil: visibleUntil,
      workflowWidget: _buildToolWorkflowBlockWidget(
        block: runningWorkflowBlock,
        sourceMessage: runningMessage,
        toolUiRegistry: toolUiRegistry,
      ),
    );
  }

  ChatMessage? _findLatestRunningInvocationMessage({
    required List<ChatMessage> sourceMessages,
    required ChatMessage resultMessage,
    required String toolName,
  }) {
    final normalizedToolName = toolName.trim();
    for (var index = sourceMessages.length - 1; index >= 0; index -= 1) {
      final message = sourceMessages[index];
      if (message.timestamp.isAfter(resultMessage.timestamp)) {
        continue;
      }
      if (message.contentType != MessageContentType.toolInvocation) {
        continue;
      }
      final payload = message.payloadJson;
      if ((payload?['toolName'] ?? '').toString().trim() != normalizedToolName) {
        continue;
      }
      if ((payload?['status'] ?? '').toString().trim() !=
          ToolWorkflowStepStatus.running.name) {
        continue;
      }
      return message;
    }
    return null;
  }

  AssistantTurnBlock? _buildRunningWorkflowPreviewBlock({
    required List<ChatMessage> sourceMessages,
    required ChatMessage runningMessage,
    required String turnId,
  }) {
    final prefixMessages = sourceMessages
        .where((message) => !message.timestamp.isAfter(runningMessage.timestamp))
        .toList(growable: false);
    if (prefixMessages.isEmpty) {
      return null;
    }

    final currentGroup = ref.read(currentGroupProvider);
    final previewBlocks = _blockBuilder.buildAssistantBlocks(
      messages: prefixMessages,
      groupId: currentGroup?.id,
    );
    for (var index = previewBlocks.length - 1; index >= 0; index -= 1) {
      final block = previewBlocks[index];
      if (block.turnId == turnId &&
          block.type == AssistantTurnBlockType.toolWorkflow) {
        return block;
      }
    }
    return null;
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

class _DelayedWorkflowPreview {
  const _DelayedWorkflowPreview({
    required this.visibleUntil,
    required this.workflowWidget,
  });

  final DateTime visibleUntil;
  final Widget workflowWidget;
}

class _MinimumVisibleToolStateSwitcher extends StatefulWidget {
  const _MinimumVisibleToolStateSwitcher({
    super.key,
    required this.visibleUntil,
    required this.runningChild,
    required this.resultChild,
  });

  final DateTime visibleUntil;
  final Widget runningChild;
  final Widget resultChild;

  @override
  State<_MinimumVisibleToolStateSwitcher> createState() =>
      _MinimumVisibleToolStateSwitcherState();
}

class _MinimumVisibleToolStateSwitcherState
    extends State<_MinimumVisibleToolStateSwitcher> {
  static const String _animationDebugTag = 'ToolAnimationDebug';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scheduleReveal();
  }

  @override
  void didUpdateWidget(covariant _MinimumVisibleToolStateSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visibleUntil != widget.visibleUntil) {
      _scheduleReveal();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _scheduleReveal() {
    _timer?.cancel();
    final remaining = widget.visibleUntil.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      Logger.temp(
        _animationDebugTag,
        'switcher_reveal_immediate',
        data: {
          'visibleUntil': widget.visibleUntil.toIso8601String(),
        },
      );
      return;
    }
    Logger.temp(
      _animationDebugTag,
      'switcher_schedule_reveal',
      data: {
        'remainingMs': remaining.inMilliseconds,
        'visibleUntil': widget.visibleUntil.toIso8601String(),
      },
    );
    _timer = Timer(remaining, () {
      if (mounted) {
        Logger.temp(
          _animationDebugTag,
          'switcher_reveal_result',
          data: {
            'visibleUntil': widget.visibleUntil.toIso8601String(),
          },
        );
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.visibleUntil.isAfter(DateTime.now())) {
      return widget.runningChild;
    }
    return widget.resultChild;
  }
}
