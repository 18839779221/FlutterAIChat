import 'package:ai_chat/constants/route_constant.dart';
import 'package:ai_chat/theme/app_colors.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/chat_providers.dart';

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
    final colors = theme.extension<AppColors>()!;
    final spacing = theme.extension<AppSpacing>()!;
    final radius = theme.extension<AppRadius>()!;
    final showDraftGroup = currentGroup != null && currentGroup.id == null;

    return Drawer(
      backgroundColor: colors.settingsPanelBackground,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(
              spacing.lg,
              MediaQuery.of(context).padding.top + spacing.lg,
              spacing.lg,
              spacing.lg,
            ),
            decoration: BoxDecoration(
              color: colors.assistantSurface,
              boxShadow: [
                BoxShadow(
                  color: colors.primaryText.withValues(alpha: 0.07),
                  blurRadius: 20,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: EdgeInsets.all(spacing.sm),
                        decoration: BoxDecoration(
                          color: colors.structuredSurface,
                          borderRadius: BorderRadius.circular(radius.md),
                          boxShadow: [
                            BoxShadow(
                              color: colors.primaryText.withValues(alpha: 0.08),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.chat_bubble_outline,
                          color: colors.primaryText,
                          size: 20,
                        ),
                      ),
                      SizedBox(width: spacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'AI 助手',
                              style: TextStyle(
                                color: colors.primaryText,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: spacing.xxs),
                            Text(
                              '继续当前对话，或从新的任务开始',
                              style: TextStyle(
                                color: colors.secondaryText,
                                fontSize: 13,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(spacing.lg),
            child: SizedBox(
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
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.symmetric(horizontal: spacing.sm),
              itemCount: groups.length + (showDraftGroup ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == 0 && showDraftGroup) {
                  return _DrawerGroupTile(
                    title: currentGroup.title,
                    subtitle: '新对话',
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
                              content: Text('确定要删除"${group.title}"吗？此操作不可恢复。'),
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
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              spacing.md,
              spacing.sm,
              spacing.md,
              0,
            ),
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
                            context, RouteConstant.settingsPage);
                      },
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(spacing.lg),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
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
    );
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
}

class _DrawerGroupTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isSelected;
  final bool enabled;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _DrawerGroupTile({
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.enabled,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return Padding(
      padding:
          EdgeInsets.symmetric(horizontal: spacing.md, vertical: spacing.xxs),
      child: Material(
        color: isSelected
            ? colors.toolWorkflowSurface
            : Colors.white.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(radius.md),
        shadowColor: Colors.transparent,
        elevation: isSelected ? 0 : 0,
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius.md),
          ),
          tileColor: isSelected
              ? colors.toolWorkflowSurface
              : Colors.white.withValues(alpha: 0.58),
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
          subtitle: Text(
            subtitle,
            style: TextStyle(
              color: colors.secondaryText,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          enabled: enabled,
          onTap: onTap,
          onLongPress: onLongPress,
        ),
      ),
    );
  }
}
