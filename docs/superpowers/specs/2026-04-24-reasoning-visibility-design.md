# 推理过程可见化设计

## 背景

当前应用已经具备部分 `reasoning` / `thinking` 数据接收能力，但用户侧基本看不到这些内容：

- `lib/models/llm/api_stream_parser.dart` 已能解析三类流式推理增量：
  - OpenAI-compatible Chat Completions 的 `delta.reasoning_content`
  - OpenAI Responses 的 `response.reasoning.delta` / `response.reasoning_summary_text.delta`
  - Anthropic Messages 的 `thinking_delta` / `redacted_thinking_delta`
- `lib/models/chat_message.dart` 已有 `reasoningContent` 字段
- `lib/providers/chat_collection_providers.dart` 已有 `appendReasoningToMessage()`
- 但 `lib/controllers/chat_send_coordinator.dart` 目前对 `ChatEventType.assistantReasoningDelta` 基本不做 UI / 持久化处理
- 现有消息渲染也只展示正文，不展示 `reasoningContent`

因此，当前问题不是“接口没有返回推理过程”，而是“推理过程没有被稳定接入 UI 展示链路”。

## 目标

本次设计目标如下：

1. 让用户在当前聊天时间线中看到模型返回的推理过程
2. 不恢复“开始深度模式”开关，改为“provider 返回则展示”
3. 保持 Anthropic continuation 对原始 thinking block 的续传要求
4. 不把 provider 原始 continuation 结构和 UI 展示文本混为一层
5. 在现有聊天消息结构与时间线模式内增量实现，避免引入第二套 reasoning 消息体系
6. 保持 reasoning 的阶段语义清晰：
   - `tool_use` reasoning 以时间线内联分析块呈现，强调“先思考，再执行工具”
   - final-answer reasoning 仅作为最终答复的折叠思考区呈现

## 非目标

本次不做以下事项：

- 不新增用户可切换的“深度模式”入口
- 不尝试展示 OpenAI 原始 chain-of-thought
- 不改造 planner / tool loop 的整体事件模型
- 不引入 provider 级 capability 协商协议

## 现状分析

### 现有能力

- `ApiStreamParser` 已可输出标准化事件：
  - `{"type":"content","content":"..."}`
  - `{"type":"reasoning","content":"..."}`
- `ChatMessage.reasoningContent` 可保存面向 UI 的聚合推理文本
- `DatabaseHelper.updateMessageReasoning()` 已可写库
- Anthropic tool loop 已开始保留 `providerState.content_blocks` 用于 continuation 续传

### 现有缺口

1. 发送协调层未消费 reasoning 增量
2. 流式缓冲器只有正文单通道，缺少 reasoning 单独缓冲
3. 消息渲染组件不显示 `reasoningContent`
4. Final / Streaming 两种 assistant block 都没有推理区
5. Responses / Chat Completions / Anthropic 三种风格的“可展示推理文本”尚未统一到一个 UI 契约

## API 风格对接策略

### 1. OpenAI Responses

策略：

- 将 Responses 返回的 reasoning summary / reasoning delta 统一视为“可展示推理文本”
- UI 上展示为“思考过程”区块
- 不尝试从 Responses 侧构造或还原原始内部思维链

原因：

- Responses 的 reasoning 更适合展示为 summary，而不是原始 chain-of-thought
- 这一路的续传主机制是 `previous_response_id`，不依赖当前 UI 聚合文本

### 2. OpenAI-compatible Chat Completions

策略：

- 将 `delta.reasoning_content` 聚合到 `ChatMessage.reasoningContent`
- 将 `delta.content` 聚合到正文
- UI 允许 reasoning 与正文并存

原因：

- DeepSeek 等兼容实现会真实返回 `reasoning_content`
- 这类 provider 最适合做“用户可见的流式思考过程”

### 3. Anthropic Messages

策略：

- UI 展示层只消费 thinking 文本聚合结果
- continuation 层继续保留原始 `content_blocks`
- 绝不使用 UI 聚合后的 `reasoningContent` 替代原始 block 回传

原因：

- Anthropic / DeepSeek Anthropic 风格 continuation 对原始 thinking block 有严格要求
- UI 展示文本与协议续传结构必须分层

## 设计方案

### 方案选择

采用“按 reasoning scope 分阶段展示”方案：

- `tool_use` reasoning 作为 assistant analysis 消息进入时间线
- final-answer / response reasoning 绑定到当前 assistant 最终答复
- 最终答复正文块上方显示一个可折叠“思考过程”区域

选择原因：

- 与当前时间线结构最兼容
- 不破坏 turn / transcript / block 的现有组织方式
- 能同时支持 streaming 与 completed 两种 assistant message
- 能把“工具前思考”和“最终答复思考”分开建模，避免 tool-use thinking 被错误吸收到 final answer
- 不会引入 provider continuation 与 UI thinking 混层问题

### UI 结构

对于 `tool_use` reasoning：

- 以 assistant analysis 块进入时间线
- 默认直接可见，不折叠到最终答复中
- 顺序上必须出现在对应工具 workflow / result 之前

对于 final-answer / response reasoning：

- 若 `reasoningContent` 为空：仅展示正文
- 若 `reasoningContent` 非空：
  - 在正文上方展示“思考过程”区
  - 支持折叠 / 展开
  - final-answer completed 阶段默认按折叠语义展示
  - response streaming 阶段可继续沿用当前展示方式

展示原则：

- 推理内容弱于最终回答，不抢主层级
- `tool_use` reasoning 以时序为先，优先表达“先思考再执行动作”
- final-answer reasoning 以答复为主，优先表达“思考过程从属于最终回答”
- Anthropic 的 redacted thinking 仅展示可见文本，不暴露结构化协议细节

### 数据与状态边界

保留双层数据边界：

1. `ChatMessage.reasoningContent`
   - 用途：UI 展示、轻量持久化、恢复历史消息时显示
   - 形式：聚合后的纯文本

2. `ChatTurn.providerStateJson.content_blocks`
   - 用途：Anthropic continuation 协议续传
   - 形式：provider 原始 block 数组

规则：

- UI 不依赖 `content_blocks`
- continuation 不依赖 `reasoningContent`
- `reasoningScope` 负责决定 UI 呈现语义：
  - `tool_use`：进入时间线 analysis block
  - 其他 scope（如 general / response / final-answer）：仅在对应 assistant 答复块上折叠展示

### 流式处理策略

assistant streaming 需要拆成双通道：

- 正文通道：现有 `text`
- 推理通道：新增 `reasoning`

两条通道都需要：

- UI 合并刷新
- 节流持久化
- turn 完成时强制 flush

补充约束：

- 不允许把 `tool_use` reasoning 作为 runtime draft 在 final answer 阶段再回填
- final answer 只能消费 final-answer / response 阶段的 reasoning，不能回退吸收 `tool_use` reasoning

## 实现边界

### 需要修改的区域

- `lib/controllers/agent_event_processor.dart`
  - 接入 `assistantReasoningDelta`
  - 将 `tool_use` reasoning 持久化为独立 assistant analysis 消息
  - 仅将 final-answer / response reasoning 合并到最终答复消息
- `lib/services/assistant_stream_output_buffer.dart`
  - 从单通道扩展为正文 / 推理双通道，或新增 reasoning companion buffer
- `lib/widgets/chat_blocks/streaming_response_block.dart`
  - 支持显示 reasoning 区
- `lib/widgets/chat_blocks/final_response_block.dart`
  - 支持显示 reasoning 区
- `lib/widgets/chat_message_list.dart`
  - 将 source message 的 `reasoningContent` 传给对应 block

### 不需要修改的区域

- Anthropic continuation 原始 block 存储边界
- planner 选择逻辑
- session context compaction 边界
- tool result / ask-user-question 卡片体系

## 测试策略

### 单元测试

- `ApiStreamParser` 现有 reasoning 解析行为保持不变
- assistant streaming reasoning 聚合逻辑正确
- reasoning 与正文不会相互污染

### Provider / Controller 测试

- `ChatController.sendMessage` 或对应 send coordinator 场景中：
  - reasoning delta 会创建 / 更新当前 assistant message
  - reasoning 内容会持久化

### Widget 测试

- 有 `reasoningContent` 的 completed assistant message 会展示“思考过程”
- 有 `reasoningContent` 的 generating assistant message 会展示流式 reasoning
- 无 `reasoningContent` 时不渲染思考区
- `tool_use` reasoning 会以独立 analysis block 出现在第一个工具展示块之前
- final answer 不会吸收 `tool_use` reasoning

## 风险与规避

### 风险 1：Anthropic continuation 回归

风险：

- 若把 UI reasoning 逻辑错误地替代 provider continuation，会重新触发 400

规避：

- 明确区分 `reasoningContent` 与 `content_blocks`
- 补测试锁定 Anthropic continuation 仍传原始 block

### 风险 2：流式刷新抖动

风险：

- reasoning 与正文分开更新，可能导致 UI 高频重建

规避：

- reasoning 也采用节流 flush
- 与正文共用或并行使用同样的 coalescing 策略

### 风险 3：UI 层级失衡

风险：

- reasoning 可见后，可能抢走最终回答关注度

规避：

- 视觉层级弱化 reasoning 区
- 文案明确标注为“思考过程”

## 验收标准

满足以下条件即可认为本次设计落地成功：

1. DeepSeek Chat Completions 返回 `reasoning_content` 时，用户可在当前 assistant 消息中看到思考过程
2. Anthropic Messages 返回 `thinking_delta` 时，用户可在当前 assistant 消息中看到思考过程
3. OpenAI Responses 返回 reasoning summary 时，用户可在当前 assistant 消息中看到思考过程
4. Anthropic continuation 仍能正确回传原始 thinking block，不因 UI 展示层而报 400
5. 无 reasoning 的 provider 不会出现空白 reasoning UI
6. 一次完整的 `thinking -> tool -> result -> final answer` 回合中，`tool_use` thinking 与 final-answer thinking 的展示语义保持分离
