import 'dart:async';

import 'package:ai_chat/models/chat/assistant_turn_block.dart';
import 'package:ai_chat/models/chat/tool_presentation_event.dart';
import 'package:ai_chat/models/chat/tool_card_presentation_variant.dart';
import 'package:ai_chat/models/chat/tool_workflow_step.dart';
import 'package:ai_chat/models/chat_message.dart';
import 'package:ai_chat/models/response/message_content_type.dart';
import 'package:ai_chat/models/tool/tool_result.dart';
import 'package:ai_chat/providers/chat_providers.dart';
import 'package:ai_chat/services/chat_block_builder.dart';
import 'package:ai_chat/services/tool_presentation_block_projector.dart';
import 'package:ai_chat/services/tool_card_presentation_mapper.dart';
import 'package:ai_chat/theme/app_motion.dart';
import 'package:ai_chat/widgets/animations/message_growth_animation.dart';
import 'package:ai_chat/widgets/chat_blocks/assistant_doc_block.dart';
import 'package:ai_chat/widgets/chat_blocks/artifact_block.dart';
import 'package:ai_chat/widgets/chat_blocks/final_response_block.dart';
import 'package:ai_chat/widgets/chat_blocks/streaming_response_block.dart';
import 'package:ai_chat/widgets/chat_blocks/structured_output_block.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_exception_card.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_inline_step_row.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_outcome_card.dart';
import 'package:ai_chat/widgets/chat_blocks/tool_workflow_card.dart';
import 'package:ai_chat/widgets/chat_blocks/unified_turn_status_bar.dart';
import 'package:ai_chat/widgets/chat_blocks/user_anchor_bubble.dart';
import 'package:ai_chat/widgets/interaction/ask_user_question_card.dart';
import 'package:ai_chat/widgets/interaction/ask_user_question_result_card.dart';
import 'package:ai_chat/widgets/interaction/ask_user_question_timeline_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'chat_timeline_item.dart';

/// Renders a single stable timeline row.
class ChatTimelineRow extends ConsumerWidget {
  static const Duration _minRunningVisibleDuration = Duration(seconds: 5);
  static const ToolPresentationBlockProjector _previewToolBlockProjector =
      ToolPresentationBlockProjector();

  final ChatTimelineItem item;
  final ChatBlockBuilder blockBuilder;
  final int? currentGroupId;
  final ValueChanged<ChatMessage> onLongPressMessage;
  final bool shouldAnimate;
  final VoidCallback? onActiveStatusLayoutChanged;

  const ChatTimelineRow({
    super.key,
    required this.item,
    required this.blockBuilder,
    required this.currentGroupId,
    required this.onLongPressMessage,
    this.shouldAnimate = false,
    this.onActiveStatusLayoutChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final row = switch (item.type) {
      ChatTimelineItemType.userBubble => _buildUserBubble(),
      ChatTimelineItemType.assistantBlock => _buildAssistantBlock(
          context,
          ref,
        ),
    };

    // Only animate if explicitly requested (for new messages)
    final displayRow = shouldAnimate
        ? MessageGrowthAnimation(
            duration: Theme.of(context).extension<AppMotion>()!.standard,
            curve: Theme.of(context).extension<AppMotion>()!.easeOut,
            child: row,
          )
        : row;

    final rowWithStatus = item.activeStatus == null
        ? displayRow
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              displayRow,
              KeyedSubtree(
                key: item.statusAnchorKey,
                child: IgnorePointer(
                  ignoring: item.hideInlineStatus,
                  child: Opacity(
                    opacity: item.hideInlineStatus ? 0 : 1,
                    alwaysIncludeSemantics: !item.hideInlineStatus,
                    child: UnifiedTurnStatusBar(status: item.activeStatus!),
                  ),
                ),
              ),
            ],
          );

    if (item.activeStatus == null) {
      return rowWithStatus;
    }

    return SizeChangedLayoutNotifier(child: rowWithStatus);
  }

  Widget _buildUserBubble() {
    final message = item.userMessage!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: GestureDetector(
        onLongPress: () => onLongPressMessage(message),
        child: UserAnchorBubble(text: message.text),
      ),
    );
  }

  Widget _buildAssistantBlock(BuildContext context, WidgetRef ref) {
    final block = item.block!;
    final sourceMessage = item.sourceMessage;
    final activeAskUserQuestion =
        ref.watch(activeAskUserQuestionMessageProvider);
    final toolUiRegistry = ref.watch(toolUiRendererRegistryProvider);
    final motion = Theme.of(context).extension<AppMotion>()!;

    late final Widget blockWidget;
    switch (block.type) {
      case AssistantTurnBlockType.analysis:
        blockWidget = GestureDetector(
          onLongPress: sourceMessage == null
              ? null
              : () => onLongPressMessage(sourceMessage),
          child: AssistantDocBlock(
            label: 'Analysis',
            text: block.text ?? '',
            reasoningText: block.reasoningText,
            markdownCacheKey: item.stableKey,
          ),
        );
        break;
      case AssistantTurnBlockType.finalResponse:
        blockWidget = GestureDetector(
          onLongPress: sourceMessage == null
              ? null
              : () => onLongPressMessage(sourceMessage),
          child: sourceMessage?.status == MessageStatus.generating
              ? StreamingResponseBlock(
                  text: block.text ?? '',
                  reasoningText: block.reasoningText,
                )
              : FinalResponseBlock(
                  title: block.title ?? '最终回答',
                  text: block.text ?? '',
                  reasoningText: block.reasoningText,
                  markdownCacheKey: item.stableKey,
                  onReasoningExpansionChanged: (_) =>
                      onActiveStatusLayoutChanged?.call(),
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
              : () => onLongPressMessage(sourceMessage),
          child: StructuredOutputBlock(
            title: block.title ?? 'Structured Output',
            fields: _extractStructuredFields(block),
          ),
        );
        break;
      case AssistantTurnBlockType.toolResultSummary:
        final result = block.toolResult ??
            (block.payload == null
                ? null
                : ToolResult.fromJson(block.payload!));
        if (result == null) {
          blockWidget = AssistantDocBlock(
            text: block.text ?? '',
            reasoningText: block.reasoningText,
            markdownCacheKey: item.stableKey,
          );
          break;
        }
        final resultWidget = _buildToolResultBlockWidget(
          context: context,
          result: result,
          sourceMessage: sourceMessage,
          toolUiRegistry: toolUiRegistry,
        );
        final delayedWorkflow = _resolveDelayedWorkflowPreview(
          ref: ref,
          context: context,
          resultBlock: block,
          result: result,
          toolUiRegistry: toolUiRegistry,
        );
        if (delayedWorkflow == null) {
          blockWidget = resultWidget;
          break;
        }
        blockWidget = _MinimumVisibleToolStateSwitcher(
          key: ValueKey(
            '${block.id}_${delayedWorkflow.visibleUntil.millisecondsSinceEpoch}',
          ),
          visibleUntil: delayedWorkflow.visibleUntil,
          runningChild: delayedWorkflow.workflowWidget,
          resultChild: resultWidget,
        );
        break;
      case AssistantTurnBlockType.toolWorkflow:
        blockWidget = _buildToolWorkflowBlockWidget(
          context: context,
          ref: ref,
          block: block,
          sourceMessage: sourceMessage,
          toolUiRegistry: toolUiRegistry,
        );
        break;
      case AssistantTurnBlockType.artifact:
        blockWidget = GestureDetector(
          key: ValueKey('gesture_${block.artifactProjection?.artifactId}'),
          onLongPress: sourceMessage == null
              ? null
              : () => onLongPressMessage(sourceMessage),
          child: ArtifactBlock(
            key: ValueKey(block.artifactProjection?.artifactId),
            projection: block.artifactProjection,
          ),
        );
        break;
    }

    final shouldUseBlockTransition =
        block.type == AssistantTurnBlockType.toolResultSummary ||
        block.type == AssistantTurnBlockType.toolWorkflow;
    if (!shouldUseBlockTransition) {
      return blockWidget;
    }

    return AnimatedSwitcher(
      duration: motion.quick,
      switchInCurve: motion.easeOut,
      switchOutCurve: motion.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: KeyedSubtree(
        key: ValueKey('${block.type.name}_${block.id}_${block.text ?? ''}'),
        child: blockWidget,
      ),
    );
  }

  Widget _buildToolResultBlockWidget({
    required BuildContext context,
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
    required BuildContext context,
    required WidgetRef ref,
    required AssistantTurnBlock block,
    required ChatMessage? sourceMessage,
    required ToolUiRendererRegistry toolUiRegistry,
  }) {
    final steps = _extractWorkflowSteps(block);
    if (steps.isNotEmpty && steps.every((step) => step.toolName == 'ask_user_question')) {
      return const SizedBox.shrink();
    }
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
              onActiveStatusLayoutChanged?.call();
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
        onActiveStatusLayoutChanged?.call();
      },
    );
  }

  _DelayedWorkflowPreview? _resolveDelayedWorkflowPreview({
    required WidgetRef ref,
    required BuildContext context,
    required AssistantTurnBlock resultBlock,
    required ToolResult result,
    required ToolUiRendererRegistry toolUiRegistry,
  }) {
    if (result.toolName.trim() == 'create_artifact__guideline') {
      return null;
    }
    final resultMessage = item.sourceMessage;
    if (resultMessage == null) {
      return null;
    }

    final runningMessage = _findLatestRunningInvocationMessage(
      sourceMessages: item.sourceMessages,
      resultMessage: resultMessage,
      toolName: result.toolName,
    );
    if (runningMessage == null) {
      return null;
    }

    final visibleUntil =
        runningMessage.timestamp.add(_minRunningVisibleDuration);
    if (!visibleUntil.isAfter(resultMessage.timestamp)) {
      return null;
    }

    final runningWorkflowBlock = _buildRunningWorkflowPreviewBlock(
      ref: ref,
      sourceMessages: item.sourceMessages,
      runningMessage: runningMessage,
      turnId: resultBlock.turnId,
    );
    if (runningWorkflowBlock == null) {
      return null;
    }

    return _DelayedWorkflowPreview(
      visibleUntil: visibleUntil,
      workflowWidget: _buildToolWorkflowBlockWidget(
        context: context,
        ref: ref,
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
      if ((payload?['toolName'] ?? '').toString().trim() !=
          normalizedToolName) {
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
    required WidgetRef ref,
    required List<ChatMessage> sourceMessages,
    required ChatMessage runningMessage,
    required String turnId,
  }) {
    final prefixMessages = sourceMessages
        .where(
            (message) => !message.timestamp.isAfter(runningMessage.timestamp))
        .toList(growable: false);
    if (prefixMessages.isEmpty) {
      return null;
    }

    final previewEvents = prefixMessages
        .where((message) => message.contentType == MessageContentType.toolInvocation)
        .map((message) {
          final payload = message.payloadJson ?? const <String, dynamic>{};
          final stepId = payload['stepId'];
          final providerCallId = (payload['providerCallId'] ?? '')
              .toString()
              .trim();
          return ToolPresentationEvent(
            toolName: (payload['toolName'] ?? '').toString(),
            phase: ToolPresentationEventPhase.running,
            turnId: turnId,
            stepId: stepId == null ? null : '$turnId-step-$stepId',
            providerCallId:
                providerCallId.isEmpty ? null : providerCallId,
            sourceContentType: MessageContentType.toolInvocation,
            sourceMessageId: message.id,
            timestamp: message.timestamp,
            data: {
              ...payload,
              'arguments': payload['arguments'] is Map
                  ? Map<String, dynamic>.from(payload['arguments'] as Map)
                  : const <String, dynamic>{},
              'summary': payload['summary'] ?? message.text,
              'requiresConfirmation':
                  payload['requiresConfirmation'] == true,
            },
          );
        })
        .toList(growable: false);
    final previewBlocks = _previewToolBlockProjector.project(
      events: previewEvents,
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

  Map<String, String> _extractStructuredFields(AssistantTurnBlock block) {
    final payload = block.payload;
    if (payload == null) {
      return {
        '内容': block.text ?? '',
      };
    }

    return payload.map((key, value) => MapEntry(key, '$value'));
  }

  List<ToolWorkflowStep> _extractWorkflowSteps(AssistantTurnBlock block) {
    final typedSteps = block.workflowSteps;
    if (typedSteps != null) {
      return typedSteps;
    }

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
      return;
    }
    _timer = Timer(remaining, () {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.visibleUntil.isAfter(DateTime.now())) {
      return AnimatedSwitcher(
        duration: Theme.of(context).extension<AppMotion>()!.quick,
        switchInCurve: Theme.of(context).extension<AppMotion>()!.easeOut,
        switchOutCurve: Theme.of(context).extension<AppMotion>()!.easeIn,
        transitionBuilder: (child, animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: KeyedSubtree(
          key: const ValueKey('tool-running-child'),
          child: widget.runningChild,
        ),
      );
    }
    return AnimatedSwitcher(
      duration: Theme.of(context).extension<AppMotion>()!.quick,
      switchInCurve: Theme.of(context).extension<AppMotion>()!.easeOut,
      switchOutCurve: Theme.of(context).extension<AppMotion>()!.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: KeyedSubtree(
        key: const ValueKey('tool-result-child'),
        child: widget.resultChild,
      ),
    );
  }
}
