import 'dart:ui';

import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/skill/skill_catalog_entry.dart';
import '../providers/chat_providers.dart';
import 'chat_input_attachment_strip.dart';
import 'context_window/context_window_usage_indicator.dart';
import '../models/chat/send_message_request.dart';
import '../models/chat/chat_attachment.dart';
import '../models/llm/llm_provider_config.dart';
import '../models/llm/llm_provider_model.dart';
import '../repositories/app_settings_repository.dart';
import '../utils/logger.dart';
import '../pages/model_management_page.dart';

final _chatInputModelSelectionProvider = FutureProvider.family
    .autoDispose<LlmProviderModel?, AppSettingsRepository>((ref, repository) async {
  final providers = await repository.getProviders();
  final selection = await repository.getSelectionState();
  for (final provider in providers) {
    if (provider.id != selection.selectedProviderId &&
        provider.id != selection.defaultProviderId) {
      continue;
    }
    for (final model in provider.models) {
      if (model.id == selection.selectedModelId ||
          model.id == selection.defaultModelId) {
        return model;
      }
    }
  }
  return null;
});

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
    final attachmentPicker = ref.watch(chatAttachmentPickerServiceProvider);
    final attachmentStorage = ref.watch(chatAttachmentStorageServiceProvider);
    final composerAttachments = ref.watch(composerAttachmentsProvider);
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final contextWindowSnapshot = ref.watch(contextWindowSnapshotProvider);
    final skillCatalog = ref.watch(enabledSkillCatalogProvider);
    AppSettingsRepository? settingsRepository;
    try {
      settingsRepository = ref.read(appSettingsRepositoryProvider);
    } on UnimplementedError {
      settingsRepository = null;
    }
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
        return skills
            .where((skill) {
              final query = slashQuery.toLowerCase();
              return skill.id.toLowerCase().contains(query) ||
                  skill.name.toLowerCase().contains(query) ||
                  skill.description.toLowerCase().contains(query);
            })
            .take(5)
            .toList(growable: false);
      },
      orElse: () => const <SkillCatalogEntry>[],
    );
    if (!identical(_listenedVoiceController, voiceInputController)) {
      _listenedVoiceController?.removeListener(_handleVoiceStateChanged);
      _listenedVoiceController = voiceInputController;
      _listenedVoiceController?.addListener(_handleVoiceStateChanged);
    }
    Future<void> submitCurrentInput() async {
      final pendingText = textController.text;
      final pendingAttachments = List<ChatAttachment>.from(composerAttachments);
      Logger.runtime(
        'ChatInput',
        'submitCurrentInput invoked',
        data: {
          'textLength': pendingText.length,
          'trimmedTextLength': pendingText.trim().length,
          'attachmentCount': pendingAttachments.length,
          'attachmentLocalIds': pendingAttachments
              .map((attachment) => attachment.localId)
              .join(','),
          'attachmentStatuses': pendingAttachments
              .map((attachment) => attachment.status.name)
              .join(','),
          'attachmentPaths': pendingAttachments
              .map((attachment) => attachment.localPath ?? '')
              .join(','),
          'attachmentDataUrlLengths': pendingAttachments
              .map(
                (attachment) =>
                    (attachment.providerFileRefJson?['data_url'] as String?)
                        ?.length ??
                    0,
              )
              .join(','),
        },
      );
      if (isComposerLocked) {
        Logger.w(
          'ChatInput',
          'submitCurrentInput ignored because composer is locked',
        );
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      if (pendingText.trim().isEmpty && composerAttachments.isEmpty) {
        Logger.w(
          'ChatInput',
          'submitCurrentInput ignored because text and attachments are both empty',
        );
        return;
      }
      final allowUnsupportedImageInputAttempt =
          await _confirmUnsupportedImageInputIfNeeded(
        context: context,
        attachments: pendingAttachments,
      );
      if (!mounted || allowUnsupportedImageInputAttempt == null) {
        return;
      }

      try {
        if (!mounted) {
          return;
        }
        textController.clear();
        ref.read(composerAttachmentsProvider.notifier).state =
            const <ChatAttachment>[];
        await chatController.sendMessageRequest(
          SendMessageRequest(
            text: pendingText,
            attachments: pendingAttachments,
            allowUnsupportedImageInputAttempt:
                allowUnsupportedImageInputAttempt,
          ),
        );
        Logger.runtime(
          'ChatInput',
          'sendMessageRequest completed, clearing composer',
          data: {
            'textLength': pendingText.length,
            'attachmentCount': pendingAttachments.length,
          },
        );
        if (!mounted) {
          return;
        }
      } catch (error, stackTrace) {
        Logger.e('ChatInput', 'send message request failed', error);
        Logger.e('ChatInput', 'send message request stack trace', stackTrace);
        if (!mounted) {
          return;
        }
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('发送失败：$error'),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    }

    final composerBorderColor = isVoiceListening
        ? colors.workflowRunning.withValues(alpha: 0.44)
        : colors.divider;
    final composerBackgroundColor = isVoiceListening
        ? colors.workflowRunning.withValues(alpha: 0.08)
        : Colors.transparent;

    Future<void> openModelPicker() async {
      final repository = settingsRepository;
      if (repository == null) {
        return;
      }
      final providers = await repository.getProviders();
      final selection = await repository.getSelectionState();
      if (!mounted) {
        return;
      }
      if (providers.isEmpty) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ModelManagementPage(repository: repository),
          ),
        );
        return;
      }

      LlmProviderConfig provider = providers.first;
      for (final item in providers) {
        if (item.id == selection.selectedProviderId ||
            item.id == selection.defaultProviderId) {
          provider = item;
          break;
        }
      }

      Future<LlmProviderConfig?> openProviderPicker({
        required LlmProviderConfig activeProvider,
      }) {
        return showModalBottomSheet<LlmProviderConfig>(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (context) => _ModelProviderPickerSheet(
            title: '切换 Provider',
            subtitle: '模型选择保持在主流程里，只有需要时再切换 Provider。',
            child: Column(
              children: providers
                  .map(
                    (item) => _PickerActionTile(
                      title: item.name,
                      subtitle: item.baseUrl,
                      selected: item.id == activeProvider.id,
                      trailing: '${item.models.length} 个模型',
                      onTap: () => Navigator.of(context).pop(item),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        );
      }

      while (mounted) {
        final models = provider.models;
        if (models.isEmpty) {
          await Navigator.of(context).push(
            MaterialPageRoute(
                  builder: (_) =>
                  ModelManagementPage(repository: repository),
            ),
          );
          return;
        }

        final selectedModel = await showModalBottomSheet<LlmProviderModel>(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (context) => _ModelProviderPickerSheet(
            title: '选择 Model',
            subtitle:
                '${provider.name} · 优先选择模型；如果当前 Provider 不合适，再切换 Provider。',
            child: Column(
              children: [
                ...models.map(
                  (model) => _PickerActionTile(
                    title: model.displayName,
                    selected: model.id == selection.selectedModelId,
                    trailing: model.id == selection.defaultModelId
                        ? '默认'
                        : null,
                    onTap: () => Navigator.of(context).pop(model),
                  ),
                ),
                _PickerActionTile(
                  title: '切换 Provider',
                  subtitle: '当前：${provider.name}',
                  trailingIcon: Icons.chevron_right,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        );

        if (!mounted) {
          return;
        }

        if (selectedModel != null) {
          await repository.selectProviderAndModel(
            providerId: provider.id,
            modelId: selectedModel.id,
          );
          if (mounted) {
            setState(() {});
          }
          return;
        }

        final nextProvider = await openProviderPicker(activeProvider: provider);
        if (nextProvider == null) {
          return;
        }
        provider = nextProvider;
      }
    }

    final modelChipLabel = settingsRepository == null
        ? '未配置模型'
        : ref
            .watch(_chatInputModelSelectionProvider(settingsRepository))
            .maybeWhen(
              data: (value) => value?.displayName ?? '未配置模型',
              orElse: () => '未配置模型',
            );

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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius.lg + 8),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 38, sigmaY: 38),
            child: DecoratedBox(
              key: const ValueKey('chat-input-dock'),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    colors.assistantSurface.withValues(alpha: 0.28),
                    colors.assistantSurface.withValues(alpha: 0.52),
                    colors.assistantSurface.withValues(alpha: 0.7),
                  ],
                  stops: const [0, 0.42, 1],
                ),
                borderRadius: BorderRadius.circular(radius.lg + 8),
                border: Border.all(
                  color: colors.semantic.text.inverse.withValues(alpha: 0.24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: colors.primaryText.withValues(alpha: 0.085),
                    blurRadius: 26,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    // 顶部内白光高亮：在 dock 表面之上轻轻提亮一道边缘，
                    // 走主题 inverse text token 保证未来引入深色主题时自动反相。
                    color: colors.semantic.text.inverse.withValues(alpha: 0.22),
                    blurRadius: 8,
                    offset: const Offset(0, -3),
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
                                    key: const ValueKey(
                                        'chat-input-voice-status'),
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
                                constraints:
                                    const BoxConstraints(minHeight: 36),
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
                                  onSubmitted: (_) {
                                    submitCurrentInput();
                                  },
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
                      if (composerAttachments.isNotEmpty) ...[
                        SizedBox(height: spacing.xxs + 2),
                        ChatInputAttachmentStrip(
                          attachments: composerAttachments,
                          onRemove: (attachment) {
                            final nextAttachments = [...composerAttachments]
                              ..removeWhere(
                                (item) => item.localId == attachment.localId,
                              );
                            ref
                                .read(composerAttachmentsProvider.notifier)
                                .state = nextAttachments;
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
                            if (attachmentPicker != null)
                              Padding(
                                padding:
                                    EdgeInsets.only(right: spacing.xxs + 2),
                                child: IconButton(
                                  key: const ValueKey('chat-input-add-image'),
                                  onPressed: isComposerLocked
                                      ? null
                                      : () async {
                                          try {
                                            final pickedAttachments =
                                                await attachmentPicker
                                                    .pickImages();
                                            Logger.i(
                                              'ChatInput',
                                              'picked image attachments',
                                            );
                                            Logger.runtime(
                                              'ChatInput',
                                              'picker returned attachments',
                                              data: {
                                                'pickedCount':
                                                    pickedAttachments.length,
                                                'pickedLocalIds':
                                                    pickedAttachments
                                                        .map((attachment) =>
                                                            attachment.localId)
                                                        .join(','),
                                                'pickedPaths': pickedAttachments
                                                    .map((attachment) =>
                                                        attachment.localPath ??
                                                        '')
                                                    .join(','),
                                              },
                                            );
                                            if (!context.mounted ||
                                                pickedAttachments.isEmpty) {
                                              return;
                                            }
                                            final preparedAttachments =
                                                attachmentStorage == null
                                                    ? pickedAttachments
                                                    : await Future.wait(
                                                        pickedAttachments.map(
                                                          (attachment) =>
                                                              attachmentStorage
                                                                  .persistSelectedImage(
                                                            attachment:
                                                                attachment,
                                                          ),
                                                        ),
                                                      );
                                            Logger.runtime(
                                              'ChatInput',
                                              'attachments prepared for composer',
                                              data: {
                                                'preparedCount':
                                                    preparedAttachments.length,
                                                'preparedLocalIds':
                                                    preparedAttachments
                                                        .map((attachment) =>
                                                            attachment.localId)
                                                        .join(','),
                                                'preparedPaths':
                                                    preparedAttachments
                                                        .map((attachment) =>
                                                            attachment
                                                                .localPath ??
                                                            '')
                                                        .join(','),
                                                'thumbnailPaths':
                                                    preparedAttachments
                                                        .map((attachment) =>
                                                            attachment
                                                                .thumbnailPath ??
                                                            '')
                                                        .join(','),
                                                'preparedStatuses':
                                                    preparedAttachments
                                                        .map((attachment) =>
                                                            attachment
                                                                .status.name)
                                                        .join(','),
                                                'preparedDataUrlLengths':
                                                    preparedAttachments
                                                        .map(
                                                          (attachment) =>
                                                              (attachment.providerFileRefJson?[
                                                                          'data_url']
                                                                      as String?)
                                                                  ?.length ??
                                                              0,
                                                        )
                                                        .join(','),
                                              },
                                            );
                                            if (!context.mounted ||
                                                preparedAttachments.isEmpty) {
                                              return;
                                            }
                                            final nextComposerAttachments = [
                                              ...composerAttachments,
                                              ...preparedAttachments,
                                            ];
                                            ref
                                                .read(
                                                    composerAttachmentsProvider
                                                        .notifier)
                                                .state = nextComposerAttachments;
                                            Logger.runtime(
                                              'ChatInput',
                                              'composer attachments updated',
                                              data: {
                                                'composerAttachmentCount':
                                                    nextComposerAttachments
                                                        .length,
                                                'composerAttachmentLocalIds':
                                                    nextComposerAttachments
                                                        .map((attachment) =>
                                                            attachment.localId)
                                                        .join(','),
                                              },
                                            );
                                          } catch (error, stackTrace) {
                                            Logger.e(
                                              'ChatInput',
                                              'failed to prepare image attachments',
                                              error,
                                            );
                                            Logger.e(
                                              'ChatInput',
                                              'attachment prepare stack trace',
                                              stackTrace,
                                            );
                                            if (!context.mounted) {
                                              return;
                                            }
                                            ScaffoldMessenger.of(context)
                                              ..hideCurrentSnackBar()
                                              ..showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    '图片准备失败：$error',
                                                  ),
                                                  behavior:
                                                      SnackBarBehavior.floating,
                                                ),
                                              );
                                          }
                                        },
                                  icon: const Icon(
                                      Icons.add_photo_alternate_outlined),
                                ),
                              ),
                            if (hasVoiceInput)
                              Padding(
                                padding:
                                    EdgeInsets.only(right: spacing.xxs + 2),
                                child: GestureDetector(
                                  key:
                                      const ValueKey('chat-input-voice-button'),
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
                                    key: const ValueKey(
                                        'chat-input-voice-button-shell'),
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isVoiceListening
                                          ? colors.workflowRunning
                                              .withValues(alpha: 0.16)
                                          : colors.settingsPanelBackground,
                                      border: Border.all(
                                        color: isVoiceListening
                                            ? colors.workflowRunning
                                                .withValues(alpha: 0.48)
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
                            Padding(
                              padding: EdgeInsets.only(right: spacing.xxs + 2),
                              child: OutlinedButton(
                                key: const ValueKey('chat-input-model-chip'),
                                onPressed: settingsRepository == null
                                    ? null
                                    : openModelPicker,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 36),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: spacing.sm + 2,
                                    vertical: spacing.xxs + 2,
                                  ),
                                  backgroundColor:
                                      colors.chatBackground.withValues(alpha: 0.46),
                                  side: BorderSide(
                                    color: colors.semantic.text.inverse
                                        .withValues(alpha: 0.2),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(radius.pill),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.auto_awesome_outlined,
                                      size: 15,
                                      color: colors.secondaryText,
                                    ),
                                    SizedBox(width: spacing.xxs + 2),
                                    Flexible(
                                      child: Text(
                                        modelChipLabel,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
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
                                  padding:
                                      EdgeInsets.only(right: spacing.xxs + 2),
                                  child: ContextWindowUsageIndicator(
                                    snapshot: snapshot,
                                    onTap:
                                        widget.onContextWindowPressed ?? () {},
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
                                        ? colors.secondaryText
                                            .withValues(alpha: 0.82)
                                        : colors.workflowRunning
                                            .withValues(alpha: 0.88),
                                    foregroundColor:
                                        colors.semantic.text.inverse,
                                    elevation: 0,
                                    shadowColor: Colors.transparent,
                                  ),
                                  onPressed: () {
                                    Logger.i(
                                      'ChatInput',
                                      'send button pressed',
                                    );
                                    if (isCancellablePhase) {
                                      Logger.i('ChatInput',
                                          'send button mapped to cancel active stream');
                                      chatController.cancelStreamSubscription();
                                      return;
                                    }

                                    if (isBlockingPhase ||
                                        isAwaitingConfirmation) {
                                      Logger.w(
                                        'ChatInput',
                                        'send button ignored because send is blocked',
                                      );
                                      return;
                                    }

                                    submitCurrentInput();
                                  },
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    child: isCancellablePhase
                                        ? const Icon(
                                            Icons.stop_rounded,
                                            key: ValueKey(
                                                'chat-input-stop-icon'),
                                            size: 18,
                                          )
                                        : isBlockingPhase
                                            ? SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                          Color>(
                                                    colors
                                                        .semantic.text.inverse,
                                                  ),
                                                ),
                                              )
                                            : Icon(
                                                isStreamingResponse
                                                    ? Icons.stop_rounded
                                                    : Icons
                                                        .arrow_upward_rounded,
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

  Future<bool?> _confirmUnsupportedImageInputIfNeeded({
    required BuildContext context,
    required List<ChatAttachment> attachments,
  }) async {
    if (attachments.isEmpty) {
      return false;
    }

    final repository = ref.read(appSettingsRepositoryProvider);
    final config = await repository.getLlmConfig();
    final providerId =
        config.additionalConfig['llm.selected_provider_id'] as String?;
    final modelId = config.additionalConfig['llm.selected_model_id'] as String?;
    final runtimeSupport = config
            .additionalConfig['llm.runtime_selected_model_supports_image_input']
        as bool?;
    final staticSupport = config
        .additionalConfig['llm.selected_model_supports_image_input'] as bool?;
    final resolvedSupport = runtimeSupport ?? staticSupport;

    Logger.runtime(
      'ChatInput',
      'image input support evaluated before send',
      data: {
        'providerId': providerId ?? '',
        'modelId': modelId ?? '',
        'runtimeSupport': runtimeSupport,
        'staticSupport': staticSupport,
        'resolvedSupport': resolvedSupport,
      },
    );

    if (resolvedSupport != false) {
      return false;
    }

    if (!context.mounted) {
      return null;
    }
    final shouldContinue = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('发送图片前确认'),
          content: const Text('当前模型可能不支持图片输入，仍然尝试发送？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('仍然发送'),
            ),
          ],
        );
      },
    );
    return shouldContinue == true ? true : null;
  }
}

class _ModelProviderPickerSheet extends StatelessWidget {
  const _ModelProviderPickerSheet({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final maxHeight = MediaQuery.of(context).size.height * 0.78;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          spacing.md,
          spacing.md,
          spacing.md,
          spacing.md + MediaQuery.of(context).padding.bottom,
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight, maxWidth: 640),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.settingsPanelBackground,
                borderRadius: BorderRadius.circular(radius.lg),
                border: Border.all(color: colors.divider),
                boxShadow: [
                  BoxShadow(
                    color: colors.primaryText.withValues(alpha: 0.08),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.all(spacing.lg),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      SizedBox(height: spacing.xxs),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.secondaryText,
                              height: 1.45,
                            ),
                      ),
                      SizedBox(height: spacing.md),
                      child,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerActionTile extends StatelessWidget {
  const _PickerActionTile({
    required this.title,
    required this.onTap,
    this.subtitle,
    this.selected = false,
    this.trailing,
    this.trailingIcon,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final String? trailing;
  final IconData? trailingIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final colors = Theme.of(context).extension<AppThemeSpec>()!;

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: Material(
        color: selected
            ? colors.assistantSurface.withValues(alpha: 0.98)
            : colors.chatBackground.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(radius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius.lg),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(spacing.md),
            child: Row(
              children: [
                if (selected)
                  Padding(
                    padding: EdgeInsets.only(right: spacing.sm),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: colors.workflowRunning,
                    ),
                  )
                else
                  SizedBox(width: spacing.lg + 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      if (subtitle != null) ...[
                        SizedBox(height: spacing.xxs),
                        Text(
                          subtitle!,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colors.secondaryText,
                                    height: 1.4,
                                  ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null)
                  Padding(
                    padding: EdgeInsets.only(left: spacing.sm),
                    child: Text(
                      trailing!,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: selected
                                ? colors.workflowRunning
                                : colors.secondaryText,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                if (trailingIcon != null)
                  Padding(
                    padding: EdgeInsets.only(left: spacing.sm),
                    child: Icon(
                      trailingIcon,
                      size: 18,
                      color: colors.secondaryText,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
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
    final colors = Theme.of(context).extension<AppThemeSpec>()!;

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
