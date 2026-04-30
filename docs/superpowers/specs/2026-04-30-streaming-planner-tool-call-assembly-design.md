# Planner 内部流式 Tool Call 组装设计

## 背景

当前 `ConfigurableHttpLLM.planTurnDecision(...)` 对三类 provider-native planner 请求都采用“非流式整包返回后再解析”的方式：

- `Anthropic Messages`
- `OpenAI Chat Completions`
- `OpenAI Responses`

这条路径对短回答和小参数 tool call 基本可用，但当 planner 需要输出较大的 tool 参数时，会暴露出明显问题：

1. provider 端其实已经在持续生成 tool call 参数，但客户端必须等整包响应完整闭合后才能看到结果；
2. 当前 planner 请求超时主要按“整请求超时”来判定，容易出现“请求已经做了大量工作，但在最终闭合前被杀掉”的情况；
3. timeout 后又会回到整轮重试语义，代价高、成功率不稳定，也会让同类大参数 tool call 重复从头生成。

我们已经确认三类上游协议都具备不同程度的流式 tool-call / 参数增量能力：

- Anthropic Messages 支持 tool use 流式输出，且存在 fine-grained tool streaming；
- OpenAI Chat Completions 支持流式 `tool_calls[].function.arguments` 增量；
- OpenAI Responses 支持 function call arguments delta / done 事件。

因此，问题的关键并不是“是否能流式拿到 tool 参数”，而是我们当前没有在 LLM 适配层内部消费这些增量能力。

## 目标

1. 在 **不改变上层 planner / turn loop / tool runtime 合约** 的前提下，让 `ConfigurableHttpLLM.planTurnDecision(...)` 在内部优先使用 provider streaming 来组装最终 `ModelTurnDecision`。
2. 把 streaming 视为 **LLM 适配层的内部传输与组装机制**，而不是直接向 event / projection / UI 暴露的新公共流程。
3. 为“大参数、长生成时间”的 tool call 提供更稳定的 planner 收敛路径，降低整包 timeout 风险。
4. 方案保持通用，围绕“tool call 参数增量组装”设计，不绑定具体工具、具体字段或具体 UI 呈现。
5. 接入顺序遵循：
   - `Anthropic Messages`
   - `OpenAI Chat Completions`
   - `OpenAI Responses`

## 非目标

- 本轮不让 `TurnHarness`、`AgentPlannerService`、`DecisionToolCallExecutor` 感知 planner 中途流式过程；
- 不新增面向 UI 的 tool-call delta 事件；
- 不修改 tool runtime 的执行协议，不做“边生成参数边执行 tool”；
- 不为了某个工具字段建立专项数据通道；
- 不在本轮重构 `BaseLLM` 顶层接口；
- 不在本轮引入新的 planner fallback 模式。

## 核心结论

本轮采用：

- **底层流式**
- **上层仍然一次性拿到完整 decision**

也就是：

1. `ConfigurableHttpLLM` 内部按 provider 支持能力使用 `stream: true`；
2. 内部 parser 将 provider 原始 SSE / chunk 规范化为统一的内部增量事件；
3. 内部 accumulator 持续聚合 assistant 文本、reasoning、tool call 元数据与参数增量；
4. 当 provider 明确结束、或 tool call / assistant 响应达到可终结状态时，再产出最终 `ModelTurnDecision`；
5. 对 `AgentPlannerService` 及以上层，`planTurnDecision(...)` 仍然表现为同步等待一个最终完整结果。

这意味着 streaming 是实现细节，而不是新的上层架构事实。

## 现状分析

### 当前能力

- `ApiStreamParser` 已能按 `ApiStyle` 解析三类文本 / reasoning 流式响应；
- `ConfigurableHttpLLM` 已按 `ApiStyle` 路由请求与 tool-loop adapter；
- `planTurnDecision(...)` 已统一产出 `ModelTurnDecision`；
- 三类 provider-native planner 续接状态已分别具备基础支持。

### 当前缺口

1. `planTurnDecision(...)` 仍发送非流式 planner 请求；
2. `ApiStreamParser` 只向上提供：
   - content
   - reasoning
   不提供 tool call 参数增量语义；
3. `ConfigurableHttpLLM` 没有“增量组装最终 decision”的内部状态机；
4. timeout 仍主要以“整请求闭合前必须完成”为前提，无法充分利用 provider 已经持续产出的进展。

## 设计原则

### 1. Streaming 只在 LLM 适配层内部传播

本轮不新增 `BaseLLM.streamTurnDecision(...)` 之类的上层公共接口。

原因：

- 上层当前没有展示中间态的需求；
- 上层也不需要边流边改 tool runtime 状态；
- 如果把中间态抬升为公共架构事实，会显著扩大改动面，并让 event / projection / UI 都承担不必要复杂度。

### 2. 组装围绕“通用 tool call 参数增量”展开

不绑定任何具体工具，不假设某个特定参数字段会更重要。

系统只处理统一语义：

- 某个 tool call 已开始；
- 某个 tool call 的参数文本 / 参数结构正在增量到达；
- 某个 tool call 已完成；
- 最终决策里可能包含：
  - 0 个或多个 tool calls
  - assistant message
  - visible reasoning
  - provider continuation state

### 3. 参数增量优先以“原始缓冲 + 最终解析”处理

不同 provider 对 tool 参数增量的外观不同：

- Anthropic fine-grained tool streaming 可能中途给出尚未闭合的参数片段；
- Chat Completions 通常持续追加 `function.arguments` 字符串；
- Responses 以 delta 事件形式给出参数片段。

因此，内部聚合时应优先维护：

- 原始参数缓冲
- 尽可能更新的已解析 arguments
- 是否已完成

而不是假设每个 delta 都能直接映射为稳定的 `Map<String, dynamic>`。

### 4. 维持既有上层语义

`TurnHarness` 仍然只消费一个完整 `ModelTurnDecision`：

- 有 tool calls 时，进入 tool execution
- 是 terminal assistant message 时，进入 final response 路径
- 失败时返回 planner failure decision

本轮不改变这些语义。

## 方案概览

### 1. 在 `ConfigurableHttpLLM.planTurnDecision(...)` 内增加流式分支

逻辑形态：

1. 读取 runtime config，识别 `ApiStyle`
2. 根据当前 style 选择：
   - 若该 style 已接入流式 planner 收敛，则发送 `stream: true`
   - 否则保留现有非流式整包路径
3. 流式响应交给 parser 解析为统一内部 chunk
4. chunk 送入 accumulator
5. 流结束后由 accumulator 产出最终 `ModelTurnDecision`

这样可以逐协议渐进接入，而不是一次全切。

### 2. 引入内部统一流块模型

建议新增仅在 LLM 内部使用的标准流块，例如：

- `contentDelta`
- `reasoningDelta`
- `toolCallStarted`
- `toolCallArgumentsDelta`
- `toolCallCompleted`
- `messageCompleted`
- `streamCompleted`

这个模型的职责是把 provider-specific 原始事件规范化，不直接承担业务判断。

### 3. 引入内部 decision accumulator

建议新增 `StreamingDecisionAccumulator`，仅用于 planner 内部最终 decision 组装。

职责：

1. 聚合 assistant 文本增量；
2. 聚合 visible reasoning；
3. 维护一个或多个 `ToolCallDraft`；
4. 在流完成时产出最终 `ModelTurnDecision`；
5. 提供最小必要的 providerState 收敛结果。

`ToolCallDraft` 建议包含：

- `providerCallId`
- `toolName`
- `rawArgumentsBuffer`
- `parsedArguments`
- `isCompleted`
- `providerMetadata`

这里 `providerMetadata` 用于保留不同协议下最终 decision 所需的最小 identity / continuation 信息，但不向上扩散 provider-specific 结构。

### 4. Parser 与 Accumulator 的边界

#### Parser 负责

- 解析协议事件；
- 做 provider-specific 字段提取；
- 产出统一 chunk。

#### Accumulator 负责

- 维护跨 chunk 状态；
- 把多个 chunk 合并成 tool call 草稿；
- 在结束时生成最终 `ModelTurnDecision`；
- 处理参数缓冲的最终解析与容错。

这样可以避免把 provider-specific 逻辑和 decision 语义混在一起。

## 三类协议的接入策略

## 1. Anthropic Messages

### 优先级

第一优先级接入。

原因：

- tool use 流式能力强；
- fine-grained tool streaming 对大参数场景收益最大；
- 中途可能出现尚未闭合的参数内容，最需要内部 accumulator 的缓冲能力。

### 解析策略

对于 Anthropic：

- 识别 tool use 相关 block / delta；
- tool 参数增量优先作为“原始参数片段”追加到 `rawArgumentsBuffer`；
- 每次追加后可尝试做宽松解析；
- 只有在参数完整闭合或 provider 发出完成信号后，才把其视为稳定的最终 arguments。

### 风险

Anthropic fine-grained tool streaming 中途可能产生“不完整但合法继续”的 JSON 文本。

因此：

- 中途解析失败不能视为 planner failure；
- 必须允许“当前还不可解析，但流仍可继续”；
- 只有在最终完成后仍无法解析，才作为 planner 无效响应处理。

## 2. OpenAI Chat Completions

### 优先级

第二优先级接入。

### 解析策略

- 解析 `choices[].delta.tool_calls`
- 按 `tool_call.id` 或稳定索引聚合
- `function.arguments` 以字符串增量方式追加到 `rawArgumentsBuffer`
- 最终统一解析为 arguments map

### 特点

Chat Completions 的流式 tool call 通常比 Anthropic 更“规整”，更适合直接做字符串追加与最终解析。

## 3. OpenAI Responses

### 优先级

第三优先级接入。

### 解析策略

- 解析 function call arguments delta / done 相关事件；
- 按 provider 事件里的 call / item identity 聚合；
- 同样走统一 accumulator。

### 说明

Responses 也具备流式工具参数能力，但在本轮优先级中排第三，以降低同时改动三类协议的复杂度。

## 接口与类设计

### 保持 `BaseLLM` 顶层接口不变

`BaseLLM.planTurnDecision(...)` 暂不改签名。

原因：

- 上层并不需要中间流式语义；
- 第一版只需改善 planner 内部收敛与 timeout 行为；
- 不扩大公共接口演进面。

### `ConfigurableHttpLLM` 内部新增能力

建议新增：

- provider-style-specific streaming request path
- `_planTurnDecisionStreaming(...)`
- `_planTurnDecisionStreamingForStyle(...)`
- `StreamingDecisionAccumulator`

但这些都保持为 `ConfigurableHttpLLM` 内部能力，不向 `BaseLLM` 外溢。

### `ApiStreamParser` 的角色扩展

当前 parser 只产出文本 / reasoning 语义。

本轮建议扩展为可产出通用内部流块，但仍保持它是：

- 协议适配层工具
- 不直接返回最终 business decision

不建议让 parser 直接产出 `ModelTurnDecision`，否则会把协议解析与业务收敛强耦合。

## 超时策略配合

既然本轮引入 provider streaming，planner timeout 策略也要调整：

- 不再只依赖“整请求在固定时长内闭合”
- 引入“只要持续收到 chunk，就视为仍有进展”的语义
- 更适合改为：
  - overall timeout
  - idle timeout

即：

- overall timeout：整次 planner 请求的上限
- idle timeout：在一段时间内完全收不到任何 chunk 才判定卡死
- 当前实现将两者都封装在 `ConfigurableHttpLLM` 的流式 planner 尝试内部，不向上层暴露新的中间态事件

这与“内部流式收敛”是配套关系。

## 错误处理

### 流中解析错误

对单个 chunk 的局部解析异常：

- 记录日志；
- 尽量跳过局部异常并继续收流；
- 不因一个 chunk 异常直接终止整次 planner。

### 最终参数无法解析

如果流结束后某个 tool call 仍无法解析成完整 arguments：

- 视为 planner 响应无效；
- 返回既有 `planner_request_failed` 语义；
- 不尝试进入 tool execution。

### provider 中途断流

若 provider 在未形成有效 terminal assistant message、也未形成完整 tool call 时断流：

- 视为 planner failure；
- 记录 provider 侧已累计的元信息以便诊断。

## 架构边界

本设计明确把边界放在：

- `ConfigurableHttpLLM` / parser / accumulator：负责“如何从 provider 流里拼出完整 decision”
- `AgentPlannerService` 及以上：只关心“拿到的最终 decision 是什么”

也就是说：

- planner/tool call 的**生产边界**停留在 LLM 适配层内部；
- event / projection / UI 不被强制绑定到本轮 streaming 实现。

这和当前项目“尽量不要为特定工具把整条架构做成特例”的方向一致。

## 验证目标

本轮完成后应满足：

1. 三类 provider 至少按优先顺序逐步支持流式 planner 内部收敛；
2. 上层 `TurnHarness` / `AgentPlannerService` 行为契约不变；
3. 大参数 tool call 的 planner 超时率下降；
4. planner 请求在持续收到 tool 参数增量时，不会因为等待整包闭合而过早失败；
5. 不引入新的 UI / timeline / renderer 架构耦合。

## 分阶段落地顺序

1. 引入通用内部 chunk 模型与 `StreamingDecisionAccumulator`
2. 先接 `Anthropic Messages` 流式 planner 收敛
3. 再接 `OpenAI Chat Completions`
4. 最后接 `OpenAI Responses`
5. 最后把 planner timeout 从整请求超时调整为更适合 streaming 的策略

## 风险与权衡

### 风险 1：内部复杂度上升

`ConfigurableHttpLLM` 会从“整包请求 + 一次解析”升级为“流式请求 + 增量组装”。

权衡：

- 复杂度被限制在 LLM 适配层内部；
- 不扩散到 event / projection / UI，整体仍是低耦合增量改造。

### 风险 2：不同协议的 tool 参数增量形式差异很大

Anthropic、Chat Completions、Responses 的 tool streaming 事件外观不同。

权衡：

- 用统一 chunk 模型隔离协议差异；
- 用 accumulator 隔离“最终 decision 组装”与“协议解析”。

### 风险 3：中途不完整参数难以稳定解析

尤其是 Anthropic fine-grained tool streaming。

权衡：

- 采用“原始缓冲 + 最终解析”为主；
- 不要求每个中间态都能成为稳定 JSON。

## 已确认决策

- 第一版不让上层完整感知 planner 中途 streaming；
- 第一版不做 UI 中途展示；
- 第一版不做边生成参数边执行 tool；
- 第一版保持 `BaseLLM.planTurnDecision(...)` 接口不变；
- 适配顺序固定为：
  - `Anthropic Messages`
  - `OpenAI Chat Completions`
  - `OpenAI Responses`
