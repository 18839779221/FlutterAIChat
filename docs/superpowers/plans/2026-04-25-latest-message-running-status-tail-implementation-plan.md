# 最新消息底部运行状态尾注 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将输入框顶部的运行状态文案迁移到最新消息块底部，以轻量尾注 + 低强度刀光的方式表达“仍在执行中”。

**Architecture:** 复用现有 `ChatSendPhase`、tool workflow / result 渲染链路和 running effects 语义，不新增第二套状态机。状态归属判断放在消息列表装配层，由消息块负责承载尾注；输入区仅移除旧 helper 文案，不再承担执行状态主展示。

**Tech Stack:** Flutter、Dart、flutter_riverpod、现有 `ChatBlockBuilder` / tool renderer 体系、`flutter_test`

---

## 文件结构与职责

### 现有文件

- `lib/widgets/chat_input.dart`
  - 当前输入框顶部 helper 文案承载点；本次需要移除运行态文案展示。
- `lib/widgets/chat_message_list.dart`
  - 当前消息列表与 assistant/tool block 装配主入口；本次需要决定“最新消息块”并注入尾注。
- `lib/providers/chat_send_state_providers.dart`
  - 提供 `ChatSendPhase`；尾注文案和是否显示的顶层语义来源之一。
- `lib/widgets/tool_renderers/tool_running_effects.dart`
  - 当前已有大卡片 sweep 和低噪音动效能力；本次复用其局部能力或抽出适配尾注的轻量效果。
- `test/widgets/chat_input_test.dart`
  - 输入区 UI 回归测试入口。
- `test/widgets/chat_message_list_test.dart`
  - 消息列表主渲染测试入口。
- `test/widgets/chat_message_list_interaction_test.dart`
  - 若需要验证尾注切换或挂载行为，可在这里补交互级测试。

### 新增文件

- `lib/widgets/chat_blocks/latest_message_running_status_tail.dart`
  - 轻量尾注组件，只负责状态点、文案、低强度刀光，不负责业务状态判断。

## 实现原则

- 不引入新的全局悬浮状态条。
- 不在 controller 中写“最新消息块”选择逻辑，归属判断放在 UI 装配层。
- 不保留“已完成”尾注残留态，执行结束后直接移除。
- 先用现有 `ChatSendPhase` + 最新 block 类型完成 MVP，再视需要补更细粒度 tool 文案映射。
- 修改遵循 TDD：先补失败测试，再做最小实现。

## 任务拆解

### Task 1: 固化输入区迁移边界

**Files:**
- Modify: `lib/widgets/chat_input.dart`
- Test: `test/widgets/chat_input_test.dart`

- [ ] **Step 1: 为输入区移除 helper 文案写失败测试**

补一个测试，覆盖非 `idle` 阶段时输入区不再渲染：

- `正在规划下一步`
- `等待工具确认`
- `工具执行中`
- `正在生成回复`

可参考已有 `ChatInput` pump 方式，断言这些文案不存在。

- [ ] **Step 2: 运行输入区测试，确认新用例先失败**

Run: `"$HOME/.pub-cache/bin/fvm" flutter test test/widgets/chat_input_test.dart`

Expected:
- 新增断言失败，原因是 `ChatInput` 仍在渲染 helper 文案。

- [ ] **Step 3: 删除输入区顶部 helper 区域的最小实现**

在 `lib/widgets/chat_input.dart`：

- 移除 `helperText` 变量和 `_buildHelperText()` 使用
- 删掉顶部 `Align + Text + SizedBox` 区块
- 保持现有输入区间距、按钮、锁定逻辑不变

- [ ] **Step 4: 重新运行输入区测试，确认通过**

Run: `"$HOME/.pub-cache/bin/fvm" flutter test test/widgets/chat_input_test.dart`

Expected:
- 相关测试全部通过

- [ ] **Step 5: 提交这一小步**

```bash
git add lib/widgets/chat_input.dart test/widgets/chat_input_test.dart
git commit -m "refactor: remove input running helper text"
```

### Task 2: 新增最新消息尾注组件

**Files:**
- Create: `lib/widgets/chat_blocks/latest_message_running_status_tail.dart`
- Modify: `lib/widgets/tool_renderers/tool_running_effects.dart`
- Test: `test/widgets/chat_message_list_test.dart`

- [ ] **Step 1: 为尾注组件写失败测试**

在消息列表测试中先定义期望：

- 尾注文案是单行轻量状态
- 左侧有状态点语义
- running 时可渲染尾注容器 key，例如 `latest-message-running-tail`

先不要求动画逐帧验证，只验证结构存在。

- [ ] **Step 2: 运行消息列表测试，确认新用例先失败**

Run: `"$HOME/.pub-cache/bin/fvm" flutter test test/widgets/chat_message_list_test.dart`

Expected:
- 因为尾注组件尚不存在，测试失败。

- [ ] **Step 3: 创建尾注组件最小实现**

在 `lib/widgets/chat_blocks/latest_message_running_status_tail.dart` 中新增组件：

- 入参建议：
  - `String statusText`
  - `bool isVisible`
- 内部结构：
  - 单行 `Row`
  - 左侧小状态点
  - 右侧状态文案
  - 外层轻量 sweep surface 或局部 sweep painter
- 样式约束：
  - 不单独描边
  - 不显式卡片化
  - 字号比正文小一级

- [ ] **Step 4: 复用或扩展 running effects**

如果 `tool_running_effects.dart` 已有可复用的 sweep 基元，则优先抽一个局部轻量版本，例如：

- `SubtleSweepInlineSurface`

要求：

- 只作用于尾注宽度
- 强度低于 `RunningSweepSurface`
- 不影响现有大卡片动效

- [ ] **Step 5: 运行消息列表测试，确认尾注结构通过**

Run: `"$HOME/.pub-cache/bin/fvm" flutter test test/widgets/chat_message_list_test.dart`

Expected:
- 新增尾注结构测试通过

- [ ] **Step 6: 提交这一小步**

```bash
git add lib/widgets/chat_blocks/latest_message_running_status_tail.dart lib/widgets/tool_renderers/tool_running_effects.dart test/widgets/chat_message_list_test.dart
git commit -m "feat: add latest message running tail widget"
```

### Task 3: 在消息列表中定位最新消息块并挂载尾注

**Files:**
- Modify: `lib/widgets/chat_message_list.dart`
- Modify: `lib/providers/chat_send_state_providers.dart`（仅当需要新增轻量文案映射 helper）
- Test: `test/widgets/chat_message_list_test.dart`
- Test: `test/widgets/chat_message_list_interaction_test.dart`

- [ ] **Step 1: 为“尾注挂在最新消息块底部”写失败测试**

在 `test/widgets/chat_message_list_test.dart` 中补至少两类用例：

- assistant 流式输出时，尾注出现在最新 assistant block 下方
- tool workflow / tool result 为最新块时，尾注挂在该 block 下方，而不是列表底部独立出现

断言重点：

- 页面上只出现一个尾注
- 尾注位于最新块的 subtree 内，而不是输入区或列表独立元素

- [ ] **Step 2: 运行消息列表测试，确认新用例先失败**

Run: `"$HOME/.pub-cache/bin/fvm" flutter test test/widgets/chat_message_list_test.dart test/widgets/chat_message_list_interaction_test.dart`

Expected:
- 因为尚未注入尾注，新增用例失败。

- [ ] **Step 3: 在 `chat_message_list.dart` 增加最新块归属判定**

实现建议：

- 在 `_buildAssistantBlocks(...)` 这一层完成注入
- 先判定本次 blocks 中哪一个是“当前最新可见输出块”
- 仅在以下条件满足时注入尾注：
  - 当前 send phase 不是 `idle`
  - 当前 block 是全列表最后一个可承载输出块

避免：

- 在每个 block renderer 内部分别判断
- 让多个 block 同时渲染尾注

- [ ] **Step 4: 添加尾注文案映射 helper**

优先简单映射：

- `preparing -> 正在规划下一步`
- `awaitingConfirmation -> 等待工具确认`
- `executingTool -> 正在执行工具`
- `streamingResponse -> 正在继续生成`

如果当前 block 是 tool workflow / result，可再按 block payload 做轻量覆盖，例如：

- `web_search -> 正在联网搜索`
- `fetch_webpage -> 正在读取网页`

注意：

- 先做最小映射，不要引入复杂工具文案路由表
- 取不到具体 tool 时回落到通用文案

- [ ] **Step 5: 将尾注作为 block 底部附加内容注入**

做法建议：

- 为对应 block 包一层 `Column`
- 原 block 在上
- `LatestMessageRunningStatusTail` 在下
- 通过较小 `SizedBox` 控制与正文节奏

不要：

- 直接把尾注插入 timeline 顶层 items
- 让尾注成为新的 assistant message

- [ ] **Step 6: 运行消息列表测试，确认挂载逻辑通过**

Run: `"$HOME/.pub-cache/bin/fvm" flutter test test/widgets/chat_message_list_test.dart test/widgets/chat_message_list_interaction_test.dart`

Expected:
- 最新块挂载测试通过
- 只显示一个尾注

- [ ] **Step 7: 提交这一小步**

```bash
git add lib/widgets/chat_message_list.dart lib/providers/chat_send_state_providers.dart test/widgets/chat_message_list_test.dart test/widgets/chat_message_list_interaction_test.dart
git commit -m "feat: attach running tail to latest message block"
```

### Task 4: 调整 tool / assistant 场景下的稳定性与细节

**Files:**
- Modify: `lib/widgets/chat_message_list.dart`
- Modify: `lib/widgets/chat_blocks/latest_message_running_status_tail.dart`
- Test: `test/widgets/chat_message_list_test.dart`

- [ ] **Step 1: 为边界场景补失败测试**

补至少这些场景：

- `idle` 时不显示尾注
- 最新块切换后，旧块不残留尾注
- tool 并发执行时仍只有一个尾注
- tool 完成后尾注消失

- [ ] **Step 2: 运行测试，确认先失败**

Run: `"$HOME/.pub-cache/bin/fvm" flutter test test/widgets/chat_message_list_test.dart`

Expected:
- 至少一个新增边界用例失败。

- [ ] **Step 3: 修正最新块切换与隐藏逻辑**

在 `chat_message_list.dart` 中确保：

- 尾注只挂在当前全列表最后一个承载块
- 数据变化后不会在旧块残留
- `sendPhase == idle` 时直接不构建尾注

- [ ] **Step 4: 收敛视觉细节**

在尾注组件里微调：

- 行高
- 文案透明度
- sweep 透明度与周期
- 状态点脉冲强度

目标：

- 明显可感知
- 不干扰正文和 tool card

- [ ] **Step 5: 重新运行消息列表测试**

Run: `"$HOME/.pub-cache/bin/fvm" flutter test test/widgets/chat_message_list_test.dart`

Expected:
- 边界场景全部通过

- [ ] **Step 6: 提交这一小步**

```bash
git add lib/widgets/chat_message_list.dart lib/widgets/chat_blocks/latest_message_running_status_tail.dart test/widgets/chat_message_list_test.dart
git commit -m "fix: stabilize latest running tail behavior"
```

### Task 5: 回归验证与文档同步

**Files:**
- Modify: `README.md`（仅当聊天页状态展示描述已过时）
- Modify: `AGENTS.md`（仅当需要沉淀新的 UI 约束）

- [ ] **Step 1: 跑定向测试集合**

Run:

```bash
"$HOME/.pub-cache/bin/fvm" flutter test test/widgets/chat_input_test.dart test/widgets/chat_message_list_test.dart test/widgets/chat_message_list_interaction_test.dart
```

Expected:
- 全部 PASS

- [ ] **Step 2: 跑静态检查**

Run:

```bash
"$HOME/.pub-cache/bin/fvm" flutter analyze lib/widgets/chat_input.dart lib/widgets/chat_message_list.dart lib/widgets/chat_blocks/latest_message_running_status_tail.dart lib/widgets/tool_renderers/tool_running_effects.dart test/widgets/chat_input_test.dart test/widgets/chat_message_list_test.dart test/widgets/chat_message_list_interaction_test.dart
```

Expected:
- `No issues found!`

- [ ] **Step 3: 判断是否需要同步文档**

检查：

- `README.md` 是否描述了输入区顶部状态
- `AGENTS.md` 是否需要补充“运行态提示优先跟随最新消息块”的 UI 约束

仅在确实过时或有新规范沉淀价值时修改，避免无关文档噪音。

- [ ] **Step 4: 如有文档修改，补对应说明并验证**

Run:

```bash
git diff -- README.md AGENTS.md
```

Expected:
- 仅保留与本次行为变更直接相关的文档更新

- [ ] **Step 5: 最终提交**

```bash
git add lib/widgets/chat_input.dart lib/widgets/chat_message_list.dart lib/widgets/chat_blocks/latest_message_running_status_tail.dart lib/widgets/tool_renderers/tool_running_effects.dart test/widgets/chat_input_test.dart test/widgets/chat_message_list_test.dart test/widgets/chat_message_list_interaction_test.dart README.md AGENTS.md
git commit -m "feat: move running status to latest message tail"
```

## 验收清单

- [ ] 输入框顶部不再显示运行状态文案
- [ ] 最新消息块底部能显示单条运行状态尾注
- [ ] assistant 流式输出时，尾注挂在最新 assistant 消息底部
- [ ] tool workflow / result 为最新块时，尾注挂在对应工具块底部
- [ ] 运行中始终只有一条尾注
- [ ] 执行完成后尾注直接消失
- [ ] 尾注刀光明显弱于大卡片 running sweep
- [ ] 定向 widget tests 与 analyze 全部通过

## 备注

- 本计划不使用 subagent reviewer，因为当前会话没有用户授权并行代理执行；执行时直接按本计划逐步落地即可。
