# Session 上下文管理设计

## 背景

当前项目已经完成了基于 `chat_turns`、`chat_turn_steps`、`chat_events` 的 agent loop 主链路改造，但“多轮会话上下文”仍然没有真正接入新的 turn-based 架构。

现状存在两个直接问题：

1. 同一个 `group` 下的多轮连续对话不会自动进入下一轮 planner 的可见上下文。`TurnHarness` 当前传给 `AgentPlannerService` 的仍然主要是“当前 turn 的 transcript”，而不是“当前 session 的上下文投影”。
2. 旧的 [`lib/models/context/context_strategies.dart`](/Users/skka/flutterSpace/FlutterAIChat/lib/models/context/context_strategies.dart) / [`lib/models/context/message_context_strategy.dart`](/Users/skka/flutterSpace/FlutterAIChat/lib/models/context/message_context_strategy.dart) 仍保留在仓库中，但它们只适用于“从单一消息列表中截取历史消息”的旧式模型，不再适配 `messages + chat_turns + chat_events + provider continuation + snapshot` 的新架构。

这导致当前体验上表现为：

- 用户连续追问时，模型不能稳定继承此前轮次里已经确认的事实、结论和限制
- 工具结果和 `AskUserQuestion` 的回答虽然被持久化了，但并不会稳定进入下一轮跨 turn 上下文
- 会话变长后没有统一的 token 预算判断与自动压缩机制，后续一旦模型上下文接近上限，既容易丢历史，也容易在不同模块里各自做一套临时裁剪

本次设计目标是引入新的 `Session` 级上下文管理体系，用统一的 token 预算策略、摘要快照机制和模型可见上下文投影，替换过时的旧上下文策略实现。

## 目标

本次设计目标如下：

- 用 `SessionContextService` 作为唯一 session 级上下文编排入口
- 明确区分 UI 时间线、turn ledger、model-visible context 三层职责
- 让同一 `group` 下的多轮用户/助手消息、工具结果、交互问答都能进入下一轮 planner 上下文
- 用 token budget pressure 作为是否压缩的主触发器，而不是固定轮数或固定消息数
- 引入 `session_context_snapshots` 持久化摘要快照，避免把内部压缩摘要污染到 UI `messages` 时间线
- 按“已完成 turn / 已完成交互闭环”作为压缩边界，避免破坏语义结构
- 直接删除过时的 `context_strategies.dart` 体系，不保留两套上下文系统并存
- 在 `docs/architecture/` 中补充新的 session 上下文架构文档，作为后续维护的收敛入口

## 非目标

本轮不包含以下内容：

- 不实现跨 `group` 的长期记忆系统
- 不引入独立的 memdir / 文件式长期 memory 检索
- 不在本轮改变现有 UI 消息卡片样式或分页交互
- 不为了兼容旧上下文策略而保留桥接层、迁移 shim 或双写逻辑
- 不把 provider 原始 payload 全量重新注入到后续 prompt

## 核心术语

### Session

本设计中的 `Session` 表示“同一个 `group` 下的一次完整连续上下文对话”，它是模型侧上下文管理的基本单位。

说明：

- `group` 仍是数据库和 UI 上的会话归属单位
- `Session` 是该 `group` 在模型输入层面的语义别名
- 当前阶段默认一个 `group` 对应一个活跃 `Session`

### UI Transcript

UI transcript 指用户在聊天界面中看到的消息时间线，当前主要由 `messages` 表驱动。

它的目标是：

- 可读
- 可滚动
- 可分页
- 保留更多展示信息

它不是模型输入的直接真相源。

### Turn Ledger

turn ledger 指单轮执行账本，当前主要由 `chat_turns`、`chat_turn_steps`、`chat_events` 组成。

它的目标是：

- 记录 turn 生命周期
- 保存 tool step 状态与 resume 所需结构化信息
- 投影 turn 内可读 transcript

它也不是 session 级上下文的最终输入格式。

### Model-visible Context

model-visible context 指每次 planner / final-answer 调用前真正发给模型的上下文消息集合。

它必须是一个经过选择、压缩和投影的上下文视图，而不是简单等于 UI 全量消息。

## 现状问题

### 1. Planner 只看当前 turn，不看当前 session

`TurnHarness._continueTurnLoop()` 当前主要按 turn 读取 transcript，然后交给 `AgentPlannerService.planNextDecision()`。

这意味着：

- 当前 turn 内的用户消息、工具结果、交互回答是可见的
- 前一轮 turn 已确认的事实、工具结果、约束条件不会自动进入下一轮 planner

结果是模型在连续追问中表现得像“短期失忆”。

### 2. 工具结果与交互结果没有 session 级投影层

当前 `toolResult`、`toolError`、`assistantQuestionPrompt`、`userInteractionResult` 已经能进入 turn transcript，但没有统一的 session 级“模型上下文投影规则”。

这会带来两个问题：

- 有价值的工具结论和用户补充信息，跨 turn 难以复用
- 原始 payload 一旦直接进入后续 prompt，又会造成噪音、冗余和 token 浪费

### 3. 旧上下文策略已经失效

`context_strategies.dart` 的设计前提是：

- 输入是一组历史消息
- 输出是裁剪后的消息列表

它没有覆盖以下新问题：

- `messages` 和 `chat_events` 来自不同层次
- tool / interaction 结果需要投影，不是简单裁消息
- 压缩边界应该以 turn 或交互闭环为单位
- token 预算需要考虑 system prompt、tool schema、输出预留和安全余量

因此这套旧策略不应继续演化，而应直接退役。

### 4. 当前缺少统一 token budget 策略

是否需要压缩 session 上下文，主判断不应依赖固定消息数、固定轮数或经验阈值。

更合理的做法是：

- 先估算当前候选上下文的总 token
- 再结合当前模型的最大上下文窗口、预留输出 token、安全余量、system prompt 和工具开销
- 判断是否接近上限

换言之，压缩应由“预算压力”驱动，而不是由“聊了多久”驱动。

## 设计总览

本次改造收敛为一套新的 Session 上下文管理体系：

1. 保留 UI 时间线和 turn ledger 作为原始事实层
2. 新增 `SessionContextService` 作为唯一 session 上下文入口
3. 新增 `SessionContextProjector`，把历史消息、工具结果、交互结果投影成模型可见消息
4. 新增 `SessionTokenBudgetService`，以当前模型上下文预算为唯一压缩判断口径
5. 新增 `SessionSummaryService`，对较早历史段生成结构化摘要
6. 新增 `session_context_snapshots` 持久化摘要快照
7. planner 输入改为“历史摘要 + 最近工作集 + 当前 turn transcript”
8. 删除旧 `context_strategies.dart` 体系
9. 在 `docs/architecture/` 中补一篇 session 上下文架构文档

## 三层职责边界

### 1. UI 时间线层

载体：

- `messages`

职责：

- 展示用户/助手消息
- 保留现有分页和消息卡片语义
- 为用户提供滚动式聊天历史

约束：

- 不插入内部压缩摘要伪消息
- 不承担模型预算控制责任

### 2. Turn Ledger 层

载体：

- `chat_turns`
- `chat_turn_steps`
- `chat_events`

职责：

- 记录单轮执行状态
- 记录 tool step 结构化状态
- 记录 turn 内 transcript 事件
- 支持恢复、确认、补问、继续执行

约束：

- 不直接等同于 session 级上下文
- 不负责跨 turn 历史压缩

### 3. Session Context 层

载体：

- `SessionContextService`
- `session_context_snapshots`
- 最近工作集投影结果
- 当前 turn transcript 投影结果

职责：

- 为模型构造单一 session 的可见上下文
- 管理 token 预算
- 决定是否压缩历史
- 选择摘要边界后的最近 working set

约束：

- 不污染 UI 时间线
- 不暴露原始 payload 到后续 prompt

## Model-visible Context 结构

每次 planner 看到的 session 上下文由三段组成：

1. 历史摘要块
2. 最近工作集
3. 当前 turn transcript

### 1. 历史摘要块

来源：

- `session_context_snapshots.summary_text`

用途：

- 表达早期历史中仍然重要的目标、事实、约束和结论
- 替代已经被压缩掉的长历史段

特点：

- 是摘要文本，不是原始消息重放
- 默认以 `system` 或固定格式 `assistant/system` 投影进入上下文

### 2. 最近工作集

来源：

- 摘要覆盖边界之后、当前 turn 之前的最近若干 turn / 交互闭环

用途：

- 保留最近连续工作的原始语义细节
- 避免模型只看摘要而缺少近距离上下文

特点：

- 以原文或轻度投影的形式保留
- 受 token budget 约束动态调节长度

### 3. 当前 turn transcript

来源：

- 当前 turn 的 `chat_events`

用途：

- 保留本轮最新动作、工具结果、用户补充和中间状态
- 维持当前 turn 的实时性

特点：

- 默认完整保留当前 turn 内的必要事件
- 优先级高于更早历史

## SessionContextProjector 规则

`SessionContextProjector` 负责把不同来源的数据投影成可用于模型输入的 `ChatMessage` 列表。

### 直接保留的内容

- 普通 `user` 消息
- 普通 `assistant` 最终答复
- 对当前任务仍重要的最近 planner 可见说明文本

### 需要投影压缩后再保留的内容

- `toolResult`
- `toolError`
- `assistantQuestionPrompt`
- `userInteractionResult`

这些内容保留的不是原始 payload，而是紧凑文本摘要，例如：

- 工具做了什么
- 得到了什么结论
- 失败原因是什么
- 用户在补问里确认了什么信息

### 默认不进入跨 turn 上下文的内容

- `assistantToolCall`
- `toolExecutionStarted`
- `turnStatus`
- 高频纯过程型中间事件

这些事件仍然保留在 turn transcript 和日志中，但不应成为跨 turn session 历史的一部分。

### 投影原则

投影层应满足以下原则：

- 保留语义，不保留噪音
- 保留结论，不保留原始 payload
- 保留用户确认和约束，不保留纯内部状态
- 保留失败原因与阻塞点，便于模型做下一步决策

## Token Budget 策略

### 统一预算公式

是否需要压缩，统一由 `SessionTokenBudgetService` 根据当前模型预算判断。

预算模型：

```text
inputBudget = maxContextTokens - reservedOutputTokens - safetyMarginTokens
```

其中：

- `maxContextTokens`：当前模型最大上下文窗口
- `reservedOutputTokens`：为最终输出或 planner 后续补充预留的输出空间
- `safetyMarginTokens`：避免估算误差导致越界的安全余量

在实际估算时，还必须包含以下输入开销：

- system prompt
- runtime sections
- 工具 schema / tool definitions
- session 摘要块
- 最近工作集
- 当前 turn transcript

### 触发原则

主原则：

- 只有当预计输入接近 `inputBudget` 时，才触发压缩

可以配置一个压力阈值，例如：

- `estimatedInputTokens >= inputBudget * threshold`

其中 `threshold` 可以是偏保守的 0.8 到 0.9 区间，但不在本设计中写死为单一值。

### 不再采用的粗粒度主规则

以下规则不再作为主触发器：

- 固定消息数
- 固定 turn 数
- 固定时间间隔

这些规则最多作为辅助手段，例如：

- 从未生成过摘要时，要求至少有一定上下文体量才允许首次摘要

但它们不能替代 token budget pressure。

### 模型窗口来源

预算服务应支持按当前模型动态读取窗口，而不是仓库内只有一套全局常量。

即：

- 不同模型可有不同 `maxContextTokens`
- `reservedOutputTokens` 和安全余量也允许按模型或 provider 策略调整

## 摘要与压缩策略

### 摘要不是 UI 伪消息

本设计明确不把压缩摘要写入 `messages` 表作为一条“假消息”。

原因：

- 会污染用户时间线
- 会影响分页与渲染语义
- 会让 UI 和模型上下文层再次混杂

因此摘要必须单独存储在 `session_context_snapshots` 中。

### 摘要覆盖边界

摘要边界默认以 `turn` 为主，而不是按单条 message 或单条 event 切分。

原因：

- turn 是当前 agent loop 的完整语义单元
- 按 turn 切分能更稳地保护工具调用、工具结果、交互问答等结构关系
- 避免把一个执行闭环切成两半

在特殊情况下，可在 turn 内进一步以“已完成交互闭环”为补充保护单元，但第一版不以单 event 切分。

### 摘要输出内容

摘要应使用固定栏目，优先覆盖：

- 当前目标与子目标
- 已确认事实
- 用户偏好与限制
- 重要工具结论
- 关键交互问答结论
- 当前阻塞点
- 未完成事项与下一步

不应包含：

- 原始工具 payload
- 全量 transcript 重复摘录
- 仅对运行时恢复有意义的内部状态字段

### 摘要更新策略

摘要更新采用“按预算需要时刷新”的策略：

- 每次 planner 前评估当前 session 的候选上下文 token
- 若未接近预算，不刷新摘要
- 若接近预算，优先尝试生成或刷新历史摘要快照

设计上允许后续演化为后台增量摘要，但第一版的最低要求是：在预算压力出现时能稳定生成可复用快照。

## Session Context Snapshot 存储设计

新增表：`session_context_snapshots`

建议字段：

- `id`
- `group_id`
- `summary_text`
- `covered_until_turn_id`
- `estimated_tokens`
- `created_at`
- `updated_at`

字段说明：

- `group_id`：该快照属于哪个 session/group
- `summary_text`：历史段压缩后的摘要正文
- `covered_until_turn_id`：该摘要已经覆盖到哪个 turn，构造最近工作集时只取其后的内容
- `estimated_tokens`：生成后估算的摘要 token，便于后续预算计算

第一版不强制增加 `covered_until_event_id`，因为以 turn 为边界已经更符合当前架构。

## 新服务边界

### SessionContextService

建议位置：

- `lib/services/session_context_service.dart`

职责：

- 构建 planner 所需的 session 上下文
- 编排 projector、token budget、summary snapshot
- 决定是否需要压缩
- 输出最终 `List<ChatMessage>`

它是唯一 session 级上下文入口。

### SessionContextProjector

建议位置：

- `lib/services/session_context_projector.dart`

职责：

- 把历史消息、事件、摘要块投影成模型可见消息
- 统一处理 tool / interaction 的上下文文本化规则
- 过滤纯过程噪音事件

### SessionTokenBudgetService

建议位置：

- `lib/services/session_token_budget_service.dart`

职责：

- 读取当前模型预算
- 估算 system prompt、工具 schema 和候选上下文 token
- 判断是否接近预算上限
- 返回 working set 可保留范围

它必须成为唯一预算口径。

### SessionSummaryService

建议位置：

- `lib/services/session_summary_service.dart`

职责：

- 根据需要被压缩的历史段生成摘要
- 维护固定摘要结构
- 不负责触发判断，只负责摘要产出

### SessionContextSnapshotRepository

建议位置：

- `lib/models/session/session_context_snapshot.dart`
- `lib/repositories/session_context_snapshot_repository.dart`

职责：

- 读取、写入、更新 `session_context_snapshots`
- 提供按 `group_id` 读取最近有效快照的接口

## 接入点设计

### 1. TurnHarness

[`lib/services/turn_harness.dart`](/Users/skka/flutterSpace/FlutterAIChat/lib/services/turn_harness.dart) 在每次 `_continueTurnLoop()` 调用 planner 前，不再直接把“当前 turn transcript 映射消息”作为完整 planner 输入。

改为：

1. 读取当前 `groupId`
2. 调用 `SessionContextService.buildPlannerMessages(...)`
3. 获取“历史摘要 + 最近工作集 + 当前 turn transcript”的组合消息
4. 将其传入 `AgentPlannerService.planNextDecision()`

### 2. AgentPlannerService

[`lib/services/agent_planner_service.dart`](/Users/skka/flutterSpace/FlutterAIChat/lib/services/agent_planner_service.dart) 保持“只负责 planner 决策”的边界，不承担 session 历史拼装逻辑。

它接收的应该已经是整理好的 planner 消息列表。

### 3. DatabaseHelper / ChatStorage

[`lib/database/database_helper.dart`](/Users/skka/flutterSpace/FlutterAIChat/lib/database/database_helper.dart) 与 [`lib/storage/chat_storage.dart`](/Users/skka/flutterSpace/FlutterAIChat/lib/storage/chat_storage.dart) 需要增加 `session_context_snapshots` 的建表与 CRUD 接口。

### 4. 旧上下文策略清理

以下内容应在本次改造中直接删除：

- [`lib/models/context/context_strategies.dart`](/Users/skka/flutterSpace/FlutterAIChat/lib/models/context/context_strategies.dart)
- [`lib/models/context/message_context_strategy.dart`](/Users/skka/flutterSpace/FlutterAIChat/lib/models/context/message_context_strategy.dart)

同时清理：

- 相关无用引用
- 过期测试
- 任何仍暗示存在“第二套上下文策略”的文档说明

## 错误处理与降级原则

### 1. 快照缺失

如果当前 session 还没有任何 snapshot：

- 系统应退化为“仅最近工作集 + 当前 turn transcript”
- 不得因此阻塞主对话

### 2. 摘要生成失败

如果 `SessionSummaryService` 生成摘要失败：

- 记录日志与 trace
- 当前轮次可退化为仅使用较短 recent working set
- 不得将损坏的摘要快照写入数据库

### 3. Token 估算误差

由于 token 估算不可能完全等于 provider 实际计费结果，因此：

- 必须保留安全余量
- 不能把预算用满到极限
- 若 provider 返回上下文超限错误，应记录并下调后续预算策略

### 4. 投影失败

如果个别 tool / interaction 事件投影失败：

- 允许跳过该条投影
- 不影响整个 session 上下文构建
- 同时通过日志记录具体 event 类型和原因

## 测试要求

本次设计必须覆盖至少以下测试类别：

### 1. Session 上下文拼装测试

验证：

- 多个已完成 turn 会进入下一轮 planner 上下文
- 快照、最近工作集、当前 turn transcript 的顺序正确
- 摘要边界之后不会重复注入已覆盖历史

### 2. 投影规则测试

验证：

- `toolResult`、`toolError`、`userInteractionResult` 会被投影成紧凑文本
- `assistantToolCall`、`toolExecutionStarted`、`turnStatus` 不进入跨 turn 历史

### 3. Token 预算测试

验证：

- 在不同模型窗口下预算计算正确
- 达到压力阈值时会触发压缩
- 未达到阈值时不会无谓生成摘要

### 4. 快照存储测试

验证：

- `session_context_snapshots` 能正确创建、更新、读取
- `covered_until_turn_id` 能稳定定义最近工作集边界

### 5. 回归测试

验证：

- 不破坏现有 tool confirmation / ask-user-question / provider continuation 流程
- 不破坏现有 UI `messages` 时间线展示

## 文档要求

由于本次改造会成为核心基础设施，应新增架构文档：

- `docs/architecture/session-context-management.md`

该文档需要说明：

- `Session` 的定义
- 三层职责边界
- `SessionContextService` 及其协作者职责
- token budget 策略
- snapshot 数据模型
- 投影规则
- 旧上下文策略为何被删除

如本次实现还需要更新能力说明，也应同步更新：

- `README.md`
- `AGENTS.md`（若上下文管理约束、文档入口或实现规则发生变化）

## 方案结论

本次会话上下文管理改造采用以下最终方案：

- 以 `Session` 作为完整连续上下文对话单位
- 用 `SessionContextService` 替换旧 `context_strategies.dart` 体系
- 将模型输入收敛为“历史摘要 + 最近工作集 + 当前 turn transcript”
- 用 `SessionTokenBudgetService` 统一按当前模型预算判断是否需要压缩
- 用 `session_context_snapshots` 持久化摘要快照，而不是把摘要写成 UI 消息
- 按已完成 turn / 已完成交互闭环保护压缩边界
- 清理过时上下文策略文件与引用
- 在 `docs/architecture/` 中补充新的 session 上下文架构说明

这套设计的目标不是简单“把历史消息拼上去”，而是让当前项目正式从“消息列表裁剪”升级为“Session 级模型上下文管理”。
