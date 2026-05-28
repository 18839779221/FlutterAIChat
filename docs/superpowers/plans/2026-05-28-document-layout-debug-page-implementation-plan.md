# Document Layout Debug Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增一个独立路由的文档排版调试页，使用仓库内固定构造案例复用真实 `AssistantDocBlock` 和 Markdown 渲染链，稳定回归大模型文档回复排版。

**Architecture:** 本计划保持首版边界很窄：新增独立页面、轻量 case/block 模型、Dart 常量案例库和一个真实 block 分发器，不接入聊天发送链路、数据库或对话模拟器。测试以 widget test 为主，验证路由页面、案例切换和真实组件复用，README 只补充最小使用说明。

**Tech Stack:** Flutter 3.35.7、MaterialApp 路由、现有 `AssistantDocBlock` / `FlutterMarkdownImpl`、Flutter widget tests、`fvm flutter test`。

---

## 文件结构

- Modify: `lib/constants/route_constant.dart`
  - 新增文档排版调试页路由常量。
- Modify: `lib/main.dart`
  - 注册调试页路由。
- Create: `lib/models/debug/layout_debug_block.dart`
  - 定义首版 block 类型与 `assistantDoc` payload 字段。
- Create: `lib/models/debug/layout_debug_case.dart`
  - 定义页面消费的固定 case 模型。
- Create: `lib/debug/layout_debug_cases.dart`
  - 集中维护首批固定 Markdown 文档案例。
- Create: `lib/pages/layout_debug_page.dart`
  - 实现独立调试页、case 切换 UI 和真实 block 预览。
- Modify: `README.md`
  - 补充调试页入口与案例库位置说明。
- Create: `test/pages/layout_debug_page_test.dart`
  - 覆盖默认渲染、case 切换和真实组件复用。

## Task 1: 锁定页面入口与最小模型边界

**Files:**
- Create: `test/pages/layout_debug_page_test.dart`
- Create: `lib/models/debug/layout_debug_block.dart`
- Create: `lib/models/debug/layout_debug_case.dart`

- [ ] **Step 1: 先写页面级失败测试，锁定默认案例和真实 block 复用**

```dart
testWidgets('layout debug page shows the first built-in case', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: const LayoutDebugPage(),
    ),
  );

  await tester.pumpAndSettle();

  expect(find.text('文档排版调试'), findsOneWidget);
  expect(find.text('基础长文'), findsOneWidget);
  expect(find.byType(AssistantDocBlock), findsWidgets);
});
```

- [ ] **Step 2: 增加案例切换失败测试**

```dart
testWidgets('layout debug page switches between built-in cases', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: const LayoutDebugPage(),
    ),
  );

  await tester.tap(find.text('复杂结构').last);
  await tester.pumpAndSettle();

  expect(find.text('复杂结构'), findsWidgets);
  expect(find.textContaining('表格'), findsWidgets);
});
```

- [ ] **Step 3: 定义最小 debug 模型骨架**

在 `lib/models/debug/layout_debug_block.dart` 里先定义首版枚举和 DTO：

```dart
enum LayoutDebugBlockType { assistantDoc }

class LayoutDebugBlock {
  final LayoutDebugBlockType type;
  final String markdownText;
  final String? label;
  final String? reasoningText;
  final String? markdownCacheKey;
}
```

在 `lib/models/debug/layout_debug_case.dart` 里定义：

```dart
class LayoutDebugCase {
  final String id;
  final String title;
  final String description;
  final List<LayoutDebugBlock> blocks;
}
```

- [ ] **Step 4: 运行新测试，确认红灯**

Run:

```bash
fvm flutter test test/pages/layout_debug_page_test.dart
```

Expected:

- FAIL
- `LayoutDebugPage` 或相关模型尚不存在

## Task 2: 建立固定案例库

**Files:**
- Create: `lib/debug/layout_debug_cases.dart`
- Modify: `lib/models/debug/layout_debug_block.dart`
- Modify: `lib/models/debug/layout_debug_case.dart`

- [ ] **Step 1: 建立集中案例库文件**

新增导出常量：

```dart
const List<LayoutDebugCase> kLayoutDebugCases = [...];
```

不要把案例硬编码在页面里。

- [ ] **Step 2: 写首批 4 个稳定案例**

至少包含：

- `基础长文`
- `复杂结构`
- `边界压力`
- `完整助手回复`

每个案例都提供稳定 `id`、`title`、`description` 和 `blocks`。

- [ ] **Step 3: 保持 block 结构为未来扩展预留 `type`**

即使当前只有 `assistantDoc`，也不要退回成“页面直接持有字符串数组”的结构。

- [ ] **Step 4: 为长 Markdown 样例使用原始多行字符串**

示例：

```dart
const _basicMarkdown = r'''
# 学习计划

这是一段用于验证段落节奏的说明文字。
''';
```

- [ ] **Step 5: 暂不做 asset loader**

不要新增 `pubspec.yaml` assets 配置；首版全部通过 Dart 常量直连。

## Task 3: 实现调试页和真实 block 分发

**Files:**
- Create: `lib/pages/layout_debug_page.dart`
- Modify: `lib/constants/route_constant.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: 新增路由常量**

在 `RouteConstant` 里新增例如：

```dart
static const String layoutDebugPage = '/layoutDebugPage';
```

- [ ] **Step 2: 在 `main.dart` 注册页面路由**

在 `getRouteMap()` 中加入：

```dart
RouteConstant.layoutDebugPage: (context) => const LayoutDebugPage(),
```

- [ ] **Step 3: 实现页面的默认 case 选择状态**

页面应：

- 默认选中 `kLayoutDebugCases.first`
- 在 `StatefulWidget` 中维护当前 case
- 不依赖 Provider、数据库或聊天 controller

- [ ] **Step 4: 实现宽窄屏布局切换**

约束：

- 宽屏：左侧案例列表，右侧预览
- 窄屏：顶部 `DropdownButton` 或等价 picker，下方预览

不需要引入复杂自定义动画或多层嵌套滚动。

- [ ] **Step 5: 实现统一 block 分发器**

在页面内增加一个小型分发方法：

```dart
Widget _buildBlock(LayoutDebugBlock block) {
  switch (block.type) {
    case LayoutDebugBlockType.assistantDoc:
      return AssistantDocBlock(
        text: block.markdownText,
        label: block.label,
        reasoningText: block.reasoningText,
        markdownCacheKey: block.markdownCacheKey,
      );
  }
}
```

- [ ] **Step 6: 给每个 block 派生稳定 cache key**

如果案例没有显式提供 `markdownCacheKey`，页面应基于 `case.id` 和 block index 派生，避免仅靠 `hashCode` 带来不稳定性。

- [ ] **Step 7: 保持预览宽度接近真实阅读宽度**

例如把内容包进一个有最大宽度的居中容器，避免无限宽布局掩盖排版问题。

- [ ] **Step 8: 运行页面测试，确认转绿**

Run:

```bash
fvm flutter test test/pages/layout_debug_page_test.dart
```

Expected:

- PASS

## Task 4: 强化页面测试覆盖

**Files:**
- Modify: `test/pages/layout_debug_page_test.dart`

- [ ] **Step 1: 增加完整助手回复案例断言**

验证 `label`、`reasoningText` 和 Markdown 主体同时出现。

- [ ] **Step 2: 增加 block 数量断言**

对至少一个案例验证：

```dart
expect(find.byType(AssistantDocBlock), findsNWidgets(2));
```

或与实际案例块数等价的断言。

- [ ] **Step 3: 只验证结构，不做像素快照**

避免在本任务内增加 golden 测试。

- [ ] **Step 4: 跑页面测试全集**

Run:

```bash
fvm flutter test test/pages/layout_debug_page_test.dart
```

Expected:

- PASS

## Task 5: 补最小使用文档并做回归验证

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 在 README 增加一小段开发调试说明**

说明至少包括：

- 页面用途
- 路由入口 `RouteConstant.layoutDebugPage`
- 固定案例库文件 `lib/debug/layout_debug_cases.dart`

- [ ] **Step 2: 运行与本改动最相关的测试**

Run:

```bash
fvm flutter test test/pages/layout_debug_page_test.dart
```

Expected:

- PASS

- [ ] **Step 3: 跑现有 chat block 相关测试，确认真实组件复用未破坏**

Run:

```bash
fvm flutter test test/widgets/chat_blocks
```

Expected:

- PASS

- [ ] **Step 4: 跑静态检查**

Run:

```bash
fvm flutter analyze
```

Expected:

- PASS

- [ ] **Step 5: 提交本轮改动**

```bash
git add \
  lib/constants/route_constant.dart \
  lib/main.dart \
  lib/models/debug/layout_debug_block.dart \
  lib/models/debug/layout_debug_case.dart \
  lib/debug/layout_debug_cases.dart \
  lib/pages/layout_debug_page.dart \
  test/pages/layout_debug_page_test.dart \
  README.md \
  docs/superpowers/specs/2026-05-28-document-layout-debug-page-design.md \
  docs/superpowers/plans/2026-05-28-document-layout-debug-page-implementation-plan.md
git commit -m "feat: add document layout debug page"
```

