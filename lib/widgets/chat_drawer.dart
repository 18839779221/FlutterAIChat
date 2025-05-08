import 'package:ai_chat/constants/route_constant.dart';
import 'package:ai_chat/widgets/about_dialog.dart';
import 'package:ai_chat/models/chat_group.dart';
import 'package:flutter/material.dart';

class ChatDrawer extends StatelessWidget {
  final List<ChatGroup> groups;
  final ChatGroup? currentGroup;
  final Function(ChatGroup) onGroupSelected;
  final Function() onNewGroup;

  const ChatDrawer({
    super.key,
    required this.groups,
    this.currentGroup,
    required this.onGroupSelected,
    required this.onNewGroup,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    
    return Drawer(
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(
              16,
              MediaQuery.of(context).padding.top + 16,
              16,
              16,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.primaryColor,
                  theme.primaryColor.withOpacity(0.8),
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 头像和名称容器
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.white,
                          child: Icon(
                            Icons.chat_bubble_outline,
                            color: Colors.blue,
                            size: 28,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'AI 助手',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '随时为您服务',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 14,
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
          // 新建分组按钮
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onNewGroup,
                icon: const Icon(Icons.add),
                label: const Text('新建对话'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          // 分组列表
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: groups.length,
              itemBuilder: (context, index) {
                final group = groups[index];
                final isSelected = currentGroup?.id == group.id;
                
                return ListTile(
                  leading: Icon(
                    Icons.chat_bubble_outline,
                    color: isSelected ? theme.primaryColor : Colors.grey[600],
                  ),
                  title: Text(
                    group.title,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? theme.primaryColor : null,
                    ),
                  ),
                  subtitle: Text(
                    '最后消息：${_formatDateTime(group.lastMessageAt)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  selected: isSelected,
                  onTap: () => onGroupSelected(group),
                );
              },
            ),
          ),
          // 底部版本信息
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Version 1.0.0',
                    style: TextStyle(
                      color: theme.primaryColor,
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