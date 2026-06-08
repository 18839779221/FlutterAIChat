import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
              Positioned.fill(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Stack(
                        children: [
                          const ChatMessageList(),
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
                                        onContinue: () => chatController
                                            .confirmToolInvocation(
                                          pendingConfirmation.message,
                                        ),
                                        onCancel: () =>
                                            chatController.cancelToolInvocation(
                                          pendingConfirmation.message,
                                        ),
                                        onContinueAndTrust: () => chatController
                                            .confirmToolInvocation(
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
}

class _TopOverlayVeil extends StatelessWidget {
  const _TopOverlayVeil();

  // header 视觉区域高度（不含状态栏），用于决定遮罩淡出位置
  static const double _headerRegionHeight = 96;

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
              colors.chatBackground.withValues(alpha: 0.9),
              colors.chatBackground.withValues(alpha: 0.62),
              colors.chatBackground.withValues(alpha: 0),
            ],
            stops: [
              0,
              headerBottomFraction * 0.55,
              headerBottomFraction,
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

class _GhostHeader extends StatelessWidget {
  final bool isSendInFlight;
  final VoidCallback onMenuPressed;
  final VoidCallback onNewChatPressed;
  final String? workspaceLabel;
  final VoidCallback? onWorkspacePressed;
  final VoidCallback? onDebugCasesPressed;
  final VoidCallback? onDebugInspectorPressed;
  final VoidCallback? onDebugInspectorLongPressed;

  const _GhostHeader({
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
  Widget build(BuildContext context) {
    final spacing = Theme.of(context).extension<AppSpacing>()!;

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
                (onDebugCasesPressed != null ? 1 : 0) +
                (onDebugInspectorPressed != null ? 1 : 0);
            final rightClusterWidth = rightButtonCount * iconButtonSize +
                (rightButtonCount - 1) * (spacing.xxs + 2);
            final leftGap = workspaceLabel != null ? spacing.xs : 0.0;
            final workspaceButtonMaxWidth = workspaceLabel == null
                ? 0.0
                : (constraints.maxWidth -
                        iconButtonSize -
                        rightClusterWidth -
                        leftGap -
                        spacing.sm)
                    .clamp(64.0, 132.0);

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _HeaderButton(
                  shellKey: const ValueKey('header-menu-button-shell'),
                  buttonKey: const ValueKey('header-menu-button'),
                  icon: Icons.menu,
                  tooltip: '会话列表',
                  onPressed: onMenuPressed,
                  filled: true,
                ),
                if (workspaceLabel != null) ...[
                  SizedBox(width: spacing.xs),
                  ConstrainedBox(
                    constraints:
                        BoxConstraints(maxWidth: workspaceButtonMaxWidth),
                    child: _HeaderButton(
                      shellKey: const ValueKey('header-workspace-button-shell'),
                      buttonKey: const ValueKey('header-workspace-button'),
                      tooltip: workspaceLabel!,
                      onPressed: onWorkspacePressed,
                      label: workspaceLabel,
                      maxLabelWidth: workspaceButtonMaxWidth,
                    ),
                  ),
                ],
                const Spacer(),
                SizedBox(width: spacing.sm),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _HeaderButton(
                      shellKey: const ValueKey('header-new-chat-button-shell'),
                      icon: Icons.add,
                      tooltip: '新建对话',
                      onPressed: isSendInFlight ? null : onNewChatPressed,
                    ),
                    if (onDebugCasesPressed != null) ...[
                      SizedBox(width: spacing.xxs + 2),
                      _HeaderButton(
                        shellKey:
                            const ValueKey('header-debug-cases-button-shell'),
                        buttonKey: const ValueKey('debug-test-cases-button'),
                        icon: Icons.science_outlined,
                        tooltip: '测试案例',
                        onPressed: onDebugCasesPressed,
                      ),
                    ],
                    if (onDebugInspectorPressed != null) ...[
                      SizedBox(width: spacing.xxs + 2),
                      _HeaderButton(
                        shellKey: const ValueKey(
                          'header-debug-inspector-button-shell',
                        ),
                        buttonKey:
                            const ValueKey('debug-turn-inspector-button'),
                        icon: Icons.bug_report_outlined,
                        tooltip: '调试检查器',
                        onPressed: onDebugInspectorPressed,
                        onLongPress: onDebugInspectorLongPressed,
                      ),
                    ],
                  ],
                ),
              ],
            );
          },
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

class _HeaderButton extends StatefulWidget {
  final Key? shellKey;
  final Key? buttonKey;
  final String tooltip;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final bool filled;
  final IconData? icon;
  final String? label;
  final double? maxLabelWidth;

  const _HeaderButton({
    this.shellKey,
    this.buttonKey,
    required this.tooltip,
    required this.onPressed,
    this.onLongPress,
    this.filled = false,
    this.icon,
    this.label,
    this.maxLabelWidth,
  }) : assert(icon != null || label != null);

  bool get _isLabelButton => label != null;

  @override
  State<_HeaderButton> createState() => _HeaderButtonState();
}

class _HeaderButtonState extends State<_HeaderButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final isLabelButton = widget._isLabelButton;
    const iconButtonSize = 46.0;
    const labelButtonHeight = 46.0;
    final labelHorizontalPadding = spacing.sm + 1;
    final maxButtonWidth = widget.maxLabelWidth;
    final maxTextWidth = maxButtonWidth == null
        ? null
        : (maxButtonWidth - labelHorizontalPadding * 2 - 4).clamp(24.0, 240.0);

    final isActivePressed = _pressed && widget.onPressed != null;

    return AnimatedScale(
      scale: isActivePressed ? 0.92 : 1,
      duration: Duration(milliseconds: isActivePressed ? 90 : 240),
      curve: isActivePressed ? Curves.easeOutCubic : Curves.easeOutBack,
      child: Material(
        key: widget.shellKey,
        color: Colors.transparent,
        child: Tooltip(
          message: widget.tooltip,
          child: InkWell(
            key: widget.buttonKey,
            customBorder: isLabelButton
                ? RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(radius.pill),
                  )
                : const CircleBorder(),
            onTap: widget.onPressed,
            onLongPress: widget.onPressed == null ? null : widget.onLongPress,
            onHighlightChanged: (value) {
              if (_pressed != value) {
                setState(() {
                  _pressed = value;
                });
              }
            },
            child: AnimatedContainer(
              // 阴影承载层：位于 ClipRRect 之外，避免被裁剪，营造悬浮感。
              // 按下时阴影收缩下沉，与缩放联动形成"按入"体感。
              duration: Duration(milliseconds: isActivePressed ? 90 : 240),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                shape: isLabelButton ? BoxShape.rectangle : BoxShape.circle,
                borderRadius:
                    isLabelButton ? BorderRadius.circular(radius.pill) : null,
                boxShadow: [
                  // 远环境阴影：营造漂浮高度
                  BoxShadow(
                    color: colors.core.elevation.shadowColor
                        .withValues(alpha: isActivePressed ? 0.07 : 0.12),
                    blurRadius: isActivePressed ? 12 : 24,
                    spreadRadius: -2,
                    offset: Offset(0, isActivePressed ? 4 : 9),
                  ),
                  // 近接触阴影：定义边界
                  BoxShadow(
                    color: colors.core.elevation.shadowColor
                        .withValues(alpha: isActivePressed ? 0.06 : 0.09),
                    blurRadius: isActivePressed ? 6 : 10,
                    spreadRadius: -1,
                    offset: Offset(0, isActivePressed ? 2 : 4),
                  ),
                  // 顶部内白光高亮
                  BoxShadow(
                    color: colors.semantic.text.inverse.withValues(alpha: 0.24),
                    blurRadius: 6,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius.pill),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape:
                          isLabelButton ? BoxShape.rectangle : BoxShape.circle,
                      borderRadius: isLabelButton
                          ? BorderRadius.circular(radius.pill)
                          : null,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          colors.assistantSurface
                              .withValues(alpha: widget.filled ? 0.28 : 0.24),
                          colors.assistantSurface
                              .withValues(alpha: widget.filled ? 0.52 : 0.46),
                          colors.assistantSurface
                              .withValues(alpha: widget.filled ? 0.72 : 0.66),
                        ],
                        stops: const [0, 0.42, 1],
                      ),
                      border: Border.all(
                        // 边缘用内容同色系（暖白）而非纯白，营造内容色在边缘
                        // 折射聚集的连续感；纯白在浅暖背景上会割裂、显突兀。
                        color: colors.assistantSurface.withValues(
                          alpha: widget.filled ? 0.95 : 0.85,
                        ),
                        width: 1.5,
                      ),
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 110),
                      curve: Curves.easeOutCubic,
                      width: isLabelButton ? null : iconButtonSize,
                      height:
                          isLabelButton ? labelButtonHeight : iconButtonSize,
                      constraints: isLabelButton && maxButtonWidth != null
                          ? BoxConstraints(maxWidth: maxButtonWidth)
                          : null,
                      padding: EdgeInsets.symmetric(
                        horizontal: isLabelButton ? labelHorizontalPadding : 0,
                        vertical: 0,
                      ),
                      alignment: Alignment.center,
                      child: isLabelButton
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: maxTextWidth ?? 120,
                                    ),
                                    child: Text(
                                      widget.label!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      softWrap: false,
                                      style: TextStyle(
                                        color: widget.onPressed == null
                                            ? colors.secondaryText
                                                .withValues(alpha: 0.45)
                                            : colors.primaryText
                                                .withValues(alpha: 0.94),
                                        fontSize: 12.2,
                                        fontWeight: FontWeight.w600,
                                        height: 1.1,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Icon(
                              widget.icon,
                              size: 17.5,
                              color: widget.onPressed == null
                                  ? colors.secondaryText.withValues(alpha: 0.45)
                                  : colors.primaryText.withValues(alpha: 0.9),
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
}
