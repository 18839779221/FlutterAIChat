# Responses Continuation 专属拼接设计

## 1. 背景

当前项目的 planner continuation 主路径建立在一个过强的统一假设上：

- `assistantTurnSnapshot.rawAssistantMessage` 保留 provider-native 原始响应
- `SessionContextService` 将其恢复为 `RawAssistantCarrier`
- adapter 在组装下一轮 planner 请求时，将 `RawAssistantCarrier` 中的 provider 原始内容按“可直接续传”的语义拼回请求

这条假设对 `chat/completions` 与 `anthropic/messages` 仍然基本成立，但对 `responses` 已经暴露出结构性问题。

最新日志中，`SdkResponsesAdapter.buildPlannerRequestSpecFromCarriers()` 在调用 `CreateResponseRequest.fromJson(...)` 时抛出：

- `FormatException: Unknown Item type: reasoning`

这说明当前 `responses` 路径把上一轮 `output` 中的 `reasoning` item 原样拼回了下一轮 `input`，而当前仓库使用的 `openai_dart 5.0.0` 请求模型并不接受该 item type 作为 request input。

本轮不讨论“升级 SDK 是否能解决”这一不确定因素。用户已明确要求：

- 本轮不升级 SDK
- 仅改造 `responses` 风格
- `chat/completions` 与 `anthropic/messages` 不动

因此，本设计的目标不是重做整个 replay 架构，而是在现有分层下，给 `responses` 提供一条专属 continuation 拼接路径，使其不再错误复用“raw output verbatim replay”。

## 2. 问题定义

### 2.1 当前 `responses` 续传语义混淆了 output 与 input

`responses` 的 provider 响应 `output` 是一组 provider-native output items。当前实现直接把它们当作下一轮 request `input` items 重新提交，这在协议语义上是不可靠的。

以当前仓库实现为例：

- `extractRawAssistantMessage()` 保存完整 `output`
- `buildPlannerPayloadFromCarriers()` 遇到 `RawAssistantCarrier` 时，直接把 `rawJson['output']` 中每个 item 追加到 request `input`

这会把“上一轮响应中存在”误解释为“下一轮输入中允许存在”。

### 2.2 问题不是单一字段过滤，而是 `responses` 缺少自己的 continuation builder

如果沿用“统一 replay + 特殊字段过滤”的思路，会反复遇到两个问题：

1. 过滤规则不稳定
2. 未来新增 output item 时，仍会继续把 output shape 当成 input shape

所以这次要修的不是“多加几个黑名单字段”，而是让 `responses` 具备独立的 continuation 拼接边界：

- 历史存储：仍可保留 provider-native raw assistant output
- planner replay：仅将真正参与 continuation 的 canonical conversation items 重新 materialize 为 request input

### 2.3 本轮不引入通用 replay strategy 抽象

从长期看，`apiStyle` 与 `replay strategy` 应拆分建模。但本轮范围必须收敛：

- 不引入新的全局 continuation strategy 枚举
- 不重写 `SessionContextService` 或 `PlannerContextCarrier` 的通用模型
- 不修改 `chat/completions` / `anthropic/messages`

本轮只在 `responses` adapter 内部实现专属 continuation builder。

## 3. 目标

本轮目标：

1. 让 `responses` planner continuation 不再直接 replay 原始 `output`
2. 在当前 `openai_dart 5.0.0` 下稳定构造可接受的 `CreateResponseRequest`
3. 保留 `responses` 历史 snapshot 的 provider-native 保真能力
4. 不影响 `chat/completions` 与 `anthropic/messages` 的现有行为
5. 不修改数据库 schema
6. 不依赖 SDK 升级

## 4. 非目标

本轮不包含以下内容：

1. 不升级 `openai_dart`
2. 不引入统一的多 replay strategy 架构
3. 不改造 `chat/completions` continuation
4. 不改造 `anthropic/messages` continuation
5. 不在本轮支持 provider-native `responses` 全量 output item replay
6. 不引入 `previous_response_id` / 服务端 state 优先策略

## 5. 设计原则

### 5.1 存储与续传分离

对于 `responses`：

- `rawAssistantMessage` 的职责是“历史保真”
- planner request builder 的职责是“续传构造”

二者不能再使用同一个“原样拼接”规则。

### 5.2 续传按 conversation semantics 构造，不按原始字段透传

`responses` continuation builder 只关心对下一轮 planner 真正有因果作用的 conversation items：

- assistant message
- assistant function call
- subsequent function call output

`reasoning` 仍然可以保留用于 UI / 历史 / 调试，但不进入本轮 request input。

### 5.3 只在 `responses` 适配器内部收口

本轮不让上层感知新的 continuation 策略分支。继续沿用：

- `SessionContextService` 产出 `RawAssistantCarrier`
- `ConfigurableHttpLLM` 调用 adapter 生成 request spec

变化仅体现在 `SdkResponsesAdapter.buildPlannerPayloadFromCarriers()` 如何解释 `RawAssistantCarrier`。

## 6. 核心设计

### 6.1 `responses` 专属 continuation builder

在 `SdkResponsesAdapter` 中，为 planner payload 构造引入 `responses` 专属解释规则：

- `SyntheticCarrier.system`
  - 继续聚合为 `instructions`
- `SyntheticCarrier.user`
  - materialize 为 `type=message, role=user`
- `SyntheticCarrier.toolResult`
  - materialize 为 `type=function_call_output`
- `RawAssistantCarrier`
  - 不再 verbatim splice `rawJson['output']`
  - 改为按 `responses` continuation builder 解释 `output`

### 6.2 `RawAssistantCarrier.output` 的 item 解释规则

对 `responses` 原始 `output`，本轮采用如下规则：

#### A. `message`

保留。转换为可接受的 request input item：

- `type=message`
- `role=assistant`
- `content` 保留 `output_text` 部分

#### B. `function_call`

保留。转换为 request input item：

- `type=function_call`
- 保留 `call_id`
- 保留 `name`
- 保留 `arguments`

#### C. `reasoning`

不进入 request input，但继续允许存在于历史 raw snapshot。

原因：

1. 当前 SDK request model 不支持它
2. 它不是 tool round-trip 与 assistant continuation 的最小必要项
3. 本轮目标是在现有 SDK 下稳定恢复 `responses` continuation，而不是一步到位支持所有 provider-native output item

#### D. 其他未知 output item

默认忽略，并打 debug log。

原因：

- 未知 output item 不应直接炸掉 planner request
- 本轮先保证 continuation 构造稳态
- 后续如果某个新 item 被证明是 continuation 必需项，再显式纳入 builder

### 6.3 为什么这不等于“重新回到字段过滤”

这次的边界不是“枚举黑名单字段”，而是：

- `responses` request input 只由 continuation builder 生成
- builder 只接受本轮明确定义的 canonical conversation items

也就是说，过滤不是主逻辑，**构造**才是主逻辑。

### 6.4 历史 raw snapshot 继续保留

`extractRawAssistantMessage()` 和 `assembleRawFromStreamingSnapshot()` 继续保留当前 provider-native 历史表示，不因为本轮 continuation 改造而降级历史保真。

原因：

- UI / 调试 / 未来更完整的 provider-native replay 仍需要 raw snapshot
- 本轮要修的是 planner request builder，不是持久化格式

## 7. 影响范围

### 7.1 需要修改

- `lib/models/llm/adapters/sdk_responses_adapter.dart`
- `test/models/llm/adapters/responses_roundtrip_test.dart`
- `test/models/llm/configurable_http_llm_test.dart`

### 7.2 不需要修改

- 数据库 schema
- `chat/completions` adapter
- `anthropic/messages` adapter
- `SessionContextService` 的 carrier 生产逻辑
- `TurnHarness` 主状态机

## 8. 测试策略

### 8.1 adapter 聚焦测试

新增/修改测试，覆盖：

1. `RawAssistantCarrier.output` 中包含 `reasoning + message + function_call`
2. planner payload 构造后：
   - `reasoning` 不进入 request `input`
   - `message` 与 `function_call` 保留
   - `function_call_output` 仍由 `SyntheticCarrier.toolResult` 追加
3. `CreateResponseRequest.fromJson(payload)` 可成功构造

### 8.2 回归测试

在 `ConfigurableHttpLLM` 聚焦测试中覆盖：

1. 第二轮 `responses` planner continuation 不再因 `reasoning` 抛 `FormatException`
2. 当前 `responses` tool round-trip 仍然正常
3. `chat/completions` 与 `anthropic/messages` 的测试不需要改动

## 9. 风险与权衡

### 9.1 风险

本轮会放弃把 `responses` 的 `reasoning` item 直接带入 request input。这意味着：

- 与某些更完整的 provider-native `responses` continuation 语义相比，本轮是保守实现

### 9.2 权衡

这是有意为之。本轮约束已经明确：

- 不升级 SDK
- 先修复当前 continuation 崩溃
- 不扩大为多协议 replay 重构

在这个边界下，优先保证 `responses` continuation 的运行稳定性，优于追求“完整 provider-native replay”。

## 10. 验收标准

满足以下条件即可视为本轮完成：

1. 最新复现路径下，不再出现 `FormatException: Unknown Item type: reasoning`
2. `responses` 第二轮 planner continuation 能继续执行
3. `responses` 历史 raw snapshot 仍保留
4. 不升级 SDK
5. `chat/completions` / `anthropic/messages` 行为不变
