import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/chat_providers.dart';
import '../widgets/chat_message_list.dart';
import '../widgets/chat_input.dart';
import '../widgets/chat_drawer.dart';

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
    // 只监听生成状态，用于App Bar的新建按钮禁用逻辑
    final isGenerating = ref.watch(isGeneratingProvider);
    final currentGroup = ref.watch(currentGroupProvider);
    final systemPrompt = ref.watch(systemPromptProvider);
    final isLoadingMore = ref.watch(isLoadingMoreProvider);
    
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
                title: const Text('小晨AI助手'),
                message: const Text('选择操作'),
                actions: [
                  CupertinoActionSheetAction(
                    child: Text(systemPrompt != null && systemPrompt.isNotEmpty
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
            onPressed: !isGenerating ? ref.read(chatControllerProvider).createNewGroup : null,
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
                  if (isLoadingMore)
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
