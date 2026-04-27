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

### SessionContextProjector

负责把消息和事件投影成模型可见 `ChatMessage`。

保留：

- 用户消息
- assistant tool use
- 最终 assistant 消息
- tool result / tool error 的紧凑文本
- ask-user-question 的提问与用户回答

过滤：

- `toolExecutionStarted`
- `turnStatus`
- 其他纯内部过程噪音

说明：

- 当前代码实现已经保留 `assistantToolCall` 对应的 tool use 结构语义
- 文档中若出现“tool call 一律过滤”的旧描述，以当前实现为准，不再适用

### ToolResult 文本约定

`ToolResult` 当前同时允许携带两类文本：

- `summary`
- `toolResultText`

两者职责不同：

- `summary` 面向 UI 时间线与结果卡片，要求短、稳、易扫读
- `toolResultText` 面向后续 planner / Session 上下文投影，表示“工具结果给模型看的标准文本”

统一规则如下：

1. 默认优先只写 `summary`
   - 如果 UI 摘要已经足够让后续模型理解结果，不需要额外填写 `toolResultText`
2. 只有当模型需要比 UI 更明确的文本时，才填写 `toolResultText`
   - 例如需要补充真实路径、失败原因、关键约束、结构化结果的自然语言总结
3. 不要机械重复 `summary` 已经表达过的信息
   - 特别是不要把同一条文件路径在同一段 `toolResultText` 中重复两遍
4. `TurnHarness` 不负责生成工具语义文本
   - orchestration 层只持久化 `summary`
   - 投影层只消费 `ToolResult` 已声明的正式文本
5. `SessionContextProjector` 与 planner transcript 投影统一优先读取 `toolResultText`
   - 若为空，再回退到事件 `content` / `summary`

文件类工具推荐做法：

- 成功时：
  - 若 `summary` 已经包含真实相对路径，`toolResultText` 可以与 `summary` 相同
- 失败时：
  - 若 `summary` 不含真实路径，而模型继续决策又需要它，可在 `toolResultText` 中补一次真实路径

### SessionTokenBudgetService

负责统一预算计算。

预算核心公式：

```text
inputBudget = maxContextTokens - reservedOutputTokens - safetyMarginTokens
```

当估算输入接近预算阈值时，触发历史压缩。

### SessionSummaryService

负责把较早历史整理为稳定摘要。

摘要栏目固定为：

- 当前目标
- 已确认事实
- 用户偏好/限制
- 重要工具结论
- 未完成事项
- 风险与下一步

### SessionContextSnapshotRepository

负责读取与写入 `session_context_snapshots`。

第一版只关心每个 `group` 的最近有效 snapshot。

### SessionContextInspectorService

负责把当前会话的真实上下文窗口整理为 UI 可见快照。

输出重点包括：

- 占总上下文窗口的比例
- 占可用输入预算的比例
- planner 可见 segment 拆解
- `reserved output`、`reasoning reserve`、`safety margin`、`free headroom`
- 当前是否已经触发历史压缩

## 存储模型

`session_context_snapshots` 字段：

- `group_id`
- `summary_text`
- `covered_until_turn_id`
- `estimated_tokens`
- `created_at`
- `updated_at`

其中 `covered_until_turn_id` 用来定义 snapshot 已覆盖到哪个 turn。
构建 working set 时，只读取这个边界之后的 turn。

## 压缩触发

压缩的主触发器是 token budget pressure，而不是固定消息数或固定 turn 数。

执行顺序：

1. 估算 system prompt、工具 schema、snapshot、recent working set、当前 turn transcript 的 token
2. 与当前模型预算比较
3. 若接近阈值，则对较早历史生成新 snapshot
4. planner 改用“snapshot + 当前 turn”或“snapshot + 较短 recent working set + 当前 turn”

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
