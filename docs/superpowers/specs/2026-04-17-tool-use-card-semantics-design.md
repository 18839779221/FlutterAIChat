# Tool Use Card Semantics Design

## 背景

当前仓库已经具备一套基础可用的 tool use 展示链路：

- `ChatBlockBuilder` 会把 assistant turn 投影成 `toolWorkflow`、`toolResultSummary`、`structuredOutput` 等 block
- [lib/widgets/chat_blocks/tool_workflow_card.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/widgets/chat_blocks/tool_workflow_card.dart) 已支持步骤折叠、当前步骤展开和确认按钮
- [lib/widgets/chat_blocks/tool_result_summary_row.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/widgets/chat_blocks/tool_result_summary_row.dart) 已支持轻量结果摘要
- [lib/widgets/interaction/ask_user_question_card.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/widgets/interaction/ask_user_question_card.dart) 已支持消息内交互问答

但当前 UI 仍有两个结构性问题：

1. 现有卡片主要按技术事件类型渲染，而不是按用户感知语义渲染。
2. 所有 tool 步骤的视觉权重过于接近，导致“上下文采集步骤”和“真正影响用户世界的动作结果”没有被正确区分。

这会直接带来体验问题：

- `web_search`、`fetch_webpage`、`Read` 这类中间取材动作占用高度偏大，打断阅读
- `create_reminder`、`create_calendar_event` 这类阶段产出没有足够明确的完成回执
- `AskUserQuestion` 仍更像默认表单卡，而不是 agent workflow 中正式的交互节点

本设计的目标不是简单重画现有卡片，而是建立一套按语义分型的 tool use UI 协议。

## 目标

1. 以“用户感知强度”而不是“底层消息类型”作为卡片形态的第一分层依据
2. 采用 `流程聚焦` 作为主视觉骨架，但避免让所有 tool step 都变成高占用大卡片
3. 让上下文采集类工具默认低占用、低干扰，并在完成后自动折叠
4. 让外部动作类工具在完成后给出明确、可靠、可读的结果卡片
5. 让确认、执行中、完成、失败、交互提问共享统一语言，但保留不同强调等级
6. 为后续 block builder 和 widget 重构提供稳定的 presentation variant 协议

## 非目标

1. 本轮不改变底层 turn loop、tool runtime 或 planner 决策协议
2. 本轮不引入桌面工作台式多栏布局
3. 本轮不实现并行工具的复杂可视化编排
4. 本轮不把所有结构化卡片统一成通用表单引擎
5. 本轮不重写所有 tool payload schema，只在展示投影层做语义归类

## 视觉方向

推荐方向为：

- 主骨架：`流程聚焦`
- 视觉气质：`quiet research / document-first`

这意味着：

- 用户应该能快速看懂“当前系统在做哪一步”
- 但 tool card 仍然是聊天文档流的一部分，而不是独立的操作台
- 高亮只应集中在“当前步骤、确认节点、阶段产出、需要处理的异常”上
- 已完成的上下文采集步骤默认应退回背景

换句话说，本设计不是把所有 tool item 都升级为强面板，而是让“当前活跃步骤更清楚、结果型步骤更明确、过程型步骤更安静”。

## 核心原则

### 1. 按语义分型，不按技术事件类型分型

当前 `toolInvocation` 和 `toolResult` 只是运行时事件，不应直接决定最终 UI 形态。

同样是 `toolResult`：

- `search_chat_history` 的成功结果本质上只是过程痕迹
- `create_reminder` 的成功结果本质上是阶段产出

它们不应共用同一视觉优先级。

### 2. 过程型工具默认退后

对于检索、读取、搜索类工具，用户真正关心的是最终回答是否更准确，而不是工具本身执行了多漂亮。

因此：

- 运行中可以高亮当前步骤
- 完成后应自动收起
- 收起后保留极简回执即可

### 3. 外部动作结果必须显式回执

对于会产生外部副作用或明确阶段产出的工具，完成后必须留下更明确的结果卡片。

例如：

- 创建提醒
- 创建日历事件
- 分享结果
- 保存笔记
- 写入/编辑文件

这些动作即使已经在 workflow 中完成，也不应只剩下一条轻量摘要行。

### 4. “当前步骤”比“所有步骤”重要

流程聚焦的核心不是把整个链路展开，而是让用户一眼看到：

- 现在在做什么
- 是否需要我操作
- 做完后发生了什么

因此，同一个 workflow 中应只有一个高强调的当前步骤。

### 5. AskUserQuestion 是正式交互节点

`AskUserQuestion` 不是普通 structured output，也不是普通工具结果，而是当前 turn 的正式挂起点。

因此它应该和 tool workflow 共享同一套语言：

- 明确的当前状态
- 继续此回合所需信息
- 完成后回到原链路

而不应继续停留在“默认表单卡”的层级。

## 语义卡片体系

推荐新增一层 UI 投影概念：`presentationVariant`。

它不替代现有消息协议，而是位于消息协议与 widget 渲染之间。

首版建议包含以下 6 类。

### 1. Inline Step

定位：

- 上下文采集型过程步骤
- 对最终回答提供材料，但不是用户真正要感知的阶段结果

典型工具：

- `search_chat_history`
- `web_search`
- `fetch_webpage`
- `LS`
- `Glob`
- `Grep`
- `Read`

视觉规则：

- 单行或双行高度
- 默认轻表面、低对比
- 展开前仅显示工具名、状态、一句摘要
- 展开后显示极短参数摘要，不展示大段原始内容

交互规则：

- 执行中时可作为当前步骤高亮
- 完成后默认折叠
- 用户可手动查看详情，但不长期持久化展开状态

### 2. Focused Active Step

定位：

- 当前正在运行的步骤
- 用户需要理解“系统现在在做什么”

适用场景：

- 多步 workflow 的当前步骤
- 当前执行中的 `web_search` / `fetch_webpage`
- 即将进入确认的当前步骤

视觉规则：

- 中等高度
- 当前步背景更亮一层
- 允许轻度运行中动效，但应克制
- 可显示 `why this step` 或参数范围摘要

交互规则：

- 同一 assistant turn 内默认只允许一个 focused active step
- 其他历史步骤压缩显示

### 3. Confirmation Step

定位：

- 用户授权节点
- 属于流程中的一步，但强调高于普通 active step

典型工具：

- `create_reminder`
- `create_calendar_event`
- `share_result`
- `Write`
- `Edit`

视觉规则：

- 保留 workflow 上下文
- 明确显示动作对象、影响范围、关键参数
- 按钮区只出现在当前待确认步骤

交互规则：

- 支持 `继续`、`取消`、`继续并记住`
- 不在输入区重复展示确认按钮

### 4. Outcome Card

定位：

- 某个阶段已经产生了用户可感知的结果

典型工具：

- `create_reminder`
- `create_calendar_event`
- `share_result`
- `save_note`
- `Write`
- `Edit`

视觉规则：

- 独立于 inline step 的更明确结果面
- 标题比普通步骤更强
- 支持展示结构化结果字段
- 成功与 fallback 都应可读表达

内容规则：

- 必须告诉用户“做成了什么”
- 必须告诉用户“以什么方式做成”
- 若存在 fallback，应明确说明 fallback 模式

例如：

- `已发起提醒创建`
- `已改为日历事件创建`
- `宿主提醒不可用，已复制提醒信息`

### 5. Exception Card

定位：

- 失败或异常需要被用户理解、处理或感知

区分规则：

- 内部过程失败且不阻塞最终回答：可退化成轻量失败摘要
- 需要用户理解或采取行动的失败：升级为 exception card

典型场景：

- `missing_api_key`
- `invalid_due_at`
- `share_unavailable`
- 写入/编辑失败

视觉规则：

- 比成功结果更强调原因解释
- 不只显示 `失败` badge
- 应包含“发生了什么 / 为什么 / 接下来怎么办”

### 6. Interaction Card

定位：

- 当前 turn 的正式交互节点

当前唯一直接映射：

- `AskUserQuestion`

视觉规则：

- 与 workflow 卡共享同一套 spacing、表面语言、状态标题
- 不再使用默认 `Card + CheckboxListTile + TextButton` 的表单感
- 多题场景更像“待补充信息的分步节点”

交互规则：

- 应明确告诉用户：提交后会继续当前回合
- 回答完成后，在消息流中留下已提交结果摘要

## 工具到卡片的推荐映射

### 上下文采集类

#### search_chat_history

- 进行中：`Focused Active Step`
- 完成后：`Inline Step`
- 默认折叠
- 展开内容：查询词、命中条数、是否存在高相关结果

#### web_search

- 进行中：`Focused Active Step`
- 完成后：`Inline Step`
- 默认折叠
- 展开内容：query、来源数量、前 2 个来源标题

#### fetch_webpage

- 进行中：`Focused Active Step`
- 完成后：`Inline Step`
- 默认折叠
- 展开内容：页面标题、域名、抽取模式

#### LS / Glob / Grep / Read

- 进行中：`Focused Active Step`
- 完成后：`Inline Step`
- 默认折叠
- 展开内容：path / pattern / 命中数量 / 读取对象

### 外部动作类

#### create_reminder

- 待确认：`Confirmation Step`
- 成功后：`Outcome Card`
- 默认保留显式结果卡

结果卡建议字段：

- 标题
- 时间
- 创建方式
- fallback 状态

#### create_calendar_event

- 待确认：`Confirmation Step`
- 成功后：`Outcome Card`
- 默认保留显式结果卡

结果卡建议字段：

- 标题
- 开始/结束时间
- 地点
- 创建方式或 fallback 状态

#### share_result

- 若需确认：`Confirmation Step`
- 完成后：`Outcome Card`
- 失败时根据是否可恢复决定是否升级为 `Exception Card`

#### save_note

- 成功后：`Outcome Card`
- 强度低于 reminder / calendar，但高于 search 类步骤

#### Write / Edit

- 若需确认：`Confirmation Step`
- 成功后：`Outcome Card`
- 失败后：`Exception Card`

原因：

- 它们触及用户资产，不应像搜索工具一样悄悄折叠为背景

### 交互类

#### AskUserQuestion

- 渲染为 `Interaction Card`
- 回答前是当前节点
- 提交后保留 `已提交答案` 的精简摘要块

## 默认展开策略

本设计最关键的控制点不是卡片种类，而是默认展开策略。

推荐规则如下：

1. 当前运行步：展开
2. 当前待确认步：展开
3. 已完成的上下文采集步：自动折叠
4. 已完成的外部动作结果：保留显式结果卡
5. 已失败但不阻塞的内部步骤：折叠成轻量异常摘要
6. 已失败且需要用户理解/处理的步骤：展开异常卡
7. 用户手动展开的历史步骤：仅会话内保留，不长期持久化

总结为一句话：

`过程类工具收起，结果类工具留下。`

## 内容显示规则

### 折叠态

折叠态只显示：

- 工具名
- 状态
- 一句结果说明

不在折叠态显示：

- 大段参数 JSON
- 大段网页正文
- 大量搜索结果列表
- 复杂错误堆栈

### 展开态

展开态优先展示：

- 当前为何执行这一步
- 影响对象或作用范围
- 关键参数摘要
- 结果的结构化字段

展开态也不应直接倾倒原始 payload；应经过压缩与字段挑选。

### 结果态

结果态应优先展示“用户能理解和复述的结果”，而不是技术实现细节。

例如：

- 用“已发起提醒创建：明天 09:00 与设计团队同步”
- 而不是“launchStatus=launched”

技术细节应放入次级字段或展开区。

## 与现有架构的映射方式

推荐保持现有 `ChatMessage` 与 `AssistantTurnBlock` 主干不变，在 UI 投影层增加语义映射。

### 当前问题

当前实现主要按以下 block 类型渲染：

- `toolWorkflow`
- `toolResultSummary`
- `structuredOutput`

这导致：

- `toolResultSummary` 默认都走同一种轻量形态
- `toolWorkflow` 默认都走同一种折叠步骤卡

### 推荐改法

在 `ChatBlockBuilder` 产出的 payload 基础上，增加一层 `presentationVariant` 解析。

建议由以下信息共同决定：

- `toolName`
- `status`
- `executionPolicy`
- 是否需要 confirmation
- 是否为外部动作类工具
- `ToolResult.data` 中是否存在结构化产出字段
- 是否为用户需要处理的错误

首版可先用一份轻量分类表完成，不必重写消息协议。

## 对现有组件的影响

### ToolWorkflowCard

[lib/widgets/chat_blocks/tool_workflow_card.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/widgets/chat_blocks/tool_workflow_card.dart)

建议职责调整为：

- 不再承担所有 tool 步骤的统一展示
- 只负责流程型步骤的基础骨架
- 支持 `inline`、`active`、`confirmation` 三种 step emphasis

### ToolResultSummaryRow

[lib/widgets/chat_blocks/tool_result_summary_row.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/widgets/chat_blocks/tool_result_summary_row.dart)

建议不要继续作为所有 tool result 的唯一结果组件。

可拆成：

- `InlineToolResultRow`
- `ToolOutcomeCard`
- `ToolExceptionCard`

### AskUserQuestionCard

[lib/widgets/interaction/ask_user_question_card.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/widgets/interaction/ask_user_question_card.dart)

建议重构为新的 `InteractionCard` 语言：

- 顶部状态标题
- 当前问题与进度
- 选项区更像 workflow node，而不是默认表单
- 提交后形成结果摘要

## 状态与强调层级

推荐统一使用以下强调顺序：

1. 当前待确认节点
2. 当前运行节点
3. 外部动作结果卡
4. 最终回答
5. 结构化输出
6. 已折叠的过程步骤

注意：

- `最终回答` 仍应是内容主轴
- 外部动作结果虽然要明确，但不能压过 assistant 的核心结论

## 测试与验证建议

本设计落地后，建议至少覆盖以下验证：

1. `search_chat_history` / `web_search` / `fetch_webpage` 成功后默认折叠
2. `create_reminder` / `create_calendar_event` 成功后渲染 outcome card
3. `share_result` / `Write` / `Edit` 失败时正确升级为 exception card
4. 同一 assistant turn 内只有一个当前高亮步骤
5. `AskUserQuestion` 使用新的 interaction card，并在提交后留下已回答摘要
6. 手动展开历史步骤不会破坏当前活动步骤判定

## 文档更新建议

若后续按本方案实施，建议同步更新：

- `README.md`
- `AGENTS.md`
- 与 tool workflow 或 interaction card 相关的设计文档

重点补充：

- tool use UI 按语义分型，而非仅按底层消息类型分型
- 过程型工具与结果型工具具有不同默认展开和保留策略
- AskUserQuestion 属于 interaction-style node，而不是普通结构化表单

## 决策摘要

本次设计确认以下方向：

1. 主视觉骨架采用 `流程聚焦`
2. 上下文采集类工具使用低占用 inline step，并在完成后默认折叠
3. 外部动作类工具在完成后保留显式 outcome card
4. 异常根据是否需要用户理解/处理决定是轻量失败摘要还是 exception card
5. AskUserQuestion 升级为正式 interaction card，统一进入 workflow 语言
6. UI 投影应引入 `presentationVariant`，避免直接被底层消息类型绑死
