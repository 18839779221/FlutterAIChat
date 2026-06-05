import 'package:ai_chat/constants/route_constant.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/chat_turn.dart';
import '../providers/chat_providers.dart';
import '../services/workspace/workspace_binding_service.dart';

class ChatDrawer extends ConsumerWidget {
  const ChatDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 获取所需状态
    final groups = ref.watch(groupsProvider);
    final currentGroup = ref.watch(currentGroupProvider);
    final sendPhase = ref.watch(sendPhaseProvider);
    final isSendInFlight = sendPhase != ChatSendPhase.idle;

    // 获取控制器
    final chatController = ref.read(chatControllerProvider);

    final ThemeData theme = Theme.of(context);
    final colors = theme.extension<AppThemeSpec>()!;
    final spacing = theme.extension<AppSpacing>()!;
    final radius = theme.extension<AppRadius>()!;
    final showDraftGroup = currentGroup != null && currentGroup.id == null;
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final isWideScreen = mediaQuery.size.shortestSide >= 600;
    final drawerWidth = screenWidth * (isWideScreen ? 0.4 : 0.8);
    final workspaceBindingService = WorkspaceBindingService();
    final workspaceChoices = _workspaceChoices(
      workspaceBindingService: workspaceBindingService,
      currentWorkspaceId: currentGroup?.workspaceId,
      groups: groups,
    );
    final resolvedWorkspace = currentGroup == null
        ? null
        : workspaceBindingService.resolveWorkspaceId(currentGroup.workspaceId);

    return Drawer(
      width: drawerWidth,
      backgroundColor: colors.settingsPanelBackground,
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  spacing.lg,
                  spacing.lg,
                  spacing.lg,
                  spacing.md,
                ),
                children: [
                  Text(
                    'AI 助手',
                    style: TextStyle(
                      color: colors.primaryText,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      height: 1.05,
                    ),
                  ),
                  SizedBox(height: spacing.lg),
                  _WorkspaceSwitcherCard(
                    title: '工作区',
                    subtitle:
                        resolvedWorkspace == null || resolvedWorkspace.isDefault
                            ? '默认'
                            : resolvedWorkspace.workspaceId,
                    onTap: currentGroup == null || isSendInFlight
                        ? null
                        : () async {
                            final selected = await showModalBottomSheet<String>(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: colors.chatBackground,
                              builder: (sheetContext) => _WorkspacePickerSheet(
                                title: '工作区',
                                items: workspaceChoices,
                                currentWorkspaceId: resolvedWorkspace
                                        ?.workspaceId ??
                                    workspaceBindingService.defaultWorkspaceId,
                                labelBuilder: (workspaceId) => _workspaceLabel(
                                  workspaceBindingService,
                                  workspaceId,
                                ),
                              ),
                            );
                            if (selected == null) {
                              return;
                            }
                            final nextWorkspaceId = selected ==
                                    workspaceBindingService.defaultWorkspaceId
                                ? null
                                : selected;
                            await chatController.updateCurrentGroupWorkspace(
                              nextWorkspaceId,
                            );
                            if (context.mounted) {
                              Navigator.of(context).pop();
                            }
                          },
                  ),
                  SizedBox(height: spacing.lg),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed:
                          isSendInFlight ? null : chatController.createNewGroup,
                      icon: const Icon(Icons.add),
                      label: const Text('新建对话'),
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: spacing.md),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(radius.md),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: spacing.lg),
                  ...List.generate(groups.length + (showDraftGroup ? 1 : 0), (
                    index,
                  ) {
                    if (index == 0 && showDraftGroup) {
                      return _DrawerGroupTile(
                        title: currentGroup.title,
                        subtitle: '新对话',
                        providerLabel:
                            _providerLabel(currentGroup.lockedProviderStyle),
                        isSelected: true,
                        enabled: false,
                      );
                    }

                    final adjustedIndex = showDraftGroup ? index - 1 : index;
                    final group = groups[adjustedIndex];
                    final isSelected = currentGroup?.id == group.id;

                    return _DrawerGroupTile(
                      title: group.title,
                      subtitle: '最后消息：${_formatDateTime(group.lastMessageAt)}',
                      providerLabel: _providerLabel(group.lockedProviderStyle),
                      isSelected: isSelected,
                      enabled: !isSendInFlight,
                      onTap: isSendInFlight
                          ? null
                          : () {
                              chatController.selectGroup(group);
                              Navigator.pop(context);
                            },
                      onLongPress: isSendInFlight
                          ? null
                          : () {
                              showCupertinoDialog(
                                context: context,
                                builder: (context) => CupertinoAlertDialog(
                                  title: const Text('删除对话'),
                                  content: Text(
                                    '确定要删除"${group.title}"吗？此操作不可恢复。',
                                  ),
                                  actions: [
                                    CupertinoDialogAction(
                                      child: const Text('取消'),
                                      onPressed: () => Navigator.pop(context),
                                    ),
                                    CupertinoDialogAction(
                                      isDestructiveAction: true,
                                      child: const Text('删除'),
                                      onPressed: () {
                                        Navigator.pop(context);
                                        chatController.deleteGroup(group.id!);
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                    );
                  }),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.lg,
                spacing.sm,
                spacing.lg,
                spacing.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Material(
                          color: colors.assistantSurface,
                          borderRadius: BorderRadius.circular(radius.md),
                          child: ListTile(
                            leading: Icon(
                              Icons.settings_outlined,
                              color: colors.secondaryText,
                            ),
                            title: Text(
                              '设置',
                              style: TextStyle(color: colors.primaryText),
                            ),
                            enabled: !isSendInFlight,
                            onTap: isSendInFlight
                                ? null
                                : () {
                                    Navigator.pop(context);
                                    Navigator.pushNamed(
                                      context,
                                      RouteConstant.settingsPage,
                                    );
                                  },
                          ),
                        ),
                      ),
                      SizedBox(width: spacing.sm),
                      Material(
                        color: colors.assistantSurface,
                        borderRadius: BorderRadius.circular(radius.md),
                        child: IconButton(
                          icon: Icon(
                            Icons.bug_report_outlined,
                            color: colors.secondaryText,
                          ),
                          tooltip: '调试中心',
                          onPressed: isSendInFlight
                              ? null
                              : () {
                                  Navigator.pop(context);
                                  Navigator.pushNamed(
                                    context,
                                    RouteConstant.debugHubPage,
                                  );
                                },
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: spacing.md),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: spacing.md,
                      vertical: spacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: colors.structuredSurface,
                      borderRadius: BorderRadius.circular(radius.pill),
                      boxShadow: [
                        BoxShadow(
                          color: colors.primaryText.withValues(alpha: 0.035),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      'Version 1.0.0',
                      style: TextStyle(
                        color: colors.secondaryText,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _workspaceChoices({
    required WorkspaceBindingService workspaceBindingService,
    required String? currentWorkspaceId,
    required List<dynamic> groups,
  }) {
    final values = <String>[workspaceBindingService.defaultWorkspaceId];
    final seen = <String>{workspaceBindingService.defaultWorkspaceId};
    for (final group in groups) {
      final workspaceId = group.workspaceId?.trim();
      if (workspaceId == null ||
          workspaceId.isEmpty ||
          !seen.add(workspaceId)) {
        continue;
      }
      values.add(workspaceId);
    }
    final currentWorkspace = currentWorkspaceId?.trim();
    if (currentWorkspace != null &&
        currentWorkspace.isNotEmpty &&
        seen.add(currentWorkspace)) {
      values.add(currentWorkspace);
    }
    return values;
  }

  String _workspaceLabel(
    WorkspaceBindingService workspaceBindingService,
    String workspaceId,
  ) {
    return workspaceId == workspaceBindingService.defaultWorkspaceId
        ? 'Default workspace'
        : workspaceId;
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}天前';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}小时前';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}分钟前';
    } else {
      return '刚刚';
    }
  }

  String _providerLabel(ChatTurnProviderStyle style) {
    switch (style) {
      case ChatTurnProviderStyle.anthropicMessages:
        return 'Claude';
      case ChatTurnProviderStyle.openaiResponses:
        return 'GPT';
      case ChatTurnProviderStyle.openaiChatCompletions:
        return 'DeepSeek';
    }
  }
}

class _WorkspaceSwitcherCard extends StatelessWidget {
  const _WorkspaceSwitcherCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppThemeSpec>()!;
    final spacing = theme.extension<AppSpacing>()!;
    final radius = theme.extension<AppRadius>()!;

    return Material(
      color: colors.assistantSurface,
      borderRadius: BorderRadius.circular(radius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius.lg),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: spacing.md,
            vertical: spacing.md,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius.lg),
            border: Border.all(color: colors.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.structuredSurface,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: colors.primaryText.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.folder_open_outlined,
                  size: 18,
                  color: colors.secondaryText,
                ),
              ),
              SizedBox(width: spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: colors.primaryText,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: spacing.xxs),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: colors.secondaryText,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerGroupTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String providerLabel;
  final bool isSelected;
  final bool enabled;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _DrawerGroupTile({
    required this.title,
    required this.subtitle,
    required this.providerLabel,
    required this.isSelected,
    required this.enabled,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return Padding(
      padding:
          EdgeInsets.symmetric(horizontal: spacing.md, vertical: spacing.xxs),
      child: Material(
        color: isSelected
            ? colors.toolWorkflowSurface
            : colors.assistantSurface.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(radius.md),
        shadowColor: Colors.transparent,
        elevation: isSelected ? 0 : 0,
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius.md),
          ),
          tileColor: isSelected
              ? colors.toolWorkflowSurface
              : colors.assistantSurface.withValues(alpha: 0.58),
          leading: Icon(
            Icons.chat_bubble_outline,
            color: isSelected ? colors.primaryText : colors.secondaryText,
          ),
          title: Text(
            title,
            style: TextStyle(
              color: colors.primaryText,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Row(
            children: [
              Flexible(
                child: Text(
                  subtitle,
                  style: TextStyle(
                    color: colors.secondaryText,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: spacing.xs),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: spacing.xs,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: colors.structuredSurface,
                  borderRadius: BorderRadius.circular(radius.sm),
                ),
                child: Text(
                  providerLabel,
                  style: TextStyle(
                    color: colors.secondaryText,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          enabled: enabled,
          onTap: onTap,
          onLongPress: onLongPress,
        ),
      ),
    );
  }
}

class _WorkspacePickerSheet extends StatelessWidget {
  const _WorkspacePickerSheet({
    required this.title,
    required this.items,
    required this.currentWorkspaceId,
    required this.labelBuilder,
  });

  final String title;
  final List<String> items;
  final String currentWorkspaceId;
  final String Function(String workspaceId) labelBuilder;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: colors.primaryText,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: spacing.md),
            ...items.map(
              (workspaceId) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(labelBuilder(workspaceId)),
                trailing: workspaceId == currentWorkspaceId
                    ? Icon(
                        Icons.check_circle_rounded,
                        color: colors.workflowRunning,
                      )
                    : null,
                onTap: () => Navigator.of(context).pop(workspaceId),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
