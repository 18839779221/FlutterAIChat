# 统一 LLM 协议运行时内核设计

## 背景

当前 `ConfigurableHttpLLM` 已经通过 `ApiStyleAdapter` 将三种协议风格拆到独立适配器中，但“协议差异”仍然同时散落在三层：

1. **请求语义映射层**
   - `SdkChatCompletionsAdapter`
   - `ResponsesAdapter`
   - `AnthropicMessagesAdapter`
2. **传输执行层**
   - `ConfigurableHttpLLM` 自己发 HTTP 请求
   - `ConfigurableHttpLLM` 自己判断流式 / 非流式返回
3. **流式事件解析层**
   - `ApiStreamParser` 按协议分支解析 SSE 文本
   - `StreamingDecisionAccumulator` 消费内部统一 chunk

这导致当前 `chat completions` 虽然已经在请求对象与非流响应解析上使用 `openai_dart`，但 planner 主链路仍然是：

- 自己拼 JSON
- 自己发 HTTP
- 自己解析 SSE 文本
- 自己回填 raw assistant message

`responses` 更进一步，当前请求构造、非流响应解析、流式事件解析都仍是手写协议对象。与此同时，下一阶段马上要对 `anthropic messages` 做同类改造。如果继续按“每种协议各改一半”的方式推进，会把协议特定逻辑持续堆在 `ConfigurableHttpLLM` 和 `ApiStreamParser` 中，下一轮改造还要再次拆边界。

## 目标

1. 建立**统一协议运行时内核**，让 `ConfigurableHttpLLM` 只负责高层编排，不再直接承担 OpenAI / Responses / Anthropic 的传输细节。
2. 让 `chat completions` 全量走 SDK-first 运行时：
   - 非流 side-task 请求走 SDK
   - planner 流式请求走 SDK
   - 非流 planner fallback 走 SDK typed response 解析
3. 让 `responses` 全量走 SDK-first 运行时：
   - 请求构造使用 typed request
   - 非流响应使用 typed response
   - 流式 planner 使用 SDK event stream
4. 为即将到来的 `anthropic messages` 改造预留同一套 runtime 接缝，使其未来只需补充协议实现，而无需再次重构上层编排。
5. 复用现有的：
   - `StreamingDecisionAccumulator`
   - `OpenAIChatCompletionsToolLoopAdapter`
   - `OpenAIResponsesToolLoopAdapter`
   - `AnthropicMessagesToolLoopAdapter`
   - planner runtime snapshots / timeline / turn ledger

## 非目标

1. 本次不引入 Anthropic 外部 SDK。
2. 本次不改动 `TurnHarness`、`AgentPlannerService`、`ToolOrchestratorService` 的核心循环边界。
3. 本次不重写 `StreamingDecisionAccumulator`。
4. 本次不把三种协议的语义结构强行揉成一个 provider 无关的中间 DSL。
5. 本次不改变现有数据库、turn ledger、timeline message 的持久化结构。

## 现状问题

### 问题一：`ConfigurableHttpLLM` 同时承担协议编排与协议执行

当前文件 [lib/models/llm/configurable_http_llm.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/models/llm/configurable_http_llm.dart) 同时负责：

- 选协议
- 组装 payload
- 发 HTTP POST / streamed POST
- 判断返回是否是 `text/event-stream`
- 把 SSE 文本喂给 `ApiStreamParser`
- 根据协议选择 `ToolLoopAdapter`

这使得：

- SDK 化无法真正落到运行时主链路
- 新协议接入必须修改中心编排器
- 测试粒度被迫过粗

### 问题二：`ApiStreamParser` 混合了解析协议文本与投影业务语义

[lib/models/llm/api_stream_parser.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/models/llm/api_stream_parser.dart) 当前承担：

- responses SSE 文本解析
- chat completions SSE 文本解析
- anthropic SSE 文本解析
- 同时将解析结果直接投影成 `StreamingPlannerChunk`

这使得 SDK 原生 stream event 无法自然接入，也让未来 `anthropic` typed runtime 难以复用统一流式路径。

### 问题三：adapter 既负责语义映射，又被迫服务于手写 HTTP 载荷

`ApiStyleAdapter` 目前固定返回 `Map<String, dynamic>` payload，导致：

- `chat completions` 只能“构造 typed request 后再 toJson”
- `responses` 无法把 `CreateResponseRequest` 作为一等对象向下传递
- runtime 层无法只关心“如何执行 typed request”

## 核心设计

### 总体思路

建立三层清晰边界：

1. **Protocol Adapter（协议语义适配器）**
   - 负责把我方语义输入映射成“协议请求规范”
   - 负责把协议响应投影成我方决策模型 / raw assistant state
2. **Protocol Runtime（协议运行时）**
   - 负责执行非流 / 流式请求
   - 负责持有 SDK client 或 typed HTTP client
   - 不负责 turn / tool loop 业务
3. **Protocol Stream Adapter（协议流式事件适配器）**
   - 负责把 SDK native event 或 typed native event 变成 `StreamingPlannerChunk`

其中 `ConfigurableHttpLLM` 只保留：

- 读取运行时配置
- 选择协议
- 构建 request purpose / request options
- 统一 trace / retry / timeout / logging
- 统一接 `StreamingDecisionAccumulator`

### 新的抽象边界

#### 1. `ProtocolRequestSpec`

新增一组协议请求规范对象，代替“所有路径都只能返回 JSON map”的限制。

建议新增密封层级：

- `ProtocolRequestSpec`
- `JsonProtocolRequestSpec`
- `ChatCompletionsRequestSpec`
- `ResponsesRequestSpec`

语义：

- `JsonProtocolRequestSpec`：保留给 anthropic 当前 HTTP-native 实现
- `ChatCompletionsRequestSpec`：持有 `oai.ChatCompletionCreateRequest`
- `ResponsesRequestSpec`：持有 `oai.CreateResponseRequest`

这样 runtime 执行层可以面向 typed request，而不是强迫 adapter 先降级成 JSON。

#### 2. `ProtocolExecutionRuntime`

新增统一接口，例如：

- `execute(ProtocolRequestSpec spec, LLMConfig runtimeConfig)`
- `streamExecute(ProtocolRequestSpec spec, LLMConfig runtimeConfig)`

返回统一结果对象：

- `ProtocolExecutionResult`
  - `rawResponseJson`
  - `usage`
  - `text`
- `ProtocolStreamExecution`
  - `events`
  - `finalResponseJson` 或 `finalAccumulatorState`

本次落地三个 runtime：

- `OpenAiChatCompletionsRuntime`
- `OpenAiResponsesRuntime`
- `HttpJsonProtocolRuntime`（先服务 anthropic）

#### 3. `ProtocolStreamEventAdapter`

新增事件适配器接口，例如：

- `Stream<StreamingPlannerChunk> adaptNativeStream(Stream<Object> events)`

本次实现：

- `ChatCompletionsStreamEventAdapter`
- `ResponsesStreamEventAdapter`
- `JsonSseStreamEventAdapter` 或保留 anthropic 当前 parser 作为临时实现

### adapter 责任收缩

`ApiStyleAdapter` 将从“直接输出 wire json”收缩为“输出协议请求规范 + 负责 provider raw round-trip”。

建议新增或演化为：

- `buildChatRequestSpec(...)`
- `buildPlannerRequestSpecFromCarriers(...)`
- `extractRawAssistantMessage(...)`
- `assembleRawFromStreamingSnapshot(...)`

保留现有 raw round-trip 相关方法，因为：

- transcript replay 的 provider 形状仍然要按协议精确保真
- 这是 planner append-only 语义的重要边界

### `chat completions` 的落地方式

#### 请求

继续由 [lib/models/llm/adapters/sdk_chat_completions_adapter.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/models/llm/adapters/sdk_chat_completions_adapter.dart) 构建 typed `ChatCompletionCreateRequest`，但不再把它仅仅作为 `toJson()` 的中间过程。

#### 执行

新增 `OpenAiChatCompletionsRuntime`，职责：

- 构建 `OpenAIClient`
- 非流调用 `client.chat.completions.create(...)`
- 流式调用 `client.chat.completions.createStream(...)`
- 将最终 typed response 序列化回 `Map<String, dynamic>` 供既有 tool-loop parser / raw message capture 复用

#### 流式

复用已有 [lib/models/llm/adapters/sdk_stream_adapter.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/models/llm/adapters/sdk_stream_adapter.dart) 思路，但抽象成通用 `ChatCompletionsStreamEventAdapter`，作为 runtime 的 companion。

### `responses` 的落地方式

#### 请求

当前 [lib/models/llm/adapters/responses_adapter.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/models/llm/adapters/responses_adapter.dart) 负责手写 `input` / `tools` / `reasoning` 结构。本次将新增 `SdkResponsesAdapter`，构建 typed `CreateResponseRequest`、`ResponseInput`、`ResponseTool`。

#### 执行

新增 `OpenAiResponsesRuntime`，职责：

- 非流调用 `client.responses.create(...)`
- 流式调用 `client.responses.createStream(...)`
- 在需要时使用 `ResponseStreamAccumulator`
- 输出 typed response 的 `toJson()` 结果供现有 `OpenAIResponsesToolLoopAdapter` 复用

#### 流式

新增 `ResponsesStreamEventAdapter`，直接消费 `ResponseStreamEvent`，再投影成 `StreamingPlannerChunk`，不再依赖 `ApiStreamParser` 对 responses 的 SSE 文本逐行判断。

### `anthropic messages` 的未来接缝

本次不改 anthropic 实现，但会让它进入同一套 runtime 架构：

- adapter 输出 `JsonProtocolRequestSpec`
- runtime 使用 `HttpJsonProtocolRuntime`
- stream adapter 暂时仍用现有 `ApiStreamParser` 的 anthropic 分支

这意味着下一次改造 anthropic 时，只需要替换：

- adapter 的 typed request/response 映射
- runtime 的执行实现
- stream adapter 的 native event 解析

而无需再改：

- `ConfigurableHttpLLM`
- `StreamingDecisionAccumulator`
- planner / side-task 编排

## 文件设计

### 新增

- `lib/models/llm/runtime/protocol_request_spec.dart`
- `lib/models/llm/runtime/protocol_execution_runtime.dart`
- `lib/models/llm/runtime/protocol_runtime_registry.dart`
- `lib/models/llm/runtime/openai_chat_completions_runtime.dart`
- `lib/models/llm/runtime/openai_responses_runtime.dart`
- `lib/models/llm/runtime/http_json_protocol_runtime.dart`
- `lib/models/llm/runtime/chat_completions_stream_event_adapter.dart`
- `lib/models/llm/runtime/responses_stream_event_adapter.dart`
- `lib/models/llm/adapters/sdk_responses_adapter.dart`
- `test/models/llm/runtime/` 下对应测试文件

### 修改

- [lib/models/llm/adapters/api_style_adapter.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/models/llm/adapters/api_style_adapter.dart)
- [lib/models/llm/adapters/sdk_chat_completions_adapter.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/models/llm/adapters/sdk_chat_completions_adapter.dart)
- [lib/models/llm/adapters/responses_adapter.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/models/llm/adapters/responses_adapter.dart)
- [lib/models/llm/adapters/anthropic_messages_adapter.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/models/llm/adapters/anthropic_messages_adapter.dart)
- [lib/models/llm/configurable_http_llm.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/models/llm/configurable_http_llm.dart)
- [lib/models/llm/api_stream_parser.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/models/llm/api_stream_parser.dart)
- [test/models/llm/configurable_http_llm_test.dart](/Users/skka/flutterSpace/FlutterAIChat/test/models/llm/configurable_http_llm_test.dart)

## 兼容性与迁移策略

### 对上层保持兼容

以下上层接口本次不变：

- `BaseLLM`
- `ConfigurableHttpLLM.planTurnDecision`
- `ConfigurableHttpLLM.summarizeConversation`
- `ConfigurableHttpLLM.processWebpageContent`
- `PlannerRuntimeStreamListener`

### 对旧实现保持渐进兼容

- `LegacyChatCompletionsAdapter` 继续保留
- `ResponsesAdapter` 可作为过渡期 fallback 保留一个版本，直到 SDK 路径稳定
- anthropic 先继续走现有 HTTP-native 实现，但挂入统一 runtime registry

### 对测试保持兼容

现有：

- tool-loop parser 测试
- configurable_http_llm planner 测试
- integration/live tests

都应继续保留，新增 runtime 级单测覆盖运行时层。

## 验证标准

1. `chat completions` 不再通过 `ConfigurableHttpLLM` 里的手写 streamed HTTP + `ApiStreamParser` 主路径执行 planner 流。
2. `responses` 不再通过手写 JSON payload + `ApiStreamParser` 主路径执行 planner 流。
3. `ConfigurableHttpLLM` 中协议差异收缩到：
   - adapter / runtime / tool-loop parser 选择
   - 不再直接展开 chat/responses 的请求和流解析细节
4. `anthropic` 现有行为不回退，并已进入统一 runtime 注册路径。
5. 以下测试通过：
   - `fvm flutter test test/models/llm/configurable_http_llm_test.dart`
   - `fvm flutter test test/models/llm/adapters/sdk_chat_completions_adapter_test.dart`
   - `fvm flutter test test/models/llm/adapters/responses_adapter_test.dart`
   - 新增 runtime 测试
   - `bash scripts/run_live_llm_contract_tests.sh minimax-openai`
   - 至少一个 `responses` provider live contract

## 风险与应对

### 风险一：`openai_dart` 对第三方 OpenAI-compatible provider 的兼容差异

应对：

- runtime 层保留 provider base URL / headers / timeout 注入能力
- 保留 `LegacyChatCompletionsAdapter` 作为应急 fallback

### 风险二：流式 typed event 与现有 accumulator 语义不完全对齐

应对：

- 先增加 event adapter 单测
- 保持 `StreamingDecisionAccumulator` 不变，只替换上游 event source

### 风险三：responses typed model 覆盖不全

应对：

- typed request 走 SDK
- raw response 仍以 `toJson()` 回到现有 tool-loop parser
- 避免一次性重写 parser 语义层

## 结论

本次应把重点放在**统一运行时边界**，而不是只把某两个协议“接上 SDK”。只要 runtime 内核边界立住，`chat completions`、`responses` 与下一步 `anthropic messages` 就会共享同一条高层流程，后续协议迁移只会发生在协议实现内部，而不会再次冲击 `ConfigurableHttpLLM` 的主编排逻辑。
