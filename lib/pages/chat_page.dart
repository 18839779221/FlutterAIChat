import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/chat_group.dart';
import '../theme/app_theme_spec.dart';
import '../theme/app_spacing.dart';
import '../providers/chat_providers.dart';
import '../widgets/chat_blocks/unified_turn_status_bar.dart';
import '../widgets/chat_message_list.dart';
import '../widgets/chat_message_list_skeleton.dart';
import '../widgets/chat_input.dart';
import '../widgets/chat_drawer.dart';
import '../widgets/chat_header_button.dart';
import '../widgets/chat_top_bar_button.dart';
import '../widgets/chat_top_chrome_motion.dart';
import '../widgets/debug/debug_test_case_sheet.dart';
import '../widgets/debug/streaming_trace_overlay_card.dart';
import '../widgets/debug/debug_turn_inspector_sheet.dart';
import '../widgets/context_window/context_window_bottom_sheet.dart';
import '../widgets/shared/app_bottom_sheet.dart';
import '../widgets/tool_confirmation/tool_confirmation_bottom_bar.dart';
import '../services/debug/debug_turn_inspector_projection_service.dart';
import '../services/workspace/workspace_binding_service.dart';
import '../providers/streaming_trace_providers.dart';

const double _bottomOverlayVeilHeadroom = 30;
const double _floatingBottomControlsReservedTop = 18;
const double _floatingBottomControlsOverlap = -1;

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
  bool _didScheduleBootstrapReadyLoad = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final bootstrapState = ref.watch(appBootstrapStateProvider);
    final isBootstrapReady = bootstrapState.isReady;
    final currentGroup = ref.watch(currentGroupProvider);
    final sendPhase = ref.watch(sendPhaseProvider);
    final isSendInFlight = sendPhase != ChatSendPhase.idle;
    final isLoadingMore = ref.watch(isLoadingMoreProvider);
    final pendingConfirmation =
        ref.watch(activePendingToolConfirmationProvider);
    final traceSnapshot = ref.watch(streamingTraceSnapshotProvider);
    final traceOverlayState =
        ref.watch(streamingTraceOverlayControllerProvider);
    final activeTurnStatus = ref.watch(activeTurnStatusPresentationProvider);
    final shouldShowFloatingActiveStatus =
        ref.watch(activeTurnStatusFloatingVisibilityProvider);
    final shouldShowScrollToBottomButton =
        ref.watch(scrollToBottomButtonVisibleProvider);
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final chatController = ref.read(chatControllerProvider);
    final scrollController = ref.read(scrollControllerProvider);

    if (isBootstrapReady && !_didScheduleBootstrapReadyLoad) {
      _didScheduleBootstrapReadyLoad = true;
      Future.microtask(() => ref.read(chatControllerProvider).loadGroups());
    }

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

    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            isDarkTheme ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDarkTheme ? Brightness.dark : Brightness.light,
      ),
      child: Scaffold(
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
                  ),
                ),
              ),
              Positioned.fill(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Stack(
                        children: [
                          if (isBootstrapReady)
                            const ChatMessageList()
                          else
                            const ChatMessageListSkeleton(),
                          if (isLoadingMore)
                            Positioned(
                              top: MediaQuery.of(context).padding.top,
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
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                top: _floatingBottomControlsReservedTop,
                              ),
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
                                              message:
                                                  pendingConfirmation.message,
                                              invocation: pendingConfirmation
                                                  .invocation,
                                              onContinue: () => chatController
                                                  .confirmToolInvocation(
                                                pendingConfirmation.message,
                                              ),
                                              onCancel: () => chatController
                                                  .cancelToolInvocation(
                                                pendingConfirmation.message,
                                              ),
                                              onContinueAndTrust: () =>
                                                  chatController
                                                      .confirmToolInvocation(
                                                pendingConfirmation.message,
                                                trustTool: true,
                                              ),
                                            ),
                                          ChatInput(
                                            onContextWindowPressed: () {
                                              unawaited(
                                                _showContextWindowSheet(
                                                  context,
                                                ),
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
                            if ((activeTurnStatus != null &&
                                    activeTurnStatus.allowFloating &&
                                    shouldShowFloatingActiveStatus) ||
                                shouldShowScrollToBottomButton)
                              Positioned(
                                left: 0,
                                right: 0,
                                top: _floatingBottomControlsOverlap,
                                child: Padding(
                                  key: const ValueKey(
                                    'chat-bottom-floating-controls-row',
                                  ),
                                  padding: EdgeInsets.fromLTRB(
                                    spacing.md,
                                    0,
                                    spacing.md,
                                    spacing.xs,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      if (activeTurnStatus != null &&
                                          activeTurnStatus.allowFloating &&
                                          shouldShowFloatingActiveStatus)
                                        Expanded(
                                          child: IgnorePointer(
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: ConstrainedBox(
                                                constraints:
                                                    const BoxConstraints(
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
                                        )
                                      else
                                        const Spacer(),
                                      if (shouldShowScrollToBottomButton)
                                        _ScrollToBottomButton(
                                          onPressed: () {
                                            if (!scrollController.hasClients) {
                                              return;
                                            }
                                            scrollController.jumpTo(
                                              scrollController
                                                  .position.maxScrollExtent,
                                            );
                                            WidgetsBinding.instance
                                                .addPostFrameCallback((_) {
                                              if (!scrollController
                                                  .hasClients) {
                                                return;
                                              }
                                              scrollController.jumpTo(
                                                scrollController
                                                    .position.maxScrollExtent,
                                              );
                                            });
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: _TopOverlayVeil(),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: _GhostHeader(
                    scrollController: scrollController,
                    isSendInFlight: isSendInFlight,
                    onMenuPressed: () =>
                        _scaffoldKey.currentState?.openDrawer(),
                    onNewChatPressed:
                        ref.read(chatControllerProvider).createNewGroup,
                    workspaceLabel:
                        resolvedWorkspace == null || resolvedWorkspace.isDefault
                            ? null
                            : resolvedWorkspace.workspaceId,
                    onWorkspacePressed:
                        resolvedWorkspace == null || resolvedWorkspace.isDefault
                            ? null
                            : () => _scaffoldKey.currentState?.openDrawer(),
                    onDebugCasesPressed:
                        kDebugMode ? () => _showDebugTestCases(context) : null,
                    onDebugInspectorPressed: kDebugMode
                        ? () => _showDebugTurnInspector(context)
                        : null,
                    onDebugInspectorLongPressed: kDebugMode
                        ? () => ref
                            .read(streamingTraceOverlayControllerProvider
                                .notifier)
                            .show(
                              anchorId: 'debug-turn-inspector-button',
                              hasActiveTrace: traceSnapshot != null,
                            )
                        : null,
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
      ),
    );
  }

  Future<void> _showDebugTestCases(BuildContext context) async {
    final library = await ref.read(debugTestCaseLibraryProvider.future);
    if (!context.mounted) {
      return;
    }

    await showAppBottomSheet<void>(
      context: context,
      mode: AppBottomSheetMode.fixed80,
      body: DebugTestCaseSheet(
        cases: library.allCases,
        onShowIdleStatus: () {
          ref.read(chatSendStateProvider.notifier).update(
                phase: ChatSendPhase.idle,
                isGenerating: false,
                statusText: _debugIdleStatusText,
              );
          Navigator.of(context).pop();
        },
        onClearIdleStatus: () {
          ref.read(chatSendStateProvider.notifier).update(
                phase: ChatSendPhase.idle,
                isGenerating: false,
                clearStatusText: true,
              );
          Navigator.of(context).pop();
        },
        onSelected: (item) {
          final textController = ref.read(textControllerProvider);
          final focusNode = ref.read(focusNodeProvider);
          textController.value = TextEditingValue(
            text: item.prompt,
            selection: TextSelection.collapsed(offset: item.prompt.length),
          );
          Navigator.of(context).pop();
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

    await showAppBottomSheet<void>(
      context: context,
      mode: AppBottomSheetMode.fixed80,
      body: ContextWindowBottomSheet(snapshot: snapshot),
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
    await showAppBottomSheet<void>(
      context: context,
      mode: AppBottomSheetMode.fixed80,
      useSafeArea: true,
      body: DebugTurnInspectorSheet(
        groupId: groupId,
        initialProjection: projection,
      ),
    );
  }
}

class _TopOverlayVeil extends StatelessWidget {
  const _TopOverlayVeil();

  // header 视觉区域高度（不含状态栏），用于决定遮罩淡出位置
  static const double _headerRegionHeight = 76;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final totalHeight = statusBarHeight + _headerRegionHeight;
    // 状态栏 + header 顶部保持高不透明度遮挡，越往下越透明
    final headerBottomFraction =
        ((statusBarHeight + 56) / totalHeight).clamp(0.0, 1.0);

    return SizedBox(
      height: totalHeight,
      child: DecoratedBox(
        key: const ValueKey('chat-top-overlay-veil'),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colors.chatBackground.withValues(alpha: 0.96),
              colors.chatBackground.withValues(alpha: 0.88),
              colors.chatBackground.withValues(alpha: 0.18),
              colors.chatBackground.withValues(alpha: 0),
            ],
            stops: [
              0,
              headerBottomFraction * 0.6,
              headerBottomFraction * 0.98,
              1,
            ],
          ),
        ),
        child: const SizedBox.expand(),
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

class _GhostHeader extends StatefulWidget {
  final ScrollController scrollController;
  final bool isSendInFlight;
  final VoidCallback onMenuPressed;
  final VoidCallback onNewChatPressed;
  final String? workspaceLabel;
  final VoidCallback? onWorkspacePressed;
  final VoidCallback? onDebugCasesPressed;
  final VoidCallback? onDebugInspectorPressed;
  final VoidCallback? onDebugInspectorLongPressed;

  const _GhostHeader({
    required this.scrollController,
    required this.isSendInFlight,
    required this.onMenuPressed,
    required this.onNewChatPressed,
    required this.workspaceLabel,
    required this.onWorkspacePressed,
    required this.onDebugCasesPressed,
    required this.onDebugInspectorPressed,
    required this.onDebugInspectorLongPressed,
  });

  @override
  State<_GhostHeader> createState() => _GhostHeaderState();
}

class _GhostHeaderState extends State<_GhostHeader> {
  @override
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;

    return AnimatedBuilder(
      animation: widget.scrollController,
      builder: (context, child) {
        final motion = ChatTopChromeMotion.fromScrollOffset(
          offset: (widget.scrollController.hasClients
                  ? widget.scrollController.offset
                  : 0)
              .toDouble(),
          transitionDistance: 40,
        );

        return Padding(
          padding: EdgeInsets.fromLTRB(
            spacing.lg,
            spacing.xxs,
            spacing.lg,
            0,
          ),
          child: SizedBox(
            key: const ValueKey('ghost-header'),
            height: 56,
            child: LayoutBuilder(
              builder: (context, constraints) {
                const iconButtonSize = 46.0;
                final rightButtonCount = 1 +
                    (widget.onDebugCasesPressed != null ? 1 : 0) +
                    (widget.onDebugInspectorPressed != null ? 1 : 0);
                final rightClusterWidth = rightButtonCount * iconButtonSize +
                    (rightButtonCount - 1) * (spacing.xxs + 2);
                final leftGap =
                    widget.workspaceLabel != null ? spacing.xs : 0.0;
                final workspaceButtonMaxWidth = widget.workspaceLabel == null
                    ? 0.0
                    : (constraints.maxWidth -
                            iconButtonSize -
                            rightClusterWidth -
                            leftGap -
                            spacing.sm)
                        .clamp(64.0, 132.0);
                final gatherInsetDx = 6 * motion.groupInsetProgress;
                final delayedWorkspaceDx = 3 * motion.centerSettleProgress;

                return Row(
                  key: const ValueKey('ghost-header-motion-host'),
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Padding(
                      key: const ValueKey('ghost-header-left-cluster'),
                      padding: EdgeInsets.only(left: gatherInsetDx),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ChatTopBarButton(
                            shellKey:
                                const ValueKey('header-menu-button-shell'),
                            buttonKey: const ValueKey('header-menu-button'),
                            icon: Icons.menu,
                            tooltip: '会话列表',
                            onPressed: widget.onMenuPressed,
                            motion: motion,
                            shadowSpec: const ChatHeaderButtonShadowSpec(
                              nearShadowAlpha: 0.13,
                              nearShadowBlur: 26,
                              nearShadowOffsetY: 10,
                              farShadowAlpha: 0.1,
                              farShadowBlur: 12,
                              farShadowOffsetY: 5,
                              highlightAlpha: 0.26,
                            ),
                          ),
                          if (widget.workspaceLabel != null) ...[
                            SizedBox(width: spacing.xs),
                            Transform.translate(
                              offset: Offset(-delayedWorkspaceDx, 0),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: workspaceButtonMaxWidth,
                                ),
                                child: ChatTopBarButton(
                                  shellKey: const ValueKey(
                                    'header-workspace-button-shell',
                                  ),
                                  buttonKey:
                                      const ValueKey('header-workspace-button'),
                                  tooltip: widget.workspaceLabel!,
                                  onPressed: widget.onWorkspacePressed,
                                  label: widget.workspaceLabel,
                                  width: workspaceButtonMaxWidth,
                                  motion: motion,
                                  shadowSpec: const ChatHeaderButtonShadowSpec(
                                    nearShadowAlpha: 0.09,
                                    nearShadowBlur: 20,
                                    nearShadowOffsetY: 7,
                                    farShadowAlpha: 0.06,
                                    farShadowBlur: 8,
                                    farShadowOffsetY: 3,
                                    highlightAlpha: 0.21,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Spacer(),
                    SizedBox(width: spacing.sm),
                    Padding(
                      key: const ValueKey('ghost-header-right-cluster'),
                      padding: EdgeInsets.only(right: gatherInsetDx),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ChatTopBarButton(
                            shellKey:
                                const ValueKey('header-new-chat-button-shell'),
                            buttonKey: const ValueKey('header-new-chat-button'),
                            icon: Icons.add,
                            tooltip: '新建对话',
                            onPressed: widget.isSendInFlight
                                ? null
                                : widget.onNewChatPressed,
                            motion: motion,
                            shadowSpec: const ChatHeaderButtonShadowSpec(
                              nearShadowAlpha: 0.11,
                              nearShadowBlur: 22,
                              nearShadowOffsetY: 8,
                              farShadowAlpha: 0.08,
                              farShadowBlur: 9,
                              farShadowOffsetY: 4,
                              highlightAlpha: 0.24,
                            ),
                          ),
                          if (widget.onDebugCasesPressed != null) ...[
                            SizedBox(width: spacing.xxs + 2),
                            ChatTopBarButton(
                              shellKey: const ValueKey(
                                'header-debug-cases-button-shell',
                              ),
                              buttonKey:
                                  const ValueKey('debug-test-cases-button'),
                              icon: Icons.science_outlined,
                              tooltip: '测试案例',
                              onPressed: widget.onDebugCasesPressed,
                              motion: motion,
                              shadowSpec: const ChatHeaderButtonShadowSpec(
                                nearShadowAlpha: 0.1,
                                nearShadowBlur: 21,
                                nearShadowOffsetY: 8,
                                farShadowAlpha: 0.07,
                                farShadowBlur: 9,
                                farShadowOffsetY: 4,
                                highlightAlpha: 0.23,
                              ),
                            ),
                          ],
                          if (widget.onDebugInspectorPressed != null) ...[
                            SizedBox(width: spacing.xxs + 2),
                            ChatTopBarButton(
                              shellKey: const ValueKey(
                                'header-debug-inspector-button-shell',
                              ),
                              buttonKey:
                                  const ValueKey('debug-turn-inspector-button'),
                              icon: Icons.bug_report_outlined,
                              tooltip: '调试检查器',
                              onPressed: widget.onDebugInspectorPressed,
                              onLongPress: widget.onDebugInspectorLongPressed,
                              motion: motion,
                              shadowSpec: const ChatHeaderButtonShadowSpec(
                                nearShadowAlpha: 0.1,
                                nearShadowBlur: 21,
                                nearShadowOffsetY: 8,
                                farShadowAlpha: 0.07,
                                farShadowBlur: 9,
                                farShadowOffsetY: 4,
                                highlightAlpha: 0.23,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
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

class _ScrollToBottomButton extends StatelessWidget {
  const _ScrollToBottomButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ChatTopBarButton(
      shellKey: const ValueKey('scroll-to-bottom-button-shell'),
      buttonKey: const ValueKey('scroll-to-bottom-button'),
      tooltip: '滑动到底部',
      onPressed: onPressed,
      icon: Icons.keyboard_arrow_down_rounded,
    );
  }
}
