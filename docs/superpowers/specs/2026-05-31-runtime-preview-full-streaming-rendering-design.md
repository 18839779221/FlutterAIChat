# runtime preview 接管整体流式渲染设计

## 背景

当前仓库已经具备统一的流式 preview 基础设施：

- provider streaming 已统一适配为 `StreamingMessageEvent`
- `TurnProjectionDispatcher` 已负责 preview 与 truth 的串行提交
- `RuntimeStreamingPreviewState` 已作为 runtime-only preview read model 存在
- `ChatTimelineProjectionService` 已成为 UI 的唯一汇聚层

但这条链路目前只在少数消费面真正落地，最明显的是 artifact runtime preview。

普通 assistant 回复正文的运行中显示，仍主要依赖另一条旧路径：

- `AgentEventProcessor` 在收到 `assistantTextDelta` 时创建 generating message
- `AssistantStreamOutputBuffer` 负责把累计文本刷新回 `messagesProvider`
- `StreamingResponseBlock` 依赖 `sourceMessage.status == generating` 来渲染运行中正文

结果是：

1. preview pipeline 与正文流式显示没有真正统一
2. `text / thinking / tool_use / artifact` 运行中语义分散在不同状态来源里
3. 如果 provider 有真实 streaming，但 truth-side 没有持续产出 `assistantTextDelta`，正文仍可能表现为整段一起出现
4. `runtimeStreamingPreviewState` 已经是统一 preview 管道，却没有真正成为“整体流式渲染”的主状态

## 目标

本次设计的目标是让 `runtime preview` 接管整体运行中回复的 UI 流式显示。

具体目标：

1. 运行中 assistant 回复的唯一显示源切换为 `runtimeStreamingPreviewState`
2. `text / thinking / tool_use / artifact` 全部通过统一 preview block 语义进入 timeline projection
3. `finalAnswer` 只负责最终 truth 提交与 takeover，不再承担“让正文看起来流起来”的职责
4. `ChatTimelineProjectionService` 继续作为唯一 UI 汇聚层
5. 不让 widget 层直接理解 provider delta，也不恢复第二套正文 streaming 协议

## 非目标

本次不做以下事情：

1. 不改写 `TurnHarness` 主循环为 mid-stream 驱动
2. 不把 preview 中间态持久化进 `chat_events`、`chat_turn_steps` 或数据库消息
3. 不让 `StreamingMessageEvent` 与 `ChatEvent` 合并为同一种事件
4. 不为普通正文重新建立独立于 preview pipeline 的 `assistantTextDelta` 新主链路
5. 不让 UI 直接订阅 provider 原始 SSE / SDK event

## 现状判断

### 1. 统一 preview 管线已经存在

当前已经存在一条正确方向的旁路线：

- provider runtime / adapter 产出 `StreamingMessageEvent`
- `TurnProjectionDispatcher` 串行提交 preview 与 truth 更新
- `RuntimeStreamingPreviewProjector` 维护 `RuntimeStreamingPreviewState`
- `ChatTimelineProjectionService` 汇聚 truth state 与 runtime preview state

这条线证明架构基础已经到位，不需要重新定义第三套 streaming 状态。

### 2. 普通正文还没有真正接入这条线

当前 `runtimeStreamingPreviewState` 虽然能承载 `text / thinking / tool_use` block，但 `ChatTimelineProjectionService` 主要只把它投影为 runtime artifact block。

普通正文运行中显示仍依赖：

- `messagesProvider` 中的 generating message
- `runtimeAssistantDraftProvider` 中的部分推理草稿

这导致：

- preview state 对正文不是真正的主状态
- artifact 走 preview，新正文走 generating message
- thinking 一部分走 runtime preview，一部分走 runtime draft

### 3. 当前最大问题不是“有没有流”，而是“谁拥有运行中显示真相”

如果运行中显示同时依赖：

- `runtimeStreamingPreviewState`
- `runtimeAssistantDraftProvider`
- `messagesProvider` 中的 generating message

那么即使 provider streaming 真实存在，UI 仍可能出现：

- 某些 block 连续增长
- 某些 block 只在 final 时一次性出现
- preview 与 final takeover 行为不一致

因此本次核心不是“补更多刷新”，而是收敛运行中显示的唯一状态来源。

## 方案判断

本次推荐方案是：

- 让 `runtimeStreamingPreviewState` 成为整体运行中 assistant 输出的主状态
- 让 `ChatTimelineProjectionService` 负责把 preview 中的通用 block 映射为统一 `AssistantTurnBlock`
- 让 `finalAnswer` 到来时仅做 preview 清理与正式 truth 接管

这意味着：

1. 运行中正文不再以 generating message 为主
2. preview 不再只是 artifact 的附属能力
3. 普通正文、thinking、tool_use、artifact 都通过同一套 projection 进入时间线

## 方案对比

### 方案 A：继续补齐 `assistantTextDelta` truth-side 正文流式链

做法：

- 保留当前正文 streaming 依赖 generating message
- 继续把 provider streaming 或累积结果翻译为 `assistantTextDelta`
- 让现有 `StreamingResponseBlock` 持续吃到 truth-side 正文增量

优点：

- 对现有正文 widget 改动较小
- 可以复用 `AssistantStreamOutputBuffer`

缺点：

- 运行中正文仍不走统一 preview 管线
- 会继续维护 preview 与 truth-side streaming 两套并行显示语义
- `text / thinking / tool_use / artifact` 无法真正统一到同一套 runtime streaming 设计

### 方案 B：让 `runtime preview` 直接接管整体运行中显示

做法：

- `runtimeStreamingPreviewState` 成为运行中 assistant 输出的主状态
- `ChatTimelineProjectionService` 新增通用 preview block projector
- `ChatTimelineRow` 继续只消费统一 projection
- `finalAnswer` 仅做最终 truth takeover

优点：

- 最符合现有 streaming preview pipeline 文档方向
- `text / thinking / tool_use / artifact` 统一到一套 runtime block 语义
- 减少正文显示对 generating message 的依赖
- 最有利于后续扩展其他 tool 的渐进渲染

缺点：

- 需要补通用 preview block 到 timeline block 的映射
- 需要重新定义 `runtimeAssistantDraftProvider` 的职责边界

### 推荐

推荐方案 B。

原因：

1. 当前仓库已经有统一 preview pipeline，继续扩写 truth-side streaming 会让双轨继续存在
2. 让 runtime preview 直接接管运行中显示，最能兑现“统一投影汇聚层”的架构目标
3. 这条方案能自然覆盖正文、thinking、tool_use 与 artifact，不会把 artifact 继续做成唯一真正受益者

## 总体设计

### 一、运行中 assistant 输出的唯一显示源

运行中 assistant 输出统一由 `runtimeStreamingPreviewState` 提供。

这里的“运行中 assistant 输出”包括：

1. 正文 text block
2. thinking block
3. tool_use block
4. 由 tool_use 推导出的 artifact runtime preview

这意味着在 assistant 仍处于 streaming 阶段时，UI 不再依赖普通正文 generating message 来决定“该显示什么内容”。

### 二、统一 preview block 投影层

`ChatTimelineProjectionService` 需要新增一层通用 preview block projector。

它的职责是：

1. 读取 `RuntimeStreamingPreviewState`
2. 把 preview message 内的 ordered block 映射为统一 `AssistantTurnBlock`
3. 与 persisted truth blocks、runtime draft blocks 一起合并成最终 timeline projection

这层 projector 不能只特判 artifact。

它至少要支持：

1. `text` -> 运行中 `finalResponse` block
2. `thinking` -> 运行中 `analysis` block
3. `tool_use` -> 运行中 `toolWorkflow` 或对应的局部可视化 block
4. `tool_use(create_artifact)` -> 运行中 `artifact` block

### 三、final takeover 语义保持集中

`finalAnswer` 到来时，流程仍由统一提交管道负责：

1. 标记 preview message 进入 finalized 生命周期
2. 清理该 message 对应的 runtime preview
3. 提交正式 truth message
4. 丢弃该 message 的晚到 preview event

`finalAnswer` 不需要再负责“补流式体验”，只负责最终 truth 接管。

### 四、widget 层继续只消费统一 projection

`ChatTimelineRow`、`ChatMessageList` 等 timeline widget 继续只消费 `ChatTimelineProjectionService` 的产物。

它们不应该：

1. 直接理解 provider delta
2. 直接读取 `RuntimeStreamingPreviewState` 并自行拼接
3. 针对某个 provider 或某个 tool 增加第二套 streaming 解释逻辑

## 状态边界调整

### 1. `runtimeStreamingPreviewState`

新的定位：

- 运行中 assistant 输出的主状态

它承担：

1. 所有 provider preview block 的当前值
2. block 生命周期
3. 运行中正文、thinking、tool_use、artifact 的统一 runtime 输入

它不承担：

1. transcript truth
2. 持久化恢复
3. turn loop 语义

### 2. `runtimeAssistantDraftProvider`

新的定位应缩窄。

建议仅保留以下用途：

1. preview pipeline 尚未覆盖的极短生命周期草稿
2. 少量 truth-side 运行时提示，而不是普通正文主显示

它不应继续与 `runtimeStreamingPreviewState` 并行承担通用正文 streaming 显示职责。

否则会再次出现：

- preview text 和 draft text 同时存在
- preview thinking 和 draft reasoning 同时存在

### 3. `messagesProvider`

新的定位保持为正式 truth message 容器。

它继续承载：

1. 已完成的正式 assistant message
2. 工具卡片 truth
3. interaction truth

普通正文运行中显示不再要求依赖 generating message 才能出现。

## 投影规则

### 1. text block

preview 中的 text block 应被投影为运行中 `finalResponse` block。

要求：

1. 与最终正式 `finalResponse` block 使用相同的文档渲染风格
2. 运行中版本只在 projection 层标记其为 runtime preview，不要求 widget 自己猜状态来源
3. 当 final truth 到来后，运行中 block 被正式 block takeover

### 2. thinking block

preview 中的 thinking block 应被投影为运行中 `analysis` block。

要求：

1. 与最终 reasoning/analysis 展示风格保持一致
2. 运行中时按 preview block 累积增长
3. 如果最终正式消息不持久化这段 thinking，则它只存在于 runtime 阶段并在 final takeover 时消失

### 3. tool_use block

preview 中的 tool_use block 应被投影为运行中 `toolWorkflow` block，或被工具专用 renderer 读取为更具体的可视化形态。

要求：

1. tool workflow 仍然通过统一 timeline projection 进入 UI
2. provider 参数累积细节停留在 preview block 与 renderer 之间
3. 不为 artifact 单独保留第二套 provider streaming 协议

### 4. artifact block

`tool_use(create_artifact)` 仍然可以投影为 artifact runtime preview。

但新的语义是：

- artifact 是通用 tool_use preview 的一个专门 renderer
- 它不再是 runtime preview 唯一真正落地到 UI 的 block 类型

## 合并与顺序

`ChatTimelineProjectionService` 在合并 block 时，需要继续保持统一顺序规则：

1. 同一 turn 内，运行中 artifact/tool workflow/finalResponse 的顺序稳定
2. preview block 与 persisted truth block 不能双重显示同一语义
3. final truth 到来后，preview block 不应短暂回流

对于正文类 block，新的关键要求是：

- runtime preview text block 进入同一 turn 的合并顺序
- final truth block 到来后，由统一提交管道和 projection merge 共同完成 takeover

## 与现有模块的改造边界

### 需要调整的模块

1. `ChatTimelineProjectionService`
   - 增加通用 preview block projector
   - 不再只消费 runtime artifact preview

2. `ChatTimelineRow`
   - 继续消费统一 projection
   - 运行中正文、thinking、tool workflow 都能从 preview projection 正常渲染

3. `AgentEventProcessor`
   - 普通正文 streaming 不再以 generating message 为必要前提
   - 避免与 preview 主状态形成重复显示

4. `runtimeAssistantDraftProvider` 相关逻辑
   - 缩窄其职责，避免和 preview 同时承担正文/推理 streaming 显示

### 不需要调整的模块

1. `TurnHarness` 主循环语义
2. provider stream adapter 的统一事件出口
3. `TurnProjectionDispatcher` 作为 preview/final 串行仲裁点的定位
4. DB schema 与 transcript truth

## 观测与验证要求

为了确认“整体流式渲染”真正成立，需要补充最小观测能力。

至少需要能区分以下四层：

1. provider chunk 是否持续到达
2. `StreamingMessageEvent` 是否持续发布到 preview state
3. `ChatTimelineProjectionService` 是否把 preview block 持续投成 runtime timeline block
4. timeline widget 是否按 projection 持续重绘并在 final 时完成 takeover

没有这层观测，就很难区分问题到底出在：

- provider 没流
- preview state 没接到
- projection 没投出来
- UI 没刷出来

## 架构约束

后续实现必须继续遵守以下约束：

1. 运行中 assistant 输出只保留一个主显示状态来源
2. `runtimeStreamingPreviewState` 成为整体 streaming UI 的主状态后，不再为普通正文重新建立平行 truth-side streaming 架构
3. `ChatTimelineProjectionService` 继续是唯一 UI 汇聚层
4. widget 层不直接解释 provider delta
5. artifact 不是 streaming 架构例外，只是通用 tool_use preview 的高价值消费方
6. final takeover 顺序继续由统一提交管道保证，而不是由 widget 层猜测

## 总结

本次设计的核心不是“把 artifact preview 做得更好”，而是把现有 preview pipeline 真正推广为整体运行中 assistant 回复的统一显示架构。

最终目标可以概括为：

1. `runtimeStreamingPreviewState` 接管整体运行中回复显示
2. `ChatTimelineProjectionService` 负责把 preview `text / thinking / tool_use / artifact` 统一投到 timeline block
3. `finalAnswer` 仅承担最终 truth takeover，而不再承担“补流式观感”职责
4. UI 继续只消费统一 projection，不直接感知 provider streaming 细节

这样才能真正做到：

- provider 有真实 streaming 时，整条 assistant 回复都能连续进入 UI
- preview 与 final 不再是“artifact 一条线、正文另一条线”
- 整体流式渲染建立在统一架构，而不是局部补丁之上
