# Provider-Native Append-Only Continuation 设计

## 背景

当前 provider continuation 组装仍依赖两条链路共同参与：

1. 当前 turn transcript 先被投影为通用 `ModelContextItem`
2. 之后再由 provider continuation 逻辑额外拼接 `assistant tool_use` 与 `user tool_result`

这会带来两个结构性问题：

- 同一轮 tool loop 可能被重复编码
- `tool_result` 与对应 `tool_use` 的相邻关系可能被打散

在严格校验 tool loop 顺序与原始 provider block 语义的 provider 上，这会触发类似错误：

- `thinking must be passed back to the API`
- `tool call result does not follow tool call`

当前方案的核心问题不是单一字段缺失，而是 continuation 的协议语义仍在“通用 transcript 投影层”和“provider-native continuation 层”之间摇摆。这个问题不仅影响 Anthropic-compatible API，也同样影响 OpenAI Responses / Chat Completions 的 tool loop continuation 可靠性与一致性。

## 本次设计目标

本次设计的目标是：

1. 将 provider continuation 改为 provider-native append-only raw block / item 模型
2. 保证 `tool_use` / `tool_result` 的配对与顺序完全由 provider-native 历史决定
3. 避免当前活跃 turn 的 tool loop 被 transcript 投影与 continuation 双重拼接
4. 保留历史压缩与通用 context 机制，但不再让它负责当前活跃 Anthropic tool loop continuation
5. 明确约束：当前会话中途切换 provider 不支持
6. Anthropic-compatible、OpenAI Responses、OpenAI Chat Completions 三类 continuation 采用统一的 append-only 协议思路，但各自保留 provider-native schema

## 非目标

本次不做以下事情：

- 不解决跨 provider continuation 兼容
- 不让 provider-native raw history 取代长期历史压缩体系
- 不恢复“切换 provider 继续当前 turn”的能力
- 不强行把不同 provider 的原始 block schema 统一成单一内部 message DSL

## 用户确认的前提约束

本设计建立在以下产品/架构前提上：

1. 中途换 provider 不允许发生
2. 所有支持 tool loop continuation 的 provider 都应保留 append-only raw history / item history
3. 当前活跃 turn 的 continuation 优先追求 provider 协议正确性，而不是 provider-agnostic 抽象统一

## 核心设计

### 1. 历史存储模型

对支持 continuation 的 turn，引入 provider-native raw history：

- 历史是 append-only 的 message 数组
- 每个 message 保留 provider-native `role` 与 `content`
- 已写入的历史 message 在后续 continuation 中一字不动
- 下一轮 continuation 只做“尾部追加”，不做“旧消息重组”

message 结构示意：

Anthropic-compatible 示例：

- assistant message
  - `thinking`
  - `text`
  - `tool_use`
- user message
  - `tool_result`

OpenAI Responses 示例：

- response item
  - `message`
  - `function_call`
  - `function_call_output`

OpenAI Chat Completions 示例：

- assistant message
  - `content`
  - `tool_calls`
- tool message
  - `tool_call_id`
  - `content`

### 2. `tool_use_id` 作为唯一配对锚点

所有工具执行配对以 provider-native 调用 id 为准：

- 每个 `tool_use` / `function_call` / `tool_call` 必须有稳定 id
- 每个 `tool_result` / `function_call_output` / `tool` message 必须引用对应调用 id
- continuation 不再依赖文本 summary 或 tool name 推断配对关系

### 3. 不重复编码 assistant 文本

上一轮 assistant 文本、thinking、tool_use 只保留在原始 provider-native assistant / output item 中：

- 不再把同一轮 assistant 文本重新投影为新的 user prompt
- 不再通过 transcript projector 把当前 turn 尾部 tool loop 重建一遍
- 不再同时保留“投影版尾部 tool loop”和“provider continuation 版尾部 tool loop”

### 4. 支持同一 assistant message 中多个并行 tool_use

若 provider 一次 assistant message / response item 里发出多个工具调用：

- raw assistant message / output item 中保留多个调用 block
- 对应结果统一组织在同一轮 provider-native continuation 容器中
- 结果的顺序、数量、调用 id 必须与该轮调用集合匹配

### 5. failure / interrupted 路径自动补齐 error tool_result

当工具执行失败、中断、超时、权限拒绝时：

- harness 必须为该调用合成一个 provider-native failure result
- 保证 raw history 中不会出现“悬空调用”
- 避免 provider 在下一轮 continuation 时因不完整 loop 直接 400

## 架构边界

### 长期历史 vs 当前活跃 continuation

本设计明确分离两层历史：

1. 长期历史 / session context
   - 仍可继续使用 `SessionContextProjector`
   - 仍可压缩、摘要、裁剪
   - 服务于“历史理解”

2. 当前活跃 provider-native continuation
   - 使用 provider-native raw message history
   - 不经过当前 turn tool loop 的再投影
   - 服务于“协议续写”

结论：

- 通用 context 继续存在
- 但当前活跃 tool loop continuation 不再建立在它之上

### 不支持中途换 provider

为了保证 raw history 可继续使用，明确规定：

- 一个 active turn 绑定一个 provider style
- provider style 变化只允许发生在新 turn
- 已存在 raw continuation state 的 turn，不允许切换成别的 provider 继续

## 数据模型建议

### providerStateJson 新增字段

对于支持 continuation 的 turn，`providerStateJson` 建议至少包含：

- `message_id`
- `content_blocks`
- `raw_message_history`
- `active_tool_use_ids`

对 OpenAI Responses / Chat Completions 需等价保留：

- `response_id` 或 provider-native response linkage
- 最近一轮 assistant / output 原始 items
- append-only raw continuation history
- 当前活跃调用 id 集合

其中：

- `content_blocks`：最后一条 assistant provider response 的原始 block
- `raw_message_history`：用于 append-only continuation 的 provider-native message 数组
- `active_tool_use_ids`：当前尚未补齐结果或刚结束的 tool_use 集合

### 生命周期

1. planner 首次返回 assistant message
   - 记录原始 assistant blocks
   - append 到 `raw_message_history`

2. tool 执行完成
   - 生成 provider-native user tool_result message
   - append 到 `raw_message_history`

3. 下一轮 continuation
   - 直接使用 `raw_message_history`
   - 不从 transcript 末尾重建当前 turn 的 tool loop

## 与现有代码的冲突点

### 现有冲突 1：transcript projector 会把当前 turn 尾部 tool loop 编进 messages

位置：

- `lib/services/session_context_projector.dart`
- `lib/services/model_context_item_encoder.dart`

问题：

- 当前 turn 的 `assistantToolUse` / `userToolResult` 经过投影后又会被 provider-native continuation 重复补一遍

### 现有冲突 2：AgentPlannerService 在不同 provider 分支里手动拼 continuation

位置：

- `lib/services/agent_planner_service.dart`

问题：

- 当前 continuation 仍是“从 step ledger 重新组装”
- 这不是 append-only raw history，而是再构造

### 现有冲突 3：ConfigurableHttpLLM 仍将 projected messages 与 continuationItems 混合

位置：

- `lib/models/llm/configurable_http_llm.dart`

问题：

- provider-native continuation 与 provider-agnostic transcript 同时进入 Anthropic / OpenAI payload

## 建议实现策略

### 方案

对所有 provider style 引入专用 continuation 路径：

1. 当前 turn 有 `raw_message_history` / raw continuation history 时
   - planner 请求直接基于 raw history 构造 provider-native continuation
   - 不再把当前 turn transcript 尾部 tool loop重复编码进请求

2. 当前 turn 没有 raw history 时
   - 允许回退到现有逻辑
   - 作为迁移期兼容路径

### append-only 规则

- append assistant / output provider response：原样追加
- append tool result / function_call_output / tool message：原样追加
- 不修改旧消息
- 不把旧消息“翻译”为别的角色或文本格式

## 风险

### 风险 1：双轨历史导致状态源变多

缓解：

- 明确 raw history 只服务当前活跃 Anthropic-compatible continuation
- 历史压缩仍以 transcript / summary 作为主视图

### 风险 2：失败路径忘记补 error tool_result

缓解：

- 在 harness 层统一封装 failure completion 逻辑
- 对中断 / 拒绝 / 超时补测试

### 风险 3：迁移期旧 turn 没有 raw history

缓解：

- 对旧 turn 允许 fallback
- 对新 turn 从创建时开始维护 raw history

## 验收标准

满足以下条件即认为设计成功：

1. MiniMax Anthropic-compatible continuation 不再因 `tool_result does not follow tool call` 报 400
2. DeepSeek Anthropic-compatible continuation 继续保持 `thinking` 回传正确
3. OpenAI Responses / Chat Completions continuation 不再重复拼接当前 turn 尾部 tool loop
4. 同一轮多个工具调用时，能够正确生成对应结果数组或消息
5. 工具失败 / 中断时，continuation 不会因悬空调用报 400
6. 当前 turn continuation 不再依赖 transcript 尾部 tool loop 的再投影
