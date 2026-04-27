import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../providers/chat_providers.dart';
import '../widgets/chat_message_list.dart';
import '../widgets/chat_input.dart';
import '../widgets/chat_drawer.dart';
import '../widgets/debug/debug_test_case_sheet.dart';
import '../widgets/context_window/context_window_bottom_sheet.dart';
import '../widgets/tool_confirmation/tool_confirmation_bottom_bar.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key, required this.title});

  final String title;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    // 初始化加载数据
    Future.microtask(() => ref.read(chatControllerProvider).loadGroups());
  }

  @override
  Widget build(BuildContext context) {
    final sendPhase = ref.watch(sendPhaseProvider);
    final isSendInFlight = sendPhase != ChatSendPhase.idle;
    final systemPrompt = ref.watch(systemPromptProvider);
    final isLoadingMore = ref.watch(isLoadingMoreProvider);
    final pendingConfirmation = ref.watch(activePendingToolConfirmationProvider);
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final colors = Theme.of(context).extension<AppColors>()!;
    final chatController = ref.read(chatControllerProvider);

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
              child: Column(
                children: [
                  Expanded(
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
                      ],
                    ),
                  ),
                  if (pendingConfirmation != null)
                    ToolConfirmationBottomBar(
                      message: pendingConfirmation.message,
                      invocation: pendingConfirmation.invocation,
                      onContinue: () => chatController.confirmToolInvocation(
                        pendingConfirmation.message,
                      ),
                      onCancel: () => chatController.cancelToolInvocation(
                        pendingConfirmation.message,
                      ),
                      onContinueAndTrust: () =>
                          chatController.confirmToolInvocation(
                        pendingConfirmation.message,
                        trustTool: true,
                      ),
                    ),
                  ChatInput(
                    onContextWindowPressed: () {
                      unawaited(_showContextWindowSheet(context));
                    },
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
                  onMorePressed: () => _showHeaderActions(
                    context,
                    hasSystemPrompt:
                        systemPrompt != null && systemPrompt.isNotEmpty,
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
      backgroundColor: Theme.of(context).extension<AppColors>()!.chatBackground,
      builder: (sheetContext) => DebugTestCaseSheet(
        cases: library.allCases,
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
      backgroundColor: Theme.of(context).extension<AppColors>()!.chatBackground,
      builder: (_) => ContextWindowBottomSheet(snapshot: snapshot),
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

class _GhostHeader extends StatelessWidget {
  final bool isSendInFlight;
  final VoidCallback onMenuPressed;
  final VoidCallback onNewChatPressed;
  final VoidCallback? onDebugCasesPressed;
  final VoidCallback onMorePressed;

  const _GhostHeader({
    required this.isSendInFlight,
    required this.onMenuPressed,
    required this.onNewChatPressed,
    required this.onDebugCasesPressed,
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
    final colors = Theme.of(context).extension<AppColors>()!;
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
