# Native Planner Tool Loop Redesign Design

## 背景

当前项目的 agent planner 已经同时存在两套语义：

- provider-native tool loop：`planTurnDecision()` 走 OpenAI Chat Completions / Responses 的原生 tool calling
- legacy JSON planner：`planNextAction()` 通过 system prompt 约束模型手写 JSON，再由本地解析成 `respond` 或 `call_tool`

这两套路径长期并存后，已经带来了三个结构性问题：

1. planner 语义被重复描述。`ToolDefinition.descriptionForModel` 已经进入 `tools[].description`，`PlannerPromptBuilder` 又把工具说明、使用边界和参数说明重复拼到 system prompt。
2. decision 抽象被压扁成“文本回复”和“工具调用”二选一，无法正确承载 OpenAI / Claude 原生模型在同一轮里同时输出 assistant 文本和 tool calls 的能力。
3. runtime 主链路虽然已经开始支持 native multi-tool planning，但仍被 legacy planner 及其兼容测试牵制，导致实现和测试都围绕旧协议打转。

本次改造不做兼容保留，目标是彻底移除 legacy planner，把 planner/tool loop 收敛到一条原生语义链路。

## 目标

本次设计目标如下：

- 删除 `PlannerPromptBuilder`，不再在 system prompt 中重复枚举工具定义
- 删除 legacy JSON planner，包括 `planNextAction()`、文本 JSON 解析和对应测试
- 让 `ToolDefinition.descriptionForModel` 成为唯一的 planner-facing 工具描述来源
- 把 planner 决策对象升级成“单轮 provider 原生输出”，允许同一轮同时包含 assistant 文本和多个 tool calls
- 让 turn loop 正确区分“过程型 assistant 文本”和“最终答复型 assistant 文本”
- 保留现有 step ledger / provider continuation / tool runtime registry 架构，但以新的 native decision 语义重新组织

## 非目标

本轮不包含以下内容：

- 不保留 legacy planner 的兼容入口
- 不为了兼容旧测试而维持 JSON `respond` / `call_tool` 协议
- 不把内部抽象完全切成 provider 原始 payload 镜像对象
- 不在这一轮同步重构全部 UI 展示样式

## 现状问题

### 1. Tool 描述重复注入

当前 planner 请求里，工具语义被同时放入两处：

- `tools[].description`
- `PlannerPromptBuilder.buildSystemPrompt()`

这会产生两个副作用：

- 工具说明存在双份真相，修改时容易偏离
- planner prompt 越来越像手写路由器，而不是原生 tool calling 的最小系统约束

### 2. Decision 抽象不符合原生模型语义

当前 `ModelTurnDecision` 的消费方式实际上仍带有强互斥假设：

- 有 tool calls 时，adapter 会把 assistant 文本丢掉或忽略
- 有 assistant 文本时，runtime 倾向于把它当作终态答复

这与 OpenAI / Claude 的原生行为不一致。模型完全可能在一轮里：

- 先输出一段可见说明
- 再发出一个或多个 tool calls
- 在后续 continuation 中继续补充文本或继续调用工具

### 3. Legacy planner 扭曲了主链路设计

即使 native planner 已经可用，当前代码结构里仍保留：

- `BaseLLM.planNextAction()`
- `AgentPlannerService.planNextAction()`
- legacy JSON 解析和兼容诊断码
- `PlannerPromptBuilder`
- 大量围绕 JSON 协议构建的测试

这会使新的 native 设计总要向旧协议妥协，无法形成统一抽象。

## 方案总览

本次改造采用一条主线：

1. 删除 legacy planner 和 `PlannerPromptBuilder`
2. 保留最小 system prompt，只描述全局 planner 约束，不再展开每个工具定义
3. 用 provider-native decision 作为唯一 planner 输出对象
4. 让 adapter 同时解析 assistant 文本和 tool calls
5. 让 turn harness 把“过程消息显示”和“工具执行推进”都纳入同一 decision 消费流程
6. 让最终答复生成保持独立，不再和 planner 内部 assistant 文本混用

## 方案 A：删除 Legacy Planner

### 删除范围

以下内容直接移除：

- `PlannerPromptBuilder`
- `AgentPlannerService.planNextAction()`
- `AgentPlannerService` 中所有 legacy JSON 解析逻辑
- `BaseLLM.planNextAction()`
- `ConfigurableHttpLLM.planNextAction()`
- `PlannerToolChoice` 及其仅服务于旧结构化 planner 的解析逻辑
- 所有围绕 `respond` / `call_tool` JSON 协议的测试

### 删除后的唯一入口

planner 只保留：

- `BaseLLM.planTurnDecision()`
- `AgentPlannerService.planNextDecision()`

也就是说，planner 从“先尝试 native，失败再 fallback legacy”改为“仅 native；失败即失败”。

### 风险与处理

风险：

- 删除 fallback 后，provider 不支持 tool calling 时将直接失败

处理：

- 本项目本轮明确不做兼容保留，运行时直接返回 `planner_request_failed`
- 测试和开发环境都统一围绕 provider-native tool loop 构建

## 方案 B：收敛 Tool 描述来源

### 新原则

`ToolDefinition.descriptionForModel` 是唯一的工具语义描述来源。

planner 请求中：

- `tools[].description` 只来自 `descriptionForModel`
- system prompt 不再重复列出每个工具的“什么时候使用 / 不要使用 / 参数说明”

### 执行策略信息

工具执行策略仍然需要暴露给模型时，不再通过额外 prompt 枚举。

建议做法：

- 在构建 `PlannerToolOption` 时，把执行策略作为结构字段保留给 runtime 和日志
- 若 provider 只能消费 `description`，则在生成单一 `description` 时统一拼入简短执行策略说明
- 不允许再出现“system prompt 一份 + tools.description 一份”的双重描述

### 结果

planner prompt 将从“工具说明手册”收缩为“最小全局行为约束”，例如：

- 你正在推进一个多步任务
- 如已有足够信息可进入终态
- 不要重复相同参数的工具调用
- 缺少必须由用户补充的信息时使用 `ask_user_question`

## 方案 C：重定义 Native Decision 语义

### 新语义

`ModelTurnDecision` 应表示“一次 provider 决策返回的完整结果”，而不是“最终答复或工具调用二选一”。

它应允许同时承载：

- 可见 assistant 文本
- 0 到多个 tool calls
- provider continuation state
- 是否进入终态

### 语义规则

新规则如下：

- `assistantMessage` 存在，不代表本轮结束
- `toolCalls` 非空，不代表 assistant 文本必须被丢弃
- `isTerminal == true` 仅表示该 decision 不再要求继续 tool loop 规划
- “最终给用户的收束答复”仍由 final answer 阶段单独生成

### 推荐数据形态

可以保留 `assistantMessage` 单字段，也可以升级成 `assistantMessages` 列表；本轮如果没有多段显示需求，保留单字段即可。

关键不在字段名，而在消费语义：

- assistant 文本是 decision payload 的一个组成部分
- 不是默认的最终答案

## 方案 D：重做 Provider Adapter

### Chat Completions

`OpenAIChatCompletionsToolLoopAdapter` 需要调整为：

- 从 `message.content` 中提取 assistant 文本
- 从 `message.tool_calls` 中提取一个或多个 tool calls
- 当两者同时存在时，同时保留

不能再采用“只要有 tool calls 就直接返回 `assistantMessage: null`”的逻辑。

### Responses

`OpenAIResponsesToolLoopAdapter` 需要调整为：

- 从 `output` 中提取 `message` 类输出文本
- 从 `function_call` 项中提取 tool calls
- 保留 `response_id` 等 continuation state
- 当 `output` 同时含文本和 `function_call` 时，一并映射到同一个 `ModelTurnDecision`

### 去重与排序

adapter 只做 provider payload 解析，不做业务级裁剪。

业务去重仍由 `AgentPlannerService._sanitizeDecision()` 负责，但必须保留 assistant 文本，不能因为工具被过滤掉就丢失文本部分。

## 方案 E：重做 Turn Harness 消费规则

### 核心执行顺序

当收到一个 `ModelTurnDecision` 时，按以下顺序处理：

1. 持久化 provider continuation state
2. 如果有 assistant 文本，先把它作为“过程型 assistant 消息”写入 transcript
3. 如果有 tool calls，继续执行工具批次
4. 当工具批次结束后，根据 turn 状态决定是否继续下一轮 planner
5. 只有在当前 decision 无待执行工具且进入终态时，才进入 final answer 生成流程

### 过程型 assistant 文本

这类文本的定位是：

- 思路说明
- 行动预告
- 工具前置说明
- 阶段性总结

它们对用户可见，但不等价于最终答案。

### 最终答复型 assistant 文本

最终答复仍保持现有 final answer 路径：

- 使用完整 transcript
- 结合 step ledger summary
- 由 planner 终态答复直接落盘，或在确有整理需求时进入按需 final answer 阶段

这样可以保证：

- planner 中间文本不会误替代最终答案
- 工具执行后的完整上下文仍能被 final answer 使用

## 方案 F：事件与状态对齐

### Transcript 对齐原则

同一轮中新增的“过程型 assistant 文本”必须在 transcript 中有稳定事件表示。

建议：

- 继续使用 assistant 消息事件，但在 eventType 或 payload 中标记其为 planner/intermediate 来源
- 不要和 final answer 的 assistant 消息混淆

### Step Ledger 对齐原则

`ChatTurnStep` 仍只跟踪工具步骤，不为过程型 assistant 文本创建 step。

原因：

- step ledger 的职责是可恢复、可确认、可 continuation 的工具轨迹
- 过程型文本属于用户可见消息，而不是工具步骤

## 测试策略

### 删除的测试

直接删除以下测试类型：

- legacy JSON planner 解析测试
- `PlannerPromptBuilder` 相关测试
- `PlannerToolChoice` 路径测试
- 所有验证 `respond` / `call_tool` 字符串协议的测试

### 新增或重写的测试

应围绕 native decision 语义新增测试：

- 同轮 `assistantMessage + single tool call`
- 同轮 `assistantMessage + multiple tool calls`
- 仅 assistant 文本且终态
- 仅 tool calls 且非终态
- responses continuation 包含 `function_call_output`
- duplicate tool call 被过滤后 assistant 文本仍保留
- tool call 被全部过滤且无可执行动作时的终态回退
- turn harness 会先落过程消息，再执行工具

## 实施步骤

建议按以下顺序落地：

1. 删除 `PlannerPromptBuilder` 和 legacy planner 接口
2. 精简 `BaseLLM` / `ConfigurableHttpLLM`，只保留 native decision 入口
3. 调整 `ModelTurnDecision` 的语义和注释
4. 修改两个 provider adapter，使其同时解析文本与工具
5. 重构 `AgentPlannerService._sanitizeDecision()` 保留 mixed output
6. 重构 `TurnHarness` 的 decision 消费顺序
7. 全量迁移测试到 native decision 语义
8. 最后更新 `README.md` 和 `AGENTS.md` 中关于 planner/tool loop 的描述

## 风险与缓解

### 风险 1：过程消息和最终答复混淆

缓解：

- 明确 transcript event 的来源标记
- final answer 仍单独生成，不直接复用 planner assistant 文本作为收束答案

### 风险 2：adapter 改造后影响 continuation

缓解：

- 保持 `providerState` / `providerCallId` / `response_id` 的现有保存方式
- 用回归测试覆盖 responses continuation

### 风险 3：测试大面积失效

缓解：

- 接受这是一轮语义迁移，而不是兼容修补
- 先删旧测试，再围绕新语义重建测试，避免被旧断言绑架

## 验收标准

完成后应满足以下标准：

- 代码中不存在 `PlannerPromptBuilder`
- 代码中不存在 legacy JSON planner 入口和解析逻辑
- planner 请求中的工具说明只有一份来源：`ToolDefinition.descriptionForModel`
- provider adapter 能正确解析同轮文本和 tool calls
- turn harness 会展示过程型 assistant 文本，并继续执行工具
- 最终答复仍由 final answer 阶段生成
- 所有 planner/tool loop 测试基于 native decision 语义通过
