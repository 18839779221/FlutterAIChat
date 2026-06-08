import 'dart:ui';

import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  final GlobalKey _modelChipKey = GlobalKey();
  final GlobalKey _composerShellKey = GlobalKey();
  static const double _modelChipFontSize = 12.2;
  static const List<_SlashSuggestionItem> _slashCommandSuggestions = [
    _SlashSuggestionItem(
      title: '/compact',
      subtitle: '压缩当前会话的历史上下文。',
      insertText: '/compact',
    ),
  ];
  TextEditingController? _listenedController;
  ChangeNotifier? _listenedVoiceController;
  FocusNode? _listenedFocusNode;
  OverlayEntry? _slashSuggestionsOverlayEntry;
  List<_SlashSuggestionItem> _activeSlashSuggestions =
      const <_SlashSuggestionItem>[];
  String? _selectedModelChipLabel;

  @override
  void initState() {
    super.initState();
    _listenedController = ref.read(textControllerProvider);
    _listenedController?.addListener(_handleTextChanged);
    _listenedVoiceController = ref.read(voiceInputControllerProvider);
    _listenedVoiceController?.addListener(_handleVoiceStateChanged);
    _listenedFocusNode = ref.read(focusNodeProvider);
    _listenedFocusNode?.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _removeSlashSuggestionsOverlay();
    _listenedController?.removeListener(_handleTextChanged);
    _listenedVoiceController?.removeListener(_handleVoiceStateChanged);
    _listenedFocusNode?.removeListener(_handleFocusChanged);
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

  void _handleFocusChanged() {
    _syncSlashSuggestionsOverlay();
  }

  Future<void> _refreshModelChipLabel(AppSettingsRepository repository) async {
    final providers = await repository.getProviders();
    final selection = await repository.getSelectionState();
    String? nextLabel;
    LlmProviderConfig? resolvedProvider;
    for (final provider in providers) {
      if (provider.id == selection.selectedProviderId) {
        resolvedProvider = provider;
        break;
      }
    }
    resolvedProvider ??= providers.cast<LlmProviderConfig?>().firstWhere(
          (provider) => provider?.id == selection.defaultProviderId,
          orElse: () => providers.isEmpty ? null : providers.first,
        );
    if (resolvedProvider != null) {
      for (final model in resolvedProvider.models) {
        if (model.id == selection.selectedModelId) {
          nextLabel = model.displayName;
          break;
        }
      }
      nextLabel ??= resolvedProvider.models
          .cast<LlmProviderModel?>()
          .firstWhere(
            (model) => model?.id == selection.defaultModelId,
            orElse: () => resolvedProvider!.models.isEmpty
                ? null
                : resolvedProvider.models.first,
          )
          ?.displayName;
    }
    if (!mounted) {
      return;
    }
    final resolvedLabel = nextLabel ?? '未配置模型';
    if (_selectedModelChipLabel == resolvedLabel) {
      return;
    }
    setState(() {
      _selectedModelChipLabel = resolvedLabel;
    });
  }

  void _removeSlashSuggestionsOverlay() {
    _slashSuggestionsOverlayEntry?.remove();
    _slashSuggestionsOverlayEntry = null;
  }

  void _dismissSlashSuggestions() {
    _listenedFocusNode?.unfocus();
    _removeSlashSuggestionsOverlay();
  }

  void _syncSlashSuggestionsOverlay() {
    if (!mounted) {
      return;
    }
    final focusNode = _listenedFocusNode;
    final shouldShow =
        focusNode?.hasFocus == true && _activeSlashSuggestions.isNotEmpty;
    if (!shouldShow) {
      _removeSlashSuggestionsOverlay();
      return;
    }

    final composerRenderObject =
        _composerShellKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (composerRenderObject == null || overlay == null) {
      _removeSlashSuggestionsOverlay();
      return;
    }

    if (_slashSuggestionsOverlayEntry == null) {
      _slashSuggestionsOverlayEntry = OverlayEntry(
        builder: (context) => _AnchoredSlashSuggestionsOverlay(
          anchorRect: _resolveSlashSuggestionsAnchorRect(
            composerRenderObject: composerRenderObject,
            overlay: overlay,
          ),
          suggestions: _activeSlashSuggestions,
          onSelected: _handleSlashSuggestionSelected,
          onDismiss: _dismissSlashSuggestions,
        ),
      );
      Overlay.of(context).insert(_slashSuggestionsOverlayEntry!);
      return;
    }

    _slashSuggestionsOverlayEntry!.markNeedsBuild();
  }

  Rect _resolveSlashSuggestionsAnchorRect({
    required RenderBox composerRenderObject,
    required RenderBox overlay,
  }) {
    final offset =
        composerRenderObject.localToGlobal(Offset.zero, ancestor: overlay);
    return offset & composerRenderObject.size;
  }

  void _handleSlashSuggestionSelected(_SlashSuggestionItem item) {
    final selection = '${item.insertText} ';
    final controller = _listenedController;
    if (controller == null) {
      return;
    }
    controller.value = TextEditingValue(
      text: selection,
      selection: TextSelection.collapsed(offset: selection.length),
    );
    _removeSlashSuggestionsOverlay();
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
    if (settingsRepository != null) {
      final repository = settingsRepository;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _refreshModelChipLabel(repository);
        }
      });
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
    final commandSuggestions = _resolveSlashCommandSuggestions(slashQuery);
    final slashSuggestions = skillCatalog.maybeWhen<List<_SlashSuggestionItem>>(
      data: (skills) {
        if (slashQuery == null) {
          return const <_SlashSuggestionItem>[];
        }
        return skills
            .where((skill) {
              final query = slashQuery.toLowerCase();
              return skill.id.toLowerCase().contains(query) ||
                  skill.name.toLowerCase().contains(query) ||
                  skill.description.toLowerCase().contains(query);
            })
            .take(5)
            .map(
              (skill) => _SlashSuggestionItem.skill(
                title: skill.id,
                subtitle: skill.description,
                insertText: '/${skill.id}',
              ),
            )
            .toList(growable: false);
      },
      orElse: () => const <_SlashSuggestionItem>[],
    );
    _activeSlashSuggestions = <_SlashSuggestionItem>[
      ...commandSuggestions,
      ...slashSuggestions,
    ];
    if (!identical(_listenedVoiceController, voiceInputController)) {
      _listenedVoiceController?.removeListener(_handleVoiceStateChanged);
      _listenedVoiceController = voiceInputController;
      _listenedVoiceController?.addListener(_handleVoiceStateChanged);
    }
    if (!identical(_listenedFocusNode, focusNode)) {
      _listenedFocusNode?.removeListener(_handleFocusChanged);
      _listenedFocusNode = focusNode;
      _listenedFocusNode?.addListener(_handleFocusChanged);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncSlashSuggestionsOverlay();
    });

    Future<bool> handleSlashCommand() async {
      final command = _extractSlashCommand(textController.text);
      if (command == null) {
        return false;
      }
      if (command != '/compact') {
        return false;
      }
      if (composerAttachments.isNotEmpty) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('压缩历史上下文前请先移除附件。'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        return true;
      }
      textController.clear();
      try {
        await chatController.compactCurrentSession();
      } catch (error) {
        if (!mounted) {
          return true;
        }
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('压缩失败：$error'),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
      return true;
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
      final handledSlashCommand = await handleSlashCommand();
      if (handledSlashCommand) {
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

    void requestComposerFocus() {
      if (isComposerLocked) {
        return;
      }
      FocusScope.of(context).requestFocus(focusNode);
    }

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

      LlmProviderConfig? selectedProvider;
      LlmProviderConfig? defaultProvider;
      for (final item in providers) {
        if (item.id == selection.selectedProviderId) {
          selectedProvider = item;
        }
        if (item.id == selection.defaultProviderId) {
          defaultProvider = item;
        }
      }
      final provider = selectedProvider ?? defaultProvider ?? providers.first;
      final renderObject =
          _modelChipKey.currentContext?.findRenderObject() as RenderBox?;
      final overlay =
          Overlay.of(context).context.findRenderObject() as RenderBox?;
      if (renderObject == null || overlay == null) {
        return;
      }
      final offset = renderObject.localToGlobal(Offset.zero, ancestor: overlay);
      final anchorRect = offset & renderObject.size;

      final result = await showGeneralDialog<_ModelSelectionResult>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'dismiss-model-menu',
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 120),
        pageBuilder: (context, _, __) => _AnchoredModelMenuDialog(
          anchorRect: anchorRect,
          providers: providers,
          initialProviderId: provider.id,
          selectedModelId:
              selection.selectedModelId ?? selection.defaultModelId,
          defaultModelId: selection.defaultModelId,
        ),
        transitionBuilder: (context, animation, _, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: child,
          );
        },
      );

      if (!mounted || result == null) {
        return;
      }

      await repository.selectProviderAndModel(
        providerId: result.providerId,
        modelId: result.modelId,
      );
      await ref
          .read(chatSessionCoordinatorProvider)
          .syncDraftGroupProviderStyle();
      await _refreshModelChipLabel(repository);
    }

    final modelChipLabel = settingsRepository == null
        ? '未配置模型'
        : (_selectedModelChipLabel ?? '未配置模型');
    final screenWidth = MediaQuery.of(context).size.width;
    final modelChipMaxTextWidth = screenWidth < 700 ? 132.0 : 156.0;

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
          // 阴影承载层：必须位于 ClipRRect 之外，否则会被裁剪掉，
          // 失去悬浮感（这正是之前“贴在背景上”的根因）。
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius.lg + 8),
            boxShadow: [
              // 远环境阴影：大范围柔和，营造漂浮高度
              BoxShadow(
                color:
                    colors.core.elevation.shadowColor.withValues(alpha: 0.13),
                blurRadius: 48,
                spreadRadius: -8,
                offset: const Offset(0, 26),
              ),
              // 近接触阴影：定义底部边界、增加厚度
              BoxShadow(
                color: colors.core.elevation.shadowColor.withValues(alpha: 0.1),
                blurRadius: 18,
                spreadRadius: -4,
                offset: const Offset(0, 9),
              ),
              // 顶部内白光高亮：表面上缘提亮一道，模拟玻璃凸起反光
              BoxShadow(
                color: colors.semantic.text.inverse.withValues(alpha: 0.26),
                blurRadius: 8,
                offset: const Offset(0, -3),
              ),
            ],
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
                    color: colors.semantic.text.inverse.withValues(alpha: 0.55),
                    width: 1.5,
                  ),
                ),
                child: GestureDetector(
                  key: const ValueKey('chat-input-focus-surface'),
                  behavior: HitTestBehavior.opaque,
                  onTap: requestComposerFocus,
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
                            child: KeyedSubtree(
                              key: _composerShellKey,
                              child: Container(
                                key:
                                    const ValueKey('chat-input-composer-shell'),
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
                                        textAlignVertical:
                                            TextAlignVertical.center,
                                        textInputAction:
                                            TextInputAction.newline,
                                        keyboardType: TextInputType.multiline,
                                        style: AppTypography.uiStyle(
                                          color: colors.primaryText,
                                          fontSize: 13.7,
                                          height: 1.34,
                                        ),
                                        decoration: InputDecoration(
                                          hintText: '继续追问，或补充你的要求',
                                          hintStyle: AppTypography.uiStyle(
                                            color:
                                                colors.secondaryText.withValues(
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
                          ),
                          if (composerAttachments.isNotEmpty) ...[
                            SizedBox(height: spacing.xxs + 2),
                            ChatInputAttachmentStrip(
                              attachments: composerAttachments,
                              onRemove: (attachment) {
                                final nextAttachments = [...composerAttachments]
                                  ..removeWhere(
                                    (item) =>
                                        item.localId == attachment.localId,
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
                                    child: _PressableScale(
                                      enabled: !isComposerLocked,
                                      child: IconButton(
                                        key: const ValueKey(
                                            'chat-input-add-image'),
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
                                                          pickedAttachments
                                                              .length,
                                                      'pickedLocalIds':
                                                          pickedAttachments
                                                              .map((attachment) =>
                                                                  attachment
                                                                      .localId)
                                                              .join(','),
                                                      'pickedPaths':
                                                          pickedAttachments
                                                              .map((attachment) =>
                                                                  attachment
                                                                      .localPath ??
                                                                  '')
                                                              .join(','),
                                                    },
                                                  );
                                                  if (!context.mounted ||
                                                      pickedAttachments
                                                          .isEmpty) {
                                                    return;
                                                  }
                                                  final preparedAttachments =
                                                      attachmentStorage == null
                                                          ? pickedAttachments
                                                          : await Future.wait(
                                                              pickedAttachments
                                                                  .map(
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
                                                          preparedAttachments
                                                              .length,
                                                      'preparedLocalIds':
                                                          preparedAttachments
                                                              .map((attachment) =>
                                                                  attachment
                                                                      .localId)
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
                                                                      .status
                                                                      .name)
                                                              .join(','),
                                                      'preparedDataUrlLengths':
                                                          preparedAttachments
                                                              .map(
                                                                (attachment) =>
                                                                    (attachment.providerFileRefJson?['data_url']
                                                                            as String?)
                                                                        ?.length ??
                                                                    0,
                                                              )
                                                              .join(','),
                                                    },
                                                  );
                                                  if (!context.mounted ||
                                                      preparedAttachments
                                                          .isEmpty) {
                                                    return;
                                                  }
                                                  final nextComposerAttachments =
                                                      [
                                                    ...composerAttachments,
                                                    ...preparedAttachments,
                                                  ];
                                                  ref
                                                          .read(
                                                              composerAttachmentsProvider
                                                                  .notifier)
                                                          .state =
                                                      nextComposerAttachments;
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
                                                                  attachment
                                                                      .localId)
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
                                                            SnackBarBehavior
                                                                .floating,
                                                      ),
                                                    );
                                                }
                                              },
                                        icon: const Icon(
                                            Icons.add_photo_alternate_outlined),
                                      ),
                                    ),
                                  ),
                                if (hasVoiceInput)
                                  Padding(
                                    padding:
                                        EdgeInsets.only(right: spacing.xxs + 2),
                                    child: GestureDetector(
                                      key: const ValueKey(
                                          'chat-input-voice-button'),
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
                                      child: _PressableScale(
                                        enabled: !isComposerLocked,
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
                                                : colors
                                                    .settingsPanelBackground,
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
                                  ),
                                Padding(
                                  padding:
                                      EdgeInsets.only(right: spacing.xxs + 2),
                                  child: KeyedSubtree(
                                    key: _modelChipKey,
                                    child: _PressableScale(
                                      enabled: settingsRepository != null,
                                      pressedScale: 0.94,
                                      child: OutlinedButton(
                                        key: const ValueKey(
                                            'chat-input-model-chip'),
                                        onPressed: settingsRepository == null
                                            ? null
                                            : openModelPicker,
                                        style: OutlinedButton.styleFrom(
                                          minimumSize: const Size(0, 36),
                                          foregroundColor: colors.primaryText,
                                          padding: EdgeInsets.symmetric(
                                            horizontal: spacing.sm + 2,
                                            vertical: spacing.xxs + 2,
                                          ),
                                          backgroundColor: colors.chatBackground
                                              .withValues(alpha: 0.46),
                                          side: BorderSide(
                                            color: colors.semantic.text.inverse
                                                .withValues(alpha: 0.2),
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                                radius.pill),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            ConstrainedBox(
                                              constraints: BoxConstraints(
                                                maxWidth: modelChipMaxTextWidth,
                                              ),
                                              child: Text(
                                                modelChipLabel,
                                                overflow: TextOverflow.ellipsis,
                                                style: AppTypography.uiStyle(
                                                  color: colors.primaryText,
                                                  fontSize: _modelChipFontSize,
                                                  fontWeight: FontWeight.w400,
                                                  height: 1.2,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
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
                                      padding: EdgeInsets.only(
                                          right: spacing.xxs + 2),
                                      child: ContextWindowUsageIndicator(
                                        snapshot: snapshot,
                                        onTap: widget.onContextWindowPressed ??
                                            () {},
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
                                  child: _PressableScale(
                                    child: SizedBox(
                                      width: 40,
                                      height: 40,
                                      child: FilledButton(
                                        style: FilledButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          shape: const CircleBorder(),
                                          backgroundColor:
                                              isAwaitingConfirmation
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
                                            chatController
                                                .cancelStreamSubscription();
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
                                          duration:
                                              const Duration(milliseconds: 200),
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
                                                          colors.semantic.text
                                                              .inverse,
                                                        ),
                                                      ),
                                                    )
                                                  : Icon(
                                                      isStreamingResponse
                                                          ? Icons.stop_rounded
                                                          : Icons
                                                              .arrow_upward_rounded,
                                                      key: ValueKey(
                                                          sendButtonLabel),
                                                      size: 18,
                                                    ),
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

  String? _extractSlashCommand(String text) {
    final trimmed = text.trim();
    if (!trimmed.startsWith('/')) {
      return null;
    }
    return trimmed.split(RegExp(r'\s+')).first;
  }

  List<_SlashSuggestionItem> _resolveSlashCommandSuggestions(
    String? slashQuery,
  ) {
    if (slashQuery == null) {
      return const <_SlashSuggestionItem>[];
    }
    final normalizedQuery = '/${slashQuery.toLowerCase()}';
    return _slashCommandSuggestions
        .where(
          (suggestion) =>
              suggestion.title.toLowerCase().contains(normalizedQuery),
        )
        .toList(growable: false);
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

/// 按压缩放反馈包装：用 [Listener] 监听指针按下/抬起，不参与手势竞技，
/// 因此不会干扰子组件（FilledButton / GestureDetector 等）的原有点击逻辑。
class _PressableScale extends StatefulWidget {
  const _PressableScale({
    required this.child,
    this.enabled = true,
    this.pressedScale = 0.9,
  });

  final Widget child;
  final bool enabled;
  final double pressedScale;

  @override
  State<_PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<_PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!widget.enabled) {
      return;
    }
    if (_pressed != value) {
      setState(() => _pressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isActivePressed = _pressed && widget.enabled;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: isActivePressed ? widget.pressedScale : 1,
        duration: Duration(milliseconds: isActivePressed ? 90 : 240),
        curve: isActivePressed ? Curves.easeOutCubic : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

class _SlashSuggestionItem {
  const _SlashSuggestionItem({
    required this.title,
    required this.subtitle,
    required this.insertText,
  });

  const _SlashSuggestionItem.skill({
    required String title,
    required String subtitle,
    required String insertText,
  }) : this(
          title: title,
          subtitle: subtitle,
          insertText: insertText,
        );

  final String title;
  final String subtitle;
  final String insertText;
}

class _ModelSelectionResult {
  const _ModelSelectionResult({
    required this.providerId,
    required this.modelId,
  });

  final String providerId;
  final String modelId;
}

class _AnchoredModelMenuDialog extends StatefulWidget {
  const _AnchoredModelMenuDialog({
    required this.anchorRect,
    required this.providers,
    required this.initialProviderId,
    required this.selectedModelId,
    required this.defaultModelId,
  });

  final Rect anchorRect;
  final List<LlmProviderConfig> providers;
  final String initialProviderId;
  final String? selectedModelId;
  final String? defaultModelId;

  @override
  State<_AnchoredModelMenuDialog> createState() =>
      _AnchoredModelMenuDialogState();
}

class _AnchoredModelMenuDialogState extends State<_AnchoredModelMenuDialog> {
  static const double _menuFontSize = 12.2;
  late String _activeProviderId;
  bool _showProviderPanel = false;

  @override
  void initState() {
    super.initState();
    _activeProviderId = widget.initialProviderId;
  }

  LlmProviderConfig get _activeProvider {
    return widget.providers.firstWhere(
      (provider) => provider.id == _activeProviderId,
      orElse: () => widget.providers.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final screenSize = MediaQuery.of(context).size;
    final panelWidth = screenSize.width < 700
        ? widget.anchorRect.width.clamp(176.0, 220.0)
        : widget.anchorRect.width.clamp(188.0, 236.0);
    final itemCount = _showProviderPanel
        ? widget.providers.length
        : _activeProvider.models.length;
    final estimatedMenuHeight = (_showProviderPanel ? 52.0 : 48.0) +
        (itemCount * 42.0) +
        spacing.xs +
        16.0;
    final availableBelow = screenSize.height - widget.anchorRect.bottom - 8;
    final availableAbove = widget.anchorRect.top - 8;
    final shouldOpenAbove =
        availableBelow < estimatedMenuHeight && availableAbove > availableBelow;
    final left = widget.anchorRect.left.clamp(
      12.0,
      screenSize.width - panelWidth - 12,
    );
    final belowTop = widget.anchorRect.bottom + 2;
    final aboveTop = widget.anchorRect.top - estimatedMenuHeight - 2;
    final top = (shouldOpenAbove ? aboveTop : belowTop).clamp(
      8.0,
      screenSize.height - estimatedMenuHeight - 8,
    );

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            child: _AnchoredMenuPanel(
              key: const ValueKey('chat-input-model-menu'),
              width: panelWidth,
              child: AnimatedSize(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Material(
                      color: colors.assistantSurface.withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(radius.md),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(radius.md),
                        onTap: () {
                          setState(() {
                            _showProviderPanel = !_showProviderPanel;
                          });
                        },
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: spacing.md,
                            vertical: spacing.sm,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.hub_outlined,
                                size: 15,
                                color: colors.secondaryText,
                              ),
                              SizedBox(width: spacing.xs),
                              Expanded(
                                child: Text(
                                  _activeProvider.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.uiStyle(
                                    color: colors.primaryText,
                                    fontSize: _menuFontSize,
                                    fontWeight: FontWeight.w400,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                              Icon(
                                _showProviderPanel
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.keyboard_arrow_down_rounded,
                                size: 18,
                                color: colors.secondaryText,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: spacing.xs),
                    if (_showProviderPanel)
                      ...widget.providers.map(
                        (provider) => _PickerActionTile(
                          title: provider.name,
                          selected: provider.id == _activeProvider.id,
                          onTap: () {
                            setState(() {
                              _activeProviderId = provider.id;
                              _showProviderPanel = false;
                            });
                          },
                        ),
                      )
                    else
                      ..._activeProvider.models.map(
                        (model) => _PickerActionTile(
                          title: model.displayName,
                          selected: model.id == widget.selectedModelId,
                          onTap: () => Navigator.of(context).pop(
                            _ModelSelectionResult(
                              providerId: _activeProvider.id,
                              modelId: model.id,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnchoredMenuPanel extends StatelessWidget {
  const _AnchoredMenuPanel({
    super.key,
    required this.child,
    required this.width,
  });

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final colors = Theme.of(context).extension<AppThemeSpec>()!;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.chatBackground.withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(radius.lg + 2),
          border: Border.all(color: colors.divider),
          boxShadow: [
            BoxShadow(
              color: colors.primaryText.withValues(alpha: 0.055),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(spacing.xs),
          child: child,
        ),
      ),
    );
  }
}

class _PickerActionTile extends StatelessWidget {
  static const double _titleFontSize = 12.2;
  const _PickerActionTile({
    required this.title,
    required this.onTap,
    this.selected = false,
    this.subtitle,
  });

  final String title;
  final bool selected;
  final String? subtitle;
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
            padding: EdgeInsets.symmetric(
              horizontal: spacing.md,
              vertical: spacing.sm + 1,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.uiStyle(
                          color: colors.primaryText,
                          fontSize: _titleFontSize,
                          fontWeight: FontWeight.w400,
                          height: 1.2,
                        ),
                      ),
                      if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                        SizedBox(height: spacing.xxs),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.uiStyle(
                            color: colors.secondaryText,
                            fontSize: 11.2,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected)
                  Padding(
                    padding:
                        EdgeInsets.only(left: spacing.sm, top: spacing.xxs),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: colors.workflowRunning,
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

class _AnchoredSlashSuggestionsOverlay extends StatelessWidget {
  const _AnchoredSlashSuggestionsOverlay({
    required this.anchorRect,
    required this.suggestions,
    required this.onSelected,
    required this.onDismiss,
  });

  final Rect anchorRect;
  final List<_SlashSuggestionItem> suggestions;
  final ValueChanged<_SlashSuggestionItem> onSelected;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final screenSize = MediaQuery.of(context).size;
    final panelWidth = screenSize.width < 700
        ? anchorRect.width.clamp(220.0, 320.0)
        : anchorRect.width.clamp(240.0, 360.0);
    final estimatedMenuHeight = (suggestions.length * 56.0) + spacing.xs + 12.0;
    final availableBelow = screenSize.height - anchorRect.bottom - 8;
    final availableAbove = anchorRect.top - 8;
    final shouldOpenAbove = availableAbove >= estimatedMenuHeight ||
        availableAbove >= availableBelow;
    final left = anchorRect.left.clamp(
      12.0,
      screenSize.width - panelWidth - 12,
    );
    final belowTop = anchorRect.bottom + 2;
    final aboveTop = anchorRect.top - estimatedMenuHeight - 2;
    final top = (shouldOpenAbove ? aboveTop : belowTop).clamp(
      8.0,
      screenSize.height - estimatedMenuHeight - 8,
    );

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: onDismiss,
            ),
          ),
          Positioned(
            left: left,
            top: top,
            child: _AnchoredMenuPanel(
              key: const ValueKey('chat-input-skill-suggestions'),
              width: panelWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: suggestions
                    .map(
                      (item) => _PickerActionTile(
                        title: item.title,
                        subtitle: item.subtitle,
                        onTap: () => onSelected(item),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
