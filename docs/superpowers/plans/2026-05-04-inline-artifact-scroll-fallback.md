# 内联 artifact 滚动与截断策略优化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `create_artifact` 的内联预览默认完整展开、由消息列表统一滚动，并在内容超过 3 屏时自动截断并提示进入详情页查看完整内容。

**Architecture:** 预览层只负责测量内容高度、决定是否截断和渲染提示，不再让 `WebView` 自己承接纵向滚动。工具提示词只约束 artifact 单屏优先、最多两屏，减少超长页面出现概率；3 屏截断与详情页出口完全由 UI 层兜底。测试优先验证滚动手势消失、内容高度阈值和提示文案稳定。

**Tech Stack:** Flutter, `webview_flutter`, `flutter_test`

---

### Task 1: 收紧 `create_artifact` 的生成提示词

**Files:**
- Modify: `lib/tools/handlers/create_artifact_tool_handler.dart:187-270`
- Test: `test/tools/handlers/create_artifact_tool_handler_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
test('create_artifact prompt asks for one-screen preferred and three-screen fallback', () {
  final description = CreateArtifactToolHandler(...).definition.descriptionForModel;

  expect(description, contains('1 屏'));
  expect(description, contains('2 屏'));
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `fvm flutter test test/tools/handlers/create_artifact_tool_handler_test.dart -r expanded`

Expected: fail because prompt text does not yet mention the new height policy.

- [ ] **Step 3: 最小实现**

```dart
// 在中英文 description 中增加：
// - 默认尽量控制在 1 屏内
// - 最多尽量不超过 2 屏
```

- [ ] **Step 4: 运行测试确认通过**

Run: `fvm flutter test test/tools/handlers/create_artifact_tool_handler_test.dart -r expanded`

Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/tools/handlers/create_artifact_tool_handler.dart test/tools/handlers/create_artifact_tool_handler_test.dart
git commit -m "feat: tighten artifact generation guidance"
```

### Task 2: 让 artifact 预览只由列表滚动，并加入 3 屏兜底截断

**Files:**
- Modify: `lib/widgets/chat_blocks/artifact_preview_surface.dart:1-260`
- Modify: `lib/widgets/chat_blocks/artifact_block.dart:1-60`
- Test: `test/widgets/chat_blocks/artifact_preview_surface_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
test('artifact preview does not register vertical drag recognizer', () {
  expect(
    artifactPreviewGestureRecognizers.any(
      (factory) => factory.type == VerticalDragGestureRecognizer,
    ),
    isFalse,
  );
});

test('artifact preview clamps to three screens when content is too tall', () {
  expect(
    clampArtifactPreviewHeight(5000, viewportHeight: 800),
    2400,
  );
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `fvm flutter test test/widgets/chat_blocks/artifact_preview_surface_test.dart -r expanded`

Expected: fail because the current preview still registers vertical drag and still clamps to a fixed max height.

- [ ] **Step 3: 最小实现**

```dart
// 1) 移除 WebView 的 vertical drag gesture recognizer
// 2) 让高度上限从固定 720 改成基于视口高度计算的 3 屏兜底
// 3) 当内容高度超过上限时，保持完整截断到上限，并在预览底部显示“内容较长，长按进入详情页查看完整内容”
// 4) ArtifactBlock 继续保留长按进入详情页，但不再承担内部滚动
```

- [ ] **Step 4: 运行测试确认通过**

Run: `fvm flutter test test/widgets/chat_blocks/artifact_preview_surface_test.dart -r expanded`

Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/widgets/chat_blocks/artifact_preview_surface.dart lib/widgets/chat_blocks/artifact_block.dart test/widgets/chat_blocks/artifact_preview_surface_test.dart
git commit -m "feat: cap inline artifact preview height"
```

### Task 3: 做一次整体验证，确认列表滚动与详情页入口都正常

**Files:**
- Modify: 无
- Test: `test/widgets/chat_blocks/artifact_preview_surface_test.dart`
- Test: `test/widgets/chat_blocks/artifact_block_test.dart`

- [ ] **Step 1: 补充或更新列表级回归测试**

```dart
testWidgets('artifact preview stays inside the chat row and does not scroll internally', (tester) async {
  // 构造一个足够长的 artifact，确认预览高度被截断但列表仍可继续滚动。
});
```

- [ ] **Step 2: 运行 widget 测试**

Run: `fvm flutter test test/widgets/chat_blocks/artifact_preview_surface_test.dart test/widgets/chat_blocks/artifact_block_test.dart -r expanded`

Expected: PASS

- [ ] **Step 3: 手动检查详情页入口**

Run: `fvm flutter test` is not required here; use the app or existing UI flow to verify long-press still opens `ArtifactDetailPage`.

- [ ] **Step 4: 提交**

```bash
git add test/widgets/chat_blocks/artifact_preview_surface_test.dart test/widgets/chat_blocks/artifact_block_test.dart
git commit -m "test: cover artifact scroll fallback"
```

### Self-Review

覆盖检查：
- 提示词约束：Task 1
- 列表独占滚动：Task 2
- 超过 3 屏兜底：Task 2
- 详情页完整内容出口：Task 2 和 Task 3
- 回归测试：Task 1、Task 2、Task 3

无 `TBD`、`TODO`、或未定义符号。
