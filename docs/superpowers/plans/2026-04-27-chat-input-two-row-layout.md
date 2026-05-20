# 输入框 2 行布局改造 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `ChatInput` 由单行 + 覆盖层 `ContextWindowStatusBar` 重构为 Column 两行布局（TextField 上，工具栏下），在右下角以轻量圆环 + 常驻百分比形式展示 context 使用率；旧 `ContextWindowStatusBar` 及其测试一并删除。

**Architecture:** UI 侧局部重构。新增纯展示组件 `ContextWindowUsageIndicator` 与共享颜色函数 `resolveContextWindowUsageColor`；`ChatInput` 改为 `Column(TextField, Row(Spacer, Indicator, SendButton))`。不新增/改动 provider、controller、service；不触达 `ContextWindowSnapshot` 模型及上游服务。

**Tech Stack:** Flutter 3.29.2 (prefer `fvm flutter`), flutter_riverpod, Material Theme extensions（`AppThemeSpec/AppSpacing/AppRadius`），`flutter_test`。

**关键参考文档：** `docs/superpowers/specs/2026-04-27-chat-input-two-row-layout-design.md`

---

## 前置说明

- 所有 Flutter 命令优先 `fvm flutter`（项目要求 Flutter 3.29.2）。
- 颜色、间距、圆角全部来自 `Theme.of(context).extension<...>()!`，不要硬编码。
- 遵循 `AGENTS.md`：内部开发阶段，禁止引入兼容层或保留旧引用。
- 每个 Task 完成后运行 `fvm flutter analyze` 必须零 error/warning。
- 提交信息用 `feat:` / `refactor:` / `test:` / `chore:` 前缀，符合现仓风格。

---

## Task 1：抽取共享颜色阈值函数

**目标：** 把目前写在 `ContextWindowStatusBar._resolveValueColor` 里的三档阈值逻辑抽成独立纯函数，供新旧两处（短暂共存期间）以及新组件使用。

**Files:**
- Create: `lib/widgets/context_window/context_window_usage_color.dart`
- Create: `test/widgets/context_window/context_window_usage_color_test.dart`

- [ ] **Step 1：先写失败测试**

创建 `test/widgets/context_window/context_window_usage_color_test.dart`：

```dart
import 'package:ai_chat/models/session/context_window_segment.dart';
import 'package:ai_chat/models/session/context_window_snapshot.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/widgets/context_window/context_window_usage_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final colors = AppThemeSpec.light();

  ContextWindowSnapshot snapshot(double ratio) {
    return ContextWindowSnapshot(
      modelName: 'gpt-test',
      maxContextTokens: 128000,
      usableInputBudget: 104000,
      compressionTriggerRatio: 0.8,
      totalEstimatedInputTokens: 0,
      totalWindowUsageRatio: ratio,
      usableInputUsageRatio: 0.0,
      didCompactHistory: false,
      recentCompletedTurnCount: 0,
      segments: const <ContextWindowSegment>[],
    );
  }

  test('low ratio uses secondaryText base color', () {
    final color = resolveContextWindowUsageColor(colors, snapshot(0.2));
    expect(color.value, colors.secondaryText.withValues(alpha: 0.48).value);
  });

  test('mid ratio (>= 85% of trigger, < trigger) uses workflowRunning', () {
    // trigger = 0.8, mid threshold = 0.68
    final color = resolveContextWindowUsageColor(colors, snapshot(0.7));
    expect(color.value, colors.workflowRunning.withValues(alpha: 0.64).value);
  });

  test('at or above trigger uses workflowWarning', () {
    final color = resolveContextWindowUsageColor(colors, snapshot(0.8));
    expect(color.value, colors.workflowWarning.withValues(alpha: 0.72).value);
  });
}
```

- [ ] **Step 2：运行测试确认失败**

Run: `fvm flutter test test/widgets/context_window/context_window_usage_color_test.dart`
Expected: 编译失败，提示 `context_window_usage_color.dart` 或 `resolveContextWindowUsageColor` 未定义。

- [ ] **Step 3：实现颜色函数**

创建 `lib/widgets/context_window/context_window_usage_color.dart`：

```dart
import 'package:flutter/material.dart';

import '../../models/session/context_window_snapshot.dart';
import '../../theme/app_theme_spec.dart';

/// 根据 context 使用率返回圆环/进度条 valueColor。
///
/// 阈值：
/// - `ratio >= compressionTriggerRatio`          → workflowWarning @0.72
/// - `ratio >= compressionTriggerRatio * 0.85`   → workflowRunning @0.64
/// - 其他                                         → secondaryText   @0.48
Color resolveContextWindowUsageColor(
  AppThemeSpec colors,
  ContextWindowSnapshot snapshot,
) {
  final ratio = snapshot.totalWindowUsageRatio.clamp(0.0, 1.0);
  final trigger = snapshot.compressionTriggerRatio;
  if (ratio >= trigger) {
    return colors.workflowWarning.withValues(alpha: 0.72);
  }
  if (ratio >= trigger * 0.85) {
    return colors.workflowRunning.withValues(alpha: 0.64);
  }
  return colors.secondaryText.withValues(alpha: 0.48);
}
```

- [ ] **Step 4：运行测试确认通过**

Run: `fvm flutter test test/widgets/context_window/context_window_usage_color_test.dart`
Expected: 3 个测试全部通过。

- [ ] **Step 5：analyze**

Run: `fvm flutter analyze lib/widgets/context_window/context_window_usage_color.dart test/widgets/context_window/context_window_usage_color_test.dart`
Expected: `No issues found!`

- [ ] **Step 6：提交**

```bash
git add lib/widgets/context_window/context_window_usage_color.dart test/widgets/context_window/context_window_usage_color_test.dart
git commit -m "feat: extract shared context window usage color helper"
```

---

## Task 2：新增 `ContextWindowUsageIndicator` 组件（轻量圆环 + 常驻百分比）

**目标：** 新建一个 Stateless 组件，入参 `ContextWindowSnapshot` + `VoidCallback onTap`；视觉上是一枚 16×16 圆环（`CircularProgressIndicator`）配合常驻百分比文字，外层 `InkWell` 热区不小于 32×32，Semantics 里保留完整百分比标签。

**Files:**
- Create: `lib/widgets/context_window/context_window_usage_indicator.dart`
- Create: `test/widgets/context_window/context_window_usage_indicator_test.dart`

- [ ] **Step 1：先写失败测试**

创建 `test/widgets/context_window/context_window_usage_indicator_test.dart`：

```dart
import 'package:ai_chat/models/session/context_window_segment.dart';
import 'package:ai_chat/models/session/context_window_snapshot.dart';
import 'package:ai_chat/theme/app_theme_spec.dart';
import 'package:ai_chat/theme/app_radius.dart';
import 'package:ai_chat/theme/app_spacing.dart';
import 'package:ai_chat/widgets/context_window/context_window_usage_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ContextWindowSnapshot _snapshot(double ratio) {
  return ContextWindowSnapshot(
    modelName: 'gpt-test',
    maxContextTokens: 128000,
    usableInputBudget: 104000,
    compressionTriggerRatio: 0.8,
    totalEstimatedInputTokens: 1000,
    totalWindowUsageRatio: ratio,
    usableInputUsageRatio: 0.0,
    didCompactHistory: false,
    recentCompletedTurnCount: 0,
    segments: const <ContextWindowSegment>[],
  );
}

Widget _host(Widget child) {
  return MaterialApp(
    theme: ThemeData(
      extensions: <ThemeExtension<dynamic>>[
        AppThemeSpec.light(),
        AppSpacing.base(),
        AppRadius.base(),
      ],
    ),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('renders a 16px determinate ring with visible percentage text',
      (tester) async {
    await tester.pumpWidget(_host(
      ContextWindowUsageIndicator(
        snapshot: _snapshot(0.23),
        onTap: () {},
      ),
    ));

    final ring = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(ring.value, closeTo(0.23, 1e-9));
    expect(ring.strokeWidth, 2.0);
    expect(find.text('23%'), findsOneWidget);

    final ringSize = tester.getSize(find.byType(CircularProgressIndicator));
    expect(ringSize.width, 16);
    expect(ringSize.height, 16);
  });

  testWidgets('tap hit area is at least 32x32 and invokes onTap once',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(
      ContextWindowUsageIndicator(
        snapshot: _snapshot(0.5),
        onTap: () => taps += 1,
      ),
    ));

    final hitSize = tester.getSize(
      find.byKey(const ValueKey('context-window-usage-indicator')),
    );
    expect(hitSize.width, greaterThanOrEqualTo(32));
    expect(hitSize.height, greaterThanOrEqualTo(32));

    await tester.tap(
      find.byKey(const ValueKey('context-window-usage-indicator')),
    );
    expect(taps, 1);
  });

  testWidgets('semantics label includes rounded percentage', (tester) async {
    await tester.pumpWidget(_host(
      ContextWindowUsageIndicator(
        snapshot: _snapshot(0.236),
        onTap: () {},
      ),
    ));

    final handle = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel(RegExp(r'Context 使用率 24%')),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('color shifts to warning at or above trigger ratio',
      (tester) async {
    await tester.pumpWidget(_host(
      ContextWindowUsageIndicator(
        snapshot: _snapshot(0.9),
        onTap: () {},
      ),
    ));

    final ring = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    final expected = AppThemeSpec.light().workflowWarning.withValues(alpha: 0.72);
    expect((ring.valueColor as AlwaysStoppedAnimation<Color>).value.value,
        expected.value);
  });
}
```

- [ ] **Step 2：运行测试确认失败**

Run: `fvm flutter test test/widgets/context_window/context_window_usage_indicator_test.dart`
Expected: 编译失败，`context_window_usage_indicator.dart` 或 `ContextWindowUsageIndicator` 未定义。

- [ ] **Step 3：实现组件**

创建 `lib/widgets/context_window/context_window_usage_indicator.dart`：

```dart
import 'package:flutter/material.dart';

import '../../models/session/context_window_snapshot.dart';
import '../../theme/app_theme_spec.dart';
import 'context_window_usage_color.dart';

/// 底部工具栏右下角的 context 使用率指示器。
///
/// 以轻量圆环和常驻百分比呈现，点击打开详情 bottom sheet。
class ContextWindowUsageIndicator extends StatelessWidget {
  const ContextWindowUsageIndicator({
    super.key,
    required this.snapshot,
    required this.onTap,
  });

  /// 驱动圆环取值、颜色、语义标签的快照数据。
  final ContextWindowSnapshot snapshot;

  /// 点击圆环触发的回调（通常用于打开详情 bottom sheet）。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeSpec>()!;
    final ratio = snapshot.totalWindowUsageRatio.clamp(0.0, 1.0);
    final valueColor = resolveContextWindowUsageColor(colors, snapshot);
    final percent = (ratio * 100).round();

    return Semantics(
      button: true,
      label: 'Context 使用率 $percent%',
      child: InkWell(
        key: const ValueKey('context-window-usage-indicator'),
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                value: ratio,
                strokeWidth: 2,
                backgroundColor: colors.secondaryText.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(valueColor),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4：运行测试确认通过**

Run: `fvm flutter test test/widgets/context_window/context_window_usage_indicator_test.dart`
Expected: 4 个测试全部通过。

- [ ] **Step 5：analyze**

Run: `fvm flutter analyze lib/widgets/context_window/context_window_usage_indicator.dart test/widgets/context_window/context_window_usage_indicator_test.dart`
Expected: `No issues found!`

- [ ] **Step 6：提交**

```bash
git add lib/widgets/context_window/context_window_usage_indicator.dart test/widgets/context_window/context_window_usage_indicator_test.dart
git commit -m "feat: add ring-only context window usage indicator"
```

---

## Task 3：重构 `ChatInput` 为两行布局

**目标：** 用 `Column(TextField, Row(Spacer, ContextWindowUsageIndicator, SendButton))` 替换目前的 `Stack(Column(Row(TextField + SendButton)) + Positioned(ContextWindowStatusBar))`；`snapshot == null` / loading / error 时不渲染圆环。

**Files:**
- Modify: `lib/widgets/chat_input.dart`（整体改动：`build` 方法 line 101–253 区域）

- [ ] **Step 1：更新 import**

把 `lib/widgets/chat_input.dart` 第 9 行

```dart
import 'context_window/context_window_status_bar.dart';
```

替换为：

```dart
import 'context_window/context_window_usage_indicator.dart';
```

- [ ] **Step 2：替换 `build` 方法的主体**

将 `lib/widgets/chat_input.dart` 中 `Semantics(container: true, label: '聊天输入主面板', child: Stack(...))` 整个子树（从 `child: Stack(` 到对应闭合的 `),`，即原行 101–253）替换为：

```dart
child: Column(
  key: const ValueKey('chat-input-panel'),
  mainAxisSize: MainAxisSize.min,
  children: [
    Semantics(
      container: true,
      textField: true,
      enabled: !isComposerLocked,
      focused: focusNode.hasFocus,
      label: '聊天输入框',
      hint: '输入消息',
      value: composerValue,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 36),
        child: TextField(
          key: const ValueKey('chat-input-field'),
          focusNode: focusNode,
          controller: textController,
          enabled: !isComposerLocked,
          minLines: 1,
          maxLines: 4,
          textInputAction: TextInputAction.newline,
          keyboardType: TextInputType.multiline,
          style: AppTypography.uiStyle(
            color: colors.primaryText,
            fontSize: 13.7,
            height: 1.34,
          ),
          decoration: InputDecoration(
            hintText: '继续追问，或补充你的要求',
            hintStyle: AppTypography.uiStyle(
              color: colors.secondaryText.withValues(alpha: 0.66),
              fontSize: 13.3,
              height: 1.28,
            ),
            isDense: true,
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            contentPadding: EdgeInsets.fromLTRB(
              spacing.xs,
              spacing.xxs + 2,
              spacing.xs,
              spacing.xxs + 2,
            ),
          ),
          onSubmitted: (_) => submitCurrentInput(),
        ),
      ),
    ),
    SizedBox(height: spacing.xxs + 2),
    Semantics(
      container: true,
      label: '输入辅助操作栏',
      child: Row(
        key: const ValueKey('chat-input-bottom-bar'),
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Spacer(),
          contextWindowSnapshot.maybeWhen(
            data: (snapshot) {
              if (snapshot == null) {
                return const SizedBox.shrink();
              }
              return ContextWindowUsageIndicator(
                snapshot: snapshot,
                onTap: onContextWindowPressed ?? () {},
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
          SizedBox(width: spacing.xxs + 2),
          Semantics(
            container: true,
            button: true,
            enabled: isSendButtonEnabled,
            label: sendButtonLabel,
            child: SizedBox(
              width: 40,
              height: 40,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  shape: const CircleBorder(),
                  backgroundColor: isAwaitingConfirmation
                      ? colors.secondaryText.withValues(alpha: 0.82)
                      : colors.workflowRunning.withValues(alpha: 0.88),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                ),
                onPressed: () {
                  if (isCancellablePhase) {
                    chatController.cancelStreamSubscription();
                    return;
                  }

                  if (isBlockingPhase || isAwaitingConfirmation) {
                    return;
                  }

                  submitCurrentInput();
                },
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: isCancellablePhase
                      ? const Icon(
                          Icons.stop_rounded,
                          key: ValueKey('chat-input-stop-icon'),
                          size: 18,
                        )
                      : isBlockingPhase
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Icon(
                              isStreamingResponse
                                  ? Icons.stop_rounded
                                  : Icons.arrow_upward_rounded,
                              key: ValueKey(sendButtonLabel),
                              size: 18,
                            ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  ],
),
```

关键点：

- 原先包裹 `Column` 的 `Padding(padding: EdgeInsets.only(top: spacing.sm))` 一并删除（由新 `Column` 自然布局 + 外层已有 `Padding` 即可）。
- 原 `Stack` 连带 `Positioned(ContextWindowStatusBar)` 覆盖层整体删除。
- `ValueKey('chat-input-panel')` 从 `Stack` 上迁到 `Column` 上（测试会用到，保持稳定）。
- `isStreamingResponse`、`isAwaitingConfirmation`、`isCancellablePhase`、`isBlockingPhase`、`isSendButtonEnabled`、`submitCurrentInput`、`sendButtonLabel` 等局部变量已经在 `build` 开头定义，无需重复声明。

- [ ] **Step 3：运行现有 chat_input 测试（预期会更新）**

Run: `fvm flutter test test/widgets/chat_input_test.dart`
Expected: 原有测试仍应通过，因为它们只校验 `chat-input-dock` / `chat-input-panel` key、发送按钮图标、TextField 的 `minLines/maxLines`——这些在新结构下都保留。若有断言失败，参考断言文本与新结构对齐修正。

- [ ] **Step 4：analyze**

Run: `fvm flutter analyze lib/widgets/chat_input.dart`
Expected: `No issues found!`

- [ ] **Step 5：提交**

```bash
git add lib/widgets/chat_input.dart
git commit -m "refactor: switch chat input to two-row layout with bottom toolbar"
```

---

## Task 4：删除旧 `ContextWindowStatusBar` 与其测试

**目标：** 按 `AGENTS.md` 规则彻底删除不再使用的组件与测试，消除死代码。

**Files:**
- Delete: `lib/widgets/context_window/context_window_status_bar.dart`
- Delete: `test/widgets/context_window/context_window_status_bar_test.dart`

- [ ] **Step 1：删除旧文件**

```bash
git rm lib/widgets/context_window/context_window_status_bar.dart
git rm test/widgets/context_window/context_window_status_bar_test.dart
```

- [ ] **Step 2：确认无其他引用**

Run: `grep -r "ContextWindowStatusBar" lib test` （只能用普通 grep 作为搜索工具调用外的临时命令；若在交互会话中请改用 Grep 工具）
Expected: 没有任何命中（只有 `docs/` 里的历史实施计划可能仍包含字面，但不影响编译，不动历史文档）。

若仍有 `lib/` 或 `test/` 中的引用，回到 Task 3 检查是否遗漏了 import 替换或组件调用。

- [ ] **Step 3：analyze + 全量 test**

Run: `fvm flutter analyze`
Expected: `No issues found!`

Run: `fvm flutter test test/widgets/chat_input_test.dart test/widgets/context_window/`
Expected: 全部通过。

- [ ] **Step 4：提交**

```bash
git commit -m "chore: remove superseded ContextWindowStatusBar"
```

---

## Task 5：补充 `ChatInput` 两行布局的增量测试

**目标：** 在 `test/widgets/chat_input_test.dart` 中新增用例，锁定「底部工具栏存在 / 圆环出现时机 / 圆环点击行为」这三条语义契约。

**Files:**
- Modify: `test/widgets/chat_input_test.dart`

- [ ] **Step 1：追加新测试块**

在现有 `main()` 末尾追加（保留既有测试）：

```dart
testWidgets('chat input renders bottom bar without indicator when snapshot is null',
    (tester) async {
  final container = ProviderContainer(
    overrides: [
      contextWindowSnapshotProvider.overrideWith(
        (ref) async => null,
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: ChatInput()),
      ),
    ),
  );
  await tester.pumpAndSettle();

  expect(find.byKey(const ValueKey('chat-input-bottom-bar')), findsOneWidget);
  expect(
    find.byKey(const ValueKey('context-window-usage-indicator')),
    findsNothing,
  );
  expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
});

testWidgets('chat input shows indicator and forwards tap when snapshot exists',
    (tester) async {
  final snapshot = ContextWindowSnapshot(
    modelName: 'gpt-test',
    maxContextTokens: 128000,
    usableInputBudget: 104000,
    compressionTriggerRatio: 0.8,
    totalEstimatedInputTokens: 12000,
    totalWindowUsageRatio: 0.23,
    usableInputUsageRatio: 0.2,
    didCompactHistory: false,
    recentCompletedTurnCount: 1,
    segments: const <ContextWindowSegment>[],
  );
  final container = ProviderContainer(
    overrides: [
      contextWindowSnapshotProvider.overrideWith((ref) async => snapshot),
    ],
  );
  addTearDown(container.dispose);

  var taps = 0;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ChatInput(onContextWindowPressed: () => taps += 1),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  expect(
    find.byKey(const ValueKey('context-window-usage-indicator')),
    findsOneWidget,
  );

  await tester.tap(
    find.byKey(const ValueKey('context-window-usage-indicator')),
  );
  expect(taps, 1);
});
```

文件顶部追加必要 import（如尚未存在）：

```dart
import 'package:ai_chat/models/session/context_window_segment.dart';
import 'package:ai_chat/models/session/context_window_snapshot.dart';
```

- [ ] **Step 2：运行测试**

Run: `fvm flutter test test/widgets/chat_input_test.dart`
Expected: 全部通过，包括原有 + 新增两个 testWidgets。

- [ ] **Step 3：analyze**

Run: `fvm flutter analyze test/widgets/chat_input_test.dart`
Expected: `No issues found!`

- [ ] **Step 4：提交**

```bash
git add test/widgets/chat_input_test.dart
git commit -m "test: cover chat input bottom bar and usage indicator"
```

---

## Task 6：全量回归与 README/AGENTS 对齐检查

**目标：** 全仓 analyze + test 通过；确认无需改 README 架构段 / AGENTS 约束段（仅 UI 局部重排应当不触发）；列出人工验收清单。

**Files:** （无源码改动，仅校验）

- [ ] **Step 1：全量 analyze**

Run: `fvm flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2：全量 test**

Run: `fvm flutter test`
Expected: 全部通过。若有不相关的既存 flaky 用例，不要在此 PR 修复，先记录到 TODO 再继续。

- [ ] **Step 3：人工/自动化端到端（可选但推荐）**

按 `AGENTS.md`：

- 有连接的 Android 真机时：`bash scripts/android_install_debug.sh` 安装并目视验证输入框两行布局、圆环出现、发送可用；
- 或：`bash scripts/android_droidrun_driver_smoke.sh` 跑一次发送回归。

- [ ] **Step 4：确认 README/AGENTS 无需更新**

Grep 确认 README 没有描述旧 `ContextWindowStatusBar` 覆盖层：

- Grep `ContextWindowStatusBar` in `README.md` → 无命中则跳过；若有，改为描述新组件 `ContextWindowUsageIndicator`。

AGENTS.md 本次无新约束需加入（布局局部重构，不影响架构边界）。

- [ ] **Step 5：提交（若 Step 4 有文档改动；否则跳过）**

```bash
git add README.md
git commit -m "docs: reflect chat input ring-only usage indicator"
```

---

## Self-Review 结果

1. **Spec coverage：** 逐节对照 spec 第 4 节—— 4.1 布局（Task 3）、4.2 新组件（Task 2）、4.3 颜色共享（Task 1）、4.4 删除旧组件与测试（Task 4）、4.5 空状态（Task 3 Step 2 的 `maybeWhen` + Task 5 用例）、4.6 数据流（Task 3）；第 7 节测试计划分散在 Task 1/2/5；第 9 节交付物清单全部命中（除可选 README 更新归 Task 6）。
2. **Placeholder 扫描：** 无 TBD/TODO/"etc."/"similar to"。所有代码块为完整可复制内容。
3. **类型一致性：** `ContextWindowSnapshot` 字段名（`totalWindowUsageRatio`、`compressionTriggerRatio`）在三处使用一致；`resolveContextWindowUsageColor(AppThemeSpec, ContextWindowSnapshot)` 签名在 Task 1 定义、Task 2 消费一致；`ContextWindowUsageIndicator` 仅接受 `snapshot` + `onTap`（Task 2 定义、Task 3 消费一致）；`ValueKey('context-window-usage-indicator')` 在组件内部与测试中一致；`ValueKey('chat-input-bottom-bar')` 在 Task 3 布局与 Task 5 测试一致。
