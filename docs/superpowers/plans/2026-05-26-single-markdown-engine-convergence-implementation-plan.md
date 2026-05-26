# Single Markdown Engine Convergence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 去除 `MarkdownWidgetImpl` 分流，让所有聊天 Markdown 统一走 `FlutterMarkdownImpl` / `flutter_markdown` 主链，并将表格风险限制为单一 block 的后续增强问题。

**Architecture:** 本计划先做单引擎收敛，不在同一轮内重建完整表格增强层。运行时上删除“有表格就切换 renderer”的逻辑；测试上从“验证走哪条引擎”改为“验证最终渲染结果”；最后保留表格回退后的真实问题清单，为后续单引擎表格增强做准备。

**Tech Stack:** Flutter 3.35.7、`flutter_markdown`、项目现有 `MarkdownBody`/`MarkdownStyleSheet`、Flutter widget tests。

---

## 文件结构

- Modify: `lib/widgets/markdown/flutter_markdown_impl.dart`
  - 删除表格检测分流。
  - 统一所有 Markdown 走 `MarkdownBody`。
- Delete: `lib/widgets/markdown/markdown_widget_impl.dart`
  - 删除 `markdown_widget` 专用渲染路径与本地 list patch。
- Modify: `test/widgets/chat_blocks/chat_blocks_test.dart`
  - 删除 `MarkdownWidgetImpl` 路由断言。
  - 增加“表格仍走 `MarkdownBody`”验证。
- Modify: `test/widgets/chat_timeline/stable_markdown_block_test.dart`
  - 清理若有的双引擎假设。
- Modify: `pubspec.yaml` / `pubspec.lock`（仅当最终确认无其他运行时使用 `markdown_widget` 时）
  - 可选：移除 `markdown_widget` 依赖。
- Optional follow-up note only, not in this implementation:
  - 表格视觉增强另起后续计划，不在本轮内一并落地。

## Task 1: 锁定单引擎目标测试

**Files:**
- Modify: `test/widgets/chat_blocks/chat_blocks_test.dart`

- [ ] **Step 1: 将表格路由测试改成单引擎目标**

把当前“markdown tables use the table-focused renderer”测试改为：

```dart
testWidgets('markdown tables stay on the default document renderer', (
  tester,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(
        body: FlutterMarkdownImpl(
          data: '''
| Plan | Owner | Status |
| --- | --- | --- |
| Table polish | UI | In progress |
| Width behavior | UX | Planned |
''',
        ),
      ),
    ),
  );

  expect(find.byType(MarkdownBody), findsOneWidget);
  expect(find.byType(Table), findsOneWidget);
}
```

- [ ] **Step 2: 删除旧的 `MarkdownWidgetImpl` 路径断言**

从同文件移除：

- `expect(find.byType(MarkdownWidgetImpl), findsOneWidget);`
- `expect(find.byType(MarkdownWidgetImpl), findsNothing);`
- 所有围绕 `MarkdownWidgetImpl` 的直接测试语义

- [ ] **Step 3: 运行单测，确认红灯**

Run:

```bash
fvm flutter test test/widgets/chat_blocks/chat_blocks_test.dart --plain-name "markdown tables stay on the default document renderer"
```

Expected:

- FAIL
- 当前实现仍会因为表格分流到 `MarkdownWidgetImpl`

## Task 2: 删除运行时表格分流

**Files:**
- Modify: `lib/widgets/markdown/flutter_markdown_impl.dart`

- [ ] **Step 1: 删除 `MarkdownWidgetImpl` import**

从文件顶部删除：

```dart
import 'markdown_widget_impl.dart';
```

- [ ] **Step 2: 删除 `_containsMarkdownTable` 分流逻辑**

移除：

```dart
if (_containsMarkdownTable(data) && !_containsMarkdownMath(data)) {
  return RepaintBoundary(
    child: MarkdownWidgetImpl(data: data),
  );
}
```

修改后 `build()` 始终返回 `MarkdownBody` 路径。

- [ ] **Step 3: 删除仅服务分流的表格检测方法**

删除：

- `_containsMarkdownTable`
- `_tableDividerPattern`

保留 `_containsMarkdownMath`，因为它仍服务现有 math 扩展行为判断。

- [ ] **Step 4: 运行目标测试，确认转绿**

Run:

```bash
fvm flutter test test/widgets/chat_blocks/chat_blocks_test.dart --plain-name "markdown tables stay on the default document renderer"
```

Expected:

- PASS

## Task 3: 清理 `MarkdownWidgetImpl` 与相关测试依赖

**Files:**
- Delete: `lib/widgets/markdown/markdown_widget_impl.dart`
- Modify: `test/widgets/chat_timeline/stable_markdown_block_test.dart`
- Modify: `test/widgets/chat_blocks/chat_blocks_test.dart`

- [ ] **Step 1: 搜索残余引用**

Run:

```bash
rg -n "MarkdownWidgetImpl" lib test
```

Expected:

- 只剩测试或待删除文件中的引用

- [ ] **Step 2: 删除 `markdown_widget_impl.dart`**

删除文件：

`lib/widgets/markdown/markdown_widget_impl.dart`

- [ ] **Step 3: 清理测试 import**

从测试文件中删除：

```dart
import 'package:ai_chat/widgets/markdown/markdown_widget_impl.dart';
```

以及所有仅服务该分支的断言。

- [ ] **Step 4: 运行搜索确认无残余引用**

Run:

```bash
rg -n "MarkdownWidgetImpl" lib test
```

Expected:

- 无结果

## Task 4: 验证单引擎主链功能未回归

**Files:**
- Test only

- [ ] **Step 1: 跑核心 chat block widget tests**

Run:

```bash
fvm flutter test test/widgets/chat_blocks/chat_blocks_test.dart
```

Expected:

- PASS

- [ ] **Step 2: 跑 markdown 语法相关 tests**

Run:

```bash
fvm flutter test test/widgets/markdown
```

Expected:

- PASS

- [ ] **Step 3: 跑 stable markdown block test**

Run:

```bash
fvm flutter test test/widgets/chat_timeline/stable_markdown_block_test.dart
```

Expected:

- PASS

## Task 5: 评估是否移除 `markdown_widget` 依赖

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`

- [ ] **Step 1: 全仓搜索 `markdown_widget`**

Run:

```bash
rg -n "markdown_widget" lib test pubspec.yaml
```

Expected:

- 若无运行时与测试残余使用，可继续移除依赖
- 若仍有其他地方依赖，则记录并保留依赖，避免本轮扩大范围

- [ ] **Step 2: 仅在确认无使用时移除依赖**

从 `pubspec.yaml` 删除：

```yaml
markdown_widget: ^2.3.2+6
```

然后运行：

```bash
fvm flutter pub get
```

- [ ] **Step 3: 若本轮不适合删依赖，则明确留存原因**

如果搜索后发现还有其他用途，则：

- 保留依赖
- 不再扩大本轮范围
- 在最终说明里明确“运行时主链已收敛，但依赖包暂未删，仅因其他残余使用或减小本轮改动面”

## Task 6: 真机验证与结果记录

**Files:**
- No required code changes

- [ ] **Step 1: 安装最新 debug APK 到 Android 真机**

Run:

```bash
bash scripts/android_install_debug.sh
```

Expected:

- Debug APK overwrite install 成功

- [ ] **Step 2: 打开包含“表格 + 列表”的同一条消息**

目标：

- 确认该消息不再因为表格切换到第二引擎
- 观察列表与正文的统一性
- 记录表格视觉回退点

- [ ] **Step 3: 截图保存**

将验证截图保存到：

`build/android-debug-screens/`

至少包括：

- 收敛后的同一条 Android 架构消息页面

- [ ] **Step 4: 记录表格后续增强清单**

在最终交付说明中列出：

- 当前单引擎已解决的结构问题
- 表格仍需后续增强的具体点

## Task 7: 提交收敛改动

**Files:**
- Stage only files from this task

- [ ] **Step 1: 检查变更范围**

Run:

```bash
git status --short
git diff -- lib/widgets/markdown/flutter_markdown_impl.dart test/widgets/chat_blocks/chat_blocks_test.dart test/widgets/chat_timeline/stable_markdown_block_test.dart pubspec.yaml pubspec.lock
```

- [ ] **Step 2: 提交**

If dependency removed:

```bash
git add lib/widgets/markdown/flutter_markdown_impl.dart \
  lib/widgets/markdown/markdown_widget_impl.dart \
  test/widgets/chat_blocks/chat_blocks_test.dart \
  test/widgets/chat_timeline/stable_markdown_block_test.dart \
  pubspec.yaml pubspec.lock
git commit -m "refactor: converge markdown rendering to flutter_markdown"
```

If dependency retained:

```bash
git add lib/widgets/markdown/flutter_markdown_impl.dart \
  lib/widgets/markdown/markdown_widget_impl.dart \
  test/widgets/chat_blocks/chat_blocks_test.dart \
  test/widgets/chat_timeline/stable_markdown_block_test.dart
git commit -m "refactor: converge markdown runtime to flutter_markdown"
```

