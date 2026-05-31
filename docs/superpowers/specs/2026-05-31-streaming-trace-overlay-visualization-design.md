# 流式时间线悬浮可视化设计

## 背景

当前回复链路已经逐步收敛为：

- provider runtime / adapter 产出 `StreamingMessageEvent`
- `RuntimeStreamingPreviewProjector` 消费事件并维护 `RuntimeStreamingPreviewState`
- `ChatTimelineProjectionService` 将 runtime preview 与 truth state 统一投影到 timeline
- `StreamingResponseBlock` / timeline row 负责最终运行中可见渲染

但原始埋点列表仍然过于底层，用户很难一眼判断“这轮回复到底把时间花在哪了”。当前更需要的是一条直接贴近用户体感的 turn 级时间线：

1. 从用户发送消息开始，整条回复总共花了多久
2. 等待模型开始动作花了多久
3. 每个具体工具调用分别花了多久
4. 工具之间的等待 / 规划阶段花了多久
5. final answer 流式显示花了多久，以及当前已经显示到哪

现有 `DebugTurnInspector` 适合离线排障与完整明细查看，但不够贴近真实聊天现场。
因此需要在聊天页本身提供一个默认不打扰主内容、只在需要时唤起的轻量流式时间线可视化能力。

## 目标

1. 在聊天页运行现场可视化展示一次 turn 的用户视角时间线
2. 默认不影响正常聊天内容 UI，不新增常驻调试入口
3. 回复完成后仍可回看刚才这一轮的 timeline
4. 支持快速判断当前卡在哪个阶段，以及当前节点具体在做什么
5. 保持现有 provider / projection / widget 主链路不被调试 UI 反向污染
6. 后续可扩展到 `DebugTurnInspector` 的完整明细，但第一版不依赖它

## 非目标

1. 本轮不做重型图表、火焰图或独立调试页面
2. 本轮不新增设置页开关
3. 本轮不引入新的正式业务状态机
4. 本轮不让调试浮层常驻页面
5. 本轮不把所有临时日志直接暴露给用户

## 交互方案

### 方案选择

本轮采用用户确认的新方案：

- 入口绑定到顶部 `DebugTurnInspectorButton`
- 普通点击继续打开 `DebugTurnInspector`
- 长按同一个顶部 debug 按钮时，显示 / 隐藏 timeline overlay
- overlay 展示的是“当前 turn”的 timeline，而不是单次 provider stream 的原始事件
- 回复结束后，只要当前 turn 的 trace snapshot 仍在，就仍可回看

### 交互语义

交互必须满足以下约束：

1. 默认不显示任何新的常驻调试入口
2. 顶部 debug 按钮点击行为不变
3. 长按顶部 debug 按钮一次：
   - 若浮层关闭，则打开当前 turn 的 timeline overlay
4. 再次长按同一个 debug 按钮：
   - 若浮层已打开，则关闭 overlay
5. 当前 trace snapshot 被清空时：
   - 浮层自动关闭
6. 只要 trace snapshot 仍存在，即使回复已完成，也允许回看

## 可视化形态

### 总体形态

采用聊天页上的轻量悬浮面板：

- 不占据消息列表正常布局高度
- 不改动 timeline item 排布
- 以底部上浮的小型面板显示
- 面板尺寸克制，优先展示关键诊断信息

推荐形态：

- 位置：输入区上方、聊天内容下缘附近
- 宽度：与当前聊天内容主列协调，但不强制满宽
- 高度：默认中低高度，避免遮住大段正文
- 视觉：弱对比、偏调试态，不抢主内容注意力

### 信息层级

第一版展示两层信息。

#### 1. 顶部诊断摘要

用于一句话回答“当前这轮花了多久、卡在哪、在做什么”。

建议展示：

- 当前 turn 总耗时
  - 例如：`本轮已耗时 8.4s`
- 当前阶段结论
  - 例如：`当前处于：调用 fetch_webpage`
- 当前节点说明
  - 例如：`正在生成：今天的主要变化是...`

#### 2. 下方聚合阶段时间线

按当前 turn 的用户视角阶段展示：

1. `等待模型响应`
2. `调用 <toolName>`
3. `步骤间等待`
4. `回复生成中`

展示规则：

- 每个 tool 单独成段，不合并
- 每段按真实耗时比例拉伸，长耗时阶段一眼更显著
- 节点主标题只写用户视角状态
- 节点副文本补当前具体在做什么，用于和主 UI 对上

例如：

- `等待模型响应 1.2s`
  - `等待模型开始下一步`
- `调用 web_search 1.8s`
  - `正在调用 web_search`
- `回复生成中 3.1s`
  - `正在生成：今天的主要变化是...`

## 数据模型设计

### 设计原则

这条可视化时间线不应直接绑定临时自由文本日志，而应有独立的轻量读模型。

也就是说：

- 日志仍然用于 file log 排障
- 浮层 UI 消费结构化 trace projection
- projection 来源于正式观测节点，而不是 widget 自己拼字符串

### 建议模型

建议新增以下读模型：

#### `StreamingTraceSnapshot`

表示当前活跃 turn 的 runtime-only 观测快照。

建议字段：

- `traceId`
- `turnId`
- `status`
  - `idle`
  - `running`
  - `completed`
  - `aborted`
- `currentStage`
- `summaryText`
- `startedAt`
- `firstVisibleAt`
- `takeoverAt`
- `entries`

注意：

- `traceId` 必须稳定绑定到整个 turn，而不是单次 planner iteration
- 同一 turn 内多个工具步骤与 final answer 流式阶段都要落到同一份 snapshot 中

#### `StreamingTraceEntry`

表示时间线中的一个节点。

建议字段：

- `eventId`
- `traceId`
- `stage`
- `timestamp`
- `elapsedMsFromStart`
- `status`
  - `reached`
  - `pending`
- `title`
- `details`

其中 `details` 需要支持：

- `toolName`
- `previewText`
- 其他必要的轻量上下文字段

#### `StreamingTurnTimeline`

表示从 `StreamingTraceSnapshot` 聚合出来的用户视角时间线。

建议字段：

- `traceId`
- `turnId`
- `status`
- `totalElapsedMs`
- `currentStatusTitle`
- `currentStatusDetail`
- `segments`

#### `StreamingTurnTimelineSegment`

表示一个用户视角阶段段落。

建议字段：

- `id`
- `type`
- `title`
- `detail`
- `startedAt`
- `endedAt`
- `durationMs`
- `isOngoing`

#### `StreamingTraceStage`

建议首批固定枚举：

- `streamEventReceived`
- `previewEventConsumed`
- `previewStateCommitted`
- `timelineProjectionBuilt`
- `uiFirstVisible`
- `uiUpdated`
- `finalTakeover`

## 采集边界

### 一、provider / runtime 层

目的：确认上游是否真的在持续产出增量。

采集节点：

- `stream.event_received`

建议挂点：

- `ConfigurableHttpLLM`
- runtime stream adapter 与统一事件分发入口附近

记录内容：

- `traceId`
- `messageId`
- `contentBlockId`
- `blockType`
- `deltaType`
- `valueLength`

### 二、preview projector / provider state 层

目的：区分“上游已到”与“UI state 已提交”。

采集节点：

- `preview.event_consumed`
- `preview.state_committed`

说明：

- `preview.event_consumed` 表示 projector 已消费该 event
- `preview.state_committed` 表示节流后的 preview state 已真正提交给上层 state

这里明确不使用 `flush` 作为正式阶段名。
因为 `flush` 更像当前实现细节，不适合作为长期架构语义。

### 三、projection 层

目的：确认 timeline projection 是否及时把 preview state 变成可渲染 block。

采集节点：

- `timeline_projection_built`

建议挂点：

- `ChatTimelineProjectionService.build(...)`

记录内容：

- `assistantBlockCount`
- `runtimePreviewBlockCount`
- `finalMergedBlockTypes`

### 四、UI 可见层

目的：回答“用户到底什么时候第一次看到了流式内容”。

采集节点：

- `ui.first_visible`
- `ui.updated`

建议挂点：

- `StreamingResponseBlock`
- 必要时在 `ChatTimelineRow` 边界补锚点

其中：

- `ui.first_visible` 只记录第一次出现非空运行中可见正文
- `ui.updated` 表示后续可见内容增量更新

### 五、最终 takeover 层

目的：识别中间态是否被最终回答快速覆盖。

采集节点：

- `final.takeover`

建议挂点：

- `TurnProjectionDispatcher.dispatchTruthEvent(...)`
- `finalAnswer` 清理 runtime preview 的统一路径

## 页面宿主设计

### 入口宿主

入口直接挂在：

- `LatestMessageRunningStatusTail`

原因：

1. 它已经是当前“系统正在运行”的最小可见提示
2. 只有它存在时才允许长按唤起，符合“默认不打扰”的目标
3. 不需要额外按钮或设置开关

### 浮层宿主

建议新增一个页面级轻量 overlay 宿主，而不是把大量逻辑写回状态条 widget 本身。

分层建议：

- `LatestMessageRunningStatusTail`
  - 负责长按事件与打开/关闭意图
- 页面级 overlay coordinator
  - 负责显示 / 隐藏浮层
- `StreamingTraceOverlayCard`
  - 负责渲染摘要与时间线内容

这样可以避免把状态条本身膨胀成复杂调试控件。

## 显示与关闭规则

### 打开规则

满足以下条件时，长按状态条可以打开：

1. 当前存在运行中状态条
2. 当前存在活跃 `StreamingTraceSnapshot`
3. 浮层当前处于关闭状态

### 关闭规则

满足以下条件时，再次长按同一状态条关闭：

1. 当前浮层已打开
2. 当前长按对应的是同一个活跃状态条锚点

### 自动关闭规则

以下情况必须自动关闭：

1. 当前运行中状态条消失
2. 当前活跃 turn 结束
3. 页面切换 group
4. 当前 trace 进入 completed / aborted 且状态条已不再存在

### 明确不采用的关闭方式

第一版明确不使用以下关闭方式作为主交互：

- 点空白关闭
- 下滑关闭
- 单独关闭按钮
- 设置页开关

## 为什么不直接复用 DebugTurnInspector

### 方案 A：只扩展 `DebugTurnInspector`

优点：

- 现有调试基础设施可复用

缺点：

- 离真实聊天现场太远
- 需要额外打开调试面板
- 不适合快速确认“刚刚那次回复为什么体感像秒出”

因此不作为第一版主入口。

### 方案 B：聊天页轻量浮层 + 后续可接入 DebugTurnInspector

优点：

- 现场感强
- 默认零打扰
- 后续仍可把同一份 trace projection 接到 `DebugTurnInspector`

因此采用方案 B。

## 风险与对策

### 风险 1：浮层本身干扰主内容阅读

对策：

- 只在长按后出现
- 面板尺寸克制
- 不改变消息列表布局

### 风险 2：节点太多，用户看不懂

对策：

- 第一版只展示少量固定节点
- 顶部先给“当前卡在哪”的总结
- 详细字段保持克制

### 风险 3：把实现细节误当成稳定架构语义

对策：

- 不使用 `flush` 作为正式节点名
- 使用更稳定的分层语义：
  - event received
  - event consumed
  - state committed
  - projection built
  - first visible
  - takeover

### 风险 4：调试采集反向影响正常渲染性能

对策：

- 只采集少量关键节点
- 用独立轻量 projection 聚合
- 不在 widget 层做高频复杂统计

## 实施建议

建议按以下顺序推进：

1. 先建立结构化 `StreamingTraceSnapshot` / `StreamingTraceEntry`
2. 在 provider -> preview -> projection -> UI -> takeover 各层补关键采集点
3. 做页面级 overlay coordinator
4. 给 `LatestMessageRunningStatusTail` 增加长按打开/再次长按关闭交互
5. 最后再考虑是否把同一份 trace projection 接到 `DebugTurnInspector`

## 验收标准

满足以下条件可认为第一版完成：

1. 当前存在运行中状态条时，长按可打开流式时间线浮层
2. 浮层不通过点空白关闭，而是再次长按同一状态条关闭
3. 默认聊天页面无新增常驻调试入口
4. 浮层能实时显示关键流式时间线节点
5. 能通过浮层直接看出当前卡在哪个阶段
6. 运行结束后浮层自动收口，不残留无主调试 UI
