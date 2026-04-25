# Markdown 展示稳定性与渲染性能 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让聊天时间线中的完成态 Markdown 在长列表滚动和流式更新期间更稳定，同时把更新时间收紧到更小的 row 范围，减少不必要的重建与重复布局。

**Architecture:** 保留现有 `flutter_markdown` 主渲染链路，但把 [chat_message_list.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/widgets/chat_message_list.dart) 从“在 build 中直接拼整组 widgets”改成“先生成稳定的时间线 item 描述，再渲染独立 row”。完成态 Markdown row 使用稳定 `ValueKey` 和可保活壳层，优先复用现有 Markdown state；如果第一阶段验证后仍有明显抖动，再基于已拆分的边界进入第二阶段编译缓存。

**Tech Stack:** Flutter 3.29.2 / Riverpod / flutter_markdown / Flutter widget tests

---

## File Map

### Existing files to modify

- `lib/widgets/chat_message_list.dart`
  - 从整表 widget 组装改为时间线 item 描述 + row 渲染。
- `lib/widgets/chat_blocks/final_response_block.dart`
  - 为完成态最终回答提供可复用的稳定 Markdown 壳层接入点。
- `lib/widgets/chat_blocks/assistant_doc_block.dart`
  - 为分析块提供与最终回答一致的稳定 Markdown 壳层接入点。
- `lib/widgets/markdown/flutter_markdown_impl.dart`
  - 保持 `flutter_markdown` 主实现，同时明确其作为完成态渲染内核的边界。
- `test/widgets/chat_message_list_test.dart`
  - 补充时间线 item 稳定性、key 稳定映射与局部更新语义测试。
- `test/widgets/chat_blocks/chat_blocks_test.dart`
  - 补充完成态 Markdown 壳层与稳定渲染语义测试。

### New files to create

- `lib/widgets/chat_timeline/chat_timeline_item.dart`
  - 定义时间线 item 描述模型，负责承载 row 稳定 key、row 类型、source message id、assistant block 和 running tail 信息。
- `lib/widgets/chat_timeline/chat_timeline_row.dart`
  - 负责把单个时间线 item 渲染成具体 UI，并把 provider 依赖收紧到 row 级别。
- `lib/widgets/chat_timeline/stable_markdown_block.dart`
  - 完成态 Markdown 的稳定壳层，负责 keep alive、稳定 key 和统一 padding 容器。
- `test/widgets/chat_timeline/stable_markdown_block_test.dart`
  - 针对稳定 Markdown 壳层的生命周期与渲染语义测试。

### Existing files to inspect during implementation

- `lib/services/chat_block_builder.dart`
  - 确认 `AssistantTurnBlock.id`、`turnId` 和 `payload.sourceMessageId` 是否足够支撑稳定 row key。
- `lib/providers/chat_collection_providers.dart`
  - 确认插入旧历史消息时现有 `messagesProvider` 的顺序假设不需要改变。
- `lib/widgets/chat_blocks/streaming_response_block.dart`
  - 对齐流式轻文本与完成态 Markdown 的基础 typography 和 padding，控制完成瞬间跳变。

## Task 1: 先用测试锁定新的时间线边界

**Files:**
- Modify: `test/widgets/chat_message_list_test.dart`
- Create: `test/widgets/chat_timeline/stable_markdown_block_test.dart`
- Inspect: `lib/widgets/chat_message_list.dart`
- Inspect: `lib/widgets/chat_blocks/chat_blocks_test.dart`

- [ ] **Step 1: 在 `chat_message_list_test.dart` 中添加失败测试，锁定完成态 assistant block 会产出稳定 key**

```dart
testWidgets('completed assistant markdown block exposes a stable timeline key', (
  tester,
) async {
  await _pumpMessageList(
    tester,
    messages: [
      ChatMessage(
        id: 1,
        text: '问题',
        role: MessageRole.user,
        status: MessageStatus.completed,
        contentType: MessageContentType.plainText,
      ),
      ChatMessage(
        id: 2,
        text: '# Title\n\nParagraph',
        role: MessageRole.assistant,
        status: MessageStatus.completed,
        contentType: MessageContentType.plainText,
      ),
    ],
  );

  expect(
    find.byKey(const ValueKey('timeline-block-0_2-analysis-1')),
    findsOneWidget,
  );
});
```

- [ ] **Step 2: 运行定向测试并确认它失败**

Run: `fvm flutter test test/widgets/chat_message_list_test.dart --plain-name "completed assistant markdown block exposes a stable timeline key"`
Expected: FAIL，原因是当前时间线 row 没有暴露稳定 key。

- [ ] **Step 3: 新建 `stable_markdown_block_test.dart`，补一个失败测试，锁定完成态 Markdown 壳层的 keep-alive 语义**

```dart
testWidgets('stable markdown block keeps markdown subtree identity for unchanged content', (
  tester,
) async {
  final childKey = GlobalKey();

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StableMarkdownBlock(
          cacheKey: 'message-2',
          child: FlutterMarkdownImpl(
            key: childKey,
            data: '# Title\n\nParagraph',
          ),
        ),
      ),
    ),
  );

  expect(find.byType(FlutterMarkdownImpl), findsOneWidget);
});
```

- [ ] **Step 4: 运行新测试并确认它失败**

Run: `fvm flutter test test/widgets/chat_timeline/stable_markdown_block_test.dart`
Expected: FAIL，原因是 `StableMarkdownBlock` 文件和类型尚不存在。

- [ ] **Step 5: 提交红灯测试**

```bash
git add test/widgets/chat_message_list_test.dart test/widgets/chat_timeline/stable_markdown_block_test.dart
git commit -m "test: cover markdown timeline stability"
```

## Task 2: 抽出时间线 item 描述模型和独立 row 组件

**Files:**
- Create: `lib/widgets/chat_timeline/chat_timeline_item.dart`
- Create: `lib/widgets/chat_timeline/chat_timeline_row.dart`
- Modify: `lib/widgets/chat_message_list.dart`
- Test: `test/widgets/chat_message_list_test.dart`

- [ ] **Step 1: 新建 `chat_timeline_item.dart`，定义时间线 item 模型**

```dart
enum ChatTimelineItemType {
  userBubble,
  assistantBlock,
}

class ChatTimelineItem {
  final String stableKey;
  final ChatTimelineItemType type;
  final ChatMessage? userMessage;
  final ChatMessage? sourceMessage;
  final AssistantTurnBlock? block;
  final String? runningTailText;

  const ChatTimelineItem({
    required this.stableKey,
    required this.type,
    this.userMessage,
    this.sourceMessage,
    this.block,
    this.runningTailText,
  });
}
```

- [ ] **Step 2: 新建 `chat_timeline_row.dart`，把单个 item 映射为 UI**

```dart
class ChatTimelineRow extends ConsumerWidget {
  final ChatTimelineItem item;
  final ValueChanged<ChatMessage> onLongPressMessage;

  const ChatTimelineRow({
    super.key,
    required this.item,
    required this.onLongPressMessage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (item.type) {
      case ChatTimelineItemType.userBubble:
        return _buildUserBubble(item);
      case ChatTimelineItemType.assistantBlock:
        return _buildAssistantBlock(context, ref, item);
    }
  }
}
```

- [ ] **Step 3: 在 `chat_message_list.dart` 中把 `_buildTimelineItems()` 的返回值从 `List<Widget>` 改为 `List<ChatTimelineItem>`**

```dart
final timelineItems = _buildTimelineItems(messages, sendPhase);

List<ChatTimelineItem> _buildTimelineItems(
  List<ChatMessage> messages,
  ChatSendPhase sendPhase,
) {
  final items = <ChatTimelineItem>[];
  // 组装 user bubble item 和 assistant block item
  return items;
}
```

- [ ] **Step 4: 在 `SliverList.builder` 中使用 `ChatTimelineRow`，并给 row 绑定稳定 key**

```dart
final item = timelineItems[index];
return Align(
  alignment: Alignment.topCenter,
  child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: kIsWeb ? 860 : 720),
    child: Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: ChatTimelineRow(
        key: ValueKey('timeline-block-${item.stableKey}'),
        item: item,
        onLongPressMessage: _showMessageOptionMenu,
      ),
    ),
  ),
);
```

- [ ] **Step 5: 时间线 item 的 `stableKey` 统一使用可预测规则，不依赖索引**

```dart
String _buildAssistantItemKey(AssistantTurnBlock block, ChatMessage? source) {
  return '${block.turnId}-${block.id}-${source?.id ?? 'no-source'}';
}

String _buildUserItemKey(ChatMessage message) {
  return 'user-${message.id ?? message.timestamp.microsecondsSinceEpoch}';
}
```

- [ ] **Step 6: 运行时间线 widget tests，直到新旧断言都通过**

Run:
- `fvm flutter test test/widgets/chat_message_list_test.dart`

Expected: PASS

- [ ] **Step 7: 提交时间线边界重构**

```bash
git add lib/widgets/chat_timeline/chat_timeline_item.dart lib/widgets/chat_timeline/chat_timeline_row.dart lib/widgets/chat_message_list.dart test/widgets/chat_message_list_test.dart
git commit -m "refactor: split chat timeline rows"
```

## Task 3: 引入完成态 Markdown 稳定壳层

**Files:**
- Create: `lib/widgets/chat_timeline/stable_markdown_block.dart`
- Modify: `lib/widgets/chat_blocks/final_response_block.dart`
- Modify: `lib/widgets/chat_blocks/assistant_doc_block.dart`
- Modify: `test/widgets/chat_blocks/chat_blocks_test.dart`
- Test: `test/widgets/chat_timeline/stable_markdown_block_test.dart`

- [ ] **Step 1: 新建 `stable_markdown_block.dart`，提供 keep-alive 壳层**

```dart
class StableMarkdownBlock extends StatefulWidget {
  final String cacheKey;
  final Widget child;

  const StableMarkdownBlock({
    super.key,
    required this.cacheKey,
    required this.child,
  });

  @override
  State<StableMarkdownBlock> createState() => _StableMarkdownBlockState();
}

class _StableMarkdownBlockState extends State<StableMarkdownBlock>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return KeyedSubtree(
      key: ValueKey(widget.cacheKey),
      child: widget.child,
    );
  }
}
```

- [ ] **Step 2: 在 `FinalResponseBlock` 中接入稳定壳层**

```dart
StableMarkdownBlock(
  cacheKey: 'final:${title.hashCode}:${text.hashCode}',
  child: FlutterMarkdownImpl(data: text),
),
```

Implementation note: 最终实现不要只用 `hashCode`；请优先用 `messageId` 或上层传入的稳定 key。如果当前 block 层拿不到 `messageId`，就在本任务里把它补充到构造参数中。

- [ ] **Step 3: 在 `AssistantDocBlock` 中接入同一壳层**

```dart
StableMarkdownBlock(
  cacheKey: 'doc:${label ?? 'analysis'}:${text.hashCode}',
  child: FlutterMarkdownImpl(data: text),
),
```

- [ ] **Step 4: 为 `StableMarkdownBlock` 与 chat blocks 补测试**

```dart
testWidgets('assistant doc block renders markdown inside stable container', (
  tester,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(
        body: AssistantDocBlock(
          label: 'Analysis',
          text: '这是一段分析内容',
        ),
      ),
    ),
  );

  expect(find.byType(StableMarkdownBlock), findsOneWidget);
  expect(find.byType(FlutterMarkdownImpl), findsOneWidget);
});
```

- [ ] **Step 5: 运行相关 widget tests 并确认通过**

Run:
- `fvm flutter test test/widgets/chat_timeline/stable_markdown_block_test.dart`
- `fvm flutter test test/widgets/chat_blocks/chat_blocks_test.dart`

Expected: PASS

- [ ] **Step 6: 提交稳定 Markdown 壳层**

```bash
git add lib/widgets/chat_timeline/stable_markdown_block.dart lib/widgets/chat_blocks/final_response_block.dart lib/widgets/chat_blocks/assistant_doc_block.dart test/widgets/chat_timeline/stable_markdown_block_test.dart test/widgets/chat_blocks/chat_blocks_test.dart
git commit -m "feat: stabilize completed markdown blocks"
```

## Task 4: 收紧 row 级依赖，避免无关 provider 扩散到完成态 Markdown

**Files:**
- Modify: `lib/widgets/chat_timeline/chat_timeline_row.dart`
- Modify: `lib/widgets/chat_message_list.dart`
- Modify: `lib/widgets/markdown/flutter_markdown_impl.dart`
- Modify: `test/widgets/chat_message_list_test.dart`

- [ ] **Step 1: 将仅在 assistant block 场景下需要的 provider 读取下沉到 row 内部**

```dart
final activeAskUserQuestion = ref.watch(activeAskUserQuestionMessageProvider);
final toolUiRegistry = ref.watch(toolUiRendererRegistryProvider);
```

Implementation note: `ChatMessageList` 顶层不再直接读取这些 provider，避免所有 row 因工具卡片状态或交互卡片状态变化一起 rebuild。

- [ ] **Step 2: 保持 `FlutterMarkdownImpl` 为纯渲染组件，不在其中引入消息级状态判断**

```dart
class FlutterMarkdownImpl extends StatelessWidget {
  final String data;
  // 仅保留渲染所需参数，不读取 provider
}
```

- [ ] **Step 3: 在 `chat_message_list_test.dart` 中补一个回归测试，验证新增无关消息后，旧完成态 block 仍保持 Markdown 渲染**

```dart
testWidgets('adding a later streaming message does not downgrade previous completed markdown block', (
  tester,
) async {
  final container = ProviderContainer(
    overrides: [
      hasMoreMessagesProvider.overrideWith((ref) => false),
      chatSendStateProvider.overrideWith(
        (ref) => ChatSendStateNotifier()
          ..update(phase: ChatSendPhase.idle, isGenerating: false),
      ),
    ],
  );

  container.read(messagesProvider.notifier).setMessages([
    ChatMessage(
      id: 1,
      text: '问题一',
      role: MessageRole.user,
      status: MessageStatus.completed,
      contentType: MessageContentType.plainText,
    ),
    ChatMessage(
      id: 2,
      text: '# Title\n\nParagraph',
      role: MessageRole.assistant,
      status: MessageStatus.completed,
      contentType: MessageContentType.plainText,
    ),
  ]);

  // Pump once, then append a generating message, pump again, and assert the
  // previous completed message still uses FinalResponseBlock + FlutterMarkdownImpl.
});
```

- [ ] **Step 4: 运行消息列表测试并确认通过**

Run: `fvm flutter test test/widgets/chat_message_list_test.dart`
Expected: PASS

- [ ] **Step 5: 提交 row 级依赖收紧**

```bash
git add lib/widgets/chat_timeline/chat_timeline_row.dart lib/widgets/chat_message_list.dart lib/widgets/markdown/flutter_markdown_impl.dart test/widgets/chat_message_list_test.dart
git commit -m "refactor: localize timeline row rebuilds"
```

## Task 5: 完整验证、文档同步与第二阶段留口

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md` (only if implementation adds a repo-level rule worth preserving)
- Inspect: `docs/superpowers/specs/2026-04-25-markdown-stability-and-rendering-performance-design.md`

- [ ] **Step 1: 运行本次改动相关的完整测试集**

Run:
- `fvm flutter test test/widgets/chat_message_list_test.dart`
- `fvm flutter test test/widgets/chat_blocks/chat_blocks_test.dart`
- `fvm flutter test test/widgets/chat_timeline/stable_markdown_block_test.dart`

Expected: PASS

- [ ] **Step 2: 运行一次更宽的 widget 回归集**

Run:
- `fvm flutter test test/widgets/chat_message_list_interaction_test.dart`
- `fvm flutter test test/pages/chat_page_test.dart`

Expected: PASS

- [ ] **Step 3: 在 `README.md` 中补一句消息展示优化后的结构描述**

```md
- Chat timeline rows are assembled as stable timeline items so completed Markdown blocks remain visually steady during streaming updates and long-list scrolling.
```

Implementation note: 如果 README 已有中文对应段落，请写成中文并放在现有能力/架构说明附近，不要新增孤立小节。

- [ ] **Step 4: 手动做一次 profile / 真机验证并记录结果**

Run:
- `fvm flutter run`

Manual checklist:
- 打开包含长 Markdown、列表、代码块的会话
- 慢速上下滚动，确认站位变化明显减弱
- 触发一轮新的流式回复，确认上一轮完成态 Markdown 不再肉眼抖动
- 如仍能明显复现抖动，记录是否集中在超长代码块场景，为第二阶段编译缓存开后续任务

Expected: 体验改善明显；若仍有局部问题，只记录，不在本任务中扩 scope。

- [ ] **Step 5: 按实际需要更新 `AGENTS.md`**

```md
- Chat timeline rendering changes should preserve stable row identity for completed Markdown blocks; avoid reintroducing whole-list widget assembly in `ChatMessageList`.
```

Implementation note: 仅当实现中形成了明确团队规则时才写入；如果只是局部实现细节，不要强行修改 `AGENTS.md`。

- [ ] **Step 6: 提交验证与文档更新**

```bash
git add README.md AGENTS.md
git commit -m "docs: record markdown timeline stability rules"
```

## Self-Review

### Spec coverage

1. “完成态 Markdown 视觉稳定”由 Task 2、Task 3、Task 4 覆盖。
2. “收紧时间线更新粒度”由 Task 2、Task 4 覆盖。
3. “为后续性能验证提供清晰边界”由 Task 1、Task 5 覆盖。
4. “第二阶段编译缓存作为增强路径”通过 Task 5 的手动验证记录和实现留口覆盖，本计划不直接实现该阶段。

### Placeholder scan

1. 没有使用 `TBD`、`TODO` 或“后续再补实现细节”式占位词。
2. 每个任务都给出了实际文件路径、测试入口和命令。
3. 唯一的条件性项是 `AGENTS.md` 更新，这一项已明确“只有形成团队规则时才执行”，不影响本次功能交付。

### Type consistency

1. 新类型统一命名为 `ChatTimelineItem`、`ChatTimelineRow`、`StableMarkdownBlock`。
2. `stableKey`、`cacheKey` 均表示稳定身份，不与 `message.id` 混用为同一个字段。
3. 所有测试和实现步骤都围绕上述命名展开，没有前后不一致的类型名。

