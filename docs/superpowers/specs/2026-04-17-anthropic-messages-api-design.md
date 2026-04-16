# Anthropic Messages API 兼容设计

## 背景

当前运行时可配置的 HTTP LLM 通道只支持两种线协议：

- OpenAI 风格的 `responses`
- OpenAI 风格的 `chat/completions`

现在的协议识别、请求构造、流式解析，以及 provider-native tool loop 解析，都是围绕这两种格式实现的。我们需要补充对 Anthropic 官方 `v1/messages` API 格式的兼容，这样应用既能接官方 Anthropic 端点，也能接入保持同样协议格式的第三方中转服务。

本设计的目标是在不改变现有运行时入口和内部消息 / 工具抽象的前提下，把 Anthropic 作为第三类协议接入。

## 目标

- 在现有运行时可配置 LLM 通道中支持 Anthropic Messages API
- 保持当前 `BaseLLM` 接口以及 controller / provider 架构不变
- 继续根据配置的 base URL 自动识别协议类型
- 同时支持普通文本回复与 provider-native tool use
- 将 Anthropic 的流式文本输出接入现有增量聊天 UI
- 当 provider 暴露 `thinking` 风格输出时，映射到现有 reasoning 通道

## 非目标

- 第一版不追求覆盖 Anthropic 的全部高级能力
- 暂不支持 prompt caching、container 等 provider 专属增强特性
- 不引入第二套顶层 LLM 类型选择流程
- 不借这次接入重构整套 provider loop 架构

## 推荐方案

在现有 `ConfigurableHttpLLM` 体系内，把 Anthropic 增加为第三种 `ApiStyle`。

这样可以保持当前产品配置模型不变：

- 用户仍然只需要提供 API Key、Base URL、Model
- 运行时解析器根据 endpoint 自动判断线协议格式
- 应用继续复用一套内部消息模型和一套 agent / tool 编排模型

相比把 Anthropic 逻辑硬塞进现有 OpenAI 分支里，新增第三种协议分支边界更清晰；相比单独再做一个 `AnthropicHttpLLM`，这种方式也更符合当前产品“基于 endpoint 自动适配协议”的方向。

## 架构变更

### 1. 协议识别

`ApiProtocolResolver` 新增 `ApiStyle.anthropicMessages`。

识别规则：

- path 以 `/v1/messages` 结尾时，识别为 `anthropicMessages`
- path 以 `/chat/completions` 结尾时，识别为 `chatCompletions`
- 其余情况继续默认走 `responses`

请求 URI 构造规则：

- 当 style 是 `anthropicMessages` 且配置 URL 已经以 `/v1/messages` 结尾时，直接使用原值
- 否则自动补齐 `/v1/messages`

这样可以保证现有 OpenAI 兼容端点行为不变，同时允许通过 URL 形态自动激活 Anthropic 兼容路径。

### 2. 请求构造

`ConfigurableHttpLLM` 新增第三类 Anthropic 请求构造逻辑。

请求头：

- `content-type: application/json`
- `x-api-key: <apiKey>`
- `anthropic-version: 2023-06-01`

后续如果第三方中转需要额外 header，可以从 `LLMConfig.additionalConfig` 中读取可选透传字段；但第一版只依赖 Anthropic 标准必需头和现有运行时配置字段，不引入额外配置复杂度。

Payload 结构：

- `model`
- `system`，仅当系统提示存在时发送
- `messages`
- `stream`
- `max_tokens`
- `tools`，仅在 planner / native tool calling 场景下发送
- `tool_choice`，仅在结构化 planner 请求中按需发送

内部消息到 Anthropic 的映射规则：

- system prompt 通过顶层 `system` 字段发送
- user / assistant 消息映射到 Anthropic `messages`
- 工具结果通过 `user` 角色消息中的 `tool_result` content block 传回
- assistant 发起的工具调用从 provider 返回的 `tool_use` block 中解析

### 3. 流式解析

`ApiStreamParser` 新增 Anthropic SSE 解析能力。

第一版流式处理范围：

- assistant 文本增量统一发射为现有内部 `content` chunk
- `thinking` 与 `redacted_thinking` 文本在 provider 暴露时映射为现有内部 `reasoning` chunk
- 对暂不支持的非文本 block 事件做安全忽略

解析器应保持容错：

- 忽略未知事件类型
- 尽量继续消费部分可解析流，而不是整条请求直接失败
- 不因为某个可选 block 不认识就让整次响应崩掉

### 4. Tool Loop 解析

新增一个 Anthropic 专用 tool-loop adapter，把 provider-native 决策解析成现有内部模型：

- `tool_use` block 映射为 `ModelToolCall`
- assistant 文本 block 聚合为最终 assistant message
- provider continuation state 只保存后续调用必须的最小 Anthropic 上下文

这与现有 OpenAI 兼容协议所采用的“请求编排和 provider 专属决策解析分离”的模式保持一致。

### 5. Planner 与 Turn Decision 支持

Anthropic 兼容需要覆盖现有三个非普通聊天入口：

- `planNextAction`
- `planNextToolChoice`
- `planTurnDecision`

实现需要保持现有行为契约：

- 如果 provider 返回工具调用，则返回一个非终态 tool decision
- 如果 provider 返回普通 assistant 文本，则返回一个终态 assistant decision
- 如果 provider 返回的结构不受支持，则软失败，并在可用场景下保留现有 fallback 行为

## 数据流

### 普通聊天流程

1. 运行时设置加载 Base URL、API Key、Model
2. 协议解析器识别为 Anthropic Messages 风格
3. `ConfigurableHttpLLM` 构造 Anthropic 请求头与 payload
4. 响应流被解析成内部 `content` / `reasoning` chunk
5. 现有聊天 UI 与持久化链路保持不变

### Tool Use 流程

1. Planner 请求中带上 Anthropic `tools`
2. Provider 返回 `tool_use` block
3. Anthropic adapter 将其转换为 `ModelToolCall`
4. 现有 orchestrator 执行工具
5. 工具输出被转换为 Anthropic `tool_result` block 用于续传
6. Provider 返回最终 assistant 文本或继续发起新的工具调用

## 错误处理

Anthropic 路径应遵循当前 configurable HTTP 的错误处理方式：

- 非 200 响应保留 provider 状态码和 body 摘要
- 流式事件格式异常时记录日志，并尽量跳过继续处理
- planner 响应不支持时回退，而不是中断整轮对话
- 运行时配置缺失时仍在请求前做校验

补充保护：

- 当配置为 Anthropic endpoint 但缺失 `model` 时，请求前直接失败
- 当工具结果无法匹配 provider tool call id 时，记录日志并跳过该 continuation，避免发送畸形 payload

## 测试策略

优先补充聚焦性的测试，不做大范围无关重构。

必要测试包括：

- 协议解析器能识别 `/v1/messages`
- 请求 URI 构造能正确补齐 `/v1/messages`
- Anthropic 请求头包含 `x-api-key` 和 `anthropic-version`
- 聊天 payload 能正确映射 system prompt 与 messages
- 流式解析能把文本增量发射到内部 `content`
- 流式解析能把 thinking 事件映射到内部 `reasoning`
- planner / tool-loop 解析能提取 `tool_use`
- planner / tool-loop 解析能回退为直接 assistant 文本
- tool result continuation payload 使用 Anthropic `tool_result`

## 发布说明

这次改动应作为兼容性扩展发布，而不是改变现有 OpenAI 兼容用户的行为。

安全约束：

- 现有 `responses` 与 `chat/completions` 测试必须继续通过
- Anthropic 路径只能由 endpoint 形态触发
- 第一版不需要 UI 改动，因为当前应用已经有 reasoning 通道和 tool-use 展示链路

## 已确认决策

- Anthropic 的 `thinking` 输出映射到现有 reasoning 通道
- 直接 Anthropic 官方端点与使用相同 Messages API 格式的第三方中转都属于本次范围

## 实施纲要

1. 扩展协议识别与请求 URI 构造
2. 新增 Anthropic 请求头与 payload builder
3. 新增 Anthropic SSE 流式解析
4. 新增 Anthropic tool-loop adapter
5. 将 planner 与 turn-decision 分支接入新协议
6. 补充协议、流式解析与 tool use 的聚焦测试
