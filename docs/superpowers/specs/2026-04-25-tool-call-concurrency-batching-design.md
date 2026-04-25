# Tool Call 并发批次调度设计

## 背景

当前 `TurnHarness` 在消费一次 planner decision 中的多个 tool call 时，仍然采用严格串行执行：

- 按 `decision.toolCalls` 顺序逐个调用 `_executePlannedToolCall()`
- 前一个 tool call 完成后，后一个才开始

这会导致两个明显问题：

1. 连续的只读工具调用被无谓串行化，尤其是 `Read`、`LS`、`Grep`、`Glob`、`web_search`、`fetch_webpage` 这类上下文收集工具会明显拖慢整轮 turn
2. planner 已经具备一次产出多个 tool call 的能力，但 runtime 没有兑现“并行可用”的执行语义，导致 `parallel_tool_calls` 的收益几乎被抵消

结合当前产品方向，我们希望把“哪些工具可并行”作为 tool 自身能力的一部分，而不是由 planner prompt 或临时规则去补丁式控制。

## 目标

1. 为一次 decision 中的多个 tool call 引入批次化调度模型
2. 将连续的只读、并发安全工具自动聚合为一个并发 batch
3. 将写工具或非并发安全工具单独成批，并保持串行
4. 为并发 batch 提供最大并发度上限，避免无限制同时执行
5. 保持 turn transcript、step ledger、UI 消息流与现有生命周期兼容
6. 保持工具失败语义独立，单个只读工具失败不影响同批其他工具继续执行

## 非目标

1. 本轮不实现跨 decision 的并发执行
2. 本轮不改变 planner 输出格式，只改 runtime 调度
3. 本轮不引入新的全局任务调度器或复杂线程池抽象
4. 本轮不做写工具的并发执行
5. 本轮不做基于工具名的硬编码并发白名单；并发能力由 tool 元数据表达

## 用户确认的关键语义

### 1. 批次切分规则

tool call 列表按原始顺序扫描：

- 连续的 `isConcurrencySafe == true` 工具合并成一个并发 batch
- `isConcurrencySafe == false` 的工具单独成批
- batch 之间始终串行执行

例如：

`Read A, Read B, Write C, Read D, Read E`

会被调度为：

1. `Read A, Read B`
2. `Write C`
3. `Read D, Read E`

### 2. 批内失败独立

同一并发 batch 中：

- 单个工具失败不会取消同批其他工具
- 单个工具失败不会改变其他同批工具的启动、执行与结果回收
- 每个工具仍然独立写入自己的 step 状态、tool result 或 tool error

也就是说，批内是“共享调度，不共享成败”。

### 3. 最大并发度

并发 batch 需要一个最大并发度上限。

当前默认值定为：

- `maxConcurrentToolCalls = 10`

当某个并发 batch 中任务数超过 10 时：

- 先启动最多 10 个任务
- 有任务完成后再补下一个
- 直到该批次全部执行结束

这是一种有限并发、排队补位的执行模型，而不是一次性把整批任务全部打出去。

## 设计原则

### 1. 并发能力属于工具元数据

runtime 不应该靠工具名猜测“这个工具是否可并行”。

推荐由 `ToolDefinition` 或可等价承载的 runtime metadata 提供：

- `isConcurrencySafe`

这样：

- 工具自身声明是否支持并发
- 调度层只消费结构化能力，不维护业务 if/else

### 2. batch 之间必须保序

尽管批内可以并发，batch 之间仍需保持严格顺序。

这样可以保证：

- 写工具前后的语义边界稳定
- turn transcript 仍然能反映用户可理解的执行顺序
- planner 在下一轮看到的上下文不会被未来批次“穿越式”污染

### 3. 并发执行不等于乱序展示

并发 batch 内部允许真实完成顺序不同，但产品层不应让 timeline 因完成时序而剧烈抖动。

本轮推荐：

- step ledger 继续按原始 planner 顺序编号
- UI / transcript 的 tool lifecycle 事件仍按“每个 tool 自己的真实生命周期”追加
- 但在需要聚合展示或回看某一批结果时，应优先基于原始 tool call 顺序组织

本轮不强行重排底层事件顺序，但要避免在上层语义里把批内完成先后错误地解释为 planner 意图顺序。

### 4. 执行器按 decision 边界抽离

本轮不建议把并发逻辑继续直接堆进 `TurnHarness`。

更合适的边界是：

- `TurnHarness` 继续负责 turn loop 主控
- 新增一个 decision 级 tool call 执行器，专门处理“这一轮 planner 产出的 tool requests 如何执行”

这样可以把：

1. tool call 切 batch
2. 并发安全 batch 的有限并发执行
3. 本轮 step / event / tool result / tool error 的回收

集中到一个独立协作者中，而不是继续扩张 `TurnHarness`。

但本轮也不需要新建重型全局 scheduler service，更不建议把 turn 生命周期裁决权从 `TurnHarness` 搬走。

## 方案总览

推荐引入一个 decision 级执行器，例如：

- `DecisionToolCallExecutor`

由它接收一次 decision 中的 `toolCalls`，把当前执行方式从：

- “`TurnHarness` 直接一个个串行执行”

改成：

- “`TurnHarness` 将这一轮 tool requests 交给执行器处理，执行器先切成批，再逐批执行”

其中执行器内部批类型分两种：

1. `concurrent-safe batch`
2. `serial batch`

执行策略如下：

### 串行批

- 只包含一个 `isConcurrencySafe == false` 工具
- 仍复用当前 `_executePlannedToolCall()` 路径

### 并发批

- 包含一组连续的 `isConcurrencySafe == true` 工具
- 每个工具仍独立建 step、发 tool call 事件、执行 tool、落 result/error
- 批内用最大并发度 10 的有限并发池调度
- 整个批次完成后，再决定是否进入下一批

## 详细设计

### 一、职责边界

#### 1. `TurnHarness`

`TurnHarness` 继续保留以下职责：

- 调用 planner 获取 `ModelTurnDecision`
- 判断这一轮是 tool decision、terminal answer 还是等待型交互
- 将 tool decision 交给 decision 级执行器
- 在这一轮执行结束后，根据执行结果决定：
  - 是否继续下一轮 planner
  - 是否停在 confirmation / user interaction
  - 是否结束 turn

也就是说，`TurnHarness` 仍然掌握 turn 级状态机与 stop/continue 的最终裁决权。

#### 2. `DecisionToolCallExecutor`

新增 decision 级执行器，负责这一轮 planner 返回的 tool requests：

- 接收 `toolCalls`
- 按 `isConcurrencySafe` 切 batch
- 执行串行批与并发批
- 为本轮工具调用创建和回收 step
- 发出本轮工具相关 event
- 汇总本轮执行结果

它不负责：

- 再次调用 planner
- 直接决定 turn completed / failed / cancelled
- 直接推进到下一轮 turn loop

#### 3. 执行结果摘要

decision 级执行器应返回一份结构化摘要，供 `TurnHarness` 判断这一轮后的控制流。

例如摘要中可包含：

- 本轮已执行多少个 tool
- 是否出现 `awaitingToolConfirmation`
- 是否出现 `awaitingUserInteraction`
- 是否存在失败 step
- 是否已有 turn 终态
- 本轮 step 结果列表或等价摘要

这样 `TurnHarness` 不需要知道批内调度细节，只消费“这一轮执行完后发生了什么”。

### 二、Tool 元数据

需要为工具增加并发安全声明：

- `isConcurrencySafe: true/false`

语义约束：

- `true` 表示此工具执行不依赖同一 turn 中其他工具对外部状态的修改，且并发执行不会引入不可接受的行为冲突
- `false` 表示此工具需要保守串行

默认值建议：

- 默认 `false`

这样新增工具不会被误判为可并行。

### 三、批次模型

执行器内部可引入轻量批次数据结构，例如：

- `ToolExecutionBatch`
  - `toolCalls`
  - `isConcurrent`

切分规则：

1. 从头扫描 `decision.toolCalls`
2. 遇到 `isConcurrencySafe == true`：
   - 持续吸收后续连续的 `true`
   - 组成一个并发 batch
3. 遇到 `false`：
   - 单独生成一个串行 batch

### 四、批次执行

#### 1. 并发批执行

并发批需要支持有限并发：

- `maxConcurrentToolCalls = 10`

执行模型：

1. 为批内所有 tool call 先建立与原顺序一致的 step 记录
2. 启动最多 10 个执行任务
3. 某任务结束后，继续补位启动下一项
4. 所有任务结束后，批次结束

批内每个任务的执行单元仍然是“单个 tool call 的完整生命周期”，包括：

- `assistantToolCall`
- `toolExecutionStarted`
- `toolResult` / `toolError`
- step running/completed/failed 更新
- turn toolCallCount 更新

#### 2. 串行批执行

串行批不新增特殊逻辑：

- 直接走现有单任务执行路径

### 五、失败与继续规则

#### 1. 批内

并发批内每个工具独立成败：

- 某个工具失败，不取消其他任务
- 某个工具失败，不阻止排队中的其他并发安全任务继续启动

#### 2. 批后

一个批次全部结束后，再统一检查 turn 状态：

- 如果 turn 已经进入 `awaitingToolConfirmation`
- 或 `awaitingUserInteraction`
- 或 `failed`
- 或 `completed`
- 或 `cancelled`

则停止后续批次。

否则继续执行下一批。

这意味着：

- 批内失败不联动
- 批后是否继续，仍由现有 turn-level 终止语义决定

### 六、计数与限制

当前 `AgentLoopLimits` 默认已放开为“不限制”，但显式限制仍需兼容。

并发执行后需要确保：

1. `toolCallCount` 依然按每个已结束 tool 独立累计
2. 显式 `maxToolCallsPerTurn` 生效时，以真实已完成的 tool 次数为准
3. `maxConsecutiveFailures` 只在仍显式启用时生效，并按“决策轮中的连续失败语义”重新审视

这里有一个额外注意点：

当前串行实现中的 `consecutiveFailures` 是沿调用顺序传播的。
并发后，同批任务不存在天然线性顺序，因此本轮不应把“批内多个失败”机械等价为更大的连续失败数。

推荐本轮做法：

- 批内失败仍独立记录
- `maxConsecutiveFailures` 只在 batch 边界上判断是否继续下一批
- 若显式启用且当前批无成功项、且失败累计达到阈值，则 turn 失败

如果本轮不想同时重构这一语义，也可以先保持：

- 并发批不参与 `consecutiveFailures` 递增传播
- 仅保留显式 `maxIterations` / `maxToolCallsPerTurn` / `maxDuration` 约束

本轮推荐后一种，先避免把历史上的“连续失败”概念强行套进并发模型。

### 七、日志与可观测性

需要新增可追踪的批次日志：

- batch 切分结果
- 当前 batch 类型（并发/串行）
- batch 大小
- 并发池当前活跃数
- 批次结束后的成功/失败统计

这样后续如果用户再次反馈“看起来很慢”或“为什么没有继续”，可以直接从日志定位：

- 是否被切成了很多串行批
- 是否并发度打满
- 是否某批结束后触发了 turn 终止

## 影响范围

核心影响文件预计包括：

- `lib/models/tool/tool_definition.dart`
- `lib/services/turn_harness.dart`
- `lib/services/decision_tool_call_executor.dart`
- `test/services/turn_harness_test.dart`
- `test/services/decision_tool_call_executor_test.dart`

可能需要联动检查：

- tool registry / tool handler 定义处对 `ToolDefinition` 的构造
- step repository 与 event repository 的时序假设
- provider-native continuation item 的 step 顺序依赖

## 风险

### 1. step / event 时序更复杂

并发后，事件追加不再天然线性，容易暴露此前默认“顺序即语义”的测试假设。

### 2. 执行器与 `TurnHarness` 责任漂移

如果执行器顺手接管了 turn stop/continue 的最终裁决，会很快演变成另一个 `TurnHarness`。

因此本轮必须守住边界：

- 执行器只负责“执行这一轮 tool requests”
- `TurnHarness` 负责“这一轮之后 turn 怎么走”

### 3. 同批中混入用户交互型工具

理论上 `AskUserQuestion` 这类等待型工具不应被标记为并发安全。
否则会出现一批中同时包含多个等待态分支，turn 语义会变得混乱。

因此本轮需要明确：

- 用户交互型工具一律 `isConcurrencySafe == false`

### 4. 并发 fetch/search 带来外部压力

`web_search` / `fetch_webpage` 并发后会明显增加同时进行的网络请求数。

因此并发上限必须内建，不能依赖外层“希望模型不要一次调太多”。

## 验收标准

1. 连续只读工具会被自动合并为并发 batch
2. 写工具和用户交互工具保持单独串行批
3. 并发 batch 内最大活跃执行数不超过 10
4. 批内单个工具失败不会影响其他工具继续执行
5. 批次结束后 turn 仍能正确进入下一轮 planner、确认态、交互态或失败态
6. 原有单工具执行与串行写工具执行路径行为不回归
7. 测试能覆盖：
   - batch 切分
   - 并发上限
   - 批内单个失败独立
   - 写工具隔离
   - 批后终止判断
