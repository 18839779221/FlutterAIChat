# Unified Bottom Sheet Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为当前全部 `showModalBottomSheet` 场景引入统一的 Bottom Sheet 外层壳与调用入口，统一点击外部关闭、下拉关闭、固定顶部 drag bar，以及 `adaptive` / `fixed80` 两档高度策略。

**Architecture:** 新增一个公共 `showAppBottomSheet` 入口和 `AppBottomSheetScaffold` 外层组件，统一管理 SafeArea、键盘 inset、drag bar、标题区和高度模式。现有 8 个业务场景逐个迁移到公共外层，业务层只保留正文内容。实现采用 TDD，先锁定公共壳行为，再迁移代表场景，最后批量收口和回归。

**Tech Stack:** Flutter 3.35.7、Dart、flutter_test、现有 `AppThemeSpec` / `AppSpacing` / `AppRadius` 主题体系、Flutter `showModalBottomSheet`。

---

## 文件结构

### 新增文件

- `lib/widgets/sheets/app_bottom_sheet.dart`
  - 定义 `AppBottomSheetMode`、`showAppBottomSheet` 与 `AppBottomSheetScaffold`。
- `test/widgets/sheets/app_bottom_sheet_test.dart`
  - 覆盖公共壳的高度、固定顶部和 dismiss 行为。

### 修改文件

- `lib/widgets/chat_drawer.dart`
  - 迁移工作区切换 sheet 到统一入口。
- `lib/pages/settings_page.dart`
  - 迁移 Skill 安装 sheet 到统一入口。
- `lib/widgets/settings/skill_install_sheet.dart`
  - 去掉自身的键盘 inset / 外层壳职责，只保留正文。
- `lib/pages/provider_form_page.dart`
  - 迁移 API Style 选择 sheet 到统一入口。
- `lib/widgets/debug/debug_test_case_sheet.dart`
  - 去掉自身外层壳职责，只保留正文。
- `lib/pages/chat_page.dart`
  - 迁移 Debug Test Cases、Context Window、Debug Turn Inspector 到统一入口。
- `lib/widgets/context_window/context_window_bottom_sheet.dart`
  - 去掉自身 drag bar 与最外层容器职责，保留内容区。
- `lib/widgets/debug/debug_turn_inspector_sheet.dart`
  - 去掉自身 drag bar 与顶部空隙。
- `lib/widgets/tool_renderers/web_search_tool_result_card.dart`
  - 改为通过统一入口打开固定 80% 高详情 sheet。
- `lib/widgets/tool_renderers/fetch_webpage_tool_result_card.dart`
  - 改为通过统一入口打开固定 80% 高详情 sheet。
- `test/widgets/context_window/context_window_bottom_sheet_test.dart`
  - 适配新的公共壳打开方式和断言。
- `test/widgets/tool_renderers/fetch_webpage_tool_cards_test.dart`
  - 适配新的统一详情 sheet 行为。
- `README.md`
  - 视需要补一句当前底部弹层采用统一外层壳。
- `AGENTS.md`
  - 如本轮形成新的明确规范，补充“新增 Bottom Sheet 默认走统一入口”约束。

## 任务 1：定义公共壳测试 contract

**Files:**
- Create: `test/widgets/sheets/app_bottom_sheet_test.dart`

- [ ] **Step 1: 写失败测试，锁定 `adaptive` 短内容高度不会被撑满**

```dart
testWidgets('adaptive sheet keeps short content below the 80 percent cap', (
  tester,
) async {
  await tester.pumpWidget(_AppBottomSheetHarness(
    mode: AppBottomSheetMode.adaptive,
    body: const SizedBox(height: 120, child: Text('short')),
  ));

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  final sheetHeight = tester.getSize(find.byKey(const ValueKey('app-bottom-sheet'))).height;
  expect(sheetHeight, lessThan(500));
});
```

- [ ] **Step 2: 运行测试，确认公共壳尚不存在**

Run: `fvm flutter test test/widgets/sheets/app_bottom_sheet_test.dart`

Expected: FAIL，提示缺少 `AppBottomSheetMode` / `showAppBottomSheet` / `AppBottomSheetScaffold`。

- [ ] **Step 3: 补失败测试，锁定 `fixed80`、固定 drag bar 和 dismiss 行为**

```dart
testWidgets('fixed80 sheet takes 80 percent height', ...);
testWidgets('drag handle stays visible after scrolling long body', ...);
testWidgets('tapping barrier dismisses sheet', ...);
testWidgets('dragging down dismisses sheet', ...);
```

- [ ] **Step 4: 再次运行测试，确认全部以缺失实现失败**

Run: `fvm flutter test test/widgets/sheets/app_bottom_sheet_test.dart`

Expected: FAIL，失败原因均指向公共壳未实现，而不是测试结构错误。

## 任务 2：实现统一 Bottom Sheet 入口与外层壳

**Files:**
- Create: `lib/widgets/sheets/app_bottom_sheet.dart`
- Test: `test/widgets/sheets/app_bottom_sheet_test.dart`

- [ ] **Step 1: 写最小实现，先满足 mode 与统一 key**

```dart
enum AppBottomSheetMode { adaptive, fixed80 }

Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required AppBottomSheetMode mode,
  String? title,
  String? subtitle,
  EdgeInsetsGeometry? bodyPadding,
  bool useSafeArea = true,
  bool useRootNavigator = false,
  required Widget body,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: useRootNavigator,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => AppBottomSheetScaffold(
      mode: mode,
      title: title,
      subtitle: subtitle,
      bodyPadding: bodyPadding,
      useSafeArea: useSafeArea,
      body: body,
    ),
  );
}
```

- [ ] **Step 2: 实现固定顶部 drag bar、标题区和两档高度**

要求：

- 根节点带稳定 key：`ValueKey('app-bottom-sheet')`
- drag bar 带稳定 key：`ValueKey('app-bottom-sheet-drag-handle')`
- `adaptive` 使用 `ConstrainedBox(maxHeight: screenHeight * 0.8)`
- `fixed80` 使用 `FractionallySizedBox(heightFactor: 0.8)`
- 底部 padding 统一加上 `viewInsets.bottom`

- [ ] **Step 3: 运行公共壳测试，修到通过**

Run: `fvm flutter test test/widgets/sheets/app_bottom_sheet_test.dart`

Expected: PASS，公共壳的核心行为通过。

- [ ] **Step 4: 代码清理**

要求：

- 只保留必要参数
- 不把 `showModalBottomSheet` 的全部低层参数做透传
- 给外部 API 和关键字段补简洁注释

## 任务 3：迁移一个 `adaptive` 场景验证模式

**Files:**
- Modify: `lib/pages/settings_page.dart`
- Modify: `lib/widgets/settings/skill_install_sheet.dart`
- Test: `test/widgets/sheets/app_bottom_sheet_test.dart`

- [ ] **Step 1: 先写或扩展失败测试，锁定表单场景仍可显示内容并保留按钮**

```dart
testWidgets('skill install content renders inside adaptive bottom sheet', ...);
```

- [ ] **Step 2: 运行相关测试，确认在旧结构下失败或缺少统一入口**

Run: `fvm flutter test test/widgets/sheets/app_bottom_sheet_test.dart`

Expected: FAIL，说明测试确实覆盖到迁移路径。

- [ ] **Step 3: 迁移 Skill 安装到 `showAppBottomSheet`**

要求：

- `settings_page.dart` 改为调用统一入口
- `SkillInstallSheet` 去掉自身 `SafeArea` / `viewInsets.bottom`
- 标题、副文案尽量迁到公共壳；若正文保留说明文字更自然，则只让公共壳承载 drag bar 和高度

- [ ] **Step 4: 运行相关测试**

Run: `fvm flutter test test/widgets/sheets/app_bottom_sheet_test.dart`

Expected: PASS，代表 `adaptive` 场景已打通。

## 任务 4：迁移一个 `fixed80` 场景验证模式

**Files:**
- Modify: `lib/pages/chat_page.dart`
- Modify: `lib/widgets/context_window/context_window_bottom_sheet.dart`
- Modify: `test/widgets/context_window/context_window_bottom_sheet_test.dart`

- [ ] **Step 1: 写失败测试，锁定 Context Window 通过公共壳打开且顶部 drag bar 固定**

```dart
testWidgets('context window sheet opens in fixed80 shared shell', ...);
```

- [ ] **Step 2: 运行测试，确认现有结构与新期望不一致**

Run: `fvm flutter test test/widgets/context_window/context_window_bottom_sheet_test.dart`

Expected: FAIL，说明迁移前后结构确实不同。

- [ ] **Step 3: 迁移 Context Window 到统一入口**

要求：

- `chat_page.dart` 使用 `showAppBottomSheet(... mode: fixed80 ...)`
- `ContextWindowBottomSheet` 删除内部 drag bar、外层圆角容器与高度限制
- 保留内容列表和现有卡片样式

- [ ] **Step 4: 运行测试直到通过**

Run: `fvm flutter test test/widgets/context_window/context_window_bottom_sheet_test.dart`

Expected: PASS。

## 任务 5：批量迁移剩余 `adaptive` 场景

**Files:**
- Modify: `lib/widgets/chat_drawer.dart`
- Modify: `lib/pages/provider_form_page.dart`

- [ ] **Step 1: 迁移工作区切换**

要求：

- 统一走 `showAppBottomSheet`
- `_WorkspacePickerSheet` 删除外层壳职责，只保留列表

- [ ] **Step 2: 迁移 API Style 选择**

要求：

- 统一走 `showAppBottomSheet`
- `_ApiStyleSelectionSheet` 删除自身 maxHeight / SafeArea 壳职责，只保留列表

- [ ] **Step 3: 运行针对性测试或最小 smoke**

Run: `fvm flutter test test/widgets/sheets/app_bottom_sheet_test.dart`

Expected: PASS，公共壳仍稳定。

## 任务 6：批量迁移剩余 `fixed80` 场景

**Files:**
- Modify: `lib/widgets/debug/debug_test_case_sheet.dart`
- Modify: `lib/widgets/debug/debug_turn_inspector_sheet.dart`
- Modify: `lib/pages/chat_page.dart`
- Modify: `lib/widgets/tool_renderers/web_search_tool_result_card.dart`
- Modify: `lib/widgets/tool_renderers/fetch_webpage_tool_result_card.dart`
- Modify: `test/widgets/tool_renderers/fetch_webpage_tool_cards_test.dart`

- [ ] **Step 1: 迁移 Debug Test Cases**

要求：

- 顶部统一交给公共壳
- 业务层只保留 grouped list 和按钮

- [ ] **Step 2: 迁移 Debug Turn Inspector**

要求：

- 删除组件内部 drag bar 和顶部 `SizedBox`
- 保留刷新区、turn 下拉、TabBar、TabBarView

- [ ] **Step 3: 迁移 `web_search` 详情**

要求：

- 顶部标题、副标题迁到公共壳
- 结果列表保留在正文区

- [ ] **Step 4: 迁移 `fetch_webpage` 详情**

要求：

- 顶部标题迁到公共壳
- Markdown 正文保留在内容区

- [ ] **Step 5: 跑相关 widget tests**

Run: `fvm flutter test test/widgets/tool_renderers/fetch_webpage_tool_cards_test.dart`

Expected: PASS。

## 任务 7：文档与规范收口

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`

- [ ] **Step 1: 判断是否需要在 README 补充统一 Bottom Sheet 外层约定**

要求：

- 只在确实存在对外部协作价值时补充

- [ ] **Step 2: 在 AGENTS.md 补一条明确规则**

建议：

- 新增 Bottom Sheet 默认通过统一入口 `showAppBottomSheet`

## 任务 8：最终验证

**Files:**
- Test only

- [ ] **Step 1: 运行公共壳测试**

Run: `fvm flutter test test/widgets/sheets/app_bottom_sheet_test.dart`

Expected: PASS。

- [ ] **Step 2: 运行 Context Window 相关测试**

Run: `fvm flutter test test/widgets/context_window/context_window_bottom_sheet_test.dart`

Expected: PASS。

- [ ] **Step 3: 运行 `fetch_webpage` tool card 测试**

Run: `fvm flutter test test/widgets/tool_renderers/fetch_webpage_tool_cards_test.dart`

Expected: PASS。

- [ ] **Step 4: 运行针对修改文件的 analyze**

Run: `fvm flutter analyze lib/widgets/sheets/app_bottom_sheet.dart lib/widgets/context_window/context_window_bottom_sheet.dart lib/widgets/debug/debug_turn_inspector_sheet.dart lib/widgets/debug/debug_test_case_sheet.dart lib/widgets/tool_renderers/web_search_tool_result_card.dart lib/widgets/tool_renderers/fetch_webpage_tool_result_card.dart lib/widgets/settings/skill_install_sheet.dart lib/pages/chat_page.dart lib/pages/settings_page.dart lib/pages/provider_form_page.dart lib/widgets/chat_drawer.dart`

Expected: PASS，或仅存在与本改动无关的既有噪音并明确记录。

- [ ] **Step 5: 可选手动回归**

Run:

```bash
bash scripts/android_install_debug.sh <device_id>
```

手动验证：

- 工作区切换
- Skill 安装
- Context Window
- `web_search`
- `fetch_webpage`

- [ ] **Step 6: 汇总结果**

要求：

- 记录哪些测试实际运行了
- 记录是否更新了 README / AGENTS
- 如果跳过真机验证，要明确说明
