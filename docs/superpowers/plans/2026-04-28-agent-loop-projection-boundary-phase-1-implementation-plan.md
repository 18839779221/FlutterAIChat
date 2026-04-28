# Agent Loop Projection Boundary Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立 `turn ledger -> projection model -> UI` 的第一阶段稳定边界，让 waiting/workflow/interaction 相关 UI 不再直接散落依赖 `messagesProvider` 与 `ChatMessage.payloadJson` 扫描。

**Architecture:** 本阶段不重写 `TurnHarness`，也不提前做 `ChatSendCoordinator` 瘦身。我们先把“UI 真正消费什么状态”收敛成一层显式 projection contract，并让 `ChatBlockBuilder`、`chat_ui_providers`、`ChatMessageList`、`ChatTimelineRow` 改为消费这层 contract。短期内 projection 仍可由现有 message/block 事实层构建，但 UI 侧不再自己重新推断状态，为第二阶段和模拟环境集成测试层打稳定基础。

**Tech Stack:** Flutter 3.29.2、Dart、flutter_riverpod、Flutter widget tests、service/provider unit tests

---

## 范围与边界

本计划只覆盖第一阶段：

- 建立显式 projection model
- 让 waiting state / workflow state / interaction state 由 projection 层统一产出
- 让 UI 与 provider 优先消费 projection contract
- 清理随迁移失效的直接消息扫描路径和重复 payload 解析辅助逻辑

本计划明确不覆盖：

- `ChatSendCoordinator` 职责瘦身
- 新的模拟环境 integration harness
- `TurnHarness` 主循环语义调整
- provider adapter / 真实 LLM 请求协议修复

## 文件结构

### 预期新增文件

- `lib/models/chat/chat_timeline_projection.dart`
  - 定义页面级 projection 聚合模型，例如 timeline items、active interaction、pending confirmation、workflow lookup 等稳定字段
- `lib/services/chat_timeline_projection_service.dart`
  - 统一从现有事实层构建 projection，集中处理 waiting/workflow/interaction 判定
- `test/services/chat_timeline_projection_service_test.dart`
  - 覆盖 projection 构建与等待态判定的主路径
- `test/providers/chat_ui_projection_test.dart`
  - 覆盖 provider 对 projection 的消费，而不是对 `messagesProvider` 的直接扫描

### 预期修改文件

- `lib/models/chat/assistant_turn_block.dart`
  - 为 block 增加 typed projection 字段，减少 render 时二次从 payload 反解
- `lib/services/chat_block_builder.dart`
  - 让 workflow/result/interaction block 输出 typed projection 数据
- `lib/providers/chat_ui_providers.dart`
  - 新增 projection provider，并将 active interaction / pending confirmation 改为消费 projection
- `lib/widgets/chat_message_list.dart`
  - 使用 projection service/provider 构建 timeline items，而不是局部拼装多套状态来源
- `lib/widgets/chat_timeline/chat_timeline_row.dart`
  - 改为消费 typed workflow/result projection，删掉多余 payload 反解辅助逻辑
- `test/services/chat_block_builder_test.dart`
  - 更新为断言 typed workflow/result projection 输出
- `test/widgets/chat_message_list_interaction_test.dart`
  - 更新为断言页面消费 projection 后的 ask-user-question / confirmation 行为
- `README.md`
  - 如本阶段引入了新的 projection service/model，需要补一条简短架构说明
- `AGENTS.md`
  - 仅当实现期发现新的长期约束需要固定时再补；不要为了同步而重复已有规则

### 需要重点检查是否可删除的旧路径

- `lib/providers/chat_ui_providers.dart` 中直接扫描 `messagesProvider` 的 waiting-state 逻辑
- `lib/widgets/chat_timeline/chat_timeline_row.dart` 中 `_extractWorkflowSteps()` / `ToolResult.fromJson(payload)` 这一类 render-time payload 反解逻辑
- `lib/services/chat_block_builder.dart` 中仅为 UI payload 兼容而存在、但迁移后不再需要的辅助字段组装

---

### Task 1: 定义 Projection Contract，并先写失败测试

**Files:**
- Create: `lib/models/chat/chat_timeline_projection.dart`
- Create: `lib/services/chat_timeline_projection_service.dart`
- Create: `test/services/chat_timeline_projection_service_test.dart`
- Modify: `lib/models/chat/assistant_turn_block.dart`
- Modify: `test/services/chat_block_builder_test.dart`

- [ ] **Step 1: 盘点当前 UI 真正需要的投影状态，并记录到计划执行注释里**

检查文件：
- `lib/providers/chat_ui_providers.dart`
- `lib/widgets/chat_message_list.dart`
- `lib/widgets/chat_timeline/chat_timeline_row.dart`
- `test/widgets/chat_message_list_interaction_test.dart`

结论至少要覆盖：
- timeline item 列表
- active ask-user-question prompt
- pending tool confirmation
- tool workflow steps
- tool result typed payload

- [ ] **Step 2: 为 projection model 写失败测试**

在 `test/services/chat_timeline_projection_service_test.dart` 先写这些失败用例：

```dart
test('returns active ask-user-question from projection instead of message scan');
test('returns pending confirmation from projection instead of message scan');
test('keeps timeline items and waiting state derived from the same projection snapshot');
test('prefers typed workflow/result data over payload re-parsing when blocks already carry projection fields');
```

再在 `test/services/chat_block_builder_test.dart` 增加失败断言：

```dart
expect(blocks.single.workflowSteps, isNotEmpty);
expect(blocks.single.toolResult, isNotNull);
```

- [ ] **Step 3: 运行失败测试，确认测试确实卡在新 contract 缺失**

Run:
```bash
fvm flutter test test/services/chat_timeline_projection_service_test.dart test/services/chat_block_builder_test.dart
```

Expected:
- `chat_timeline_projection.dart` / `ChatTimelineProjectionService` / typed block 字段不存在
- 至少 1 个新增断言失败，而不是误通过

- [ ] **Step 4: 最小实现 projection model 骨架与 typed block 字段**

实现最小骨架：
- `ChatTimelineProjection`
- `ProjectedPendingToolConfirmation`
- `ProjectedAskUserQuestion`
- block 上的 typed `workflowSteps` / `toolResult` 字段

要求：
- 不在 model 里直接耦合 provider
- 不提前引入过厚 schema
- 字段只覆盖当前 UI 和测试确实需要的状态

- [ ] **Step 5: 再次运行测试，确保骨架层通过或只剩预期失败**

Run:
```bash
fvm flutter test test/services/chat_timeline_projection_service_test.dart test/services/chat_block_builder_test.dart
```

Expected:
- model/typed 字段相关编译错误消失
- 如仍有失败，只剩 service 逻辑尚未实现的预期失败

- [ ] **Step 6: 提交这一小步**

```bash
git add lib/models/chat/assistant_turn_block.dart lib/models/chat/chat_timeline_projection.dart lib/services/chat_timeline_projection_service.dart test/services/chat_timeline_projection_service_test.dart test/services/chat_block_builder_test.dart
git commit -m "refactor: add chat timeline projection foundation"
```

### Task 2: 让 ChatBlockBuilder 输出 Typed Projection，减少 render-time payload 反解

**Files:**
- Modify: `lib/models/chat/assistant_turn_block.dart`
- Modify: `lib/services/chat_block_builder.dart`
- Modify: `test/services/chat_block_builder_test.dart`

- [ ] **Step 1: 为 ChatBlockBuilder 新增失败断言，锁定 typed 输出行为**

在 `test/services/chat_block_builder_test.dart` 增补：

```dart
test('maps confirmation message to typed workflow steps');
test('maps tool result message to typed tool result');
test('keeps ask-user-question blocks as typed structured interaction projections');
test('does not require payload step reconstruction in consumers once typed fields exist');
```

- [ ] **Step 2: 运行单测，确认当前 builder 还没有完整满足 typed contract**

Run:
```bash
fvm flutter test test/services/chat_block_builder_test.dart
```

Expected:
- 新增 typed 断言失败

- [ ] **Step 3: 修改 ChatBlockBuilder，让 workflow/result/interactions 直接挂 typed 字段**

要求：
- `toolWorkflow` block 直接产出 `List<ToolWorkflowStep>`
- `toolResultSummary` block 直接产出 `ToolResult`
- `structuredOutput` 至少带稳定的 interaction 标识信息
- 保留最小必要 payload 兼容字段，避免一次性打断全部 UI

- [ ] **Step 4: 清理 builder 中迁移后不再需要的 UI-only payload 拼装**

删除前先确认没有存活引用。

优先清理：
- 仅服务 render-time `_extractWorkflowSteps()` 的重复字段
- 已被 typed 字段替代的 result payload 再编码

- [ ] **Step 5: 运行 builder 相关测试，确认通过**

Run:
```bash
fvm flutter test test/services/chat_block_builder_test.dart test/widgets/tool_renderers/write_tool_cards_test.dart test/widgets/tool_renderers/edit_tool_cards_test.dart test/widgets/tool_renderers/web_search_tool_cards_test.dart test/widgets/tool_renderers/fetch_webpage_tool_cards_test.dart
```

Expected:
- 所有相关测试 PASS
- 没有因为删字段导致现有 tool renderer 退化

- [ ] **Step 6: 提交这一小步**

```bash
git add lib/models/chat/assistant_turn_block.dart lib/services/chat_block_builder.dart test/services/chat_block_builder_test.dart test/widgets/tool_renderers/write_tool_cards_test.dart test/widgets/tool_renderers/edit_tool_cards_test.dart test/widgets/tool_renderers/web_search_tool_cards_test.dart test/widgets/tool_renderers/fetch_webpage_tool_cards_test.dart
git commit -m "refactor: project typed workflow and tool results"
```

### Task 3: 引入 Projection Provider，并迁移 waiting-state provider

**Files:**
- Modify: `lib/providers/chat_ui_providers.dart`
- Modify: `lib/services/chat_timeline_projection_service.dart`
- Create: `test/providers/chat_ui_projection_test.dart`
- Modify: `test/widgets/chat_message_list_interaction_test.dart`

- [ ] **Step 1: 为 provider 消费 projection 写失败测试**

在 `test/providers/chat_ui_projection_test.dart` 先写：

```dart
test('active ask-user-question provider reads projection snapshot');
test('pending confirmation provider reads projection snapshot');
test('resolved interaction no longer depends on scanning historical result messages');
```

同时在 `test/widgets/chat_message_list_interaction_test.dart` 增补一个失败用例：

```dart
testWidgets('timeline and active interaction stay consistent when derived from one projection snapshot');
```

- [ ] **Step 2: 运行失败测试**

Run:
```bash
fvm flutter test test/providers/chat_ui_projection_test.dart test/widgets/chat_message_list_interaction_test.dart
```

Expected:
- projection provider 尚不存在或仍走旧消息扫描逻辑

- [ ] **Step 3: 在 chat_ui_providers 中新增 projection provider**

建议形态：
- 基于 `messagesProvider`、`sendPhaseProvider`、当前 groupId、`ChatBlockBuilder` / `ChatTimelineProjectionService`
- 产出单一 projection snapshot

要求：
- `activeAskUserQuestionMessageProvider` 改为消费 projection
- `activePendingToolConfirmationProvider` 改为消费 projection
- 不再在 provider 内直接做多轮消息扫描推断

- [ ] **Step 4: 删除或收缩迁移后无用的消息扫描逻辑**

删除前确认引用。

重点：
- `resolvedTurnIds` 这种 provider 内部局部重建逻辑
- 仅为 pending confirmation 推断而存在的重复 message 遍历

- [ ] **Step 5: 运行 provider + widget 测试**

Run:
```bash
fvm flutter test test/providers/chat_ui_projection_test.dart test/widgets/chat_message_list_interaction_test.dart test/widgets/chat_message_list_test.dart
```

Expected:
- 所有 waiting-state 相关测试 PASS
- 没有出现 ask-user-question 卡片激活态倒退

- [ ] **Step 6: 提交这一小步**

```bash
git add lib/providers/chat_ui_providers.dart lib/services/chat_timeline_projection_service.dart test/providers/chat_ui_projection_test.dart test/widgets/chat_message_list_interaction_test.dart test/widgets/chat_message_list_test.dart
git commit -m "refactor: derive chat waiting state from projection"
```

### Task 4: 让 Timeline 渲染消费 Projection Contract，并清理死路径

**Files:**
- Modify: `lib/widgets/chat_message_list.dart`
- Modify: `lib/widgets/chat_timeline/chat_timeline_row.dart`
- Modify: `lib/services/chat_timeline_projection_service.dart`
- Modify: `test/widgets/chat_message_list_interaction_test.dart`
- Modify: `README.md`
- Modify: `AGENTS.md`（仅在出现新长期规则时）

- [ ] **Step 1: 为 timeline 渲染迁移补失败测试**

在 `test/widgets/chat_message_list_interaction_test.dart` 或新 widget test 中增加：

```dart
testWidgets('tool workflow row renders from typed projection without payload step parsing');
testWidgets('tool result row renders from typed projection without ToolResult.fromJson in row layer');
```

- [ ] **Step 2: 运行失败测试**

Run:
```bash
fvm flutter test test/widgets/chat_message_list_interaction_test.dart
```

Expected:
- 当前 row 仍依赖 payload 反解，新增断言失败

- [ ] **Step 3: 修改 ChatMessageList / ChatTimelineRow，改为消费 projection contract**

要求：
- timeline item 列表尽量由 projection snapshot 统一提供或统一驱动
- `ChatTimelineRow` 优先读取 block 上的 typed workflow/result 数据
- 避免 render 阶段再次手工 `ToolResult.fromJson(payload)` / `_extractWorkflowSteps()`

- [ ] **Step 4: 删除已废弃辅助逻辑并确认不是活代码**

优先检查并清理：
- `ChatTimelineRow` 中迁移后无用的 payload 解析辅助方法
- 任何仅用于旧 waiting-state 推断的分叉逻辑

如果发现调用仍存活，先保留并在注释中说明，不强删。

- [ ] **Step 5: 运行本阶段完整回归**

Run:
```bash
fvm flutter test test/services/chat_timeline_projection_service_test.dart test/services/chat_block_builder_test.dart test/providers/chat_ui_projection_test.dart test/widgets/chat_message_list_interaction_test.dart test/widgets/chat_message_list_test.dart
```

再运行更广一点的回归：
```bash
fvm flutter test test/providers/chat_controller_tool_flow_test.dart test/controllers/chat_send_coordinator_test.dart
```

Expected:
- 第一阶段新增测试全部 PASS
- 现有 tool flow / interaction flow 回归不过度破坏

- [ ] **Step 6: 更新文档并提交**

若实现落地后确实引入了新的 projection service / boundary 约束，补一条最小必要说明到 `README.md`。
只有在发现新的长期协作规则时才更新 `AGENTS.md`。

```bash
git add lib/widgets/chat_message_list.dart lib/widgets/chat_timeline/chat_timeline_row.dart lib/services/chat_timeline_projection_service.dart test/widgets/chat_message_list_interaction_test.dart README.md AGENTS.md
git commit -m "refactor: move chat timeline ui to projection boundary"
```

## 验收清单

完成本计划后，必须满足以下结果：

- `activeAskUserQuestionMessageProvider` 不再以消息扫描为主来源
- `activePendingToolConfirmationProvider` 不再以消息扫描为主来源
- `ChatTimelineRow` 不再把 payload 解析当成 workflow/result 的唯一来源
- `ChatBlockBuilder` 可以输出 typed workflow/result projection
- 至少一组 service/provider/widget 测试可以直接围绕 projection contract 构造夹具
- 迁移中确认废弃的旧逻辑已同步删除，而不是继续叠加兼容

## 执行提醒

- 默认所有 Flutter 命令使用 `fvm flutter`
- 每个任务开始前，先确认目标路径是否仍然存活；如为死代码，先删后测
- 不要在第一阶段提前重构 `ChatSendCoordinator`
- 不要为了 UI 迁移重新把 loop 语义塞回 widget/provider
- 如果发现 projection model 已开始膨胀成展示 DSL，立即回退到“只保留当前 UI 与测试真正需要的稳定字段”
