# Append-Only Transcript 架构约束

## 目标

本文档定义当前 Agent Loop 的唯一语义主路径，用来约束后续实现不要再次漂移到“多真相源并存”的状态。

当前项目中，planner、tool loop、resume、context assembly 必须统一建立在 append-only transcript 之上。

## 核心原则

一句话版本：

> Agent Loop 的语义状态只允许来自 append-only transcript；provider 特定状态只能作为运行时元数据，不能成为独立语义来源。

## 什么是事实源

当前只承认两类事实源：

### 1. Transcript

载体：`chat_events`

职责：

- 记录一个 turn 内按时间顺序发生的可见语义事件
- 作为 planner-visible context 的唯一语义输入
- 支撑 tool loop、interaction、resume 的上下文重放

必须 append 的事件包括：

- `userMessage`
- `assistantPlannerMessage`
- `assistantToolCall`
- `assistantQuestionPrompt`
- `toolResult`
- `toolError`
- `userInteractionResult`
- `finalAnswer`

规则：

- transcript 是 append-only 的
- 不允许因为 provider 能“续传”而删除、跳过、过滤这些语义事件
- 不允许把工具轨迹折叠成普通 assistant 摘要后再替代原始事件

### 2. Ledger

载体：`chat_turn` / `chat_turn_step`

职责：

- 记录执行状态真相
- 记录 step 生命周期、失败原因、等待态、resume 所需结构化字段
- 为 verifier、恢复、UI 工作流提供状态依据

规则：

- ledger 负责“状态”
- transcript 负责“语义时间线”
- 两者允许互相引用，但不能互相替代

## 什么不是事实源

以下对象都不是语义事实源：

- provider-native continuation
- `previous_response_id`
- provider message id / response id
- provider thinking block 缓存
- UI `messages`
- adapter 内部拼装出的 wire payload

这些对象最多只能算：

- provider runtime metadata
- wire/protocol optimization
- 调试和兼容信息

它们不能决定 planner 下一轮“看见什么”。

## 唯一主路径

当前唯一允许的主路径是：

1. 模型输出 tool use / ask-user / assistant text
2. 先 append 到 transcript
3. tool / interaction 执行
4. 再 append `toolResult` / `toolError` / `userInteractionResult`
5. `SessionContextService` 从 transcript + snapshot + recent turns 投影 planner-visible context
6. `AgentPlannerService` 将结构化 planner messages 交给 `BaseLLM.planTurnDecision()`
7. adapter 只负责把这些 messages 映射成 provider wire payload

tool result 额外约束：

- `toolResult` / `toolError` 的 transcript event `content` 只承载紧凑 UI 文本
- tool result 的正式语义 payload 必须来自 `ToolResult.toJson()`
- planner / Session context 必须从 payload 中的结构化 `ToolResult` 投影工具结果语义
- 该投影必须以 `data` 为主输入，可辅助使用 `toolName`、`status`、`errorMessage`
- 不允许回退到 `summary` 作为 planner 语义
- 不允许通过 `additionalContextMessages`、临时 ChatMessage 列表或 provider continuation item 回灌另一份工具结果语义

## 明确禁止的路径

以下做法属于架构违规：

### 1. 因 provider continuation 存在而过滤当前 turn transcript

禁止：

- 按 provider style 删除 `assistantToolCall`
- 删除 `toolResult` / `toolError`
- 删除 `assistantQuestionPrompt` / `userInteractionResult`

原因：

- 这会导致 planner-visible context 与 transcript 脱钩
- 一旦 provider continuation 断裂，就会出现上下文塌陷和死循环

### 2. 在 planner 层传递 continuation item

禁止：

- `AgentPlannerService` 组装 provider continuation item
- `BaseLLM.planTurnDecision()` 接收 continuation item
- adapter 依赖上层传入 continuation item 决定下一轮语义

原因：

- 这会把 optimization 提升成第二条语义路径

### 3. 把结构化 transcript 降级成“伪协议文本”再作为上层契约

允许：

- adapter 最终把结构化消息映射成 provider 所需格式

禁止：

- 上层逻辑依赖“某段字符串前缀”理解 tool 语义
- planner/service 把 transcript 重写成普通 assistant 文本摘要替代原轨迹
- 通过 transcript 外的 side-channel 重新塞入另一份 tool result context

## Provider 状态的边界

provider 状态仍然允许存在，但只能位于以下边界：

- `ModelTurnDecision.providerState`
- `chat_turn.providerStateJson`
- adapter / parser / stream accumulator 内部

允许用途：

- 保留 provider 返回的 response id / message id
- 记录 provider 特定调试元信息
- 支撑 trace / observability

禁止用途：

- 作为 planner input 的主来源
- 决定 transcript 中哪些事件可以不投影
- 要求上层构造 provider continuation item 才能继续运行

## 代码落点

当前这些入口必须共同执行本约束：

- `lib/services/session_context_service.dart`
- `lib/services/agent_planner_service.dart`
- `lib/models/llm/base_llm.dart`
- `lib/models/llm/configurable_http_llm.dart`
- `lib/models/llm/adapters/*.dart`

要求：

- 文件头应引用本文档或 `agent-loop-boundaries-and-decoupling.md`
- 关键注释必须直接声明 transcript-only invariant

## 测试要求

至少要覆盖以下不变量：

### 1. Transcript replay 不变量

给定同一段 transcript：

- planner-visible context 必须包含同等语义的 tool use / tool result / interaction result
- 不得因 provider state 是否存在而改变这些事件是否出现

### 2. 故障注入不变量

当这些字段缺失时，系统仍应依赖 transcript 正常继续：

- `providerCallId`
- `response_id`
- `message_id`
- `content_blocks`

允许失败的部分是 provider 自身 wire 兼容，不允许失败的部分是：

- 本地 context 组装
- 本地 transcript 投影
- loop 语义闭环

### 3. 工具轨迹可见性不变量

recent turns 和 current turn 中：

- `assistantToolCall` 与 `toolResult` 必须保持可区分
- 不得被 generic assistant summary 替代

## 与其他文档的关系

- 边界与职责划分：`docs/architecture/agent-loop-boundaries-and-decoupling.md`
- 日志与 trace 规则：`docs/architecture/logging.md`
- Session context 组装：`docs/architecture/session-context-management.md`
- ToolResult 单一语义源设计：`docs/superpowers/specs/2026-05-04-tool-result-single-source-context-design.md`

本文档优先回答的是：

- 什么是语义真相源
- 什么路径被明确禁止
- 如何通过代码结构和测试防止回潮
