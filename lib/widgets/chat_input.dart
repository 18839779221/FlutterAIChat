import 'package:ai_chat/theme/app_colors.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/chat_providers.dart';

class ChatInput extends ConsumerWidget {
  const ChatInput({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final useReasoning = ref.watch(useReasoningProvider);
    final useConciseMode = ref.watch(useConciseModeProvider);
    final sendPhase = ref.watch(sendPhaseProvider);
    final textController = ref.watch(textControllerProvider);
    final focusNode = ref.watch(focusNodeProvider);
    final chatController = ref.read(chatControllerProvider);
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final colors = Theme.of(context).extension<AppColors>()!;

    final bottomSafeArea = MediaQuery.of(context).padding.bottom;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isStreamingResponse = sendPhase == ChatSendPhase.streamingResponse;
    final isAwaitingConfirmation =
        sendPhase == ChatSendPhase.awaitingConfirmation;
    final isBlockingPhase = sendPhase == ChatSendPhase.preparing ||
        sendPhase == ChatSendPhase.executingTool ||
        sendPhase == ChatSendPhase.streamingResponse;
    final isComposerLocked = sendPhase != ChatSendPhase.idle;
    final composerValue =
        textController.text.trim().isEmpty ? '空白' : textController.text;
    final sendButtonLabel = isStreamingResponse
        ? '停止生成'
        : isAwaitingConfirmation
            ? '等待工具确认'
            : '发送消息';
    final isSendButtonEnabled =
        isStreamingResponse || (!isBlockingPhase && !isAwaitingConfirmation);
    final helperText = _buildHelperText(
      useReasoning: useReasoning,
      useConciseMode: useConciseMode,
      sendPhase: sendPhase,
    );

    void submitCurrentInput() {
      if (isComposerLocked) {
        return;
      }

      final pendingText = textController.text;
      if (pendingText.trim().isEmpty) {
        return;
      }

      textController.clear();
      chatController.sendMessage(pendingText);
    }

    return Semantics(
      container: true,
      label: '聊天输入区域',
      child: Container(
        padding: EdgeInsets.fromLTRB(
          spacing.sm,
          spacing.xs,
          spacing.sm,
          keyboardHeight > 0 ? spacing.xs : spacing.xs + bottomSafeArea,
        ),
        decoration: BoxDecoration(
          color: colors.chatBackground.withValues(alpha: 0.96),
          border: Border(top: BorderSide(color: colors.divider)),
        ),
        child: Container(
          padding: EdgeInsets.all(spacing.sm),
          decoration: BoxDecoration(
            color: colors.assistantSurface,
            borderRadius: BorderRadius.circular(radius.lg),
            border: Border.all(color: colors.divider),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Semantics(
                      container: true,
                      textField: true,
                      enabled: !isComposerLocked,
                      focused: focusNode.hasFocus,
                      label: '聊天输入框',
                      hint: '输入消息',
                      value: composerValue,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 96),
                        child: TextField(
                          focusNode: focusNode,
                          controller: textController,
                          enabled: !isComposerLocked,
                          maxLines: null,
                          minLines: 1,
                          textInputAction: TextInputAction.newline,
                          keyboardType: TextInputType.multiline,
                          style: TextStyle(
                            color: colors.primaryText,
                            fontSize: 13,
                            height: 1.4,
                          ),
                          decoration: InputDecoration(
                            hintText: '继续提问，或让助手继续下一步工具...',
                            hintStyle: TextStyle(
                              color: colors.secondaryText,
                              fontSize: 12,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onSubmitted: (_) => submitCurrentInput(),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: spacing.xs),
                  Semantics(
                    container: true,
                    button: true,
                    enabled: isSendButtonEnabled,
                    label: sendButtonLabel,
                    child: SizedBox(
                      height: 36,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.symmetric(horizontal: spacing.md),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(radius.md),
                          ),
                          backgroundColor: isAwaitingConfirmation
                              ? colors.secondaryText
                              : colors.workflowRunning,
                        ),
                        onPressed: () {
                          if (isStreamingResponse) {
                            chatController.cancelStreamSubscription();
                            return;
                          }

                          if (isBlockingPhase || isAwaitingConfirmation) {
                            return;
                          }

                          submitCurrentInput();
                        },
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: isBlockingPhase
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Text(
                                  isAwaitingConfirmation ? '等待' : '发送',
                                  style: const TextStyle(fontSize: 12),
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: spacing.xs),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      helperText,
                      style: TextStyle(
                        color: colors.secondaryText,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _ModeChip(
                    label: '深度',
                    selected: useReasoning,
                    onTap: () => chatController.setUseReasoning(!useReasoning),
                  ),
                  SizedBox(width: spacing.xxs),
                  _ModeChip(
                    label: '简洁',
                    selected: useConciseMode,
                    onTap: () =>
                        chatController.setUseConciseMode(!useConciseMode),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildHelperText({
    required bool useReasoning,
    required bool useConciseMode,
    required ChatSendPhase sendPhase,
  }) {
    if (sendPhase == ChatSendPhase.awaitingConfirmation) {
      return '等待工具确认';
    }

    if (sendPhase == ChatSendPhase.executingTool) {
      return '工具执行中';
    }

    final segments = <String>['Balanced', '可追溯输出'];
    if (useReasoning) {
      segments.add('深度');
    }
    if (useConciseMode) {
      segments.add('简洁');
    }
    return segments.join(' · ');
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return InkWell(
      borderRadius: BorderRadius.circular(radius.pill),
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.xs,
          vertical: spacing.xxs,
        ),
        decoration: BoxDecoration(
          color: selected
              ? colors.workflowRunning.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(radius.pill),
          border: Border.all(
            color: selected ? colors.workflowRunning : colors.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? colors.workflowRunning : colors.secondaryText,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
