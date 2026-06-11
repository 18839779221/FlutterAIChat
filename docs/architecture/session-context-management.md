# Session 上下文管理架构

## 目标

本文档定义项目当前的 Session 上下文管理架构。
它说明同一个 `group` 内的多轮上下文如何进入 planner、何时触发压缩，以及为什么旧的消息裁剪策略已经被移除。

## 核心定义

### Session

当前项目中，一个 `group` 对应一个 Session 级上下文单元。
Session 代表“同一个会话容器下的完整连续上下文对话”。

### 三层边界

项目中的上下文相关数据必须保持三层分离：

1. UI 时间线层
   - 载体：`messages`
   - 作用：渲染用户可见聊天历史
2. Turn Ledger 层
   - 载体：`chat_turns`、`chat_turn_steps`、`chat_events`
   - 作用：记录单轮执行状态、tool step、turn transcript
3. Session Context 层
   - 载体：`SessionContextService`、`session_context_snapshots`
   - 作用：构建真正发给模型的 Session 上下文

基于这一层，项目还提供一个只读观察能力：

- `SessionContextInspectorService`
  - 作用：把当前真实 planner 上下文和预算保留区整理为 `ContextWindowSnapshot`，供主界面状态条和详情面板展示

任何新逻辑都不应再把 UI `messages` 直接当成模型输入，也不应把压缩摘要伪装成 UI 消息。

## 组件

### SessionContextService

主入口，负责构建 planner 可见上下文。

输出结构固定为：

- 历史 snapshot 摘要
- snapshot 边界之后的最近 working set
- 当前 turn transcript

补充约束：

- `history summary`、`recent working set`、`current turn transcript` 三段必须互斥
- 若 snapshot 命中了当前 turn 且存在 event 级边界，则当前 turn 只保留边界之后的 transcript 后缀
- active-turn 自动压缩后，会结束旧 turn 并立即切到一个新的 continuation turn；新的 planner 请求只依赖 `runtime user context + snapshot summary + continuation turn 新增 transcript`

### SessionContextProjector

负责把消息和事件投影成模型可见上下文。

保留：

- 用户消息
- tool result / tool error 的紧凑文本
- ask-user-question 的提问与用户回答
- `assistantTurnSnapshot` 对应的 provider-native assistant message
- `assistantPlannerMessage` 对应的中间 assistant 文本（通过 carrier 路径继续参与后续 loop）

过滤：

- `toolExecutionStarted`
- `turnStatus`
- 其他纯内部过程噪音

说明：

- 当前代码实现已经保留 `assistantToolCall` 对应的 tool use 结构语义
- 文档中若出现“tool call 一律过滤”的旧描述，以当前实现为准，不再适用
- `create_artifact` 与后续 `Write/Edit` 仍按真实 tool transcript 进入上下文；当前架构不为 artifact 额外注入 summary-style 派生回传

### ToolResult 结果约定

`ToolResult` 当前正式 contract 只保留两类核心结果字段：

- `summary`
- `data`

两者职责固定如下：

- `summary`
  - 只面向 UI 时间线、tool result summary row、结果卡片等展示层
  - 也用于 transcript event `content` 的紧凑可读文本
  - 要求短、稳、易扫读
- `data`
  - 是 tool result 的唯一结构化结果真相
  - 面向后续 planner / Session 上下文投影
  - 承载搜索命中、网页片段、文件路径、动作标识、失败细节等真正可继续决策的结果

统一规则如下：

1. transcript payload 是 tool result 的唯一语义来源
   - `toolResult` / `toolError` 事件必须持久化 `ToolResult.toJson()`
   - `SessionContextProjector` 必须从 payload 解析结构化 `ToolResult`
   - planner-visible tool result 文本必须由统一投影逻辑基于 `toolName + status + data + errorMessage` 派生
2. `summary` 不得承担 planner 语义职责
   - 不允许再把 `summary` 回退成模型上下文文本
3. 不允许再引入 `contextText` / `toolResultText`
   - 也不允许保留另一个与 `data` 平行的 planner-facing 文本字段
4. 不允许再引入 `additionalContextMessages`
   - handler 不得绕过 transcript，直接附加另一份“给模型看的消息列表”
5. `TurnHarness` / orchestration 层不生成派生语义文本
   - orchestration 只持久化 transcript event `content`
   - 真实模型可见语义来自 payload 中的结构化结果投影

文件类工具推荐做法：

- 成功时：
  - 若后续模型还需要稳定路径，应把真实相对路径稳定写入 `data`
- 失败时：
  - 若后续恢复/继续决策仍需要路径、原因、约束，也应进入 `data`

artifact 相关补充：

- `create_artifact` 应把稳定 `sourcePath` 写入 `data`
- Session 上下文层不为 artifact 额外生成“摘要回投”文本；继续编辑所需的语义应尽量由真实 transcript 与结构化结果表达

实现与防漂移约束：

- 代码 contract 见 [`lib/models/tool/tool_result.dart`](/Users/skka/flutterSpace/FlutterAIChat/lib/models/tool/tool_result.dart)
- transcript-only 约束见 [`append-only-transcript.md`](/Users/skka/flutterSpace/FlutterAIChat/docs/architecture/append-only-transcript.md)
- 本轮收口设计见 [`2026-05-04-tool-result-single-source-context-design.md`](/Users/skka/flutterSpace/FlutterAIChat/docs/superpowers/specs/2026-05-04-tool-result-single-source-context-design.md)

### SessionTokenBudgetService

负责统一预算计算。

正式输入预算公式：

```text
effectiveInputBudget =
  min(
    providerInputCap 或 +inf,
    maxContextTokens
      - reservedOutputTokens
      - reasoningReserveTokens
      - safetyMarginTokens
  )
```

正式自动压缩阈值：

```text
autoCompactTriggerTokens =
  effectiveInputBudget - autoCompactBufferTokens
```

其中 `plannerInputUsageRatio = estimatedPlannerInputTokens / autoCompactTriggerTokens` 是当前唯一正式主指标。

### SessionSummaryService

负责把较早历史整理为稳定摘要。

当前使用 Claude 风格 continuation summary prompt：

- 输出要求包含 `<analysis>...</analysis>` 与 `<summary>...</summary>`
- 持久化时只保留 `<summary>` body
- summary 仍按一整块原始文本存储，不做字段级结构化解析

### SessionContextSnapshotRepository

负责读取与写入 `session_context_snapshots`。

第一版只关心每个 `group` 的最近有效 snapshot。

### SessionContextInspectorService

负责把当前会话的真实上下文窗口整理为 UI 可见快照。

输出重点包括：

- `plannerInputUsageRatio`
- 占总上下文窗口的比例
- 占 effective input budget 的比例
- planner 可见 segment 拆解
- `reserved output`、`reasoning reserve`、`safety margin`、`free headroom`
- 当前是否已经触发历史压缩

UI 约束：

- composer 小圆环与颜色分级只看 `plannerInputUsageRatio`
- `totalWindowUsageRatio` 与 `effectiveInputUsageRatio` 只在 bottom sheet 中作为诊断值展示

## 存储模型

`session_context_snapshots` 字段：

- `group_id`
- `summary_text`
- `covered_until_turn_id`
- `covered_until_event_id`
- `estimated_tokens`
- `created_at`
- `updated_at`

其中：

- `covered_until_turn_id` 用来定义 snapshot 已覆盖到哪个 turn
- `covered_until_event_id` 允许同一 turn 内只覆盖到某个 event 前缀

构建 working set 时：

- `covered_until_turn_id` 之前的 whole turns 不再进入 planner
- 若当前 turn 命中 `covered_until_turn_id` 且存在 `covered_until_event_id`，只读取该 turn 的后缀事件

## 压缩触发

压缩的主触发器是 `totalInputTokens >= autoCompactTriggerTokens`，而不是固定消息数或固定 turn 数。

执行顺序：

1. 估算 system prompt、runtime user context、snapshot、recent working set、当前 turn transcript 的 token
2. 与 `effectiveInputBudget` / `autoCompactTriggerTokens` 比较
3. 若 completed history 已足够缓解压力，则先滚动 summary 压缩历史
4. 若压力仍然来自当前 active turn，则把“snapshot 后的 recent completed turns + 当前 turn 到边界 event 为止的 planner-visible 前缀”压成新的 summary
5. 旧 turn 以 `completed + stopReason=auto_compacted_continue` 收口，并立即创建 summary-only continuation turn 自动续跑

## 为什么删除旧 context strategy

旧的 `context_strategies.dart` / `MessageContextStrategy` 只适用于“从单一历史消息列表中裁剪消息”的旧模型。

它已经无法正确表达当前架构的关键问题：

- UI 消息与模型输入分离
- tool / interaction 事件需要投影而不是原样回填
- 压缩边界应按 turn/交互闭环保护
- 压缩必须由 token 预算驱动
- 历史摘要需要独立持久化，不应混入 UI 时间线

因此旧策略已退役，不应重新引入。

## 实施约束

- 新增上下文逻辑时，优先扩展 `SessionContext*` 服务，而不是把逻辑塞回 `ChatService`
- 若需要新的上下文事件投影规则，先改 `SessionContextProjector`
- 若需要新的压缩判断，先改 `SessionTokenBudgetService`
- 若引入新等待态或 resumable interaction，必须同时考虑其是否进入 Session 上下文
