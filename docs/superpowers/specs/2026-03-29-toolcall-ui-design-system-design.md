# FlutterAIChat Tool Call And UI Design System

## 背景

当前项目的两个直接问题是：

1. `tool call` 链路虽已具备基础调度能力，但剩余能力仍有不少只声明未实现。
2. 现有 UI 仍偏默认 Flutter 聊天界面，`tool call` 展示也更像临时拼接，缺少产品级统一风格。

本次设计优先解决第二个问题，即先建立一套可长期复用的全应用设计系统和消息渲染协议，再让剩余 `tool call` 能力按该协议接入。

## 目标

- 建立全应用级设计系统，覆盖聊天页、设置页及后续工具相关页面。
- 将聊天主界面重构为更适合移动端高信息密度阅读的产品形态。
- 让用户消息、助手正文、`tool call` 过程、`tool result` 摘要、结构化输出、最终回复具备清晰且统一的视觉语义。
- 为后续补全剩余 `tool call` 功能提供稳定的展示容器，避免继续在旧消息组件上打补丁。

## 非目标

- 本设计阶段不直接定义每个未实现工具的具体平台适配细节。
- 本设计阶段不扩展桌面端或平板优先布局，目标设备为手机。
- 本设计阶段不引入复杂的新交互体系，如多窗格、多栏布局或桌面工作台模式。

## 产品定位

产品定位为 `高端研究助手`，而不是通用闲聊应用。

设计气质采用 `Quiet Research`：

- 基调参考 Claude 式温和克制。
- 强调内容阅读和连续思考，而不是强烈的工具面板感。
- 通过排版、层级、分隔和有限状态色建立品质感。
- `tool call` 是研究过程的一部分，而不是突兀插入的系统卡片。

## 核心界面模型

聊天主界面采用 `锚点气泡 + 文档流 + 工作流块` 的三层模型。

### 1. 用户层

- 用户消息保留短气泡。
- 气泡只承担“问题锚点”和节奏分隔作用。
- 用户消息通常较短，因此保留气泡不会显著损失信息密度。

### 2. 助手文档层

- 助手消息不再统一渲染成大气泡。
- 助手正文改为连续文档式阅读块。
- 长回答、分析段落、小结、最终回答都属于这一层。
- 目标是让阅读体验更接近研究文档，而不是 IM 对话泡泡。

### 3. 工作流层

- `tool call` 不作为“特殊消息补丁”插入，而是作为文档流中的工作流块。
- 工作流块承载：
  - 当前执行中的工具步骤
  - 中间结果摘要
  - 需要确认的操作
  - 已完成步骤的折叠摘要

## Tool Call 展示原则

### 折叠规则

- `tool call` 整体采用可折叠工作流卡片。
- 默认仅展开当前正在进行的 `tool call`。
- 已完成的 `tool call` 自动折叠。
- 折叠后只保留最终结果摘要。
- 只有以下情况主动展开：
  - 当前执行中的步骤
  - 需要用户确认的步骤
  - 用户手动展开查看详情

### 边界规则

- 一个 assistant turn 内，默认只允许一个“当前展开中的步骤”。
- 若底层出现多轮内部 `tool call`，它们在 UI 上属于同一个 `tool workflow card` 的多个 step。
- 若未来支持并行工具，首版 UI 仍按串行展示，按开始时间排序；并行能力不在本轮实现范围内。
- step 失败时保持展开，不自动折叠，直到：
  - 用户重试
  - 用户关闭
  - assistant 明确结束本轮并生成失败摘要
- 用户手动展开历史步骤后，该展开状态仅在当前会话停留期间保留，不写入长期持久化。
- 折叠摘要必须限制为 `1 行标题 + 1 行说明`，在手机默认字号下不超过约 `56dp` 高度。
- 摘要至少包含：
  - 工具名
  - 最终状态
  - 一句结果说明

### 展示层级

从高到低建议如下：

1. 用户消息锚点
2. 当前展开中的 `tool workflow card`
3. `final response block`
4. `structured output block`
5. `intermediate analysis`
6. 已折叠的历史 `tool result summary`

### 语义区分

- `tool workflow card`
  - 展示当前工作流步骤和确认动作
  - 适合多轮内部 `tool call`
- `tool result summary`
  - 展示工具完成后的精简回执
  - 默认折叠，保留可重新展开能力
- `structured output block`
  - 展示结构化字段、摘要卡、对比信息
  - 不与 `tool result` 混为同类
- `final response block`
  - 展示真正面向用户的结论与建议
  - 视觉权重高于工具过程和中间结果

### 内容来源判定

不同 block 的来源必须有单一判定规则，不能在渲染层用文案猜测：

- `analysis`
  - 来源于 assistant 的普通文本输出
  - 用于承载过程性解释、分析段落、小结
- `tool_workflow`
  - 来源于工具编排层的显式状态事件
  - 不能由正文字符串反推
- `tool_result_summary`
  - 来源于工具执行成功或失败后的标准化结果
  - 由 `ToolResult` 映射生成
- `structured_output`
  - 来源于现有结构化响应解析器或后续明确的结构化 payload
  - 不能与普通 markdown 文本混用
- `final_response`
  - 来源于一次 assistant turn 的最终可见结论文本
  - 首版实现允许将 assistant 最后一个正文块标记为 `final_response`

首版决策：

- 不在 UI 中单独展示“深度思考原始中间推理”。
- `intermediate analysis` 指可展示给用户的普通分析段落，不等同于模型私有推理。

## 页面结构

### 顶部栏

- 保持轻量，不占据阅读空间。
- 仅承载：
  - 当前会话标题
  - 当前模式或模型状态
  - 到设置页或会话详情的入口

### 消息列表

消息列表是主阅读区，按内容类型混排，而不是统一按“消息气泡”处理。

首版明确采用 `时间正序` 展示，即旧内容在上，新内容在下。

- 这与当前项目中部分“倒序列表 + reverse:true”的实现不同。
- 为满足文档流阅读体验，聊天页应迁移到正序渲染。
- 自动滚动逻辑仍保持“新内容到来时默认滚动到底部”。

典型顺序：

1. 用户短气泡
2. 助手文档段落
3. 当前展开的 `tool workflow card`
4. 已折叠的 `tool result summary`
5. `structured output block`
6. `final response block`

### 输入区

- 输入区必须压缩成 `单行主输入 + 一行极轻状态信息`。
- 默认高度尽量薄，仅在多行输入时自然增高。
- 需要设置上限，避免吞掉主阅读区。
- `发送`、`停止`、`等待工具确认` 等状态共享同一条紧凑控制线。

输入区首版交互规则：

- 默认展示：
  - 左侧为输入框
  - 右侧为主按钮
  - 下方为一行状态信息
- 主按钮规则：
  - `idle` / `completed` / `failed` 时显示 `发送`
  - `submitting` / `toolRunning` / `streamingAnswer` 时显示 `停止`
  - `awaitingToolConfirmation` 时主按钮不触发发送，而显示“等待工具确认”
- 键盘弹起后：
  - 输入区可自然增高，但上限不超过 `4` 行文本高度
  - 超过上限后内部滚动，不继续侵占主阅读区
- 当存在待确认工具时，确认动作只出现在 `tool workflow card` 内，不在输入区重复放置确认按钮。

### 滚动策略

- 默认保证当前活动块可见。
- 当前 `tool call` 展开时，滚动到其附近。
- 工具执行完成后自动折叠，但不要过度强制滚动。
- 用户手动上滑后暂停自动滚动。

## 视觉风格

### 总体风格

采用 `Quiet Research` 风格：

- 温和克制
- 内容优先
- 安静的专业感
- 轻工具感

### 页面风格变体

同一设计系统下允许存在不同页面气质，但不能演变成彼此割裂的两套产品。

- 聊天页采用 `Quiet Research`
  - 更强调连续阅读、文档感、温和克制
- 设置页采用 `Precision Settings`
  - 更强调高对比、精密控件感、清晰分组和专业工具秩序

两者共享：

- 同一套 spacing token
- 同一套 typography token
- 同一套 radius token
- 同一套控件语义和交互逻辑

两者只在语义色板和局部强调方式上区分。

### 色彩

- 主色基调为暖灰与冷灰蓝。
- 避免高纯度科技蓝、夸张渐变或过强品牌色。
- 状态色仅在风险、执行中、成功等局部场景增强。

首版 token 方向：

- 页面背景：暖灰白 `#F5F3EF` 到冷灰白 `#F7F8FA`
- 主文本：深灰蓝 `#1D2733`
- 次文本：中灰蓝 `#5F6B7A`
- 细分隔线：`rgba(29, 39, 51, 0.08)`
- 用户气泡底色：低饱和灰蓝 `#DCE6F2`
- 工具工作流底色：极浅蓝灰 `#EEF3F8`
- 成功态：低饱和绿 `#3D7A57`
- 执行态：冷蓝 `#4D6FA3`
- 风险态：低饱和琥珀 `#A46A2A`

### 排版

- 强调标题、摘要、正文、辅助信息四层排版层级。
- 助手正文需要具备研究文档般的连续阅读节奏。
- 避免大而松散的卡片堆叠。

### 分隔与层次

- 优先使用细分隔线、明度差和轻边框表达层次。
- 阴影极弱，不依赖厚重卡片和悬浮面板。
- 圆角存在，但保持克制。

首版 token 方向：

- 正文字号：`15sp`
- 辅助文本：`12sp`
- 小标签：`10sp`
- 标题层级：
  - 页面标题：`18sp semibold`
  - block 标题：`14sp semibold`
  - 正文：`15sp regular`
- 基础间距单位：`4dp`
- 常用 block 内边距：`10dp / 12dp`
- 圆角：
  - 用户短气泡：`16dp`
  - 文档块 / tool block：`12dp`
  - 小标签：`999dp`
- 阴影：
  - 默认无阴影或极弱阴影
  - 不使用大面积悬浮卡阴影

### Flutter 主题承载

- 首版采用 `ThemeData + ColorScheme + ThemeExtension` 组合实现。
- `ColorScheme` 负责全局基础色。
- 自定义 `ThemeExtension` 负责：
  - 消息语义色
  - tool workflow 色
  - 结构化输出块色
  - 间距和圆角 token
- 首版仅实现亮色主题。
- 设计系统必须为亮色与暗色都预留语义色板。
- 本轮实现可优先完成亮色主题，但 token 定义必须允许后续无破坏地补齐暗色主题。
- 可访问性要求：
  - 正文与背景对比度不低于 `4.5:1`
  - 辅助文本与背景对比度不低于 `3:1`

### 设置页主题要求

设置页参考的是“高对比度、精密、简洁清爽”的工具页语言，而不是固定采用深色面板。

设置页风格要求：

- 强调：
  - 高对比
  - 低噪音
  - 清晰分组
  - 精密控件感
- 页面结构采用分组式设置面板：
  - 每组有清晰标题
  - 组内条目高度统一
  - 左侧为设置语义
  - 右侧为当前值、开关、分段选择器或跳转入口
- 控件视觉追求“利落、稳定、可读”：
  - 输入框短而稳重
  - 分段选择器、开关、步进器、跳转行视觉统一
  - 主按钮允许突出，但整页只能保留少量强强调色

设置页主题变体：

- 亮色主题
  - 使用浅暖灰或浅冷灰作为页面背景
  - 面板通过细边框、轻明度差和极弱阴影建立层次
  - 整体观感应清爽、整洁、专业
- 暗色主题
  - 使用接近黑或深灰背景
  - 通过高对比文本和轻面板层级建立精密感
  - 避免高饱和荧光式配色泛滥

无论明暗主题如何切换：

- 页面结构不变
- 控件尺寸不变
- 交互逻辑不变
- 仅切换语义色值

## 设计系统边界

本次实现不应只做聊天页样式修改，而应建立全应用可复用的设计系统。

建议拆成四层：

### 1. Design Tokens

统一定义：

- 颜色
- 字号
- 字重
- 间距
- 圆角
- 边框
- 阴影
- 状态色

### 2. Semantic Components

建议以语义角色命名，而不是按页面命名，例如：

- `AppTopBar`
- `CompactComposer`
- `UserAnchorBubble`
- `AssistantDocBlock`
- `ToolWorkflowCard`
- `ToolResultSummaryRow`
- `StructuredOutputBlock`
- `FinalResponseBlock`

### 3. Message Rendering Protocol

当前方案更像基于 `contentType` 做条件分支。后续需要升级为“消息块协议”：

- 一个 assistant turn 可以包含多个 block。
- block 类型建议包括：
  - `analysis`
  - `tool_workflow`
  - `tool_result_summary`
  - `structured_output`
  - `final_response`

这样才能自然支持：

- 当前步骤展开
- 历史步骤折叠
- 工具结果摘要保留
- 结构化结果独立展示

首版 block 数据模型建议如下：

- `AssistantTurnBlock`
  - `id: String`
  - `turnId: String`
  - `type: String`
  - `sequence: int`
  - `createdAt: DateTime`
  - `updatedAt: DateTime`
  - `status: String?`
  - `title: String?`
  - `text: String?`
  - `payload: Map<String, dynamic>?`

block 约束：

- `sequence` 决定同一 assistant turn 内的显示顺序。
- `updatedAt` 用于流式刷新当前 block。
- `status` 仅对 `tool_workflow` 和 `tool_result_summary` 等状态型 block 强制要求。
- `payload` 用于结构化字段，不在渲染层解析自由文本。

首版 block 类型字段规则：

- `analysis`
  - 使用 `text`
- `tool_workflow`
  - 使用 `title`、`status`、`payload.steps`
- `tool_result_summary`
  - 使用 `title`、`status`、`text`
- `structured_output`
  - 使用 `title`、`payload.fields`
- `final_response`
  - 使用 `title`、`text`

首版持久化策略：

- 不立即修改数据库主表结构来存 block 明细。
- 首版允许在内存态构建 block 列表，并将必要摘要回写到现有消息记录。
- 若后续 block 协议稳定，再单独推进数据库 schema 升级。
- 历史消息兼容方案：
  - 老消息默认映射为单一 `analysis` block
  - 已有结构化卡片继续映射为 `structured_output`
  - 已有 tool invocation / tool result 记录映射为对应 workflow / summary block

### 4. Page Composition

- 聊天页只负责拼装顶部栏、block 列表、输入区。
- 设置页和后续页面复用相同 tokens 与组件语义。

## 状态管理建议

建议将一轮发送状态拆分，而不是继续让工具状态和正文状态共用一套展示语义。

推荐状态：

- `idle`
- `submitting`
- `awaitingToolConfirmation`
- `toolRunning`
- `streamingAnswer`
- `completed`
- `failed`

关键原则：

- `tool workflow` 状态与 `assistant 文本输出` 状态分离。
- 输入区状态只负责交互控制，不承担主要展示职责。
- UI 应围绕“当前活动块”更新，而不是整条消息统一变更。

首版状态机约束：

- `idle -> submitting`
  - 用户点击发送，且输入非空
- `submitting -> awaitingToolConfirmation`
  - 模型返回需要确认的工具步骤
- `submitting -> toolRunning`
  - 模型直接进入工具执行
- `submitting -> streamingAnswer`
  - 模型不需要工具，直接输出正文
- `awaitingToolConfirmation -> toolRunning`
  - 用户在 workflow card 内点击确认
- `awaitingToolConfirmation -> completed`
  - 用户取消工具，assistant 本轮结束
- `toolRunning -> streamingAnswer`
  - 工具结束，assistant 继续生成可见正文
- `toolRunning -> completed`
  - 工具结束且本轮无后续正文
- `toolRunning -> failed`
  - 工具执行失败且 assistant 未恢复
- `streamingAnswer -> completed`
  - 文本流结束
- `streamingAnswer -> failed`
  - 文本流失败
- `failed -> idle`
  - 用户开始下一轮输入或手动恢复

并发规则：

- 首版不允许 `toolRunning` 与 `streamingAnswer` 并行渲染为两个活跃主状态。
- 若底层事件重叠到来，以“先结束 tool，再进入 streamingAnswer”的顺序合并到 UI。
- 输入区是否可编辑只由顶层发送状态决定，不由单个 block 决定。

## 实施顺序建议

1. 建立全应用 `design tokens` 和基础主题。
2. 重构聊天页骨架：顶部栏、主列表、紧凑输入区。
3. 引入新的 assistant block 渲染模型。
4. 实现 `ToolWorkflowCard` 折叠规则。
5. 在新协议下补全剩余 `tool call` 功能。
6. 将设置页统一到新设计系统。

## 为什么先做 UI 设计系统

- 当前更大的问题不是“少几个工具能力”，而是“能力进入产品后没有成熟的展示方式”。
- 如果继续在现有消息渲染上叠加功能，`tool call` 会继续以特殊分支堆积，后续维护成本越来越高。
- 先建立设计系统与消息块协议，后续每个新工具都能落到稳定的交互容器中。

## 验收标准

本设计在实现后应满足以下结果：

- 以 `390 x 844` 逻辑分辨率为基线设备，在聊天页首屏应至少同时可见：
  - `1` 条用户锚点消息
  - `1` 个展开中的 workflow 或 `2` 个折叠摘要
  - `1` 段 assistant 正文
- 用户消息仍清晰可见，但不再主导版面。
- 助手长内容阅读体验明显优于当前气泡式布局。
- 多轮 `tool call` 在默认状态下不会打断主阅读流。
- 当前正在执行的步骤清楚可见。
- 已完成步骤自动折叠且能保留结果摘要。
- 输入区默认高度不超过约 `72dp`，在多行输入上限内不超过约 `132dp`。
- 折叠后的 tool 结果摘要高度不超过约 `56dp`。
- assistant 文档块默认内边距不超过 `12dp`。
- 聊天页与设置页能共享统一的设计语言。
- 聊天页在新内容插入时不出现明显滚动抖动；首版以“肉眼无明显跳跃”为最低要求，后续可再加性能指标。
