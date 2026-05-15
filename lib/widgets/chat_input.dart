import 'package:ai_chat/theme/app_colors.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/skill/skill_catalog_entry.dart';
import '../providers/chat_providers.dart';
import 'context_window/context_window_usage_indicator.dart';

class ChatInput extends ConsumerStatefulWidget {
  const ChatInput({
    super.key,
    this.onContextWindowPressed,
  });

  final VoidCallback? onContextWindowPressed;

  @override
  ConsumerState<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends ConsumerState<ChatInput> {
  TextEditingController? _listenedController;
  ChangeNotifier? _listenedVoiceController;

  @override
  void initState() {
    super.initState();
    _listenedController = ref.read(textControllerProvider);
    _listenedController?.addListener(_handleTextChanged);
    _listenedVoiceController = ref.read(voiceInputControllerProvider);
    _listenedVoiceController?.addListener(_handleVoiceStateChanged);
  }

  @override
  void dispose() {
    _listenedController?.removeListener(_handleTextChanged);
    _listenedVoiceController?.removeListener(_handleVoiceStateChanged);
    super.dispose();
  }

  void _handleTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleVoiceStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final sendPhase = ref.watch(sendPhaseProvider);
    final textController = ref.watch(textControllerProvider);
    final focusNode = ref.watch(focusNodeProvider);
    final chatController = ref.read(chatControllerProvider);
    final voiceInputController = ref.watch(voiceInputControllerProvider);
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final colors = Theme.of(context).extension<AppColors>()!;
    final contextWindowSnapshot = ref.watch(contextWindowSnapshotProvider);
    final skillCatalog = ref.watch(enabledSkillCatalogProvider);
    final voiceState = voiceInputController?.state;
    final hasVoiceInput = voiceInputController != null;
    final isVoiceListening = voiceState?.isListening ?? false;

    final bottomSafeArea = MediaQuery.of(context).padding.bottom;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isStreamingResponse = sendPhase == ChatSendPhase.streamingResponse;
    final isAwaitingConfirmation =
        sendPhase == ChatSendPhase.awaitingConfirmation;
    final isCancellablePhase = sendPhase == ChatSendPhase.preparing ||
        sendPhase == ChatSendPhase.executingTool ||
        sendPhase == ChatSendPhase.streamingResponse;
    final isBlockingPhase = isCancellablePhase;
    final isComposerLocked = sendPhase != ChatSendPhase.idle;
    final composerValue =
        textController.text.trim().isEmpty ? '空白' : textController.text;
    final sendButtonLabel = isCancellablePhase
        ? '停止生成'
        : isAwaitingConfirmation
            ? '等待工具确认'
            : '发送消息';
    final isSendButtonEnabled =
        isCancellablePhase || (!isBlockingPhase && !isAwaitingConfirmation);
    final slashQuery = _extractSlashQuery(textController.text);
    final slashSuggestions = skillCatalog.maybeWhen<List<SkillCatalogEntry>>(
      data: (skills) {
        if (slashQuery == null) {
          return const <SkillCatalogEntry>[];
        }
        return skills.where((skill) {
          final query = slashQuery.toLowerCase();
          return skill.id.toLowerCase().contains(query) ||
              skill.name.toLowerCase().contains(query) ||
              skill.description.toLowerCase().contains(query);
        }).take(5).toList(growable: false);
      },
      orElse: () => const <SkillCatalogEntry>[],
    );
    if (!identical(_listenedVoiceController, voiceInputController)) {
      _listenedVoiceController?.removeListener(_handleVoiceStateChanged);
      _listenedVoiceController = voiceInputController;
      _listenedVoiceController?.addListener(_handleVoiceStateChanged);
    }
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

    final composerBorderColor = isVoiceListening
        ? colors.workflowRunning.withValues(alpha: 0.44)
        : colors.divider;
    final composerBackgroundColor = isVoiceListening
        ? colors.workflowRunning.withValues(alpha: 0.08)
        : Colors.transparent;

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
                  Semantics(
                    container: true,
                    textField: true,
                    enabled: !isComposerLocked,
                    focused: focusNode.hasFocus,
                    label: '聊天输入框',
                    hint: '输入消息',
                    value: composerValue,
                    child: Container(
                      key: const ValueKey('chat-input-composer-shell'),
                      decoration: BoxDecoration(
                        color: composerBackgroundColor,
                        borderRadius: BorderRadius.circular(radius.md),
                        border: Border.all(color: composerBorderColor),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isVoiceListening)
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                spacing.xs,
                                spacing.xxs + 2,
                                spacing.xs,
                                0,
                              ),
                              child: Row(
                                key: const ValueKey('chat-input-voice-status'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    key: const ValueKey(
                                      'chat-input-voice-status-dot',
                                    ),
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: colors.workflowRunning,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  SizedBox(width: spacing.xxs + 2),
                                  Text(
                                    '正在聆听',
                                    style: AppTypography.uiStyle(
                                      color: colors.workflowRunning,
                                      fontSize: 11.8,
                                      height: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ConstrainedBox(
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
                        ],
                      ),
                    ),
                  ),
                  if (slashSuggestions.isNotEmpty) ...[
                    SizedBox(height: spacing.xxs + 2),
                    _SlashSkillSuggestions(
                      suggestions: slashSuggestions,
                      onSelected: (skill) {
                        final selection = '/${skill.id} ';
                        textController.value = TextEditingValue(
                          text: selection,
                          selection: TextSelection.collapsed(
                            offset: selection.length,
                          ),
                        );
                      },
                    ),
                  ],
                  SizedBox(height: spacing.xxs + 2),
                  Semantics(
                    container: true,
                    label: '输入辅助操作栏',
                    child: Row(
                      key: const ValueKey('chat-input-bottom-bar'),
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (hasVoiceInput)
                          Padding(
                            padding: EdgeInsets.only(right: spacing.xxs + 2),
                            child: GestureDetector(
                              key: const ValueKey('chat-input-voice-button'),
                              onLongPressStart: (_) {
                                if (isComposerLocked) {
                                  return;
                                }
                                voiceInputController.pressStart();
                              },
                              onLongPressEnd: (_) {
                                if (isComposerLocked) {
                                  return;
                                }
                                voiceInputController.releaseStop();
                              },
                              child: Container(
                                key: const ValueKey('chat-input-voice-button-shell'),
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isVoiceListening
                                      ? colors.workflowRunning.withValues(alpha: 0.16)
                                      : colors.settingsPanelBackground,
                                  border: Border.all(
                                    color: isVoiceListening
                                        ? colors.workflowRunning.withValues(alpha: 0.48)
                                        : colors.divider,
                                  ),
                                ),
                                child: Icon(
                                  Icons.mic_none_rounded,
                                  size: 18,
                                  color: isVoiceListening
                                      ? colors.workflowRunning
                                      : colors.secondaryText,
                                ),
                              ),
                            ),
                          ),
                        const Spacer(),
                        contextWindowSnapshot.maybeWhen(
                          data: (snapshot) {
                            if (snapshot == null) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: EdgeInsets.only(right: spacing.xxs + 2),
                              child: ContextWindowUsageIndicator(
                                snapshot: snapshot,
                                onTap: widget.onContextWindowPressed ?? () {},
                              ),
                            );
                          },
                          orElse: () => const SizedBox.shrink(),
                        ),
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
                                if (isCancellablePhase) {
                                  chatController.cancelStreamSubscription();
                                  return;
                                }

                                if (isBlockingPhase ||
                                    isAwaitingConfirmation) {
                                  return;
                                }

                                submitCurrentInput();
                              },
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: isCancellablePhase
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
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _extractSlashQuery(String text) {
    final trimmedLeft = text.trimLeft();
    if (!trimmedLeft.startsWith('/')) {
      return null;
    }
    final firstLine = trimmedLeft.split('\n').first;
    final afterSlash = firstLine.substring(1);
    if (afterSlash.contains(' ')) {
      return null;
    }
    return afterSlash;
  }
}

class _SlashSkillSuggestions extends StatelessWidget {
  const _SlashSkillSuggestions({
    required this.suggestions,
    required this.onSelected,
  });

  final List<SkillCatalogEntry> suggestions;
  final ValueChanged<SkillCatalogEntry> onSelected;

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final colors = Theme.of(context).extension<AppColors>()!;

    return Container(
      key: const ValueKey('chat-input-skill-suggestions'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.settingsPanelBackground,
        borderRadius: BorderRadius.circular(radius.md),
        border: Border.all(color: colors.divider),
      ),
      padding: EdgeInsets.symmetric(vertical: spacing.xxs),
      child: Column(
        children: suggestions
            .map(
              (skill) => ListTile(
                dense: true,
                title: Text(skill.id),
                subtitle: Text(
                  skill.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => onSelected(skill),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}
