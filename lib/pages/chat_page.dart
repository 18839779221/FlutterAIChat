import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/chat_group.dart';
import '../theme/app_theme_spec.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../providers/chat_providers.dart';
import '../widgets/chat_blocks/unified_turn_status_bar.dart';
import '../widgets/chat_message_list.dart';
import '../widgets/chat_input.dart';
import '../widgets/chat_drawer.dart';
import '../widgets/debug/debug_test_case_sheet.dart';
import '../widgets/debug/debug_turn_inspector_button.dart';
import '../widgets/debug/streaming_trace_overlay_card.dart';
import '../widgets/debug/debug_turn_inspector_sheet.dart';
import '../widgets/context_window/context_window_bottom_sheet.dart';
import '../widgets/tool_confirmation/tool_confirmation_bottom_bar.dart';
import '../services/debug/debug_turn_inspector_projection_service.dart';
import '../services/workspace/workspace_binding_service.dart';
import '../providers/streaming_trace_providers.dart';

const double _bottomOverlayVeilHeadroom = 30;

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key, required this.title});

  final String title;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  static const String _debugIdleStatusText = '测试边界状态';
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final WorkspaceBindingService _workspaceBindingService =
      WorkspaceBindingService();

  @override
  void initState() {
    super.initState();
    // 初始化加载数据
    Future.microtask(() => ref.read(chatControllerProvider).loadGroups());
  }

  @override
  Widget build(BuildContext context) {
    final currentGroup = ref.watch(currentGroupProvider);
    final sendPhase = ref.watch(sendPhaseProvider);
    final isSendInFlight = sendPhase != ChatSendPhase.idle;
    final systemPrompt = ref.watch(systemPromptProvider);
    final isLoadingMore = ref.watch(isLoadingMoreProvider);
    final pendingConfirmation =
        ref.watch(activePendingToolConfirmationProvider);
    final traceSnapshot = ref.watch(streamingTraceSnapshotProvider);
    final traceOverlayState =
        ref.watch(streamingTraceOverlayControllerProvider);
    final activeTurnStatus = ref.watch(activeTurnStatusPresentationProvider);
    final shouldShowFloatingActiveStatus =
        ref.watch(activeTurnStatusFloatingVisibilityProvider);
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final chatController = ref.read(chatControllerProvider);

    ref.listen(streamingTraceSnapshotProvider, (previous, next) {
      if (next == null) {
        ref
            .read(streamingTraceOverlayControllerProvider.notifier)
            .closeIfAnchorDisappeared();
      }
    });
    ref.listen<ChatGroup?>(currentGroupProvider, (previous, next) {
      if (!mounted || previous == null || next == null) {
        return;
      }
      if (previous.id == null || previous.id != next.id) {
        return;
      }
      final previousWorkspace =
          _workspaceBindingService.resolveWorkspaceId(previous.workspaceId);
      final nextWorkspace =
          _workspaceBindingService.resolveWorkspaceId(next.workspaceId);
      if (!previousWorkspace.isDefault || nextWorkspace.isDefault) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('当前对话已切换到 workspace ${nextWorkspace.workspaceId}'),
          duration: const Duration(seconds: 3),
        ),
      );
    });
    final resolvedWorkspace = currentGroup == null
        ? null
        : _workspaceBindingService.resolveWorkspaceId(currentGroup.workspaceId);

    return Scaffold(
      key: _scaffoldKey,
      drawer: const ChatDrawer(),
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity! > 0) {
            _scaffoldKey.currentState?.openDrawer();
          }
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.chatBackground,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colors.assistantSurface.withValues(alpha: 0.78),
                      colors.chatBackground,
                      colors.toolWorkflowSurface.withValues(alpha: 0.52),
                      colors.chatBackground,
                    ],
                    stops: const [0, 0.38, 0.82, 1],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Container(
                  height: 88,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        colors.chatBackground.withValues(alpha: 0.96),
                        colors.chatBackground.withValues(alpha: 0.62),
                        colors.chatBackground.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Stack(
                children: [
                  if (resolvedWorkspace != null)
                    Positioned(
                      top: 32,
                      left: spacing.lg,
                      child: _WorkspaceBadge(
                        workspaceId: resolvedWorkspace.workspaceId,
                        isDefault: resolvedWorkspace.isDefault,
                      ),
                    ),
                  Positioned.fill(
                    child: Stack(
                      children: [
                        const ChatMessageList(),
                        if (isLoadingMore)
                          Positioned(
                            top: 0,
                            left: spacing.lg,
                            right: spacing.lg,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                minHeight: 3,
                                backgroundColor: Colors.transparent,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                        if (traceSnapshot != null &&
                            traceOverlayState.isVisible)
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: () => ref
                                  .read(
                                    streamingTraceOverlayControllerProvider
                                        .notifier,
                                  )
                                  .close(),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: SizedBox(
                      width: double.infinity,
                      child: _MeasuredBottomOverlayHost(
                        child: Stack(
                          children: [
                            const Positioned.fill(
                              child: IgnorePointer(
                                child: _BottomOverlayVeil(),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(
                                top: _bottomOverlayVeilHeadroom,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (pendingConfirmation != null)
                                    ToolConfirmationBottomBar(
                                      message: pendingConfirmation.message,
                                      invocation:
                                          pendingConfirmation.invocation,
                                      onContinue: () =>
                                          chatController.confirmToolInvocation(
                                        pendingConfirmation.message,
                                      ),
                                      onCancel: () =>
                                          chatController.cancelToolInvocation(
                                        pendingConfirmation.message,
                                      ),
                                      onContinueAndTrust: () =>
                                          chatController.confirmToolInvocation(
                                        pendingConfirmation.message,
                                        trustTool: true,
                                      ),
                                    ),
                                  if (activeTurnStatus != null &&
                                      activeTurnStatus.allowFloating &&
                                      shouldShowFloatingActiveStatus)
                                    IgnorePointer(
                                      child: Padding(
                                        padding: EdgeInsets.fromLTRB(
                                          spacing.md - 2,
                                          0,
                                          spacing.md - 2,
                                          spacing.xxs + 1,
                                        ),
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              maxWidth: 320,
                                            ),
                                            child: Transform.translate(
                                              offset: const Offset(0, -2),
                                              child: KeyedSubtree(
                                                key: const ValueKey(
                                                  'floating-turn-status-bar',
                                                ),
                                                child: UnifiedTurnStatusBar(
                                                  status: activeTurnStatus,
                                                  variant:
                                                      UnifiedTurnStatusBarVariant
                                                          .floating,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ChatInput(
                                    onContextWindowPressed: () {
                                      unawaited(
                                        _showContextWindowSheet(context),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: _GhostHeader(
                  isSendInFlight: isSendInFlight,
                  onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  onNewChatPressed:
                      ref.read(chatControllerProvider).createNewGroup,
                  onDebugCasesPressed:
                      kDebugMode ? () => _showDebugTestCases(context) : null,
                  onDebugInspectorPressed: kDebugMode
                      ? () => _showDebugTurnInspector(context)
                      : null,
                  onDebugInspectorLongPressed: kDebugMode
                      ? () => ref
                          .read(
                              streamingTraceOverlayControllerProvider.notifier)
                          .show(
                            anchorId: 'debug-turn-inspector-button',
                            hasActiveTrace: traceSnapshot != null,
                          )
                      : null,
                  onMorePressed: () => _showHeaderActions(
                    context,
                    hasSystemPrompt:
                        systemPrompt != null && systemPrompt.isNotEmpty,
                  ),
                ),
              ),
            ),
            if (traceSnapshot != null && traceOverlayState.isVisible)
              Positioned(
                top: 44,
                right: spacing.lg,
                child: SafeArea(
                  bottom: false,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: StreamingTraceOverlayCard(
                      snapshot: traceSnapshot,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDebugTestCases(BuildContext context) async {
    final library = await ref.read(debugTestCaseLibraryProvider.future);
    if (!context.mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          Theme.of(context).extension<AppThemeSpec>()!.chatBackground,
      builder: (sheetContext) => DebugTestCaseSheet(
        cases: library.allCases,
        onShowIdleStatus: () {
          ref.read(chatSendStateProvider.notifier).update(
                phase: ChatSendPhase.idle,
                isGenerating: false,
                statusText: _debugIdleStatusText,
              );
          Navigator.of(sheetContext).pop();
        },
        onClearIdleStatus: () {
          ref.read(chatSendStateProvider.notifier).update(
                phase: ChatSendPhase.idle,
                isGenerating: false,
                clearStatusText: true,
              );
          Navigator.of(sheetContext).pop();
        },
        onSelected: (item) {
          final textController = ref.read(textControllerProvider);
          final focusNode = ref.read(focusNodeProvider);
          textController.value = TextEditingValue(
            text: item.prompt,
            selection: TextSelection.collapsed(offset: item.prompt.length),
          );
          Navigator.of(sheetContext).pop();
          focusNode.requestFocus();
        },
      ),
    );
  }

  Future<void> _showContextWindowSheet(BuildContext context) async {
    final snapshot = await ref.read(contextWindowSnapshotProvider.future);
    if (!context.mounted || snapshot == null) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          Theme.of(context).extension<AppThemeSpec>()!.chatBackground,
      builder: (_) => ContextWindowBottomSheet(snapshot: snapshot),
    );
  }

  Future<void> _showDebugTurnInspector(BuildContext context) async {
    final currentGroup = ref.read(currentGroupProvider);
    final groupId = currentGroup?.id;
    if (groupId == null || !context.mounted) {
      return;
    }
    final service = DebugTurnInspectorProjectionService(
      chatTurnRepository: ref.read(chatTurnRepositoryProvider),
      chatEventRepository: ref.read(chatEventRepositoryProvider),
      sessionContextService: ref.read(sessionContextServiceProvider),
      traceRecorder: ref.read(traceRecorderProvider),
      runtimeAssistantDraft: ref.read(runtimeAssistantDraftProvider),
      runtimePreviewState: ref.read(runtimeStreamingPreviewStateProvider),
      toolPresentationEvents:
          ref.read(chatTimelineProjectionProvider).toolPresentationEvents,
      sendPhase: ref.read(chatSendStateProvider).phase,
      activeAskUserQuestionMessage:
          ref.read(activeAskUserQuestionMessageProvider),
    );
    final projection = await service.build(groupId: groupId);
    if (!context.mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.92,
        child: DebugTurnInspectorSheet(
          groupId: groupId,
          initialProjection: projection,
        ),
      ),
    );
  }

  void _showHeaderActions(
    BuildContext context, {
    required bool hasSystemPrompt,
  }) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        message: const Text('选择操作'),
        actions: [
          CupertinoActionSheetAction(
            child: Text(hasSystemPrompt ? '修改系统提示词' : '设置系统提示词'),
            onPressed: () {
              Navigator.pop(context);
              _showSystemPromptDialog(context);
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

  void _showSystemPromptDialog(BuildContext context) {
    final systemPrompt = ref.read(systemPromptProvider);
    final controller = TextEditingController(text: systemPrompt);

    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('系统提示词'),
        content: Padding(
          padding: const EdgeInsets.only(top: 16.0),
          child: CupertinoTextField(
            controller: controller,
            placeholder: '输入系统提示词...',
            maxLines: 5,
            minLines: 3,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            child: const Text('确定'),
            onPressed: () {
              ref.read(chatControllerProvider).setSystemPrompt(controller.text);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}

class _WorkspaceBadge extends StatelessWidget {
  const _WorkspaceBadge({
    required this.workspaceId,
    required this.isDefault,
  });

  final String workspaceId;
  final bool isDefault;

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final colors = Theme.of(context).extension<AppThemeSpec>()!;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.assistantSurface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(radius.pill),
        border: Border.all(color: colors.divider),
        boxShadow: [
          BoxShadow(
            color: colors.primaryText.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.sm,
          vertical: spacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open_outlined,
              size: 14,
              color: colors.secondaryText,
            ),
            SizedBox(width: spacing.xs),
            Text(
              isDefault ? 'Workspace .default' : 'Workspace $workspaceId',
              style: TextStyle(
                color: colors.primaryText,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomOverlayVeil extends StatelessWidget {
  const _BottomOverlayVeil();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;

    return DecoratedBox(
      key: const ValueKey('chat-bottom-overlay-veil'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colors.chatBackground.withValues(alpha: 0),
            colors.assistantSurface.withValues(alpha: 0.32),
            colors.assistantSurface.withValues(alpha: 0.5),
            colors.assistantSurface.withValues(alpha: 0.5),
          ],
          stops: const [0, 0.08, 0.18, 1],
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _GhostHeader extends StatelessWidget {
  final bool isSendInFlight;
  final VoidCallback onMenuPressed;
  final VoidCallback onNewChatPressed;
  final VoidCallback? onDebugCasesPressed;
  final VoidCallback? onDebugInspectorPressed;
  final VoidCallback? onDebugInspectorLongPressed;
  final VoidCallback onMorePressed;

  const _GhostHeader({
    required this.isSendInFlight,
    required this.onMenuPressed,
    required this.onNewChatPressed,
    required this.onDebugCasesPressed,
    required this.onDebugInspectorPressed,
    required this.onDebugInspectorLongPressed,
    required this.onMorePressed,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        spacing.lg,
        spacing.xs,
        spacing.lg,
        0,
      ),
      child: SizedBox(
        key: const ValueKey('ghost-header'),
        height: 28,
        child: Row(
          children: [
            _HeaderButton(
              icon: Icons.menu,
              tooltip: '会话列表',
              onPressed: onMenuPressed,
              filled: true,
            ),
            const Spacer(),
            _HeaderButton(
              icon: Icons.add,
              tooltip: '新建对话',
              onPressed: isSendInFlight ? null : onNewChatPressed,
            ),
            if (onDebugCasesPressed != null) ...[
              SizedBox(width: spacing.xs),
              _HeaderButton(
                buttonKey: const ValueKey('debug-test-cases-button'),
                icon: Icons.science_outlined,
                tooltip: '测试案例',
                onPressed: onDebugCasesPressed,
              ),
            ],
            if (onDebugInspectorPressed != null) ...[
              SizedBox(width: spacing.xs),
              DebugTurnInspectorButton(
                onPressed: onDebugInspectorPressed!,
                onLongPress: onDebugInspectorLongPressed,
              ),
            ],
            SizedBox(width: spacing.xs),
            _HeaderButton(
              icon: Icons.more_horiz,
              tooltip: '更多操作',
              onPressed: onMorePressed,
            ),
          ],
        ),
      ),
    );
  }
}

class _MeasuredBottomOverlayHost extends ConsumerStatefulWidget {
  const _MeasuredBottomOverlayHost({required this.child});

  final Widget child;

  @override
  ConsumerState<_MeasuredBottomOverlayHost> createState() =>
      _MeasuredBottomOverlayHostState();
}

class _MeasuredBottomOverlayHostState
    extends ConsumerState<_MeasuredBottomOverlayHost> {
  static const double _timelineOverlapAllowance = 8;
  final GlobalKey _measurementKey = GlobalKey(
    debugLabel: 'chat-bottom-overlay-host',
  );
  double _lastReportedHeight = -1;
  bool _pendingMeasurement = false;

  @override
  void initState() {
    super.initState();
    _scheduleMeasurement();
  }

  void _scheduleMeasurement() {
    if (_pendingMeasurement) {
      return;
    }
    _pendingMeasurement = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingMeasurement = false;
      if (!mounted) {
        return;
      }
      final renderObject =
          _measurementKey.currentContext?.findRenderObject() as RenderBox?;
      final rawHeight = renderObject?.size.height ?? 0.0;
      final nextHeight = rawHeight <= _timelineOverlapAllowance
          ? 0.0
          : (rawHeight - _timelineOverlapAllowance).toDouble();
      if ((nextHeight - _lastReportedHeight).abs() < 0.5) {
        return;
      }
      _lastReportedHeight = nextHeight;
      ref.read(chatBottomOverlayHeightProvider.notifier).state = nextHeight;
    });
  }

  @override
  Widget build(BuildContext context) {
    _scheduleMeasurement();
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _scheduleMeasurement();
        return false;
      },
      child: SizeChangedLayoutNotifier(
        child: KeyedSubtree(
          key: _measurementKey,
          child: widget.child,
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final Key? buttonKey;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool filled;

  const _HeaderButton({
    this.buttonKey,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final backgroundColor = colors.assistantSurface.withValues(
      alpha: filled ? 0.93 : 0.89,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius.pill),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Material(
          color: backgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius.pill),
          ),
          elevation: 0,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius.pill),
              boxShadow: [
                BoxShadow(
                  color: colors.primaryText.withValues(alpha: 0.09),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.14),
                  blurRadius: 1.2,
                  offset: const Offset(0, -0.5),
                ),
              ],
            ),
            child: IconButton(
              key: buttonKey,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
              padding: EdgeInsets.zero,
              tooltip: tooltip,
              onPressed: onPressed,
              icon: Icon(
                icon,
                size: 15.5,
                color: onPressed == null
                    ? colors.secondaryText.withValues(alpha: 0.45)
                    : colors.primaryText.withValues(alpha: 0.9),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
