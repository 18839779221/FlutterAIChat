# Provider Contract 边界收口设计

## 背景

当前三种 `ApiStyle` 已经在执行层出现了比较清晰的进展：

1. `TurnHarness -> AgentPlannerService -> BaseLLM` 主链路基本不感知 provider wire 细节
2. `ProtocolRuntimeRegistry` 已经把 `chat completions`、`responses`、`anthropic messages` 挂到独立 runtime
3. `StreamingDecisionAccumulator` 已经把多种 provider 的流式增量收口为统一的 `StreamingPlannerChunk -> ModelTurnDecision`

但 provider 适配层还没有真正形成“一个协议、一份完整契约”的结构。

当前一个 `ApiStyle` 的协议知识仍然被拆散在三处：

1. `ApiStyleAdapter`
   - 构建 request spec
   - 提取非流文本
   - 提取/重组 `raw_assistant_message`
2. `*ToolLoopAdapter`
   - 将 provider 最终响应解析为 `ModelTurnDecision`
3. `ConfigurableHttpLLM`
   - 按 `ApiStyle` 选择 streaming 路径
   - 按 `ApiStyle` 分派最终 decision parse
   - 回填 provider-style 元数据

这导致当前架构虽然已经比早期更清晰，但 provider 抽象仍然只完成了一半：

- 出站请求语义大多被下沉了
- 入站最终决策语义还没有被同样下沉

随着接下来要继续推进 anthropic 改造，这个问题会立刻变成维护成本：

1. 新增或替换 provider SDK 时，需要同时修改 adapter、runtime、tool-loop parse 分支
2. `ConfigurableHttpLLM` 会继续成为 provider 特判汇聚点
3. 对同一个协议的请求/响应/streaming 规则理解会继续散落，难以验证“这就是该协议的完整边界”

## 目标

1. 让每个 `ApiStyle` 都拥有一份**完整的 provider contract**，统一承载该协议的请求构造、最终响应解析、raw assistant roundtrip 语义和能力声明。
2. 让 `ConfigurableHttpLLM` 退回为**纯高层编排器**：
   - 读取运行时配置
   - 选择 active contract / runtime
   - 做 retry / timeout / trace / accumulator 接线
   - 不再持有 provider-specific `switch`
3. 保持 `TurnHarness`、`AgentPlannerService`、append-only transcript、turn ledger、UI projection 不受影响。
4. 继续复用已经健康的公共层：
   - `StreamingDecisionAccumulator`
   - `ProtocolExecutionRuntime`
   - `ProtocolRuntimeRegistry`
   - `PlannerContextCarrier`
5. 为后续 anthropic 继续改造和未来新增 provider 保留干净接缝，而不是继续叠加过渡逻辑。

## 非目标

1. 本次不改变 `TurnHarness`、`AgentPlannerService`、`ToolCallService` 的主循环语义。
2. 本次不发明新的 provider 无关 message DSL。
3. 本次不改变数据库、turn ledger、timeline message、context snapshot 的持久化结构。
4. 本次不重写 `StreamingDecisionAccumulator`。
5. 本次不为了兼容已退休协议重新引入 legacy planner format 或旧 continuation 状态源。

## 当前问题

### 问题一：provider contract 是割裂的

`ApiStyleAdapter` 当前接口包括：

- `buildChatRequestSpec(...)`
- `buildPlannerRequestSpecFromCarriers(...)`
- `extractRawAssistantMessage(...)`
- `assembleRawFromStreamingSnapshot(...)`

但“把 provider 响应解释成 `ModelTurnDecision`”这一件事并不在同一接口内，而是在：

- `OpenAIChatCompletionsToolLoopAdapter`
- `OpenAIResponsesToolLoopAdapter`
- `AnthropicMessagesToolLoopAdapter`

中分别实现，再由 `ConfigurableHttpLLM._parseTurnDecisionForStyle(...)` 分发。

结果是：一个 provider 的协议知识被拆成“请求构造”和“响应解释”两套抽象族，边界不闭合。

### 问题二：`ConfigurableHttpLLM` 仍然是 provider 中央路由器

虽然 runtime 已经抽出来了，但 `ConfigurableHttpLLM` 仍然亲自决定：

1. 是否走 streaming planner
2. 非流结果该交给哪个 parse 分支
3. fallback payload 该如何回到决策模型
4. provider style metadata 如何补写

这说明目前真实结构更接近：

- `ConfigurableHttpLLM` 编排一批半抽象组件

而不是：

- 每个 provider contract 自洽，`ConfigurableHttpLLM` 只做公共 orchestration

### 问题三：同一 provider 的语义理解存在重复来源

同一个协议现在往往有多处解析逻辑：

1. `ApiStyleAdapter.parsePlannerChoice(...)`
2. `*ToolLoopAdapter.parseDecision(...)`
3. `extractRawAssistantMessage(...)`
4. `assembleRawFromStreamingSnapshot(...)`

这些方法都在理解 provider response shape，只是产出类型不同。它们分散在不同类里，会让后续改动容易出现：

- 某一层已经支持某个字段
- 另一层忘了同步
- streaming / non-streaming / replay 三条路径语义不一致

### 问题四：能力判断没有进入 contract

像 planner 是否支持 streaming，目前仍由 `ConfigurableHttpLLM` 基于 `ApiStyle` 硬编码判断。  
这在当前三种 style 都支持 streaming 时问题不大，但从架构上看，能力声明不应该停留在中央编排器里。

## 设计原则

### 原则一：一个协议只有一份完整契约

一个 `ApiStyle` 的协议语义应该集中在同一个 contract 中，至少覆盖：

1. request spec 构建
2. 最终响应解析
3. raw assistant roundtrip 提取/回组装
4. provider capability 声明

不要再把“请求构造”和“最终决策解析”拆成两套平行接口。

### 原则二：runtime 只负责执行，不负责业务语义

`ProtocolExecutionRuntime` 的职责保持为：

1. 执行非流请求
2. 执行流式请求
3. 将 native SDK / HTTP 事件归一成统一流式 chunk
4. 返回 typed 或 JSON 结果给上层 contract

它不负责：

1. tool loop 业务解释
2. append-only transcript 语义
3. turn terminal/non-terminal 规则

### 原则三：`ConfigurableHttpLLM` 只保留公共 orchestration

`ConfigurableHttpLLM` 允许保留的职责：

1. runtime config 读取与校验
2. `ApiStyle` 选择与 session-style 一致性校验
3. request purpose / budget / trace / retry / timeout
4. `StreamingDecisionAccumulator` 接线
5. 统一的 `providerStyle` / `modelName` 补写

它不应该继续承担：

1. provider-specific parse switch
2. provider-specific capability switch
3. provider-specific fallback 语义判断

### 原则四：复用健康的公共 streaming 内核

`StreamingDecisionAccumulator` 已经是正确的公共边界：

- provider runtime / stream adapter 负责把 native event 变成 `StreamingPlannerChunk`
- accumulator 负责把 chunk 变成统一 `ModelTurnDecision`

不要把 provider-specific 组装逻辑重新抬回上层 planner。

## 目标结构

### 1. `ProviderContract` / 扩展后的 `ApiStyleAdapter`

当前最自然的演进方式是直接扩展 `ApiStyleAdapter`，使其成为真正的 provider contract。

建议 contract 至少包含：

- `ApiStyle get style`
- `ProviderCapabilities get capabilities`
- `ProtocolRequestSpec buildChatRequestSpec(...)`
- `ProtocolRequestSpec buildPlannerRequestSpecFromCarriers(...)`
- `ModelTurnDecision? parseDecision(Map<String, dynamic> payload)`
- `PlannerToolChoice? parsePlannerChoice(Map<String, dynamic> payload)`
- `String extractNonStreamText(Map<String, dynamic> payload)`
- `Map<String, dynamic>? extractRawAssistantMessage(...)`
- `Map<String, dynamic>? assembleRawFromStreamingSnapshot(...)`

其中 `ProviderCapabilities` 应至少表达：

- `supportsPlannerStreaming`
- `supportsParallelToolCalls`
- 未来可扩展：
  - `supportsReasoning`
  - `supportsNativePreviousResponseId`
  - `requiresContentBlockReplay`

### 2. runtime 层保持 provider-native

runtime 层继续保留当前方向：

- `OpenAiChatCompletionsRuntime`
- `OpenAiResponsesRuntime`
- `AnthropicMessagesRuntime`

它们只负责：

1. 执行 request spec
2. 暴露非流结果 JSON
3. 暴露流式统一 chunk 或 fallback JSON

不再持有最终 decision parse 逻辑。

### 3. 删除独立 `tool_loop_adapter` 家族

`OpenAIChatCompletionsToolLoopAdapter`、`OpenAIResponsesToolLoopAdapter`、`AnthropicMessagesToolLoopAdapter` 的职责应被并回各自 provider contract。

保留文件名还是重命名都可以，但语义上不再把它们视为“另一个并列适配层”。

推荐两种落地方式：

1. 直接把 `parseDecision(...)` 合并进各自 adapter 文件
2. 保留独立 parser 文件，但由 provider contract 内部持有，不再让 `ConfigurableHttpLLM` 直接依赖三种 parser 类型

推荐第 2 种作为过渡步骤，原因是：

- 代码迁移更平滑
- 单测更容易保留
- 最终对外仍然表现为“一份完整 contract”

### 4. `ConfigurableHttpLLM` 的最终职责

目标上的 `planTurnDecision()` 主链应变成：

1. 解析 runtime config 与 `ApiStyle`
2. 取出 provider contract
3. 用 contract 构建 `ProtocolRequestSpec`
4. 根据 `contract.capabilities.supportsPlannerStreaming` 决定走 `execute` 还是 `streamExecute`
5. 若是非流：
   - `contract.parseDecision(payload)`
6. 若是流式 fallback JSON：
   - `contract.parseDecision(fallbackJson)`
7. 若是流式 chunk：
   - 交给 `StreamingDecisionAccumulator`
   - 再用 `contract.assembleRawFromStreamingSnapshot(...)` 构建 raw assistant replay state

这样 `ConfigurableHttpLLM` 不再需要：

- `_parseTurnDecisionForStyle(...)`
- `_shouldUseStreamingPlanner(...)`
- 三个 provider-specific tool-loop adapter 字段

## 分阶段落地方案

### 阶段一：contract 收口，不大改 runtime

先做最小但关键的结构收口：

1. 给 `ApiStyleAdapter` 增加 `parseDecision(...)`
2. 把现有三个 `*ToolLoopAdapter.parseDecision(...)` 委托进去
3. `ConfigurableHttpLLM` 改为只依赖 `ApiStyleAdapter.parseDecision(...)`
4. 用 `capabilities.supportsPlannerStreaming` 替代 `_shouldUseStreamingPlanner(...)`

这一阶段做完，provider 语义就已经从“两套抽象”收拢成“一套 contract”。

### 阶段二：剥离过渡期 legacy surface

在 contract 收口稳定后，再考虑收缩这些过渡接口：

- `buildHeaders(...)`
- `buildChatPayload(...)`
- `buildPlannerPayloadFromCarriers(...)`

保留它们作为测试辅助或 HTTP fallback 也可以，但不应再是主执行链路必经能力。

### 阶段三：Anthropic 与未来 provider 按同一 contract 接入

等 contract 结构稳定后，后续 anthropic 或新增 provider 的改造只需要：

1. 实现一份新的 provider contract
2. 实现或替换对应 runtime
3. 让 registry 注册这两者

上层 planner/turn loop 无需再改。

## 测试策略

### 单元测试

需要补强三类测试：

1. provider contract tests
   - `parseDecision(...)`
   - `extractRawAssistantMessage(...)`
   - `assembleRawFromStreamingSnapshot(...)`
2. `ConfigurableHttpLLM` orchestration tests
   - 确认不再依赖 provider-specific parse switch
   - 确认 planner streaming 路径由 capability 控制
3. runtime tests
   - 保持与当前 SDK / HTTP runtime 行为一致

### 回归测试

重点回归：

1. `test/models/llm/configurable_http_llm_test.dart`
2. 各 provider adapter / roundtrip tests
3. `test/models/llm/configurable_http_llm_live_test.dart`

至少要覆盖：

1. `chat completions`
2. `responses`
3. `anthropic messages`

并且 live 路径不能只跑纯文本 smoke，必须覆盖 planner 首轮解析和 append-only transcript tool roundtrip。

## 风险与控制

### 风险一：contract 合并时出现语义漂移

当前 `parseDecision` 与 `raw_assistant_message` 相关逻辑分散，收口时容易出现：

- non-streaming decision 解析和 streaming raw replay 语义不一致

对策：

1. 迁移时先保持 parser 代码不变，只改变依赖方向
2. 先做“委托式并入”，再做文件级合并

### 风险二：`ConfigurableHttpLLM` 过渡期同时持有新旧入口

如果迁移过程中既保留旧 switch，又加新 contract API，会让结构更糟。

对策：

1. 第一阶段就删除 `_parseTurnDecisionForStyle(...)`
2. 第一阶段就删除 `_shouldUseStreamingPlanner(...)`

### 风险三：为了少改代码保留不必要的中间层

如果继续长期保留“独立 tool-loop adapter + adapter facade”双层结构，会让名义上统一、实际上继续分裂。

对策：

1. 接受短期委托式过渡
2. 但在计划里明确最终目标是 provider contract 自洽

## 完成标准

满足以下条件才算这次收口完成：

1. `ConfigurableHttpLLM` 不再持有 provider-specific `parseDecision` 分支
2. `ConfigurableHttpLLM` 不再按 `ApiStyle` 硬编码 planner streaming 能力
3. 每个 provider 的最终 decision 解析入口都通过同一份 contract 暴露
4. `TurnHarness`、`AgentPlannerService`、append-only transcript、UI projection 行为不变
5. 三种 API style 的 mocked contract tests 和至少一个真实 provider live contract test 通过

## 总结

当前整体架构方向是对的：

- 上层 turn loop 边界已经比较干净
- runtime 层也已经走向 provider-native
- streaming 公共内核已经形成

这次真正需要补上的，不是再造一层新 abstraction，而是把 provider 语义收口到一份完整 contract 中。  
只要这一步做实，后面的 anthropic 深化改造和未来新增 provider，都会自然落在同一套稳定边界内。
