# 基于 ChatSendCoordinator 的 Headless 真实环境集成测试设计

## 背景

当前项目已经补齐了较多 provider 兼容性单测、adapter 契约测试、`TurnHarness` 模拟集成测试与真实 provider live contract 测试，但仍然存在一个明显空档：

- 纯单测与 provider live contract 能验证局部 payload / continuation 是否正确
- 端到端自动化测试能验证真实用户路径，但太重、太慢、太脆弱
- 缺少一层“无 UI、但保留真实发送链路”的真实环境集成测试

近期暴露出的多类问题说明，仅靠下层契约测试并不足以稳定前置发现问题：

1. Anthropic continuation 中当前 turn transcript 与 provider continuation 双重注入
2. Anthropic 同一 assistant message 多 `tool_use` 时，`tool_result` 没有聚合到紧随其后的同一条 user message
3. 不同 API style 在多轮 loop、ask-user resume、tool error resume、mixed assistant text + tool calls 场景下，问题往往只会在更接近真实链路时暴露

因此，需要新增一层以 `ChatSendCoordinator` 为主入口的 headless 真实环境集成测试，用真实 provider 调用与真实大部分工具链路，前置暴露高层发送编排、落库、projection 与 provider wire compatibility 的组合问题。

## 目标

本设计的目标是：

1. 新增一层以 `ChatSendCoordinator` 为主入口的 headless 真实环境集成测试
2. 保留真实 `ChatSendCoordinator -> TurnHarness -> AgentPlannerService -> SessionContextService -> repositories/SQLite` 链路
3. 使用真实 provider API 调用，而不是 fake provider 规则裁判
4. 尽量使用真实工具，只在必要时使用最少量可控替身
5. 以链路状态正确为主要断言目标，而不是以最终回答文本正确为主要目标
6. 让同一条 scenario case 能挂载多个 provider/style，避免 case 资产按 provider 碎裂
7. 形成“默认只跑被触及 style，CI/手动回归跑三类 style 固定全集”的运行策略

## 当前阶段备注

本设计已进入执行阶段，并已完成基础 live harness、真实发送链路、workspace fixture 与首个 `news_multi_tool` 实战探路。

当前新增的一条重要架构结论是：

- `providerResponseId` 与 `providerCallId` 已足够表达 provider 侧“批次 + 叶子调用”语义
- 但 Headless Live Integration 层继续推进前，需要先统一 Core / Projection / Assertion 对“批次语义”的理解

同时，首个真实 `news_multi_tool` 探路还确认了一条测试策略约束：

- 真实 provider live case 不应把模型决策形状写死为“同一 decision 内并发双 tool call”
- 当前更稳定、也更符合 live 测试职责的断言目标是：
  - 至少覆盖多次真实工具 continuation
  - 每次工具调用都能沿 `assistantToolCall -> step -> toolResult/toolError` 闭合
  - turn 最终能继续收敛到等待态或完成态

也就是说：

- “同批多 tool call” 适合作为 unit / simulated integration 中的确定性语义覆盖
- “真实 provider live case” 优先覆盖 provider-native continuation 标识链是否稳定贯通

因此，当前会在本设计之上插入一个受控子任务：

- 先补最小 `DecisionBatch` 领域模型设计
- 先不引入新表
- 先让后续 live assertions 与 workflow projection 以 batch 语义组织

这样做的目的不是扩大范围，而是避免继续在“step 是否代表整批调用”这个未收敛问题上重复返工。

## 非目标

本次不做以下事情：

1. 不引入 `StrictAnthropicFakeProvider`、`StrictOpenAIFakeProvider` 之类规则裁判层
2. 不把这层测试做成 Widget / UI E2E 自动化
3. 不要求最终 assistant 文本逐字稳定
4. 不追求所有工具都必须走真实外部副作用
5. 不把真实 provider 测试默认绑定到所有普通 `flutter test`
6. 不在本次直接重构 `ChatSendCoordinator`、`AgentEventProcessor`、`ChatBlockBuilder` 的职责边界

## 用户确认的关键约束

### 1. 主入口必须是 `ChatSendCoordinator`

本层测试不以 `TurnHarness` 为主入口，而以更贴近真实产品发送路径的：

- `ChatSendCoordinator.sendMessage()`
- `ChatSendCoordinator.confirmToolInvocation()`
- `ChatSendCoordinator.submitQuestionAnswers()`

作为主要入口。

原因是：

- 这层测试需要覆盖 turn 创建、发送事务、事件消费、落库、projection、等待态恢复等更完整链路
- 仅测 `TurnHarness` 无法覆盖上层应用编排壳的真实接线问题

### 2. 真实 provider API 调用优先

这层测试的核心价值在于：

- 不依赖我们手写的 Anthropic/OpenAI 协议理解去“假装校验”
- 而是让真实 provider 来暴露实际不兼容问题

因此：

- planner / continuation / resume 都必须经过真实 provider API
- 不使用 fake provider 代替真实 wire-level 验证

### 3. 真实 test DB

用户确认本层测试优先使用真实 test DB，而不是 mock repository。

这样能覆盖：

- `chat_turns`
- `chat_turn_steps`
- `chat_events`
- `messages`
- `session_context_snapshots`

的真实落库与读取路径。

### 4. 尽量减少可控替身

工具侧遵循“真实优先、最小替身”的原则：

- 优先通过构造测试工作目录、测试文件树、测试网页夹具，让 `Read`、`Write`、`Edit`、`LS`、`Grep`、`Glob`、`fetch_webpage` 等工具走真实链路
- 仅当工具副作用太强、外部依赖太重、不可重复、强绑定宿主环境时，才允许使用最少量可控替身

### 5. 断言以链路状态正确为核心

用户明确要求：

- 当前无需把“最终对话结果正确”作为核心目标
- 因为模型回答天然带有不可控性

因此本层测试主要断言：

- turn / step / event / message / continuation 的链路状态是否正确

而不是断言：

- 最终回答必须逐字等于某段文本

### 6. 运行策略

用户确认最终策略为：

- 默认开发阶段：只跑被触及 style
- CI 或手动回归：跑三类 style 的固定全集
- 同一 scenario case 必须支持挂载多 provider/style

## 总体设计

## 分层定位

新增测试层位于以下位置：

```mermaid
flowchart LR
    A["单元 / 契约测试"] --> B["Headless Live Integration"]
    B --> C["真实 UI E2E / 设备自动化"]
```

其中：

### 1. 单元 / 契约测试

继续负责：

- adapter payload 构造
- continuation item 组装
- context projector
- `TurnHarness` 局部 loop 语义

### 2. Headless Live Integration

本设计新增的主力测试层。

它负责：

- `ChatSendCoordinator` 主入口
- 真实 provider API
- 真实 test DB
- 真实大部分工具
- 无 UI 渲染依赖

它的目标是：

- 在比单测更接近真实用户路径的位置暴露协议兼容与链路状态问题
- 同时避免 E2E 的高脆弱性和高成本

### 3. UI E2E / 设备自动化

只保留少量：

- UI 展示
- 平台交互
- 滚动 / 焦点 / 输入栏 / 卡片操作

相关冒烟验证，不再承担主协议验证职责。

## 关键测试形态

每个测试用例都应遵循同一结构：

1. 构造独立 test DB
2. 构造独立测试工作目录 / 网页夹具 / 必要环境
3. 用真实 provider config 初始化发送链路
4. 从 `ChatSendCoordinator` 入口触发消息发送
5. 必要时驱动确认 / ask-user resume
6. 等待 turn 完成或进入等待态
7. 断言数据库中的 turn / step / event / message / snapshot 状态
8. 断言 provider wire compatibility 没有在真实调用中失败

## 测试对象边界

本层测试真实保留以下对象：

- `DefaultChatSendCoordinator`
- `TurnHarness`
- `AgentPlannerService`
- `SessionContextService`
- `AgentEventProcessor`
- `ChatTurnRepository`
- `ChatTurnStepRepository`
- `ChatEventRepository`
- `DatabaseHelper` / SQLite test DB
- `ConfigurableHttpLLM`

这意味着，本层测试主要验证的是：

- 应用发送编排壳
- Agent Loop Core
- Planner Input Assembly
- Persistence Adapter

在真实 provider 下的组合行为。

## 场景模型

本设计不按 provider 组织测试资产，而按 scenario case 组织。

### `ScenarioCase`

建议新增统一的场景模型，至少包含：

- `id`
- `title`
- `userMessage`
- `initialWorkspaceFixture`
- `availableTools`
- `followUpActions`
- `assertions`
- `providerTargets`

其中：

### 1. `initialWorkspaceFixture`

描述测试前需要准备的真实环境，例如：

- 文件目录结构
- 初始文件内容
- 网页 HTML / Markdown 夹具
- 本地配置

### 2. `followUpActions`

描述是否需要：

- tool confirmation
- ask-user resume
- 多轮追问
- 第二次 sendMessage

### 3. `assertions`

描述要断言的链路状态，而不是仅断言文本。

### 4. `providerTargets`

描述本 case 能挂载哪些 provider/style。

例如同一个 case 可以同时支持：

- `deepseek-anthropic`
- `minimax-anthropic`
- `beehears-responses`
- `minimax-openai-chat-completions`

这样：

- case 资产按用户真实场景沉淀
- provider 只是执行矩阵
- 新增 provider 时可以复用既有 case

## Provider Matrix

每个 scenario case 的 provider 目标分为两层：

### 1. 默认目标

用于本地开发快速验证，只跑被触及 style。

例如：

- 若本次改动触及 Anthropic continuation，只跑该 case 在 `anthropic messages` 下的 provider 目标

### 2. 回归全集目标

用于 CI 或手动回归，跑三类 style 固定全集：

- `anthropic messages`
- `responses`
- `chat completions`

同一 case 在回归全集中至少允许映射到：

- 一个 Anthropic-style provider
- 一个 Responses-style provider
- 一个 Chat Completions-style provider

必要时也可同 style 挂多个 provider，以发现 relay 差异。

## 工具策略

## 真实工具优先

以下工具优先通过测试夹具走真实链路：

- `Read`
- `Write`
- `Edit`
- `LS`
- `Grep`
- `Glob`
- `fetch_webpage`

建议方式：

- 在测试工作目录下构造真实文件树
- 对 `fetch_webpage` 使用本地静态网页夹具或测试 HTTP server
- 对 `Read/Write/Edit` 直接操作测试目录内文件

### 为什么必须真实优先

因为这些工具不仅影响最终结果，也会影响：

- tool args
- tool result payload
- transcript 内容
- planner continuation
- UI projection

如果过早替身，很多真实链路问题仍可能被掩盖。

## 最小替身原则

仅以下类型工具允许优先替身：

- 强副作用外部动作
- 宿主设备特定工具
- 难以稳定复现的系统级工具
- 会污染用户真实环境的数据写入工具

并且替身必须满足：

1. 数量尽量少
2. 只替换工具执行，不替换上层 loop
3. 输出结构必须与真实工具契约一致

## 断言策略

本层测试以链路状态正确为第一优先级。

## 主要断言对象

### 1. `chat_turns`

重点断言：

- `status`
- `iterationCount`
- `toolCallCount`
- `providerStyle`
- `providerStateJson`
- `errorMessage`

### 2. `chat_turn_steps`

重点断言：

- step 数量与顺序
- `providerResponseId`
- `providerCallId`
- `toolName`
- `status`
- `resultSummary`
- `errorCode`

尤其要覆盖：

- 同一 decision 多 tool call
- 同一 step 内多个 tool call identity 区分
- tool error / success mixed
- ask-user resume
- confirmation resume

### 3. `chat_events`

重点断言：

- 事件序列是否符合预期
- `assistantToolCall` / `toolResult` / `toolError` / `assistantQuestionPrompt` / `userInteractionResult` 是否对齐
- provider continuation 所需的关键 payload 是否完整

### 4. `messages`

本层不以最终回答逐字正确为主目标，但要断言：

- 消息投影是否完成
- waiting / confirmation / ask-user card 是否正确落为消息
- tool workflow 与 tool result 是否没有明显错位

### 5. provider wire compatibility

重点断言：

- 真实 provider 调用过程中没有因 wire-level 兼容问题直接报错
- 若失败，失败必须暴露为测试失败，而不是被吞掉

## 不作为主要断言的内容

以下内容不作为本层主要成功标准：

- 最终 assistant 回答逐字匹配
- 总结措辞一致
- 轻微表述差异

因为这类内容受模型非确定性影响较大。

## 第一批必须覆盖的场景

第一批 scenario case 建议聚焦高风险高收益链路。

### 场景 1：单轮搜索后继续总结

覆盖：

- `web_search`
- 单次 tool continuation
- assistant text + tool use mixed decision

### 场景 2：同一轮多个工具调用并继续

覆盖：

- 同一 assistant message 多 `tool_use`
- 多个 `tool_result` continuation
- 同一 step 内多 tool call identity

这是本次 Anthropic 400 的直接回归场景。

### 场景 3：工具成功与失败混合

覆盖：

- mixed `toolResult` / `toolError`
- provider continuation 中 success/failure 混合

### 场景 4：ask-user resume

覆盖：

- `assistantQuestionPrompt`
- `userInteractionResult`
- 第二轮 continuation

### 场景 5：真实文件工具链路

覆盖：

- `Read`
- `Write`
- `Edit`
- 基于测试目录的真实工具执行

### 场景 6：多轮历史上下文与 continuation 组合

覆盖：

- `SessionContextService`
- recent working set
- 当前 turn continuation
- 防止 transcript / continuation 双重注入

## 运行策略

## 本地默认运行

默认开发阶段：

- 只跑被触及 style 对应的 scenario 集

例如：

- 改 Anthropic continuation：先只跑 `anthropic messages`
- 改 Responses continuation：先只跑 `responses`

## CI / 手动回归运行

在以下场景，应跑三类 style 的固定全集：

- CI 中的高风险 job
- 准备合入前的手动回归
- 触及 agent loop / provider compatibility / context assembly 的重构批次

固定全集至少包含：

- `anthropic messages`
- `responses`
- `chat completions`

## 触发条件

以下改动默认视为需要运行本层测试：

- `ChatSendCoordinator`
- `TurnHarness`
- `AgentPlannerService`
- `SessionContextService`
- `SessionContextProjector`
- `ConfigurableHttpLLM`
- provider adapter / continuation builder
- ask-user / confirmation / waiting-state / projection 关键链路

普通纯 UI、文案、样式类改动不默认触发。

## 数据与日志支持

本层测试需要保留足够诊断信息，便于真实 provider 失败时快速定位：

- provider id
- style
- scenario id
- turn id
- step id
- providerResponseId
- providerCallId
- 请求失败时的 provider body 摘要

这里不要求测试断言所有日志字段，但要求日志链路能支撑定位。

详细日志规则继续统一以：

- `docs/architecture/logging.md`

为准，避免在本 spec 里重复定义完整字段。

## 与当前架构方向的关系

本设计符合当前项目既定边界：

1. `ChatSendCoordinator` 作为应用编排壳，不把 UI 带进测试
2. `TurnHarness` 继续是 loop 核心入口
3. provider/API 兼容问题继续留在 `Model Gateway / Provider Adapter`
4. 持久化继续用真实 repository / DB，而不是让 UI 消息表成为唯一真相
5. 通过 headless 集成测试加强前后端边界，而不是继续依赖 E2E 去兜底所有问题

## 方案对比

### 方案 A：`TurnHarness` 级真实 provider 测试

优点：

- 更轻
- 更聚焦 loop core

缺点：

- 覆盖不到 `ChatSendCoordinator` 上层真实编排链路
- 无法作为主要“用户发送流程”验证层

### 方案 B：`ChatSendCoordinator` 级 headless 真实 provider 测试

优点：

- 更贴近真实产品发送路径
- 能覆盖 turn 创建、事件消费、落库、projection、resume
- 与“真实用户场景 case”更对齐

缺点：

- 更重
- 定位面稍宽

本设计选择方案 B 作为主力层。

### 方案 C：继续只靠 live contract + E2E

优点：

- 不需要新增中间层测试

缺点：

- live contract 太低层，无法覆盖发送链路组合问题
- E2E 太重，定位慢，维护成本高

因此不采用。

## 实施建议

建议分阶段落地：

### 阶段 1：最小主链路框架

- 建立 `ChatSendCoordinator` headless test harness
- 接通真实 test DB
- 接通真实 provider config 读取
- 接通测试工作目录夹具

### 阶段 2：首批高风险 scenario

- 单 tool continuation
- 多 tool continuation
- ask-user resume
- mixed success/failure

### 阶段 3：provider matrix 与运行策略

- 默认只跑被触及 style
- 增加三类 style 固定全集入口
- 让同一 scenario 映射多个 provider

## 验收标准

本设计完成后，应满足：

1. 存在一层以 `ChatSendCoordinator` 为主入口的 headless 真实环境集成测试
2. 该层测试使用真实 test DB
3. 该层测试使用真实 provider API
4. 该层测试默认尽量使用真实工具
5. 至少一条 scenario case 能映射多个 provider/style
6. 至少覆盖单 tool、多 tool、ask-user、mixed success/failure 四类高风险场景
7. 默认运行与回归全集运行策略可分离
8. 新增 provider 或 style 时，可复用既有 scenario case，而不是复制一套测试资产
