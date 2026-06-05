# Chat List Dynamic Inset Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore a stable bottom-safe inset for the chat timeline and pin the newest user message under the header when a send starts, then shrink the extra inset monotonically as content fills the viewport.

**Architecture:** Keep the existing `ChatPage` overlay layout intact. Add a small UI-state surface for the dynamic extra bottom inset, perform a one-time send-time anchor measurement in `ChatMessageList`, and thereafter shrink the extra inset from real viewport measurements of the latest timeline content instead of maintaining a separate scroll-mode state machine.

**Tech Stack:** Flutter 3.35.7, Dart, Riverpod, existing chat timeline widgets, widget tests

---

## 文件结构与职责

### 需要修改的文件

- `lib/providers/chat_ui_providers.dart`
  - 增加消息列表动态底部 inset 的 UI 状态 provider
- `lib/widgets/chat_message_list.dart`
  - 恢复稳定最小底部 inset
  - 识别最新用户块并执行发送后的一次性顶置
  - 根据最后一个时间线块的底部距离单调收缩 extra inset
- `test/pages/chat_page_test.dart`
  - 更新底部 inset 相关页面级布局契约
- `test/widgets/chat_message_list_test.dart`
  - 增加发送时顶置与 extra inset 单调收缩的回归测试

### 实施前注意事项

- 不要改 `ChatPage` 的 overlay 结构，也不要回退现有 ghost header / floating status 改动
- 不要把新滚动规则写进 `ChatSendCoordinator` 或 controller；该行为属于 UI 投影层
- 每个行为先写失败测试，再写最小实现，再跑针对性测试

---

### Task 1: 锁定底部最小 inset 契约

**Files:**
- Modify: `test/pages/chat_page_test.dart`
- Test: `test/pages/chat_page_test.dart`

- [ ] **Step 1: 写失败测试，要求 overlay 存在时底部 inset 明显大于浅重叠值**

```dart
testWidgets('chat page keeps a stable bottom-safe inset beneath the overlay composer', (tester) async {
  // 构造一组最新消息
  // 渲染 ChatPage
  // 读取 SliverPadding.bottom
  // 断言它大于 spacing.xl，而不是退化到 spacing.sm
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `fvm flutter test test/pages/chat_page_test.dart --plain-name "chat page keeps a stable bottom-safe inset beneath the overlay composer"`

Expected: FAIL because the current bottom inset still collapses to `spacing.sm`.

- [ ] **Step 3: 在消息列表中实现稳定最小 inset**

实现：
- 用固定的 `minBottomInset` 替换当前 `bottomOverlayHeight > 0 ? spacing.sm : ...` 逻辑
- 保持页面级“列表视口延伸到 overlay 下方”的现有结构不变

- [ ] **Step 4: 运行测试确认通过**

Run: `fvm flutter test test/pages/chat_page_test.dart --plain-name "chat page keeps a stable bottom-safe inset beneath the overlay composer"`

Expected: PASS

### Task 2: 锁定发送后最新用户消息顶到 header 下方

**Files:**
- Modify: `test/widgets/chat_message_list_test.dart`
- Modify: `lib/providers/chat_ui_providers.dart`
- Modify: `lib/widgets/chat_message_list.dart`
- Test: `test/widgets/chat_message_list_test.dart`

- [ ] **Step 1: 写失败测试，要求 preparing 阶段的最新用户消息贴近顶部目标线**

```dart
testWidgets('latest user message pins beneath the header target when a send starts', (tester) async {
  // 构造旧对话 + 最新用户消息
  // sendPhase = ChatSendPhase.preparing
  // 渲染 ChatMessageList
  // 断言最新用户 row top 接近列表 top + sliver top padding
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `fvm flutter test test/widgets/chat_message_list_test.dart --plain-name "latest user message pins beneath the header target when a send starts"`

Expected: FAIL because no send-time anchor logic exists yet.

- [ ] **Step 3: 写最小实现**

实现：
- 新增 `chatMessageListExtraBottomInsetProvider`
- 在 `ChatMessageList` 中识别最新用户块变化
- 只在最新用户块首次进入发送期时测量一次目标差值
- 通过“设置 extra inset + 下一帧补 scroll offset”的方式把该块顶到目标线

- [ ] **Step 4: 运行测试确认通过**

Run: `fvm flutter test test/widgets/chat_message_list_test.dart --plain-name "latest user message pins beneath the header target when a send starts"`

Expected: PASS

### Task 3: 锁定 extra inset 的单调收缩

**Files:**
- Modify: `test/widgets/chat_message_list_test.dart`
- Modify: `lib/widgets/chat_message_list.dart`
- Test: `test/widgets/chat_message_list_test.dart`

- [ ] **Step 1: 写失败测试，要求最新内容增长时 extra inset 只减不增**

```dart
testWidgets('dynamic extra bottom inset shrinks monotonically as the latest content grows', (tester) async {
  // 先渲染只有最新用户消息的 sending 场景
  // 记录 provider 中的 extra inset
  // 再追加一条较长 assistant 消息并重新 pump
  // 断言 extra inset 变小或持平，且不会小于 0
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `fvm flutter test test/widgets/chat_message_list_test.dart --plain-name "dynamic extra bottom inset shrinks monotonically as the latest content grows"`

Expected: FAIL because the list does not yet measure and shrink the extra inset.

- [ ] **Step 3: 写最小实现**

实现：
- 给最新测量目标 row 分配可测量 key
- 在 scroll listener、`SizeChangedLayoutNotification`、发送后 post-frame 中统一触发 shrink 检查
- 用“最后一个时间线块到底部安全线的剩余距离”裁剪当前 extra inset
- 显式保证新 extra inset 只能 `<=` 旧值

- [ ] **Step 4: 运行测试确认通过**

Run: `fvm flutter test test/widgets/chat_message_list_test.dart --plain-name "dynamic extra bottom inset shrinks monotonically as the latest content grows"`

Expected: PASS

### Task 4: 跑针对性回归并检查无关契约未破坏

**Files:**
- Test: `test/pages/chat_page_test.dart`
- Test: `test/widgets/chat_message_list_test.dart`

- [ ] **Step 1: 运行页面级相关回归**

Run: `fvm flutter test test/pages/chat_page_test.dart`

Expected: PASS

- [ ] **Step 2: 运行消息列表相关回归**

Run: `fvm flutter test test/widgets/chat_message_list_test.dart`

Expected: PASS

- [ ] **Step 3: 如有必要运行格式化**

Run: `dart format lib/providers/chat_ui_providers.dart lib/widgets/chat_message_list.dart test/pages/chat_page_test.dart test/widgets/chat_message_list_test.dart`

Expected: Files formatted without touching unrelated docs or markdown
