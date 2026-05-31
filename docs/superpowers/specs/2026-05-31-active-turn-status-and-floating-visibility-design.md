# 统一主状态条与悬浮可见性设计

## 背景

当前应用在 agent loop 执行期间已经具备较多真实状态信号：

- `TurnHarness` / `AgentEventProcessor` 会持续产出 planner、tool、final answer 相关事件
- `chatTimelineProjectionProvider` 已能统一投影 tool workflow、tool result、ask-user-question、runtime preview
- `runtimeStreamingPreviewStateProvider` 已能表达流式输出中的 runtime-only 预览状态
- 页面级 `chatSendStateProvider` 也保留了 `phase` 与 `statusText`

但用户最终看到的“当前正在发生什么”仍然比较弱，主要存在两类问题：

1. 状态暴露粒度过粗  
   当前运行态提示基本依赖 `ChatSendPhase` 与少量文案兜底，难以稳定表达：
   - 正在请求模型
   - 正在规划下一步
   - 正在执行具体工具
   - 工具已返回，正在继续规划
   - 正在流式生成回复

2. 状态位置不稳定  
   当前运行态提示以 `LatestMessageRunningStatusTail` 的形式附着在最新消息末尾。  
   当最新 assistant 内容较长、状态条滚出视口，用户会失去对“系统仍在工作”的直观感知。

本设计的目标不是发明新的 agent loop 状态机，而是在保持现有 execution / transcript / projection 边界稳定的前提下，让 UI 拥有一条事件驱动、可扩展、且始终可见的统一主状态条。

## 目标

1. 继续保持“只有一个主状态条”的整体交互形态
2. 将主状态条的语义来源升级为事件驱动，而不是消息扫描驱动
3. 支持后续平滑扩充更细的 planner / tool / streaming 状态文案
4. 当内联状态条滚出视口时，在输入框上方显示同一份悬浮状态条
5. 当内联状态条重新可见时，悬浮状态条自动消失
6. 保持消息时间线与输入区之间只有一个纵向滚动拥有者
7. 不回流修改 `TurnHarness` 的主循环语义，不新增 UI 专属执行状态机

## 非目标

1. 本轮不引入多条并列状态栈
2. 本轮不新增 tool-specific 独立状态条样式体系
3. 本轮不改变 `ToolInvocationStatus`、`ToolExecutionStatus`、`ChatSendPhase` 的核心语义
4. 本轮不将悬浮状态条扩展成确认条、上下文条、debug 条的通用宿主
5. 本轮不做复杂吸附跟随动画或二级状态展开面板

## 现状分析

### 现有状态来源

当前与“运行中状态”直接相关的信号主要分布在三处：

1. `chatSendStateProvider`
   - 提供 `ChatSendPhase`
   - 提供瞬时 `statusText`
   - 更偏页面级发送事务状态

2. `chatTimelineProjectionProvider`
   - 提供 `toolPresentationEvents`
   - 提供 `pendingToolConfirmation`
   - 提供 `runtimeAssistantDraft` 与 `runtimePreviewState`
   - 更偏统一时间线投影事实

3. `messagesProvider`
   - 可反向扫描当前 turn 的 `toolInvocation` / `toolResult`
   - 但它是 transcript / timeline 数据，不应继续承担越来越复杂的主状态归纳职责

### 当前实现的问题本质

当前 `LatestMessageRunningStatusResolver` 通过：

- `messages`
- `sendPhase`
- `statusTextOverride`

来推导消息尾部的一条轻量文案。  
这种方式可以支持早期需求，但继续扩展会遇到三个问题：

1. 主状态语义依赖消息重扫，timeline 结构反过来影响状态解释
2. 同一状态的“内容来源”与“显示宿主”耦合在一起
3. 当需要新增更细的 planner / tool / streaming 文案时，逻辑容易散落到多个 widget 与 resolver 中

### 当前 UI 宿主结构

当前页面结构大致为：

- `ChatMessageList`
  - 渲染时间线
  - 为最新 item 附着 `LatestMessageRunningStatusTail`
- `ToolConfirmationBottomBar`
  - 渲染等待确认的底部条
- `ChatInput`
  - 渲染输入停靠区

这说明“运行状态条”当前默认属于 timeline，而不是一个可独立协调的页面级能力。

## 设计原则

### 1. 一个状态源，两个显示宿主

任意时刻只允许存在一份统一的主状态语义。  
时间线尾部与输入框上方悬浮条只是它的两个显示宿主，不允许分别推断状态。

### 2. 事件归纳优先，页面状态兜底

主状态条应优先基于：

- tool presentation events
- pending confirmation
- runtime streaming preview
- assistant runtime draft

进行归纳。  
`ChatSendPhase` 只作为兜底阶段信号，而不是未来扩展 richer status 的主数据源。

### 3. 状态语义与可见性切换解耦

需要严格分层：

- `ActiveTurnStatusPresentation` 负责“显示什么”
- 可见性协调器负责“显示在哪里”

二者不可混合，否则后续状态扩展与宿主切换会互相污染。

### 4. 不新增第二套 loop 状态机

本轮不在 `TurnHarness`、controller、widget 中额外引入一套“专门给状态条服务”的执行状态机。  
主状态条只能消费现有正式事件与统一投影。

### 5. UI 只消费最终结果，不反向定义执行语义

widget 层只渲染统一状态模型。  
tool-specific 文案、planner/streaming 兜底文案、状态优先级都集中在 resolver / projection 层。

## 方案总览

推荐新增两类局部能力：

1. 统一主状态投影模型
2. 页面级可见性协调器

```text
正式 transcript / runtime preview / send phase
    ↓
ChatTimelineProjection
    ↓
ActiveTurnStatusResolver
    ↓
ActiveTurnStatusPresentation
    ↓
可见性协调器
    ↓
时间线内联状态条 或 输入框上方悬浮状态条
```

其中：

- timeline 内联条仍然是默认宿主
- 输入框上方悬浮条只在内联锚点不可见时接管显示

## 详细设计

### 一、统一主状态模型

新增统一 UI 投影对象：`ActiveTurnStatusPresentation`。

它只表达“当前最应该告诉用户的一条主状态”，不携带 widget 布局实现细节。

建议字段如下：

- `phase`
  - 统一主状态阶段，例如：
    - `planning`
    - `awaitingConfirmation`
    - `executingTool`
    - `streamingResponse`
- `text`
  - 当前主状态文案
- `turnId`
  - 当前状态所属 turn 标识
- `sourceMessageId`
  - 当前状态锚点对应的源 message id
- `toolName`
  - 若当前阶段由 tool 驱动，则记录 tool 名
- `sourceKind`
  - 当前状态来源，例如：
    - confirmation
    - toolEvent
    - runtimePreview
    - sendPhaseFallback
- `allowFloating`
  - 是否允许悬浮显示

该模型不负责判断状态条显示在时间线还是输入框顶部，也不负责决定动画或容器样式。

### 二、事件驱动主状态归纳器

新增 `ActiveTurnStatusResolver`。  
输入建议为：

- `ChatTimelineProjection projection`
- `ChatSendState sendState`

输出为：

- `ActiveTurnStatusPresentation?`

其职责是从现有正式事实中归纳唯一主状态，而不是重扫全部 message 文本。

#### 1. 阶段优先级

推荐使用如下优先级：

1. `awaitingConfirmation`
2. `executingTool`
3. `streamingResponse`
4. `planning`
5. 无状态

原因如下：

- confirmation 是最强的用户等待节点，优先级最高
- tool 正在运行时，用户最关心“系统正在做哪件外部动作”
- streaming response 说明系统已经进入输出阶段
- planning 是工具前后都可能出现的“短暂思考阶段”，信息价值弱于明确的可观察外部动作

#### 2. 文案解析规则

在阶段判定完成后，再解析主文案。

##### `awaitingConfirmation`

优先来源：

1. confirmation invocation 的 `summary`
2. tool display name 派生的保守文案
3. 兜底：`等待工具确认`

##### `executingTool`

优先来源：

1. 当前最新未闭合 running tool event 对应的集中映射文案
2. 若只有 tool name，则走通用 tool 文案映射
3. 兜底：`正在执行工具`

首批建议保留并集中化如下映射：

- `web_search` -> `正在联网搜索`
- `fetch_webpage` -> `正在读取网页`
- `Read` -> `正在读取文件`
- `LS` -> `正在列出目录`
- `Grep` -> `正在搜索文件内容`
- `Glob` -> `正在查找文件`

该映射应从旧的 `LatestMessageRunningStatusResolver` 迁移到新的统一 resolver 中，避免 widget 层继续持有 tool-specific if/else。

##### `streamingResponse`

本轮默认保守文案为：

- `正在生成回复`

后续若 `runtimePreviewState` 能稳定区分：

- 仍在组织回答
- 已开始输出正文

则可以平滑扩展更细文案，但扩展应继续发生在 resolver 层。

##### `planning`

推荐区分两种场景：

1. 若前一步刚结束 tool result，则文案为：
   - `正在规划下一步`
2. 否则文案为：
   - `正在请求模型`
   - 或 `正在思考`

这可以让“工具已返回，但最终回答还没开始”这一阶段拥有更真实的用户反馈。

#### 3. 兜底策略

当事件层信息不足时，才允许使用 `ChatSendPhase` 兜底：

- `preparing` -> `正在请求模型` / `正在规划下一步`
- `awaitingConfirmation` -> `等待工具确认`
- `executingTool` -> `正在执行工具`
- `streamingResponse` -> `正在生成回复`

这样可以保持当前体验下限，但不让页面状态再次成为 richer status 的主入口。

### 三、统一状态条 UI 组件

当前 `LatestMessageRunningStatusTail` 只适用于消息尾部。  
本轮建议将其抽象为可复用的统一组件，例如 `UnifiedTurnStatusBar`。

职责：

- 渲染统一主状态条样式
- 消费 `ActiveTurnStatusPresentation`
- 支持：
  - 内联渲染
  - 悬浮渲染

要求：

1. 视觉样式保持当前低噪声、冷静、轻量的状态提示气质
2. 不额外引入第二套 tool-specific 状态条样式体系
3. 文案与状态点效果复用现有 running surface 能力即可

这样后续要改状态条样式时只改一处，不会出现：

- timeline 尾巴一套
- composer 上方悬浮条一套

的双份维护。

### 四、双宿主显示与可见性切换

#### 1. 默认宿主仍为时间线尾部

只要当前状态锚点仍在视口中，主状态条继续以内联方式显示在最新状态承载 item 下方。  
这能保持当前阅读节奏，不打断已有时间线使用习惯。

#### 2. 输入框上方作为悬浮宿主

当内联状态锚点滚出视口时，在 `ChatInput` 上方显示同一份主状态条。  
一旦原锚点重新可见，悬浮条自动消失。

#### 3. 切换只处理可见性，不改状态内容

必须保持如下规则：

- `ActiveTurnStatusPresentation` 只决定显示什么
- 可见性协调器只决定显示在哪里

不允许悬浮宿主与内联宿主分别各自推断主文案。

### 五、状态锚点与页面级可见性协调

新增页面级可见性协调器，例如 `ActiveTurnStatusVisibilityCoordinator`。

它需要解决两个问题：

1. 当前主状态对应哪个 timeline item
2. 该 item 当前是否在可视区内

建议它消费：

- `ActiveTurnStatusPresentation`
- scroll controller / viewport 信息
- 当前时间线 item 的稳定 key 或 source message id

输出可以是轻量布尔或枚举，例如：

- `inlineOnly`
- `floatingOnly`
- `hidden`

#### 1. 锚点选择

主状态模型需要携带足够稳定的锚点信息，优先使用：

- `sourceMessageId`
- `turnId`

来定位当前真正承载该状态的 timeline item，避免退回“最后一条消息”这种弱推断。

#### 2. 抖动控制

为避免状态条在视口边缘来回闪烁，建议可见性协调器具备轻微滞回策略：

- 不要在刚碰到边界时立即切换宿主
- 可以要求锚点明确离开视口后再显示悬浮条
- 锚点明确回到安全可见区后再撤销悬浮条

本轮只需做轻量滞回，不需要引入复杂动画系统。

### 六、与现有 provider / projection 的关系

#### 1. 可复用部分

本轮建议直接复用：

- `AgentEventProcessor`
- `chatTimelineProjectionProvider`
- `runtimeStreamingPreviewStateProvider`
- `activePendingToolConfirmationProvider`

原因：

- 这些能力已经代表当前正式的 UI 投影边界
- 它们足以支持事件驱动主状态条，不需要新增第二套事实通道

#### 2. 建议新增的 provider / service

建议新增：

- `activeTurnStatusResolverProvider`
- `activeTurnStatusPresentationProvider`
- 页面级可见性 provider / coordinator

其中：

- presentation provider 只关心当前主状态内容
- visibility provider 只关心当前宿主策略

#### 3. 对旧 resolver 的处理

`LatestMessageRunningStatusResolver` 不应继续作为长期主入口。  
建议将其职责迁移为：

- 删除
- 或降级为兼容壳，并内部转读新的 `ActiveTurnStatusPresentation`

推荐优先选择“迁移后替换”，避免继续存在两套语义入口。

### 七、页面集成方式

#### `ChatMessageList`

职责调整建议：

- 不再独立归纳运行态文案
- 改为消费统一主状态 presentation
- 在匹配到当前状态锚点的 timeline item 时附着内联状态条

#### `ChatPage`

职责新增建议：

- 作为跨 timeline 与 composer 的页面级协调宿主
- 在 `ChatInput` 之上、`ToolConfirmationBottomBar` 之下或相邻位置承接悬浮状态条
- 统一读取状态内容与宿主可见性策略

#### `ChatInput`

本轮不应自行推断运行态语义。  
它只作为悬浮状态条的邻近宿主区域，不承担状态解释职责。

## 失败模式与约束

### 1. 状态源打架

错误表现：

- timeline 尾部与悬浮条同时显示不同文案

约束：

- 只允许 `ActiveTurnStatusPresentation` 产出唯一主状态

### 2. 状态滞留

错误表现：

- turn 已结束，但状态条未消失

约束：

- 清空路径必须与正式 turn 完成 / idle 回落保持一致

### 3. 可见性抖动

错误表现：

- 滚动至边缘时内联与悬浮频繁来回切换

约束：

- 可见性协调器需具备轻微滞回

### 4. 锚点错位

错误表现：

- 当前活跃状态绑定到了错误的 timeline item

约束：

- 主状态模型必须携带稳定锚点信息

### 5. 扩展时逻辑回流到 widget

错误表现：

- 后续新增 richer status 时，又在 `ChatPage` / `ChatMessageList` / `ChatInput` 分别添加 if/else

约束：

- 文案、优先级、tool 映射都集中在 resolver / projection 层

## 测试策略

### 单元测试

覆盖 `ActiveTurnStatusResolver`：

- confirmation 优先于 executingTool
- executingTool 优先于 streamingResponse
- streamingResponse 优先于 planning
- tool result 后回到 planning
- final answer 完成后清空主状态
- tool-specific 文案映射与兜底文案正确

### Provider / Projection 测试

覆盖状态投影与切换：

- 基于真实 event / projection 变化，主状态能稳定推进
- `runtimePreviewState` 与 tool events 不会互相覆盖出错
- send phase 只在事件不足时作为兜底

### Widget 测试

覆盖双宿主显示规则：

- 锚点可见时仅显示内联状态条
- 锚点不可见时仅显示悬浮状态条
- turn 结束后两边都消失
- 长消息场景下悬浮条会正确接管

### 轻量集成测试

建议覆盖一条真实状态推进链路：

- `user message`
- `toolExecutionStarted`
- `toolResult`
- `assistantTextDelta`
- `finalAnswer`

验证主状态条随事件顺序自然推进，且宿主切换不改变状态语义。

## 方案选择结论

本轮推荐采用：

- 统一主状态投影模型
- 事件驱动主状态归纳器
- 双宿主显示
- 页面级可见性协调

而不采用：

- 继续基于消息扫描扩展旧 tail resolver
- 直接让 composer 独占状态语义与推导逻辑
- 新增第二套 UI 专属执行状态机

其主要原因是：

1. 最符合当前仓库“统一投影 + 页面消费”的架构方向
2. 能在不破坏 agent loop 主边界的前提下增强状态真实性
3. 后续扩 richer status 时，只需扩 resolver 规则，而不是重写多个 widget 的局部猜测逻辑
4. 能自然解决“长消息把状态顶出屏幕”的核心可见性问题

## 实施建议

建议后续 implementation plan 分为四步：

1. 建立 `ActiveTurnStatusPresentation` 与 resolver
2. 将旧 `LatestMessageRunningStatusResolver` 迁移到统一状态模型
3. 抽取 `UnifiedTurnStatusBar` 并接入时间线内联显示
4. 增加页面级可见性协调与输入框上方悬浮显示

这样可以先稳定状态语义，再处理宿主切换，降低回归风险。
