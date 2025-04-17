import 'package:ai_chat/constants/route_constant.dart';
import 'package:ai_chat/widgets/about_dialog.dart';
import 'package:flutter/material.dart';

class ChatDrawer extends StatelessWidget {
  const ChatDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.white,
                  child: Icon(
                    Icons.chat,
                    size: 40,
                    color: Colors.blue,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'AI 助手',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                ListTile(
                  leading: const Icon(Icons.settings),
                  title: const Text('设置'),
                  onTap: () {
                    Navigator.pop(context); // 关闭抽屉
                    // 导航到设置页面
                    Navigator.pushNamed(context, RouteConstant.chatPage);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('历史记录'),
                  onTap: () {
                    Navigator.pop(context);
                    // TODO: 导航到历史记录页面
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.color_lens),
                  title: const Text('主题设置'),
                  onTap: () {
                    Navigator.pop(context);
                    // TODO: 打开主题设置
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('关于'),
                  onTap: () {
                    Navigator.pop(context);
                    // 显示关于对话框
                    showAboutAppDialog(context);
                  },
                ),
              ],
            ),
          ),
          // 底部版本信息
          Container(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Version 1.0.0',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
} 