import 'package:ai_chat/theme/app_colors.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/chat_providers.dart';

class ChatInput extends ConsumerWidget {
  const ChatInput({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      label: '聊天输入停靠区',
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          spacing.md - 2,
          spacing.xxs,
          spacing.md - 2,
          keyboardHeight > 0 ? spacing.xxs : spacing.xs + bottomSafeArea,
        ),
        child: DecoratedBox(
          key: const ValueKey('chat-input-dock'),
          decoration: BoxDecoration(
            color: colors.assistantSurface.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(radius.lg + 8),
            boxShadow: [
              BoxShadow(
                color: colors.primaryText.withValues(alpha: 0.065),
                blurRadius: 20,
                offset: const Offset(0, 9),
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.42),
                blurRadius: 1,
                offset: const Offset(0, -1),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              spacing.sm,
              spacing.xxs + 3,
              spacing.xs,
              spacing.xxs + 3,
            ),
            child: Semantics(
              container: true,
              label: '聊天输入主面板',
              child: Column(
                key: const ValueKey('chat-input-panel'),
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
                            constraints: const BoxConstraints(minHeight: 36),
                            child: TextField(
                              key: const ValueKey('chat-input-field'),
                              focusNode: focusNode,
                              controller: textController,
                              enabled: !isComposerLocked,
                              minLines: 1,
                              maxLines: 4,
                              textInputAction: TextInputAction.newline,
                              keyboardType: TextInputType.multiline,
                              style: AppTypography.uiStyle(
                                color: colors.primaryText,
                                fontSize: 13.7,
                                height: 1.34,
                              ),
                              decoration: InputDecoration(
                                hintText: '继续追问，或补充你的要求',
                                hintStyle: AppTypography.uiStyle(
                                  color: colors.secondaryText.withValues(
                                    alpha: 0.66,
                                  ),
                                  fontSize: 13.3,
                                  height: 1.28,
                                ),
                                isDense: true,
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                                errorBorder: InputBorder.none,
                                focusedErrorBorder: InputBorder.none,
                                contentPadding: EdgeInsets.fromLTRB(
                                  spacing.xs,
                                  spacing.xxs + 2,
                                  spacing.xs,
                                  spacing.xxs + 2,
                                ),
                              ),
                              onSubmitted: (_) => submitCurrentInput(),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: spacing.xxs + 2),
                      Semantics(
                        container: true,
                        button: true,
                        enabled: isSendButtonEnabled,
                        label: sendButtonLabel,
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              padding: EdgeInsets.zero,
                              shape: const CircleBorder(),
                              backgroundColor: isAwaitingConfirmation
                                  ? colors.secondaryText.withValues(alpha: 0.82)
                                  : colors.workflowRunning
                                      .withValues(alpha: 0.88),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shadowColor: Colors.transparent,
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
                              child: isStreamingResponse
                                  ? const Icon(
                                      Icons.stop_rounded,
                                      key: ValueKey('chat-input-stop-icon'),
                                      size: 18,
                                    )
                                  : isBlockingPhase
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          Colors.white,
                                        ),
                                      ),
                                    )
                                  : Icon(
                                      isStreamingResponse
                                          ? Icons.stop_rounded
                                          : Icons.arrow_upward_rounded,
                                      key: ValueKey(sendButtonLabel),
                                      size: 18,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
