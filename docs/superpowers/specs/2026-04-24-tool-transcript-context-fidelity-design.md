# Tool Transcript 保真上下文设计

## 背景

当前项目已经完成了基于 agent loop 的主链路改造，planner 可见上下文主要由 [`SessionContextService`](/Users/skka/flutterSpace/FlutterAIChat/lib/services/session_context_service.dart) 构建，再由 [`SessionContextProjector`](/Users/skka/flutterSpace/FlutterAIChat/lib/services/session_context_projector.dart) 将 turn transcript 与历史 turn 投影为模型输入。

真实使用中暴露出一个稳定问题：

- 当用户连续执行多次 `Write` / `Edit` 等写操作后
- 当前系统会把这些工具结果压缩成摘要式 assistant 文本，例如“已写入文件：my_hobbies.md”
- 这些摘要会在后续 turn 里以普通 assistant 历史消息的形式重新进入上下文
- 长对话下，模型会逐渐把这类摘要误学成一种“可直接回复给用户的自然语言答案”
- 当用户后续继续要求编辑时，模型可能直接文本回复“已写入文件：my_hobbies.md”，而不是继续调用工具

这不是单纯的 prompt 提示不够，也不是 `Write` / `Edit` 工具定义本身出错，而是“工具链路在进入模型上下文时丢失了 transcript 原始结构”。

## 目标

- 保留 tool use 的发起与结果进入模型上下文时的原始结构语义，而不是把它们重新翻译成摘要式 assistant 对话
- 为 planner、final answer、session history 建立一致的 tool transcript 投影规则
- 为 `tool_result` 进入上下文时预留一层“可选工具级转换”能力，默认所有工具都不做转换
- 在不处理具体工具裁剪策略的前提下，先完成 context 流程改造
- 修复 `Write` / `Edit` 成功结果污染后续 planner 的问题

## 非目标

- 本轮不设计 `Read` / `fetch_webpage` / `web_search` 等具体工具的裁剪策略
- 本轮不改变 UI timeline 的展示结构
- 本轮不重写 tool card renderer
- 本轮不重构 provider-native tool continuation 协议本身
- 本轮不把 `history summary` 改造成完整 transcript 回放层

## 问题拆解

### 1. 当前上下文层把 tool transcript 扁平化成了普通消息

[`SessionContextProjector`](/Users/skka/flutterSpace/FlutterAIChat/lib/services/session_context_projector.dart) 当前会：

- 将 `userMessage` 投影为普通 `user` 消息
- 将 `assistantPlannerMessage` / `finalAnswer` 投影为普通 `assistant` 消息
- 将 `toolResult` / `toolError` 也投影为普通 `assistant` 消息

其中 `toolResult` / `toolError` 还会优先使用 `ToolResult.resolvedToolResultText`。这意味着：

- tool transcript 的“这是一次工具执行结果”这一层结构语义已经丢失
- 模型看到的只是 assistant 历史上说过一句“已写入文件：xxx”

### 2. 副作用工具的成功回执不应伪装成 assistant 对话

对 `Write` / `Edit` / `create_reminder` 这一类副作用工具来说：

- 成功结果本质上是工具执行状态
- 而不是 assistant 面向用户的自然语言结论

如果系统把它们重新包装成 assistant 历史文本，模型会把“工具执行回执”错误地学习为“对用户答复模板”。

### 3. 当前三层上下文边界仍然有效

项目当前的 session context 边界仍然成立：

- `history summary`
- `recent completed turns`
- `current turn transcript`

这次要改的不是三层边界，而是“current turn transcript / recent completed turns 在进入模型前的表示方式”。

### 4. 完整保留 transcript 不等于无条件保留所有全文

本次设计认可以下原则：

- context 应完整保留 tool use 的发起与结果
- 但对超长结果，允许在进入 context 前做一层工具级自定义转换

这两条并不矛盾。

“完整保留”指的是：

- 保留 tool transcript 的原始结构
- 保留 tool_result 的原始语义归属
- 不再重新翻译成摘要式 assistant 对话

“允许转换”指的是：

- 某些工具可以在其 result 进入 context 前进行预算友好的裁剪
- 默认工具不做转换
- 该能力是可选扩展点，而不是本轮必须实现的具体裁剪策略

## 设计原则

### 1. 模型上下文要保留 transcript 结构，而不是 UI 摘要

UI timeline 可以继续展示：

- “准备执行工具：写入文件”
- “已写入文件：notes/db-version.md”

但模型上下文不应直接复用这些 UI 摘要作为 assistant 历史对话。

### 2. tool use 与 tool result 是 transcript item，不是普通 assistant/user message

新的上下文投影层应保留以下语义类型：

- 普通用户消息
- 普通 assistant 文本
- assistant tool use
- user tool result

### 3. tool_result 可选转换默认 passthrough

系统应支持：

- 默认：`tool_result` 文本原样进入 context
- 可选：某个工具注册自己的 context transformer

但本轮不为具体工具接入特殊转换逻辑，只把钩子搭好。

### 4. 当前 turn 与 recent completed turns 保持一致 contract

本轮不应该出现：

- 当前 turn transcript 采用高保真 tool transcript
- recent completed turns 仍然退化成摘要 assistant 消息

否则跨 turn 仍会持续污染 planner。

### 5. history summary 仍然是压缩层

`history summary` 仍然可以保留总结性质，而不要求回放 tool transcript 原形。
但 summary 不应继续累积低价值的“已写入文件 xxx”这类动作回执堆栈。

## 方案总览

本次改造分为三层：

1. 引入结构化上下文项模型
2. 重写 tool transcript 投影链路
3. 为 tool_result context transformer 预留扩展点

## 方案 A：结构化 Context Item

### 定义

新增一层比 `ChatMessage` 更贴近 transcript 原貌的上下文模型，建议命名为：

- `ModelContextItem`
- 或 `ProjectedTranscriptItem`

它至少需要覆盖以下类型：

- `systemMessage`
- `userMessage`
- `assistantMessage`
- `assistantToolUse`
- `userToolResult`

其中：

- `assistantToolUse` 表示一次工具发起
- `userToolResult` 表示一次工具结果回填

这里采用 `userToolResult`，是为了与 provider-native tool-calling transcript 语义对齐，而不是沿用当前事件表中的 `role: system`。

### 为什么不能继续只用 ChatMessage

`ChatMessage` 只有：

- `role`
- `text`

它不足以表达：

- 这是普通 assistant 文本，还是 tool use
- 这是普通 user 文本，还是 tool result
- 这个 `tool_result` 属于哪个工具
- 这个结果是否经过 context transformer

因此如果继续只用 `ChatMessage`，系统很容易再次滑回“把 tool transcript 翻译成摘要消息”的实现方式。

## 方案 B：可选 Tool Result Context Transformer

### 定义

为工具定义层新增一个面向 context projection 的可选扩展口。

建议语义为：

- 输入：`ToolResult` + 执行上下文相关元信息
- 输出：用于进入模型 context 的文本

默认行为：

- 不做转换
- 直接使用原始 tool result 文本

未来可选行为：

- `Read` 裁剪超长文件内容
- `fetch_webpage` 截断网页正文
- `web_search` 截断超长结果块

### 关键边界

这个 transformer 的职责是：

- 做预算友好的转换
- 不做“重写成摘要 assistant 文本”

也就是说，它不是 `summaryBuilder`，而是 `contextResultTransformer`。

## 方案 C：统一 current turn 与 historical turn 的 transcript 保真投影

### current turn transcript

当前 turn 在 planner 和 final answer 构建中，应保留如下形态：

- `[user]`
- `[assistant tool_use]`
- `[user tool_result]`
- `[assistant]`

### recent completed turns

recent completed turns 也应遵循同一套规则，而不是继续：

- 把 `toolResult` 投影成 assistant 摘要文本

### history summary

summary 仍然是压缩层，不要求保留 transcript 原型。但在 summarize 历史时，输入材料应尽量基于新的结构化 transcript 语义，而不是基于已经被翻译污染过的 assistant 摘要句。

## 关键流程变化

### 改造前

1. 读取 `ChatEvent`
2. `SessionContextProjector` 把事件压平成 `ChatMessage`
3. `toolResult` 被投影成 assistant 文本
4. planner/final answer 消费这些普通消息

### 改造后

1. 读取 `ChatEvent`
2. `SessionContextProjector` 先投影成结构化 context item
3. `toolResult` 在这里保留为 `userToolResult`
4. 如有 transformer，则在写入 `userToolResult.text` 前做可选转换
5. planner/final answer 再把这些 context item 编码为模型输入

## 与现有架构的关系

### SessionContextService

仍负责：

- snapshot
- recent completed turns
- current turn transcript

但其 working set 不应再直接依赖“全部被压平成 `ChatMessage` 的工具摘要历史”。

### TranscriptBuilderService

仍负责 final answer 阶段 transcript 构建，但应改为消费新的 context item contract，而不是继续把 `toolResult` 当 assistant 历史消息。

### ToolHandler

仍负责：

- runtime 执行
- 生成 `ToolResult`

本轮不强制所有 handler 提供新 transformer，只需为将来预留接口，默认 passthrough。

## 兼容性与迁移策略

### 兼容原则

- 不重写旧数据库数据
- 不做 schema 迁移
- 不修改已有 timeline 消息结构

### 迁移方式

本次迁移只影响：

- 运行时 context projection
- planner/final-answer 的模型输入构建

也就是说：

- 数据库存量事件继续保留原样
- 但它们在被重新投影进模型上下文时，将按新规则解释

## 测试策略

### 单元测试

需要覆盖：

- `toolResult` 不再被投影成 assistant 摘要消息
- `Write` / `Edit` 成功结果会以 `userToolResult` 语义进入 context
- 默认 transformer 为 passthrough

### SessionContextService 回归测试

需要覆盖：

- recent completed turns 中出现多次 `Write` / `Edit` 成功事件时
- 后续 planner 构建结果中仍保留 tool transcript 结构
- 不再出现“assistant: 已写入文件：xxx”这类污染形式

### TranscriptBuilderService 回归测试

需要覆盖：

- final answer 构建时仍能看到当前 turn 内的 tool use / tool result
- 但不会把其重新翻译为 assistant 摘要历史

## 风险

### 1. provider 适配层需要同步理解新 context item

如果 planner/final-answer 最终仍只能接受 `ChatMessage`，那就需要在更靠后的一层再编码 transcript item。否则改造可能只是在 projector 层换了个壳，最终又被重新压扁。

### 2. Read 类工具的全文结果后续可能带来预算压力

本轮不会处理具体裁剪策略，因此需要接受：

- 新 contract 落地后，某些长结果工具的预算问题会更显性地暴露出来

这是预期内的后续任务，不属于本轮阻塞。

### 3. summary 生成输入可能仍然混入旧式事件文本

如果 summary service 的输入仍来自旧的扁平文本，需要在后续考虑是否也应改成消费新 context item 语义。但本轮先以修复 planner/final-answer 污染为主。

## 决策结论

本轮采用以下方案：

- 保留“context 完整保留 tool use 的发起和结果”的总体原则
- 不再把工具执行过程翻译成摘要式 assistant 历史对话
- 新增结构化 context item 作为模型上下文中间表示
- 为 `tool_result` 增加可选工具级 context transformer 扩展点
- 默认所有工具不做转换
- 先完成流程改造，不在本轮实现具体工具输出优化策略

这会直接修复 `Write` / `Edit` 成功结果污染后续 planner 的问题，同时为未来 `Read` / `fetch_webpage` 等工具的裁剪策略留出稳定扩展口。
