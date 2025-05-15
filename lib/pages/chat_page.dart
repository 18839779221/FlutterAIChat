import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_state_provider.dart';
import '../widgets/chat_message_list.dart';
import '../widgets/chat_input.dart';
import '../widgets/chat_drawer.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.title});

  final String title;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatStateProvider>(
      builder: (context, chatState, _) {
        return Scaffold(
          key: _scaffoldKey,
          drawer: const ChatDrawer(),
          appBar: AppBar(
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            leading: IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () {
                _scaffoldKey.currentState?.openDrawer();
              },
            ),
            title: GestureDetector(
              onTap: () {
                showCupertinoModalPopup(
                  context: context,
                  builder: (context) => CupertinoActionSheet(
                    title: const Text('AI Chat'),
                    message: const Text('选择操作'),
                    actions: [
                      CupertinoActionSheetAction(
                        child: Text(chatState.systemPrompt != null && chatState.systemPrompt!.isNotEmpty 
                          ? '修改系统提示词' 
                          : '设置系统提示词'),
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
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.title),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down, size: 20),
                ],
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: '新建对话',
                onPressed: !chatState.isGenerating ? chatState.createNewGroup : null,
              ),
            ],
          ),
          body: GestureDetector(
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity! > 0) {
                _scaffoldKey.currentState?.openDrawer();
              }
            },
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      const ChatMessageList(),
                      if (chatState.isLoadingMore)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: LinearProgressIndicator(
                            backgroundColor: Colors.transparent,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).primaryColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, -1),
                      ),
                    ],
                  ),
                  child: const ChatInput(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSystemPromptDialog(BuildContext context) {
    final chatState = Provider.of<ChatStateProvider>(context, listen: false);
    
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('系统提示词'),
        content: Padding(
          padding: const EdgeInsets.only(top: 16.0),
          child: CupertinoTextField(
            controller: TextEditingController(text: chatState.systemPrompt),
            placeholder: '输入系统提示词...',
            maxLines: 5,
            minLines: 3,
            onChanged: (value) {
              chatState.setSystemPrompt(value);
            },
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            child: const Text('确定'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}
