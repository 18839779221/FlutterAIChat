# 设置域结构与视觉统一 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 重构配置相关页面的信息架构、视觉语言和轻量交互边界，让一级页承担展示与摘要、二级页承担管理型变更、复杂对象仅在必要时进入三级页，并统一到首页同源但更工具化的设置域语法。

**Architecture:** 先收口设置域的共享语法，再重构一级设置页，然后收紧模型管理页与 Provider 编辑页的层级职责，最后统一 bottom sheet、轻量选择和动效 token。实现中复用稳定的分组壳、状态展示行和标签系统，但不强行抽象每个页面的内容结构。

**Tech Stack:** Flutter 3.35.7, Dart, Riverpod, flutter_test, SharedPreferences, AppThemeSpec, AppMotion

---

## 文件结构与职责

### 重点修改文件

- `lib/pages/settings_page.dart`
  - 一级设置页，重构为分组式总览面板，优先展示状态与摘要
- `lib/pages/model_management_page.dart`
  - 二级管理页，承担 Provider / 运行时的管理型变更
- `lib/pages/provider_form_page.dart`
  - 复杂对象编辑页，只保留真正需要深编辑的内容
- `lib/widgets/shared/app_bottom_sheet.dart`
  - 轻量配置层统一壳，承接 sheet 级选择和短流程
- `lib/widgets/settings/settings_group_section.dart`
  - 升级为设置域共享分组壳，不再是线框感分组卡
- `lib/widgets/settings/settings_row.dart`
  - 升级为状态展示行，而不是普通表单行
- `lib/widgets/settings/settings_segmented_control.dart`
  - 收口轻量选择语法与选中态
- `lib/theme/app_component_theme.dart`
  - 收口输入框、卡片、轻面板等共享语法
- `lib/theme/app_motion.dart`
  - 作为设置域动效的唯一正式 token 来源

### 建议新增文件

- `lib/widgets/settings/settings_value_badge.dart`
  - 当前值 / 状态 / 数量标签组件
- `lib/widgets/settings/settings_summary_group.dart`
  - 一级页分组壳与标题/摘要/管理入口组合
- `lib/widgets/settings/settings_inline_picker_row.dart`
  - 当前页可直接变更的轻量行级触发器
- `test/pages/settings_page_test.dart`
  - 一级页结构、摘要、就地交互回归
- `test/pages/model_management_page_test.dart`
  - 二级页管理结构回归
- `test/pages/provider_form_page_test.dart`
  - 三级页复杂编辑与轻量弹层边界回归
- `test/widgets/settings/settings_summary_group_test.dart`
  - 共享分组壳视觉语义回归
- `test/widgets/settings/settings_row_test.dart`
  - 状态展示行与 badge 语义回归

### 辅助参考文件

- `docs/superpowers/specs/2026-06-18-settings-domain-structure-and-visual-unification-design.md`
- `lib/theme/app_theme_spec.dart`
- `lib/theme/app_spacing.dart`
- `lib/theme/app_radius.dart`
- `lib/theme/app_typography.dart`

## 实施策略

- 先打底层视觉语法，再改页面，避免页面先各自发明新样式
- 一级页优先落地，作为设置域母版
- 二级页仅保留管理语义，不抢一级页的展示职责
- 三级页只保留复杂对象编辑，能弹层解决的回退到轻量交互
- 动效与状态标签最后统一收口，避免前期页面各自散落实现

---

### Task 1: 建立设置域共享语法与测试护栏

**Files:**
- Create: `lib/widgets/settings/settings_value_badge.dart`
- Create: `lib/widgets/settings/settings_summary_group.dart`
- Modify: `lib/widgets/settings/settings_group_section.dart`
- Modify: `lib/widgets/settings/settings_row.dart`
- Modify: `lib/widgets/settings/settings_segmented_control.dart`
- Modify: `lib/theme/app_component_theme.dart`
- Test: `test/widgets/settings/settings_summary_group_test.dart`
- Test: `test/widgets/settings/settings_row_test.dart`

- [ ] **Step 1: 为分组壳写失败测试**

```dart
testWidgets('settings summary group renders title, summary and action',
    (tester) async {
  await tester.pumpWidget(
    buildTestApp(
      child: SettingsSummaryGroup(
        title: '模型与运行时',
        summary: '当前模型可用',
        actionLabel: '进入管理',
        onActionPressed: () {},
        children: const [
          SettingsRow(
            title: '当前 Provider',
            subtitle: '用于主对话的默认来源',
            trailing: SettingsValueBadge(label: 'Claude'),
          ),
        ],
      ),
    ),
  );

  expect(find.text('模型与运行时'), findsOneWidget);
  expect(find.text('当前模型可用'), findsOneWidget);
  expect(find.text('进入管理'), findsOneWidget);
  expect(find.text('Claude'), findsOneWidget);
});
```

- [ ] **Step 2: 为去线框感和标签语义写失败测试**

```dart
testWidgets('settings row prefers value badge over outlined chip styling',
    (tester) async {
  await tester.pumpWidget(
    buildTestApp(
      child: const SettingsRow(
        title: '执行模式',
        subtitle: '当前自动化策略',
        trailing: SettingsValueBadge(label: '平衡'),
      ),
    ),
  );

  expect(find.text('平衡'), findsOneWidget);
  expect(find.byType(SettingsValueBadge), findsOneWidget);
});
```

- [ ] **Step 3: 运行组件测试，确认当前失败**

Run:
- `fvm flutter test test/widgets/settings/settings_summary_group_test.dart`
- `fvm flutter test test/widgets/settings/settings_row_test.dart`

Expected: FAIL，因为新组件尚不存在，旧组件也不符合新的结构语义

- [ ] **Step 4: 实现 `SettingsValueBadge`**

```dart
class SettingsValueBadge extends StatelessWidget {
  const SettingsValueBadge({
    super.key,
    required this.label,
    this.tone = SettingsValueBadgeTone.neutral,
  });

  final String label;
  final SettingsValueBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final spacing = Theme.of(context).extension<AppSpacing>()!;
    final radius = Theme.of(context).extension<AppRadius>()!;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: _resolveBackground(colors, tone),
        borderRadius: BorderRadius.circular(radius.pill),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.sm,
          vertical: spacing.xxs + 2,
        ),
        child: Text(label, style: _resolveTextStyle(context, colors, tone)),
      ),
    );
  }
}
```

- [ ] **Step 5: 实现 `SettingsSummaryGroup` 与升级后的 `SettingsRow`**

```dart
class SettingsSummaryGroup extends StatelessWidget {
  // title + summary + children + optional action
}

class SettingsRow extends StatelessWidget {
  // 左侧标题/说明，右侧当前值/数量/状态标签
}
```

要求：
- 主边界靠背景层次与留白，不靠完整描边
- 组标题、摘要、内容行形成稳定层级
- `SettingsSegmentedControl` 的选中态改为轻面板反差，不用重边框

- [ ] **Step 6: 收口组件共享 theme**

修改 `app_component_theme.dart`：

```dart
static CardThemeData cardTheme(AppThemeSpec spec) {
  return CardThemeData(
    color: spec.semantic.surfaces.panelBackground,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(spec.core.radius.lg),
      side: BorderSide.none,
    ),
  );
}
```

同时保证输入框、轻面板和 badge 语法一致。

- [ ] **Step 7: 重新运行组件测试**

Run:
- `fvm flutter test test/widgets/settings/settings_summary_group_test.dart`
- `fvm flutter test test/widgets/settings/settings_row_test.dart`

Expected: PASS

- [ ] **Step 8: 提交共享语法改动**

```bash
git add \
  lib/widgets/settings/settings_value_badge.dart \
  lib/widgets/settings/settings_summary_group.dart \
  lib/widgets/settings/settings_group_section.dart \
  lib/widgets/settings/settings_row.dart \
  lib/widgets/settings/settings_segmented_control.dart \
  lib/theme/app_component_theme.dart \
  test/widgets/settings/settings_summary_group_test.dart \
  test/widgets/settings/settings_row_test.dart
git commit -m "feat: add shared settings domain presentation primitives"
```

---

### Task 2: 重构一级设置页为分组式总览面板

**Files:**
- Modify: `lib/pages/settings_page.dart`
- Modify: `lib/theme/app_theme_controller.dart`
- Test: `test/pages/settings_page_test.dart`

- [ ] **Step 1: 为一级页新结构写失败测试**

```dart
testWidgets('settings page renders grouped overview with current values',
    (tester) async {
  await tester.pumpWidget(buildSettingsPageWithRepository(...));

  expect(find.text('模型与运行时'), findsOneWidget);
  expect(find.text('工具与安全'), findsOneWidget);
  expect(find.text('扩展能力'), findsOneWidget);
  expect(find.text('外观与兼容'), findsOneWidget);
  expect(find.text('当前 Provider'), findsOneWidget);
  expect(find.text('当前主题'), findsOneWidget);
  expect(find.text('进入管理'), findsNWidgets(4));
});
```

- [ ] **Step 2: 为一级页轻量直改项写失败测试**

```dart
testWidgets('settings page supports inline theme and mode changes without navigation',
    (tester) async {
  await tester.pumpWidget(buildSettingsPageWithRepository(...));

  await tester.tap(find.text('主题'));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('theme-picker-sheet')), findsOneWidget);
});
```

- [ ] **Step 3: 运行页面测试，确认当前失败**

Run: `fvm flutter test test/pages/settings_page_test.dart`
Expected: FAIL，因为页面仍是传统设置列表，且未提供新的 grouped overview 结构

- [ ] **Step 4: 重写 `SettingsPage` 的数据加载和分组组装**

需要补齐：
- `blockedToolNames`
- `themeId`
- `chatCompletionsAdapterType`
- 生图默认 provider/model 摘要

实现类似：

```dart
class _SettingsOverviewState {
  final String? themeId;
  final Set<String> blockedToolNames;
  final String adapterType;
}
```

- [ ] **Step 5: 用 `SettingsSummaryGroup` 重构 4 个分组**

4 组固定为：
- 模型与运行时
- 工具与安全
- 扩展能力
- 外观与兼容

要求：
- 每组都有标题、状态摘要、具体内容行
- 每组只有一个主入口动作
- `theme`、`tool execution mode`、`duplicate skill invocation mode` 这类离散项优先轻量弹层或行内触发

- [ ] **Step 6: 将简单配置改为轻量交互**

例如：

```dart
Future<void> _openThemePicker() async {
  final selected = await showAppBottomSheet<String>(...);
  if (selected != null) {
    await ref.read(appThemeControllerProvider.notifier).setThemeById(selected);
  }
}
```

一级页允许：
- 主题切换
- 执行模式切换
- 重复调用策略切换

一级页不允许：
- 复杂 Provider 编辑
- 长列表管理

- [ ] **Step 7: 重跑一级页测试**

Run: `fvm flutter test test/pages/settings_page_test.dart`
Expected: PASS

- [ ] **Step 8: 提交一级页重构**

```bash
git add \
  lib/pages/settings_page.dart \
  lib/theme/app_theme_controller.dart \
  test/pages/settings_page_test.dart
git commit -m "feat: redesign settings page as grouped overview"
```

---

### Task 3: 收紧二级页职责，弱化三级页使用范围

**Files:**
- Modify: `lib/pages/model_management_page.dart`
- Modify: `lib/pages/provider_form_page.dart`
- Test: `test/pages/model_management_page_test.dart`
- Test: `test/pages/provider_form_page_test.dart`

- [ ] **Step 1: 为二级页“管理型变更”写失败测试**

```dart
testWidgets('model management focuses on provider management instead of overview duplication',
    (tester) async {
  await tester.pumpWidget(buildModelManagementPage(...));

  expect(find.text('当前 Provider'), findsNothing);
  expect(find.text('新增 Provider'), findsOneWidget);
  expect(find.text('编辑'), findsWidgets);
  expect(find.text('删除'), findsWidgets);
});
```

- [ ] **Step 2: 为三级页只保留复杂编辑写失败测试**

```dart
testWidgets('provider form keeps complex editing and moves simple choices to sheets',
    (tester) async {
  await tester.pumpWidget(buildProviderFormPage(...));

  expect(find.text('选择 API Style'), findsOneWidget);
  expect(find.byKey(const ValueKey('api-style-sheet-trigger')), findsOneWidget);
});
```

- [ ] **Step 3: 运行二三级页测试，确认当前失败**

Run:
- `fvm flutter test test/pages/model_management_page_test.dart`
- `fvm flutter test test/pages/provider_form_page_test.dart`

Expected: FAIL，因为二级页仍有较重 overview 复制，三级页仍承接过多可轻量化项

- [ ] **Step 4: 收紧 `ModelManagementPage`**

原则：
- 只保留二级管理语义
- 列表、增删、进入编辑是主职责
- 不重复一级页的总览摘要
- 当前值可有，但不再做一级页式状态展示

实现要点：

```dart
// 保留 provider list + create / test actions
// 收掉重复的 overview hero，改成轻量管理头部
```

- [ ] **Step 5: 收紧 `ProviderFormPage`**

原则：
- 保留复杂对象编辑
- 简单离散选择继续用 sheet / 下拉 / segmented control
- 不把可轻量配置的项升级成新页面

保留：
- Provider 名称
- Base URL
- API Key
- 模型目录
- Side Model

继续轻量化：
- API Style
- 生图能力测试确认

- [ ] **Step 6: 重跑二三级页测试**

Run:
- `fvm flutter test test/pages/model_management_page_test.dart`
- `fvm flutter test test/pages/provider_form_page_test.dart`

Expected: PASS

- [ ] **Step 7: 提交二三级页职责收口**

```bash
git add \
  lib/pages/model_management_page.dart \
  lib/pages/provider_form_page.dart \
  test/pages/model_management_page_test.dart \
  test/pages/provider_form_page_test.dart
git commit -m "feat: tighten settings management and edit page boundaries"
```

---

### Task 4: 统一轻量弹层、动效 token 与交互反馈

**Files:**
- Modify: `lib/widgets/shared/app_bottom_sheet.dart`
- Modify: `lib/theme/app_motion.dart`
- Modify: `lib/widgets/settings/settings_segmented_control.dart`
- Modify: `lib/widgets/settings/skill_install_sheet.dart`
- Test: `test/widgets/shared/app_bottom_sheet_test.dart`
- Test: `test/widgets/settings/settings_segmented_control_test.dart`

- [ ] **Step 1: 为 bottom sheet 和轻量选择动效写失败测试**

```dart
testWidgets('bottom sheet uses shared shell and stable motion tokens',
    (tester) async {
  await tester.pumpWidget(buildBottomSheetHarness());
  await tester.tap(find.text('打开'));
  await tester.pump();
  expect(find.byKey(const ValueKey('app-bottom-sheet')), findsOneWidget);
});
```

- [ ] **Step 2: 为 segmented control 选中态写失败测试**

```dart
testWidgets('segmented control uses soft selected surface instead of outline emphasis',
    (tester) async {
  await tester.pumpWidget(buildSegmentedControlHarness());
  expect(find.text('平衡'), findsOneWidget);
});
```

- [ ] **Step 3: 运行交互测试，确认当前失败**

Run:
- `fvm flutter test test/widgets/shared/app_bottom_sheet_test.dart`
- `fvm flutter test test/widgets/settings/settings_segmented_control_test.dart`

Expected: FAIL，因为现有实现未针对统一 token 与新反馈语义收口

- [ ] **Step 4: 收口 `AppMotion` 使用**

实现要求：
- 同类交互统一使用 `AppMotion` 中已有时长和曲线
- 删除设置域中零散的裸 `Duration(...)` / `Curve`

例如：

```dart
final motion = Theme.of(context).extension<AppThemeSpec>()!.core.motion;
final duration = motion.quick;
final curve = motion.emphasizedDecelerate;
```

- [ ] **Step 5: 统一弹层与选中态反馈**

需要实现：
- sheet 出现时的统一层级变化
- segmented control 的 soft selected state
- 轻量 picker 行的统一触发反馈

- [ ] **Step 6: 重跑交互测试**

Run:
- `fvm flutter test test/widgets/shared/app_bottom_sheet_test.dart`
- `fvm flutter test test/widgets/settings/settings_segmented_control_test.dart`

Expected: PASS

- [ ] **Step 7: 提交交互与动效收口**

```bash
git add \
  lib/widgets/shared/app_bottom_sheet.dart \
  lib/theme/app_motion.dart \
  lib/widgets/settings/settings_segmented_control.dart \
  lib/widgets/settings/skill_install_sheet.dart \
  test/widgets/shared/app_bottom_sheet_test.dart \
  test/widgets/settings/settings_segmented_control_test.dart
git commit -m "feat: unify settings lightweight interactions and motion"
```

---

### Task 5: 验证、文档同步与最终回归

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `docs/superpowers/specs/2026-06-18-settings-domain-structure-and-visual-unification-design.md`（如实施后有必要回填）

- [ ] **Step 1: 更新 README 中设置域说明**

补充：
- 设置页已改为分组式总览
- 配置相关页面采用轻量交互优先、复杂编辑才下沉

- [ ] **Step 2: 更新 AGENTS 中设置域约束**

补充：
- 一级设置页展示优先
- 简单配置优先当前页 / sheet
- 设置域避免线框感
- 设置域动效统一使用 `AppMotion`

- [ ] **Step 3: 运行定向 analyze**

Run: `fvm flutter analyze lib/pages/settings_page.dart lib/pages/model_management_page.dart lib/pages/provider_form_page.dart lib/widgets/settings lib/widgets/shared/app_bottom_sheet.dart`
Expected: PASS

- [ ] **Step 4: 运行定向测试**

Run:
- `fvm flutter test test/pages/settings_page_test.dart`
- `fvm flutter test test/pages/model_management_page_test.dart`
- `fvm flutter test test/pages/provider_form_page_test.dart`
- `fvm flutter test test/widgets/settings`
- `fvm flutter test test/widgets/shared/app_bottom_sheet_test.dart`

Expected: PASS

- [ ] **Step 5: 进行主题双态人工校验**

Run:
- `fvm flutter run -d web-server --web-hostname 127.0.0.1 --web-port 7357`

Manual checks:
- `claude` 主题
- `olive-paper` 主题
- 一级页总览结构
- 二级页管理密度
- 三级页编辑聚焦感
- sheet 与轻量选择反馈

- [ ] **Step 6: 提交文档与验证收口**

```bash
git add README.md AGENTS.md docs/superpowers/specs/2026-06-18-settings-domain-structure-and-visual-unification-design.md
git commit -m "docs: document settings domain interaction rules"
```
