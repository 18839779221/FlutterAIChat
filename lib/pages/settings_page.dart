import 'package:flutter/material.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isDarkMode = false;
  bool _autoShowKeyboard = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('深色模式'),
            subtitle: const Text('切换应用主题'),
            value: _isDarkMode,
            onChanged: (bool value) {
              setState(() {
                _isDarkMode = value;
              });
              // TODO: 实现主题切换
            },
          ),
          SwitchListTile(
            title: const Text('自动显示键盘'),
            subtitle: const Text('打开聊天页面时自动显示键盘'),
            value: _autoShowKeyboard,
            onChanged: (bool value) {
              setState(() {
                _autoShowKeyboard = value;
              });
              // TODO: 保存设置
            },
          ),
          ListTile(
            title: const Text('清除缓存'),
            subtitle: const Text('清除应用缓存数据'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              // TODO: 实现清除缓存
            },
          ),
        ],
      ),
    );
  }
} 