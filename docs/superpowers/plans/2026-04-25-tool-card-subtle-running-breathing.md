# Tool Card 轻量 Running 呼吸动效 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为工具卡片补充分层运行态动效：重点卡片使用扫光加状态点脉冲，低噪音卡片使用状态点脉冲加极弱背景呼吸。

**Architecture:** 保持现有 tool UI renderer 结构不变，在 UI 层新增可复用的运行态动效组件，并在 workflow/compact 两条链路上显式透传 `isRunning`。重点卡片接入淡扫光和状态点脉冲，低噪音卡片接入状态点脉冲和极弱背景呼吸，状态胶囊保持静态。

**Tech Stack:** Flutter, Dart, Material, existing tool card renderer architecture

---

### Task 1: 补充运行态展示模型

**Files:**
- Modify: `lib/models/chat/tool_card_presentation_model.dart`
- Modify: `lib/services/tool_card_presentation_mapper.dart`
- Modify: `lib/widgets/tool_renderers/compact_tool_row_renderer.dart`

- [ ] **Step 1: 为轻量展示模型补充 `isRunning` 字段**

在 `ToolCardPresentationModel` 与 `CompactToolRowModel` 中增加显式运行态字段，避免 widget 通过文案猜状态。

- [ ] **Step 2: 在 mapper 中透传 workflow step 的运行态**

`ToolCardPresentationMapper.mapStep(...)` 根据 `ToolWorkflowStepStatus.running` 设置 `isRunning`，result 默认关闭。

- [ ] **Step 3: 让 compact renderer 与 research/workflow 卡片同步产出 `isRunning`**

保证 `Read/LS/Grep/Glob`、`web_search`、`fetch_webpage` 与通用 workflow 大卡片能拿到统一语义。

### Task 2: 增加共享运行态动效组件

**Files:**
- Create: `lib/widgets/tool_renderers/...`
- Modify: `lib/widgets/chat_blocks/tool_inline_step_row.dart`
- Modify: `lib/widgets/tool_renderers/compact_tool_row_renderer.dart`
- Modify: `lib/widgets/chat_blocks/tool_workflow_card.dart`
- Modify: `lib/widgets/tool_renderers/research_tool_card_shell.dart`
- Modify: `lib/widgets/tool_renderers/web_search_tool_workflow_card.dart`
- Modify: `lib/widgets/tool_renderers/fetch_webpage_tool_workflow_card.dart`

- [ ] **Step 1: 新建共享状态点脉冲组件**

- [ ] **Step 2: 新建重点卡片扫光组件**

仅在 `running` 态启用，扫光透明度很低，避免覆盖正文。

- [ ] **Step 3: 保留轻量卡片背景呼吸组件**

只用于 compact / inline 卡片，alpha 区间很窄。

- [ ] **Step 4: 为 `ToolInlineStepRow` 与 `CompactToolRow` 接入脉冲点与背景呼吸**

保留原有排版与文案，不接入扫光。

- [ ] **Step 5: 为重点 workflow 大卡片接入扫光与脉冲点**

确保 `web_search`、`fetch_webpage`、通用 `ToolWorkflowCard` 的运行态卡片一致。

### Task 3: 定向验证

**Files:**
- Verify only

- [ ] **Step 1: 运行定向 analyze**

Run: `fvm flutter analyze lib/widgets/chat_blocks/tool_inline_step_row.dart lib/widgets/tool_renderers/compact_tool_row_renderer.dart lib/widgets/tool_renderers/subtle_running_breathing_surface.dart lib/models/chat/tool_card_presentation_model.dart lib/services/tool_card_presentation_mapper.dart`

Expected: analyze 通过，无新增错误。

- [ ] **Step 2: 人工检查重点卡片与低噪音卡片的动效差异**

确认：

- 重点卡片只有 running 态出现扫光与点脉冲
- 低噪音卡片只有 running 态出现点脉冲与极弱呼吸
- completed/failed/result 保持静态

- [ ] **Step 3: 如需设备验证，再执行安装脚本**

Run: `bash scripts/android_install_debug.sh`

Expected: 最新 debug 包成功安装到设备。
