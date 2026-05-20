# 输入框 2 行布局改造设计

- 日期：2026-04-27
- 作者：协作（用户 + Claude）
- 相关文件：`lib/widgets/chat_input.dart`、`lib/widgets/context_window/context_window_status_bar.dart`

## 1. 背景与目标

当前输入框（`ChatInput`）是单行 `Row(TextField + 圆形发送按钮)`，`ContextWindowStatusBar` 以 `Positioned` 覆盖在输入框右上角，属于覆盖层方案。随着后续要在输入区承载更多状态信息（首要是 context 已用比例的直观呈现），单行 + 覆盖层的组织方式已经不够扩展。

目标：将输入区改造为 **2 行布局**——

- 第一行：文本输入（保持现有 `minLines: 1, maxLines: 4` 行为）；
- 第二行：底部工具栏，右下角承载 context 使用率信息（圆环 + 百分比）与发送按钮。

本次改造仅做**布局重排**和**表达形式迁移**，不新增功能按钮（无附件、权限、模型选择器等）。

## 2. 非目标

- 不新增 `+` / 权限 / 模型选择器 / 自定义标签等参考图中的能力；
- 不改动 `contextWindowSnapshotProvider` 及其上游任何服务；
- 不改动发送按钮的状态机（idle / preparing / streamingResponse / awaitingConfirmation 等）；
- 不改动 `ContextWindowDetailBottomSheet` 自身；
- 不对 `ChatInput` 之外的页面进行视觉调整。

## 3. 现状梳理

- 入口：`lib/widgets/chat_input.dart:11` 的 `ChatInput extends ConsumerWidget`；
- 容器结构：`Padding → DecoratedBox → Padding → Stack`；
- `Stack` 里：
  - `Padding → Column → Row(TextField + SendButton)`；
  - `Positioned(top:0, right: spacing.xs + 44)` 套 `ContextWindowStatusBar(compact: true)`；
- 数据源：`ref.watch(contextWindowSnapshotProvider)`，`snapshot == null` 时覆盖层不渲染；
- `ContextWindowStatusBar` 目前只有一种形态（compact 线性进度条），颜色分三档，基于 `totalWindowUsageRatio` 与 `compressionTriggerRatio`。

## 4. 设计方案

### 4.1 输入框布局

将 `Stack` 外壳移除，改为：

```
DecoratedBox
  Padding
    Column
      TextField             // minLines: 1, maxLines: 4（不变）
      SizedBox(工具栏间距)
      Row(bottomBar, crossAxisAlignment: center)
        Spacer()            // 左侧暂留空（已确认不新增按钮）
        ContextWindowUsageIndicator(snapshot, onTap)   // 仅圆环
        SizedBox(间距)
        SendButton(...)     // 原 40×40 圆形按钮
```

- 外层 `DecoratedBox`（圆角、阴影、背景）保留现状；
- 容器内 `Padding` 略作调整以适配双行（视觉 QA 时微调）；
- `TextField` 本体、`InputDecoration`、`Semantics` 语义节点保持不变；
- 不再需要原 `Stack` 和 `Positioned` 覆盖层。

### 4.2 新组件 `ContextWindowUsageIndicator`

位置：`lib/widgets/context_window/context_window_usage_indicator.dart`

职责：在底部工具栏 inline 显示 context 使用率。

形态：**轻量圆环 + 常驻百分比文字**。

```dart
class ContextWindowUsageIndicator extends StatelessWidget {
  const ContextWindowUsageIndicator({
    super.key,
    required this.snapshot,
    required this.onTap,
  });

  final ContextWindowSnapshot snapshot; // 入参与 ContextWindowStatusBar 对齐
  final VoidCallback onTap;             // 点击打开 ContextWindowDetailBottomSheet
}
```

视觉规格：

- 圆环本体：`CircularProgressIndicator(value: ratio, strokeWidth: 2)`，尺寸 16×16；
- 百分比文字：常驻显示，例如 `54%`，使用弱化 caption 风格，不单独显示更多说明文案；
- 颜色：沿用当前三档逻辑（`secondaryText → workflowRunning → workflowWarning`），阈值与 `ContextWindowStatusBar._resolveValueColor` 完全一致；
- 背景：`secondaryText.withValues(alpha: 0.12)`（与现状一致）；
- 点击热区：外层 `InkWell` + `Padding`，热区不小于 32×32，保证小尺寸下仍可点击；
- 无障碍：`Semantics(label: 'Context 使用率 ${(ratio*100).round()}%', button: true)`。

### 4.3 颜色阈值函数共享

把 `ContextWindowStatusBar._resolveValueColor` 提取为顶层函数或独立工具文件：

- 建议：新增 `lib/widgets/context_window/context_window_usage_color.dart`，导出 `Color resolveContextWindowUsageColor(AppThemeSpec colors, ContextWindowSnapshot snapshot)`；
- 仅由新组件 `ContextWindowUsageIndicator` 使用（旧 `ContextWindowStatusBar` 将被删除，见 4.4）；
- 避免两处重复阈值逻辑。

### 4.4 旧组件与测试去向

按 `AGENTS.md` "内部开发阶段，不保留兼容层" 原则：

- 删除 `lib/widgets/context_window/context_window_status_bar.dart`；
- 删除 `test/widgets/context_window/context_window_status_bar_test.dart`；
- 新增 `test/widgets/context_window/context_window_usage_indicator_test.dart`，覆盖：
  - `ratio` 在三个阈值档位下，`CircularProgressIndicator.valueColor` 取值正确；
  - 点击触发 `onTap` 一次；
  - 屏幕上直接显示正确的百分比；
  - `Semantics.label` 包含正确的百分比（四舍五入）；
  - 热区至少 32×32（通过查询渲染盒尺寸验证）；
- `docs/superpowers/plans/2026-04-27-session-context-window-visualization-implementation-plan.md` 中若引用了 `ContextWindowStatusBar`，保留历史引用不修订（历史文档不回写）。

### 4.5 空状态

`contextWindowSnapshotProvider` 返回 `AsyncValue<ContextWindowSnapshot?>`：

- `data(null)`、`loading`、`error`：**均不渲染圆环**（工具栏只剩 `Spacer + SendButton`），与当前 status bar 行为保持一致；
- 不引入占位符或骨架屏。

### 4.6 数据流

- `ChatInput` 继续 `ref.watch(contextWindowSnapshotProvider)`；
- 将 `snapshot` 和 `onContextWindowPressed ?? () {}` 作为 props 传给 `ContextWindowUsageIndicator`；
- `ContextWindowUsageIndicator` 自身不直接访问 provider（与 `ContextWindowStatusBar` 的依赖方向一致，便于测试）。

## 5. 架构一致性检查

- Riverpod：不新增 provider，不改动 controller 边界；
- UI/Controller 分层：新组件属纯展示（Stateless），消费由页面级组件注入的 snapshot；
- 会话上下文：完全不触达 `SessionContextService` 及相关服务；
- 日志：无新增日志需求，不触发 `docs/architecture/logging.md` 更新；
- README / AGENTS：本次仅为 UI 局部重排，不改变架构约束，暂不更新。

## 6. 视觉细节与交互

- `TextField` 保持 `minLines: 1, maxLines: 4`；"2 行" 由独立的底部工具栏实现，而非 `TextField` 最小 2 行；
- 底部工具栏高度由 `SendButton`（40 px）决定，`ContextWindowUsageIndicator` 与其在 `Row` 内垂直居中；
- `Spacer` 占据左侧空间，使圆环与发送按钮紧贴右侧；
- 键盘弹出 / 回落时的外层 `Padding` 逻辑（`keyboardHeight > 0`、`bottomSafeArea`）保持不变；
- `Semantics(container: true, label: '聊天输入主面板')` 保留；底部工具栏可追加 `Semantics(label: '输入辅助操作栏')` 以改善读屏。

## 7. 测试计划

- **widget 测试** `context_window_usage_indicator_test.dart`：见 4.4；
- **widget 测试** `chat_input_test.dart`（若不存在则新建精简版）：
- `snapshot == null` 时工具栏不含 context 使用率信息；
- `snapshot != null` 时百分比与圆环可见，点击触发 `onContextWindowPressed` 回调一次；
  - 发送按钮在 `idle` / `streamingResponse` / `preparing` 三态下图标与可点击性正确（至少覆盖 idle + streamingResponse）；
- **回归**：`fvm flutter analyze` + `fvm flutter test` 全量通过；
- **端到端**：按 `AGENTS.md` 推荐，在 Android 真机或 Droidrun driver smoke 上手动确认输入框视觉与发送路径。

## 8. 风险与回滚

- 风险：圆环尺寸过小导致点击困难 → 以 32×32 热区 + `InkWell` 缓解，测试中验证；
- 风险：底部工具栏高度让整个 dock 变高，挤压消息区 → QA 阶段在多种设备尺寸下确认（≤ 小屏 5.5 寸）；
- 回滚：本改动无数据结构、无 schema 变更，如需回滚可直接 revert 该 PR。

## 9. 交付物

- `lib/widgets/chat_input.dart`：布局重排；
- `lib/widgets/context_window/context_window_usage_indicator.dart`：新建；
- `lib/widgets/context_window/context_window_usage_color.dart`：新建（颜色阈值函数）；
- `lib/widgets/context_window/context_window_status_bar.dart`：删除；
- `test/widgets/context_window/context_window_status_bar_test.dart`：删除；
- `test/widgets/context_window/context_window_usage_indicator_test.dart`：新建；
- 可选：`test/widgets/chat_input_test.dart` 增量补测。
