# Debug Turn Inspector 设计

## 背景

当前项目已经具备较完整的 agent loop 主链路：

- `TurnHarness` 作为单轮执行入口
- `AgentPlannerService` 负责 planner decision
- `chat_turns` / `chat_turn_steps` / `chat_events` 作为正式账本
- `SessionContextService` 负责 planner-visible context
- `runtimeAssistantDraft` / `runtimeStreamEntries` 负责当前运行态投影

在真机端到端调试中，当前最大的困难不是缺少日志，而是缺少一个可见的、结构化的、只读的调试界面，能够回答下面这些问题：

- 当前 Agent Loop 卡在哪个阶段
- 当前 turn 的上下文具体是什么
- provider 实际返回了什么
- tool call 在哪里中断或失真
- 现在 UI 看到的 waiting 状态对应哪份底层事实

本次需求的目标，是新增一个 debug 专用的 turn inspector 面板，让开发阶段可以直接从更底层观测 agent loop 的实时状态与历史事实，而不是只能从最终 UI 结果反推。

## 目标

本次设计目标如下：

1. 在聊天页右上角新增 debug 专用悬浮入口
2. 仅在 debug 包可见，不进入 release/profile
3. 支持查看当前活跃 turn 与最近几个 turn
4. 提供三个核心 tab：
   - `Overview`
   - `Timeline`
   - `Context`
5. 展示尽量接近原始事实，不为了可读性牺牲细节
6. Debug 数据不持久化，不成为新的真相源
7. 如果信息不够，优先补充正式运行链路的数据来源，而不是在 debug 侧单独造数据

## 非目标

本轮明确不做以下事情：

1. 不把 debug 面板做成正式产品功能
2. 不为 debug 视图新增数据库表或持久化层
3. 不在 debug 侧重建一套独立的 agent 状态机
4. 不让 debug UI 反向影响主流程执行
5. 不追求极致美观，优先追求真实、完整、可排障

## 设计原则

### 1. 偏原始，少解释

Debug 面板优先展示接近真实底层的数据，而不是过度加工后的友好文案。

允许存在简短摘要，但必须同时能看到原始 payload 或原始结构。

### 2. 只读，不持久化

Debug 面板本身不新增持久化事实，不记录一份 debug 专用事件账本。

它只消费现有正式数据源，以及为正式运行链路补充的通用可观察性数据。

### 3. Debug UI 是事实浏览器，不是解释器

它负责聚合、排序、展示、折叠、复制。

它不负责推断、修正或创建新的业务含义。

## 方案选择

### 方案 A：独立 debug 投影层

本轮采用。

做法：

- 新增 `DebugTurnInspectorProjectionService`
- 统一读取现有 turn / step / event / runtime state / trace / context
- 输出一个只读 inspector projection
- UI 仅消费 projection，不再自己拼装业务事实

优点：

- 边界清晰
- 不污染主流程
- 易于扩展

### 方案 B：widget 直接拼现有 provider

不采用。

原因：

- 容易让 UI 变成第二套状态拼装逻辑
- 后续维护成本高
- 容易与主链路事实边界混淆

### 方案 C：只做日志面板

不作为主方案。

原因：

- 能看到“发生了什么”
- 但不足以回答“上下文是什么”“当前状态是什么”“为什么卡住”

## 入口设计

### 入口位置

聊天页右上角固定悬浮按钮。

### 可见范围

仅在 debug 包可见。

### 交互

点击后打开 `DebugTurnInspector` 面板，不遮挡输入框和底部交互区。

## 顶层结构

`DebugTurnInspectorProjection` 建议包含四组顶层数据：

- `turnOptions`
- `activeTurnOverview`
- `timelineEntries`
- `contextSections`

### 1. Turn Options

用于顶部切换最近几个 turn。

每项建议字段：

- `turnId`
- `status`
- `updatedAt`
- `userInputPreview`

### 2. Overview

用于快速判断当前卡在哪。

建议字段：

- `turnId`
- `groupId`
- `status`
- `sendPhase`
- `iterationCount`
- `toolCallCount`
- `providerStyle`
- `modelName`
- `diagnosticCode`
- `errorMessage`
- `hasRuntimeDraft`
- `runtimeStreamEntryCount`
- `hasPendingConfirmation`
- `hasActiveQuestion`
- `startedAt`
- `updatedAt`
- `durationMs`

### 3. Timeline

按时间顺序展示 turn 内发生的事实。

建议统一字段：

- `id`
- `timestamp`
- `kind`
- `title`
- `summary`
- `source`
- `severity`
- `payloadJson`

建议 kind 首版至少包括：

- `turnCreated`
- `userMessage`
- `plannerStarted`
- `plannerFirstChunk`
- `plannerProgress`
- `plannerDecisionReady`
- `plannerDecisionFailed`
- `toolCallPlanned`
- `toolCallStreaming`
- `toolCallParseFailed`
- `toolExecutionStarted`
- `toolResult`
- `awaitingConfirmation`
- `awaitingUserInteraction`
- `finalAnswerStarted`
- `finalAnswerChunk`
- `finalAnswerCompleted`
- `turnCompleted`
- `turnFailed`

### 4. Context

按结构化 section 展示当前上下文。

建议固定 section：

- `Planner Messages`
- `Transcript Events`
- `Turn Steps`
- `Provider State`
- `Runtime Stream Entries`
- `Runtime Assistant Draft`
- `Latest Decision Snapshot`

## 数据来源

### Persisted Facts

来源于正式账本：

- `chat_turns`
- `chat_turn_steps`
- `chat_events`

用于提供：

- `turnOptions`
- `Overview`
- `Transcript Events`
- `Turn Steps`
- `Provider State`

### Runtime Facts

来源于当前运行态：

- `runtimeAssistantDraftProvider`
- `runtimeStreamEntriesProvider`
- `chatSendStateProvider`

用于提供：

- `Overview` 中的实时状态
- `Runtime Stream Entries`
- `Runtime Assistant Draft`
- 时间线中的实时 chunk / draft 项

### Derived Inspector Facts

来源于正式只读投影或 trace：

- `SessionContextService`
- `ChatTraceRecorder`
- 最近一次 `ModelTurnDecision` 快照

用于提供：

- `Planner Messages`
- `Latest Decision Snapshot`
- 时间线中的 trace 项

## 结构约束

### 原始数据优先

Debug 面板应优先展示原始 payload、原始 JSON、原始文本。

不因为“看起来难读”而隐藏细节。

### 不做持久化

Debug 面板不新增数据库表，不记录 debug 专用事件，不制造第二真相源。

### 缺什么补什么

如果 debug 视角下觉得信息不够，应该补充正式运行链路的数据来源，而不是在 debug 侧临时伪造数据。

## 风险与控制

### 风险 1：debug 面板变成第二套状态机

控制方式：

- projection 只做读模型聚合
- widget 不直接拼业务语义

### 风险 2：debug 信息与正式事实不一致

控制方式：

- 所有数据都来自正式事实源或正式 runtime state
- 不允许 debug 自行持久化

### 风险 3：面板过重影响主流程

控制方式：

- 仅 debug 包可见
- 悬浮入口独立
- 不进入主流程逻辑分支

## 测试

需要补充以下覆盖：

1. projection service 单测
2. widget 渲染单测
3. turn 切换和当前 turn 选中逻辑
4. Timeline/Context section 的原始 payload 展示

