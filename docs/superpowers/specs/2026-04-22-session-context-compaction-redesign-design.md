# Session 上下文压缩重构设计

## 背景

当前项目已经具备 `SessionContextService`、`SessionSummaryService`、`SessionTokenBudgetService` 与 `session_context_snapshots` 的基本框架，但现有上下文压缩策略仍然偏简陋，主要问题集中在以下几个方面：

1. 模型上下文预算通过模型名字符串匹配和固定默认值推断，缺少独立的预算注册表与可配置预算策略。
2. planner 上下文虽然已经具备“摘要 + 最近历史 + 当前 turn”的雏形，但边界定义不够严格，容易把“最近 completed turns”和“当前 turn transcript”混在一起理解。
3. 历史压缩策略本质上仍是“尽量保留最近 turn，其余压缩”，没有把“recent completed turns 的默认条数”和“recent 原文占预算比例”同时纳入控制。
4. 压缩目标过于保守，只要勉强低于预算阈值就停止，容易在下一轮快速再次触发压缩，无法形成“接近新对话”的轻量历史状态。
5. 对最早问题与长期约束的保留依赖最近工作集的隐含覆盖，不够稳妥；一旦退出 working set，应该由 summary 持续承载，而不是直接丢弃。

本次重构不推翻现有 Session 上下文架构，而是在其上引入一套更明确、可配置、贴近成熟 Agent 方案的压缩与预算管理策略。

## 目标

本次设计目标如下：

- 将模型预算配置、压缩阈值和 recent turn 保留策略从硬编码中抽离出来，形成明确的可配置模型。
- 明确 planner 上下文的最终分层，仅保留：
  - `system prompt`
  - `runtime sections`
  - `tools schema`
  - `history summary`
  - `recent completed turns`
  - `current turn transcript`
- 保证 `history summary`、`recent completed turns`、`current turn transcript` 三层严格互斥，不重复覆盖同一个 turn。
- 将“所有退出 recent working set 的旧历史”统一并入 summary，而不是直接丢弃；`turn 1` 等最早问题通过 summary 持续保留语义。
- 将 recent working set 的选择改为“双约束”：
  - 默认保留最近 `N` 个 completed turns
  - 但 recent 原文总量不得超过可用输入预算的指定比例
- 将压缩后的历史目标收紧为“小历史负载模式”，使压缩后上下文更接近一个携带少量必要记忆的新对话。
- 所有核心阈值均支持后续配置调整，不把策略写死在服务实现中。

## 非目标

本次设计不包含以下内容：

- 不引入跨 group 的长期记忆检索系统
- 不引入向量数据库或额外 memory store
- 不改变现有 UI 消息分页、卡片展示或 chat timeline 交互
- 不在本轮追求 provider 官方 tokenizer 级别的完全精确 token 计数
- 不把 provider 原始 payload 或大段工具 JSON 原样回灌进 summary
- 不在本轮引入三态或更复杂的多级压缩状态机

## 设计原则

### 1. 固定前缀稳定化

`system prompt`、`runtime sections` 与 `tools schema` 属于固定前缀。它们不是历史消息的一部分，也不应参与“recent working set”的取舍。

这样做的目的有两个：

- 在预算评估时明确区分“固定成本”和“历史负载”
- 为后续 prompt caching 或静态前缀优化留下稳定结构

### 2. 当前 turn 永不压缩

当前 turn transcript 永远单独保留，不进入 summary，也不与 recent completed turns 重叠。

这里的“当前 turn”是指当前仍在进行中的 turn，包括：

- 用户本轮输入
- planner/assistant 本轮中间文本
- 本轮产生的 tool call / tool result / interaction 事件

### 3. 旧历史整体做 summary

所有需要退出 recent working set 的 completed turns，都应整体并入 summary。即使是最早的 `turn 1`，也不因为“老”而直接丢弃，而是通过结构化 summary 保留其目标、约束和关键结论。

summary 不是“最近历史的缩略版”，而是“当前会话到某个边界之前的稳定记忆视图”。

### 4. recent working set 仅保留少量原文

recent working set 的职责是保留最近若干 completed turns 的细节原文，帮助模型继承局部工作连续性。它不是长期记忆层，也不承担保存最初需求的职责。

因此它应该受严格预算约束，并在压缩后维持较小规模。

### 5. 压缩目标要显著低于触发阈值

压缩不是“刚好低于阈值即可”，而是应该把历史负载收紧到远低于触发线的目标区间，以避免下一轮又立刻需要重新压缩。

本次设计采用：

- 触发阈值：默认 `80%`
- 压缩后历史负载目标：默认 `15%`

## 最终上下文分层

每次真正发给模型的上下文固定为六层：

1. `system prompt`
2. `runtime sections`
3. `tools schema`
4. `history summary`
5. `recent completed turns`
6. `current turn transcript`

其中前 3 层属于固定前缀，后 3 层属于会话上下文负载。

### 边界定义

#### history summary

- 覆盖范围：`turn 1 .. coveredUntilTurnId`
- 来源：`session_context_snapshots.summary_text`
- 语义：早期历史中的稳定目标、事实、约束、决策与关键结论

#### recent completed turns

- 覆盖范围：`coveredUntilTurnId + 1 .. currentTurnId - 1` 中尾部若干个 completed turns
- 来源：已完成 turn 的投影结果
- 语义：最近局部工作细节

#### current turn transcript

- 覆盖范围：仅 `currentTurnId`
- 来源：当前 turn 的 `chat_events`
- 语义：当前正在发生的输入、工具结果和交互状态

三者必须互斥，不允许同一个 turn 同时出现在两层中。

## 预算模型

### 1. 模型预算配置

新增 `ModelBudgetProfile` 与 `ModelBudgetRegistry`。

`ModelBudgetProfile` 至少包含：

- `modelId`
- `maxContextTokens`
- `reservedOutputTokens`
- `reasoningReserveTokens`
- `safetyMarginTokens`
- `compressionTriggerRatio`
- `postCompressionHistoryRatio`

`ModelBudgetRegistry` 负责：

- 根据运行时模型名解析预算 profile
- 按多层数据来源合并预算配置
- 优先精确匹配
- 次选 family 匹配
- 最后 fallback 到保守默认值

### 2. 模型预算数据来源

`ModelBudgetRegistry` 的预算数据来源按以下优先级解析：

1. 当前 provider/model 的运行时显式覆盖
2. 可选的本地 defaults/config 覆盖
3. 应用内置的模型预算默认表
4. 保守 fallback 默认值

第一版实现至少必须覆盖以下三层：

- 应用内置默认表
- 运行时 provider/model 覆盖
- fallback 默认值

本地 defaults/config 覆盖可以作为兼容接口或后续增强预留，但不要求在第一版必须完成。

第一版不要求联网查询 provider 官方 capability，也不依赖运行时远程拉取模型元数据。

### 3. 内置默认表

内置默认表是第一版的主数据源，用于维护当前产品明确支持或重点适配的模型预算配置，例如：

- `gpt-5`
- `gpt-4.1`
- `claude-sonnet-*`
- `gemini-*`
- 通用 fallback

这些值不要求严格等于 provider 官方理论上限，但必须足够保守，避免因预算过于乐观导致超窗。

### 4. 运行时覆盖

运行时覆盖用于处理“同一模型名在不同 provider/网关下可用能力不同”的情况。

它的来源应与当前实际请求所使用的 provider/model 配置链路保持一致，也就是与运行时 `ChatConfig`、provider 设置和 `ChatService.getModelName(config)` 所依赖的配置体系对齐。

当运行时配置提供显式预算字段时，应优先覆盖内置默认表；未提供的字段继续回落到内置 profile 或 fallback。

### 5. 可用输入预算

`usableInputBudget` 的计算方式如下：

```text
usableInputBudget
= maxContextTokens
- reservedOutputTokens
- reasoningReserveTokens
- safetyMarginTokens
```

### 6. 分项预算

在一次 planner 组装时，预算分项统一拆为：

- `fixedPrefixTokens`
  - `system prompt`
  - `runtime sections`
  - `tools schema`
- `summaryTokens`
- `recentCompletedTurnsTokens`
- `currentTurnTokens`

总输入估算为：

```text
totalInputTokens
= fixedPrefixTokens
+ summaryTokens
+ recentCompletedTurnsTokens
+ currentTurnTokens
```

压缩触发条件为：

```text
totalInputTokens / usableInputBudget >= compressionTriggerRatio
```

## 压缩策略

### 1. recent completed turns 的双约束规则

recent completed turns 的选择规则为：

1. 默认最多保留最近 `N` 个 completed turns
2. 但 recent 原文总量不得超过：

```text
usableInputBudget * recentTurnsMaxRatio
```

3. 若超过该比例，则从最老的 recent completed turn 开始移出，直到满足比例
4. 至少保留 `minRecentCompletedTurns = 1`
5. 当前 turn 永远单独保留，不参与该缩减

因此默认兜底始终为两个 turn 的语义：

- 当前 turn
- 前一个 completed turn

### 2. summary 滚动吸收

当达到压缩阈值时，策略不是直接删除更早历史，而是：

```text
旧 summary
+ 本次退出 recent working set 的更早 completed turns
=> 新 summary
```

新 summary 的 `coveredUntilTurnId` 更新为本次被吸收的最后一个 completed turn。

### 3. 压缩后目标

压缩后的目标不是压到“刚好可塞入窗口”，而是让历史负载尽量下降到：

```text
historyPayloadTokens
= summaryTokens + recentCompletedTurnsTokens
<= usableInputBudget * postCompressionHistoryRatio
```

默认目标为 `15%`。

若由于固定前缀或 summary 本身过大，无法完全满足 15% 目标，则采用以下优先级：

1. 优先保证总输入不超过可用预算
2. 在此前提下尽量逼近 15% 历史目标

## Summary 结构

为确保最初问题、长期约束和关键决策在退出原文后仍然稳定存在，summary 继续使用结构化栏目。建议固定为：

- 当前目标
- 已确认事实
- 用户偏好/限制
- 已确认决策
- 已否决方案
- 重要工具结论
- 未完成事项
- 风险与下一步

要求如下：

- 不输出原始 JSON 或 payload
- 保留后续继续工作所需的事实与结论
- 同一事实优先保留“结论”，不保留冗长推导过程

## 服务职责调整

### ModelBudgetRegistry

职责：

- 管理模型预算与压缩配置
- 输出 `ModelBudgetProfile`

不负责：

- 不直接拼装上下文
- 不直接做消息投影

### SessionTokenBudgetService

职责：

- 解析模型预算 profile
- 估算分项 token
- 计算 `usableInputBudget`
- 判断是否触发压缩

不负责：

- 不自己切 recent turns
- 不自己生成 summary

### SessionContextService

职责：

- 加载 snapshot
- 加载 `< currentTurnId` 的 completed turns
- 构建 `recent completed turns`
- 投影 `current turn transcript`
- 调用 budget service 决定是否 compact
- 必要时调用 summary service 生成新 snapshot
- 输出最终 planner messages

### SessionSummaryService

职责：

- 接收“旧 summary + 更早历史”的输入
- 生成新 summary
- 返回新 summary 文本与 `estimatedTokens`

不负责：

- 不决定 recent turns 保留几个
- 不决定最终 planner messages 排列

## 配置项

新增 `ContextCompactionConfig`，默认值如下：

- `compressionTriggerRatio = 0.80`
- `postCompressionHistoryRatio = 0.15`
- `defaultRecentCompletedTurns = 6`
- `recentTurnsMaxRatio = 0.10`
- `minRecentCompletedTurns = 1`

这些值必须集中配置，避免散落在多个 service 中。

## 决策流程

一次 planner 上下文组装的推荐流程为：

1. 解析当前模型预算 profile
2. 读取最新 snapshot
3. 读取 `< currentTurnId` 的 completed turns
4. 排除已被 snapshot 覆盖的历史
5. 投影当前 turn transcript
6. 按默认 `N` 选择 recent completed turns
7. 若 recent completed turns 超过 `10%` 配额，则继续缩减
8. 计算总输入预算
9. 若未达到 `80%` 触发线，直接输出
10. 若达到触发线：
    - 将 recent 窗口之外的更早历史并入新 summary
    - 更新 snapshot
    - 重新评估历史负载
11. 若 `summary + recent` 仍高于 `15%` 历史目标，则继续缩减 recent completed turns
12. 至少保留 1 个 completed turn，再加当前 turn 组成兜底两 turn 语义
13. 输出最终上下文

## 兼容性与迁移

本次设计建立在现有 Session 上下文体系之上：

- 不改变 `session_context_snapshots` 的核心语义
- 不改变 UI timeline 的展示数据来源
- 不改变 turn ledger 的事实记录方式

它主要替换的是：

- budget 解析方式
- recent working set 的选择方式
- 压缩触发与压缩目标
- summary 滚动吸收规则

## 测试重点

本次改造需要重点覆盖以下测试场景：

1. `history summary`、`recent completed turns`、`current turn transcript` 三层无重叠
2. 当前 turn 不会重复进入 recent completed turns
3. recent completed turns 同时受 `N` 和 `10%` 比例双约束
4. 压缩触发后，旧历史会进入 summary，而不是直接丢弃
5. `turn 1` 被并入 summary 后，其目标/约束语义仍能保留
6. 压缩后历史负载尽量下降到 `15%` 附近
7. 当 15% 无法完全满足时，仍能保证总预算不超窗

## 方案取舍

本次方案刻意不采用更复杂的设计，例如：

- 三态 `healthy / pressured / critical`
- 基于语义打分的 turn 重要性排序
- 跨 session 的长期记忆抽取

原因是当前仓库已经有成熟的 snapshot 与 turn-based 架构，优先目标是把“预算驱动 + summary 滚动压缩 + recent 双约束”这套经过验证的简化策略落稳，而不是一次性引入过多策略复杂度。

## 总结

本次重构后的 Session 上下文管理方案可以概括为：

- 固定前缀独立计算
- 当前 turn 永不压缩
- 最近少量 completed turns 保留原文
- 更早历史整体滚动进 summary
- 压缩由 token 预算压力触发
- recent working set 同时受默认条数和预算比例约束
- 压缩后把历史负载压到接近“新对话”水平

这样既能保留多轮任务延续性，又能避免长会话不断膨胀，贴近成熟 Agent 在上下文窗口管理上的主流做法。
