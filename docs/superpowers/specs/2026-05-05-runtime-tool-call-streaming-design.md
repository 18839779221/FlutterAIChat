# Runtime Tool Call Streaming 设计

## 背景

当前项目的 planner/tool use 已经具备 provider 侧的流式能力：

- `ConfigurableHttpLLM` 会在 planner 阶段发起 streaming 请求
- `ApiStreamParser` 会把 provider 响应解析为 `StreamingPlannerChunk`
- `StreamingDecisionAccumulator` 会持续消费：
  - `contentDelta`
  - `reasoningDelta`
  - `toolCallStarted`
  - `toolCallArgumentsDelta`
  - `toolCallCompleted`

但这条流式能力当前只存在于 LLM adapter 内部。上层只会在 streaming 结束后拿到一个最终完整的 `ModelTurnDecision`，因此：

1. assistant 正文可以通过既有事件链路流式显示
2. tool call 参数虽然底层已增量到达，但上层完全看不到
3. `create_artifact` 只能在完整 `source` 组装结束后一次性渲染

这导致 artifact 的等待体感较重，用户无法看到“artifact 正在长出来”的过程。

## 目标

本次设计目标如下：

1. 允许 planner/tool call 的流式参数增量向上层暴露
2. 保持这是一种通用能力，而不是 `create_artifact` 专属协议
3. 首个消费方仅为 `create_artifact`
4. `create_artifact` 自己解析 tool call input，不要求框架理解 `source`
5. 不污染 `TurnHarness` 的 agent loop 主语义
6. 不把未完成增量写入 transcript 真相层或持久化层
7. 尽量参考 Claude Visualizer 的流式友好约束，优化 artifact 生成顺序与体验

## 非目标

本轮明确不做以下事情：

1. 不把流式 tool call 增量持久化到 `chat_events` / `chat_turn_steps`
2. 不把 `TurnHarness` 改造成依赖 planner mid-stream delta 的主循环
3. 不要求所有工具都消费增量 tool call
4. 不要求 framework 解析工具私有字段，例如 `create_artifact.source`
5. 不为中间态无效 HTML 制定大量硬编码修复规则
6. 不改变最终 `ModelTurnDecision` 仍然是 planner 完整输出这一事实

## 核心判断

### 1. 现有问题不在 tool 协议，而在流式边界被封闭

`create_artifact` 当前不是没有流式输入来源，而是：

- provider 已在流式输出 tool call 参数
- `StreamingDecisionAccumulator` 已在持续拼接原始参数文本
- 但这些增量在 adapter 内部被收敛为最终 `ModelTurnDecision`
- 上层直到 tool call 完整闭合后才首次看到它

因此本次设计的关键不是重新发明一套 artifact 专属协议，而是把“已有的底层流式 tool call 参数”以受控方式暴露给上层。

### 2. Agent Loop 不应理解 tool call 增量细节

`TurnHarness` 的职责是：

- 驱动单轮 planner/tool loop
- 处理 confirmation / interaction resume
- 管理完成态 tool execution 与 stop condition

它不应承担“tool call 参数当前累积到哪里了”这类运行中细节，否则会把 loop core 和具体输出形态耦合。

因此：

- Agent Loop 仍然只关心最终完整 `ModelTurnDecision`
- tool call 的 streaming 增量不应成为 loop stop condition 或 loop semantic state 的一部分

### 3. 上层识别依据应是流类型，而不是工具字段语义

当前 `runtimeAssistantDraft` 并不是“所有流式内容的通用容器”，它只承接：

- assistant reasoning 流
- assistant response 流前的临时展示

其消费分流依据来自上层事件类型，而不是底层自动猜测语义。

同理，tool call 增量上浮后，上层也不应该靠分析某段 JSON 文本来猜“这是 tool 还是 answer”，而应该依赖一层明确的运行时流类型标识。

## 设计原则

### 1. 底层保持通用，只上浮原始增量文本

框架只负责提供通用 tool call 流式事实：

- call identity
- tool name
- raw arguments text delta / snapshot
- phase

框架不负责：

- 解析 `create_artifact.source`
- 解析特定工具私有字段
- 定义工具专属中间态语义

### 2. 运行时增量只属于 runtime read model

流式 tool call 增量属于 runtime-only 数据：

- 可以丢失
- 不要求重启恢复
- 不进入 transcript 真相层
- 不参与 session context 投影

它的职责只有一个：支持当前运行中的 UI 渐进展示。

### 3. `create_artifact` 是首个消费方，但能力保持通用

本轮只有 `create_artifact` 使用这条能力。

但架构表达必须保持为：

- “通用 tool call 参数流”
- 而不是 “create_artifact 流”

未来如果其他工具也需要消费 tool call 增量，应复用同一能力，而不是复制新链路。

## 方案选择

### 方案 A：通过 TurnHarness 正式上浮 planner mid-stream delta

不采用。

原因：

1. 会把 agent loop 主状态和 tool call 渐进细节耦合
2. 让 `TurnHarness` 关心“tool call 正在形成中”的语义
3. 不符合本项目对 loop boundary 的长期约束

### 方案 B：runtime-only 流式投影源

本轮采用。

做法：

1. 在 LLM streaming 组装层继续消费 `StreamingPlannerChunk`
2. 在最终 `ModelTurnDecision` 之外，额外产出 runtime-only 的流式投影数据
3. 上层根据“流类型”进行分流与展示
4. `TurnHarness` 仍然只消费最终 decision

优点：

1. 保持 Agent Loop 简洁
2. 不污染 transcript truth
3. 可以首发服务 `create_artifact`
4. 仍保留未来扩展到其他工具的通用性

### 方案 C：把 tool call 增量持久化成 chat events

不采用。

原因：

1. 会把未完成中间态混入 append-only transcript 真相层
2. 恢复、回放、上下文投影边界会变复杂
3. 当前需求只要求降低体感等待时间，不要求持久化中间态

## 运行时流模型

### 通用 runtime stream entry

本轮不新增独立 `RuntimeToolCallFeed` 顶层概念，也不直接复用 `RuntimeAssistantDraft`。

而是建议引入一个更底层、通用的 runtime stream entry 模型，由上层根据 `kind` 分流。

建议字段：

- `turnId`
- `entryId`
- `kind`
  - `assistant_text`
  - `reasoning`
  - `tool_call_arguments`
- `providerCallId`
- `toolName`
- `createdAt`
- `updatedAt`
- `text`
  - 对于 `assistant_text` / `reasoning` 是文本内容
  - 对于 `tool_call_arguments` 是当前累计的 raw arguments text
- `payload`
  - 保留轻量 runtime 元信息

### 为什么不直接扩展 RuntimeAssistantDraft

`RuntimeAssistantDraft` 当前语义过窄：

- 它代表 assistant/reasoning 的临时块
- 其字段命名、blockType、消费位置都偏向 assistant 文本

如果强行扩展到 tool call，会出现：

1. assistant 语义污染
2. timeline projection 难以从类型上区分“这是一段 assistant 草稿”还是“这是一段 tool 参数 buffer”
3. `create_artifact` renderer 需要在 assistant draft 上倒推工具语义，边界混乱

因此更合理的方式是：

- 保留 `RuntimeAssistantDraft` 作为现有兼容层
- 新 runtime stream entry 作为更底层通用模型
- projection 层再把不同 `kind` 映射到具体 UI block

## 上层识别与消费方式

### 1. 识别依据是 kind，而不是工具字段

上层不需要知道 `source`、`title` 等具体字段才进行分流。

它只需要知道：

- 这是 `assistant_text`
- 这是 `reasoning`
- 这是 `tool_call_arguments`

之后：

- assistant/reasoning 走现有文本 draft 投影逻辑
- tool_call_arguments 走工具运行态投影逻辑

### 2. create_artifact 自己解析 raw arguments text

`create_artifact` 是 tool call input 的拥有者，因此它自己负责：

1. 维护当前 raw input buffer 的消费逻辑
2. 尝试从 buffer 中提取可用 `source`
3. 根据当前提取结果生成渐进式预览

框架不负责：

- JSON 局部修补
- `source` 字段提取
- 对 HTML 做工具专属规则化修复

### 3. 中间态容错依赖渲染器自身与刷新节流

对于无效 HTML 或未闭合片段：

- 不用框架层写大量规则硬修
- 优先依赖 HTML/WebView 渲染器的容错行为
- 通过合理的刷新节流，避免过高频率的重载和抖动

## create_artifact 的渐进渲染策略

### 1. 基本流程

当 runtime stream 中出现 `tool_call_arguments` entry 且 `toolName == create_artifact` 时：

1. `create_artifact` 的专属 renderer 读取当前 raw arguments text
2. 尝试从中提取当前可用 `source`
3. 若提取成功，则刷新当前 artifact 预览
4. 若提取失败，则保留上一次成功预览或等待下一次增量
5. tool call 完成后，再由既有 completed tool/result 路径接管正式语义

### 2. 渲染频率控制

需要显式控制刷新节奏，避免每个字符都触发重渲染。

建议原则：

1. 允许增量刷新
2. 但通过节流/合并降低刷新频率
3. 优先在可见内容明显增长时刷新，而不是机械逐 token 刷新

本轮不在 spec 中锁死具体毫秒数，实现阶段按设备表现与 WebView 成本调优。

### 3. 生成侧约束

prompt 需要吸收流式友好规则，尽量让 artifact 更适合渐进渲染。

建议新增约束：

1. 优先先输出 `<style>`
2. 可见内容优先于 `<script>`
3. 将交互逻辑尽量放在末尾
4. 避免大段阻塞渲染的同步脚本
5. 避免依赖隐藏后再 JS 展开的主内容结构
6. 优先竖向堆叠、可提前看到的布局
7. 对 SVG 结构优先从上到下、从定义到可见内容输出

这些约束的目的不是要求模型完全模拟浏览器传输层，而是提高“source 前缀本身即可形成可见预览”的概率。

## 与现有架构的关系

### 1. 对 TurnHarness 的要求

`TurnHarness` 维持现状：

- 仍只消费最终完整 `ModelTurnDecision`
- 不新增 planner mid-stream loop 状态语义
- 不因为 `create_artifact` 引入 loop 级特判

### 2. 对 transcript / context 的要求

runtime tool call 增量：

- 不落盘
- 不进入 `chat_events`
- 不进入 session context
- 不参与模型下轮可见上下文

completed tool call / tool result：

- 仍按现有正式链路落盘
- 仍是唯一 transcript truth

### 3. 对 UI projection 的要求

projection 层需要同时处理两类输入：

1. persisted transcript facts
2. runtime-only stream entries

但不得因此形成第二套独立消息状态机。

理想边界是：

- persisted facts 决定历史与完成态
- runtime entries 决定当前临时展示
- 两者在 projection 层合成一份统一 timeline snapshot

## 风险与取舍

### 1. runtime-only 中间态不可恢复

这是刻意接受的取舍。

如果 app 重启或 group 切换导致当前流式中间态丢失：

- 不视为数据错误
- 因为最终真相仍由 completed tool/result 落盘保证

### 2. 中间态 HTML 可能阶段性不可渲染

这是渐进渲染天然现象。

应对原则：

- 尽力刷新
- 节流更新
- 保留最近一次有效预览
- 依赖 renderer 容错，不写大量工具专属规则补丁

### 3. prompt 约束不能替代架构能力

即使 prompt 明确要求 style-first / script-last，如果上层拿不到 tool call delta，仍然不会出现真正的渐进式渲染。

因此 prompt 约束是增强项，不是根因修复。

## 验收标准

本轮完成后，应满足以下验收标准：

1. planner streaming 中的 tool call arguments delta 能以 runtime-only 形式上浮给上层
2. `TurnHarness` 主循环语义不因该能力发生复杂化
3. `create_artifact` 能在 tool call 完整结束前开始显示渐进预览
4. 渐进预览支持频率控制，避免高频抖动
5. completed tool/result 仍沿用现有正式 transcript truth
6. prompt 已加入流式友好 artifact 生成约束
7. 新能力在架构表达上是“通用 tool call 参数流”，而不是“artifact 专属私链路”

## 后续实现建议

后续 implementation plan 应重点覆盖以下方面：

1. streaming LLM 层如何同时产出最终 decision 与 runtime stream entries
2. runtime stream entry 的 provider / state 挂载位置
3. projection 层如何合并 persisted facts 与 runtime entries
4. `create_artifact` renderer 如何解析 raw arguments text 并做节流刷新
5. prompt 文案如何吸收流式友好约束
6. 如何为 runtime-only 行为补充 focused tests，而不误导为持久化语义
