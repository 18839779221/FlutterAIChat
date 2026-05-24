# Anthropic Messages Runtime 改造设计

## 背景

在上一轮统一协议运行时内核改造后，OpenAI `chat/completions` 与 `responses` 已经基本进入统一的 runtime 执行边界：

1. `ApiStyleAdapter` 负责协议语义映射
2. `ProtocolExecutionRuntime` 负责请求执行
3. runtime 内部 stream event adapter / parser 负责把协议流式事件投影成 `StreamingPlannerChunk`

当前 `anthropic messages` 虽然已经挂进同一套 `ProtocolRuntimeRegistry`，但仍然停留在“共享 JSON runtime + 通用 parser”阶段：

- adapter：`AnthropicMessagesAdapter`
- runtime：`HttpJsonProtocolRuntime`
- streaming parser：`ApiStreamParser` 中的 anthropic 分支

这意味着 `anthropic` 目前在架构上仍然是“先接进统一边界，但执行细节还没有真正抽离完成”的状态。随着下一步要正式推进 anthropic 改造，如果继续沿用当前 `HttpJsonProtocolRuntime(apiStyle: anthropicMessages)` 的形态，会有几个问题：

1. anthropic 的协议细节仍然埋在共享 JSON runtime 与通用 parser 中
2. `ApiStreamParser` 同时承担 OpenAI / Responses / Anthropic 三种语义，职责不够干净
3. 后续如果要替换 anthropic 执行实现，仍然容易回头污染 `ConfigurableHttpLLM`
4. live/provider 差异排查时，很难区分“通用 JSON runtime 问题”与“Anthropic 协议实现问题”

因此，这一轮的目标不是重写整个 Anthropic 语义层，而是把它像前两种协议一样，补齐为**独立、干净、可替换的 runtime 执行实现**。

## 目标

1. 让 `anthropic messages` 从“共享 JSON runtime 的特例”升级为“独立协议 runtime”。
2. 继续保持 `ConfigurableHttpLLM` 为高层编排器，不重新承担 Anthropic HTTP / SSE 细节。
3. 保留当前已经稳定的 Anthropic 语义层成果：
   - `AnthropicMessagesAdapter`
   - `AnthropicMessagesToolLoopAdapter`
   - append-only transcript / turn ledger / UI projection
4. 把 anthropic 的执行细节收敛到专属 runtime 边界，让非流与 planner streaming 都进入同一套 runtime 主链路。
5. 为未来进一步替换底层执行实现预留空间，但本次优先采用社区 Dart SDK `anthropic_sdk_dart` 作为 Anthropic native runtime 的 typed event / typed response 边界。

## SDK 选型

当前 Anthropic 官方公开的 client SDK 不包含 Dart；官方列出的语言为 Python、TypeScript、Java、Go、Ruby、C#、PHP 与 CLI，因此本仓库不能像 OpenAI 那样直接接入官方 Dart SDK。

与此同时，Anthropic 官方提供的 OpenAI SDK compatibility 明确更偏向“测试 / 对比能力”的兼容层，而不是大多数生产场景下的长期方案；并且官方明确建议，若想获得完整 Claude API 能力，应优先使用 native Claude API。

基于这一点，本次选择：

- 在 Dart/Flutter 层引入社区维护的 `anthropic_sdk_dart`
- 仅在 `AnthropicMessagesRuntime` 边界内依赖该 SDK
- 保持上层 adapter / transcript / tool-loop 完全由仓库自有抽象掌控

选择理由：

1. `anthropic_sdk_dart` 已提供 typed `client.messages.create(...)`
2. 已提供 typed `client.messages.createStream(...)`
3. 已覆盖 tool calling、extended thinking、token counting 等原生 Claude API 能力
4. 是 pure Dart package，适合当前 Flutter 项目
5. 即便它是社区 SDK，只要依赖被限制在 runtime 边界内，未来若 Anthropic 官方推出 Dart SDK，替换成本也可控

## 当前稳定落地策略

考虑到当前仓库中的 anthropic planner streaming fixtures 与部分兼容 provider 仍依赖现有 SSE 事件形状，本次稳定落地采用混合策略：

- 非流请求：`AnthropicMessagesRuntime.execute()` 使用 `anthropic_sdk_dart`
- planner streaming：`AnthropicMessagesRuntime.streamExecute()` 走统一 runtime 流式主链路：
  单次 HTTP SSE 响应 -> 最小兼容归一化 -> `anthropic_sdk_dart` typed `MessageStreamEvent` -> `AnthropicStreamEventAdapter`
- `AnthropicStreamEventAdapter` 负责把 typed stream event 映射为统一 `StreamingPlannerChunk`

这样可以让 Anthropic 的非流与流式执行都进入统一 runtime 边界，同时把历史 provider 兼容噪音限制在一个很小的 streaming normalization 层。

## 非目标

1. 本次不改 `TurnHarness`、`AgentPlannerService`、`ToolOrchestratorService` 主循环。
2. 本次不重写 `AnthropicMessagesAdapter` 的 tool transcript 语义。
3. 本次不改变数据库、timeline message、turn step 持久化形状。
4. 本次不引入一套新的 provider 无关消息 DSL。
5. 本次不顺手重构 OpenAI `chat/completions` / `responses` 已稳定的 runtime 路径。

## 当前状态分析

### 已经比较干净的部分

`AnthropicMessagesAdapter` 当前已经具备较好的协议语义边界：

- 能构建 `JsonProtocolRequestSpec`
- 能把 system prompt 提升到顶层 `system`
- 能把 `tool_use` / `tool_result` 映射为 anthropic 原生 content block
- 能从 streaming snapshot 还原 `thinking` / `text` / `tool_use` 的 raw assistant message

`AnthropicMessagesToolLoopAdapter` 与现有 roundtrip 测试也说明：

- planner append-only transcript 语义已经稳定
- ask-user resume / tool result continuation / multi-tool continuation 已有明确预期

也就是说，**Anthropic 的“语义层”不是当前主要问题**。

### 仍然不够干净的部分

#### 问题一：Anthropic 执行层仍是共享 JSON runtime 特例

当前 `ConfigurableHttpLLM` 为 `ApiStyle.anthropicMessages` 注入的是：

- `HttpJsonProtocolRuntime(apiStyle: ApiStyle.anthropicMessages)`

这会让 anthropic 的请求执行与其它未来可能的 JSON-style 协议耦合在同一个 runtime 中。虽然技术上能工作，但从架构上不够清晰：

- 无法一眼判断“这是 anthropic 专属能力”还是“所有 JSON 协议共享能力”
- 难以为 anthropic 单独演进重试、header、streaming fallback 与错误语义

#### 问题二：Anthropic 流式事件仍依赖通用 `ApiStreamParser`

当前 `ApiStreamParser` 同时承担：

- chat completions SSE 解析
- responses SSE 解析
- anthropic SSE 解析

其中 anthropic 的分支其实已经具备自己独立的协议特征：

- `content_block_start`
- `content_block_delta`
- `input_json_delta`
- `content_block_stop`
- `message_delta`
- `message_stop`
- thinking signature

这类逻辑如果继续放在通用 parser 中，会让未来的职责边界重新变得模糊。

#### 问题三：Anthropic side-task 与 planner 虽共用执行层，但缺少专属语义约束点

当前 `summarizeConversation()`、`processWebpageContent()` 与 `planTurnDecision()` 都能通过统一 runtime 走 anthropic，但 anthropic 特有的：

- `max_tokens`
- `thinking.disabled`
- 非流 fallback 形态
- 工具块与文本块的混合返回

仍然没有一个专属 runtime 位置来集中表达和约束。

## 设计原则

### 原则一：只替换执行边界，不重写语义边界

这次 anthropic 改造优先复用：

- `AnthropicMessagesAdapter`
- `AnthropicMessagesToolLoopAdapter`
- `StreamingDecisionAccumulator`
- turn ledger / transcript projection

不要为了“统一得更彻底”去重新设计 Anthropic 的 message / tool transcript 语义。

### 原则二：Anthropic 的协议实现必须有独立 runtime 归属

即便底层仍然使用 `http.Client`，也应该通过专属 runtime 表达：

- anthropic request execution
- anthropic streaming fallback
- anthropic stream event adaptation
- anthropic response serialization

而不是继续把它表现为“共享 JSON runtime 的一个 `apiStyle` 参数”。

### 原则三：把 parser 从“跨协议通用类”收缩为“协议专属能力”，但允许分阶段推进

目标不是一定删除 `ApiStreamParser`，而是先让 Anthropic 的主执行边界足够清晰。可以接受的过渡形态包括：

- 抽出 `AnthropicStreamEventAdapter`
- 在 provider / fixture 事件形状稳定后，再让 `ApiStreamParser` 的 anthropic 逻辑迁移进去
- 在迁移完成前，允许 `ApiStreamParser` 继续作为 anthropic planner streaming 的兼容主路径

### 原则四：执行期差异留在 runtime，不回流到 `ConfigurableHttpLLM`

与前一轮统一 runtime 一样，Anthropic 的错误语义、流式/非流 fallback、header 与 content-type 处理都应停留在 runtime 边界，不再把条件分支放回 `ConfigurableHttpLLM`。

## 核心设计

### 1. 新增 Anthropic 专属 runtime

新增：

- `AnthropicMessagesRuntime`

职责：

- 接收 `JsonProtocolRequestSpec`
- 内部使用 `anthropic_sdk_dart` 构建 `AnthropicClient`
- 构建 anthropic 请求 URI
- 执行非流请求
- 为流式请求提供 Anthropic 专属 runtime 归属点，即使底层暂时仍复用原始 SSE 路径
- 统一处理 anthropic 响应反序列化
- 对外返回统一的 `ProtocolExecutionResult` / `ProtocolStreamExecutionResult`

这样 `ProtocolRuntimeRegistry` 中的 anthropic 注册项将从：

- `HttpJsonProtocolRuntime(apiStyle: ApiStyle.anthropicMessages)`

替换为：

- `AnthropicMessagesRuntime(...)`

### 2. 新增 Anthropic 专属流式事件适配器

新增：

- `AnthropicStreamEventAdapter`

职责：

- 只处理 anthropic SDK typed stream event 语义
- 把 anthropic 协议事件投影为 `StreamingPlannerChunk`
- 保留当前已经验证过的：
  - tool call argument 增量拼装
  - whitespace 保真
  - thinking block / signature 处理
  - ping / keepalive 容错

当前阶段它主要承担“未来迁移目标的 typed 语义锁定”职责；待 provider / fixture 事件形状可被安全归一后，再作为主 streaming 适配路径接入 runtime。

### 3. 保持 `AnthropicMessagesAdapter` 的请求语义边界

本次不把 `AnthropicMessagesAdapter` 改成新的 provider DSL，只做最小收敛：

- 继续输出 `JsonProtocolRequestSpec`
- 继续负责 anthropic message / tool / raw assistant roundtrip
- 如有必要，只补小范围 helper，避免在 runtime 中重新拼语义 payload

### 4. 收缩 `HttpJsonProtocolRuntime` 的定位

有两种可接受的方向：

#### 方向 A：保留为通用兜底 runtime

- `HttpJsonProtocolRuntime` 只服务未来未拆专属 runtime 的 JSON-style 协议
- anthropic 不再是它的主要调用方

#### 方向 B：仅作为 anthropic runtime 的内部 helper

- `AnthropicMessagesRuntime` 可以在内部复用少量通用 HTTP 逻辑
- 但对外 registry 中只暴露 anthropic 专属 runtime

推荐方向 A，因为边界更清晰，也更有利于未来增量接入其它 JSON-style provider。

## 关键约束

### transcript / tool roundtrip 必须完全保真

以下行为必须保持不变：

- assistant `tool_use` 在 transcript 中的 providerCallId 保真
- user `tool_result` 与 `tool_use_id` 对齐
- ask-user interaction 结果继续以 anthropic continuation 的方式进入下一轮 planner
- same-turn / resumed-turn 的 step ledger 对齐

### streaming snapshot 语义必须保持不变

以下行为必须继续通过：

- `thinking -> text -> tool_use` 的 raw assistant 还原顺序
- 不完整工具参数时保留 decision
- 带 trailing garbage 的工具参数容错
- keepalive / ping chunk 不打断 planner streaming

### side-task 行为不能因 runtime 拆分而退化

需要确保：

- `summarizeConversation()` 仍可通过 anthropic 路径执行
- `processWebpageContent()` 仍可通过 anthropic side-model 路径执行
- 非流响应和流式 fallback 的错误语义清晰可观察

## 测试策略

### 单测

新增或更新：

- `test/models/llm/runtime/anthropic_messages_runtime_test.dart`
- `test/models/llm/runtime/anthropic_stream_event_adapter_test.dart`
- `test/models/llm/configurable_http_llm_test.dart` 中 anthropic runtime 走向断言

重点覆盖：

- 非流执行
- 流式 SSE 解析
- 非 SSE fallback
- thinking / tool_use / tool_result 相关块

### 既有 roundtrip 测试

必须继续通过：

- `test/models/llm/adapters/anthropic_messages_adapter_test.dart`
- `test/models/llm/adapters/anthropic_messages_roundtrip_test.dart`
- `test/services/agent_planner_service_test.dart` 中 anthropic continuation 相关用例

### live 集成测试

至少保留并建议复跑：

- `test/integration/chat_send_live/chat_send_live_anthropic_test.dart`

重点关注：

- news multi-tool continuation
- ask-user resume
- mixed success/failure
- file ops confirmation + resume

## 预期结果

完成后，三种协议风格都会落在一致的总边界上：

1. adapter 负责协议语义映射
2. 专属 runtime 负责协议执行
3. 专属 stream adapter 负责已完成收敛的流式事件转换；Anthropic 当前保持 runtime 专属边界 + SSE 兼容主路径
4. `ConfigurableHttpLLM` 只负责编排、重试、timeout、logging、accumulator 接线

届时 anthropic 将不再是“共享 JSON runtime 的特例协议”，而是先以独立 runtime 形式稳定落地，再在后续阶段继续完成 streaming 主路径收敛。
