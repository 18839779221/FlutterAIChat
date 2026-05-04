# 推理过程可见化实现计划

我正在使用 writing-plans skill 来创建 implementation plan。

## 目标

基于 `docs/superpowers/specs/2026-04-24-reasoning-visibility-design.md`，把三类 API 风格的 reasoning/thinking 接入到现有 assistant 消息展示链路中，并保持 Anthropic continuation 边界不被破坏。

补充约束：

- `tool_use` reasoning 必须作为时间线顺序块展示，不得被 final answer 吸收
- final-answer reasoning 才允许继续采用当前折叠展示方式

## 代码结构与职责

### 需要修改的文件

- 修改：`lib/controllers/agent_event_processor.dart`
  - 消费 `assistantReasoningDelta`
  - 将 `tool_use` reasoning 写入独立 assistant analysis 消息
  - 将 final-answer / response reasoning 写入最终 assistant message

- 修改：`lib/services/assistant_stream_output_buffer.dart`
  - 从单通道文本缓冲升级为正文 / 推理双通道缓冲
  - 提供 reasoning flush 回调

- 修改：`lib/widgets/chat_message_list.dart`
  - 将 `sourceMessage.reasoningContent` 传给 streaming / final block

- 修改：`lib/widgets/chat_blocks/streaming_response_block.dart`
  - 新增 reasoning 区域展示

- 修改：`lib/widgets/chat_blocks/final_response_block.dart`
  - 新增 reasoning 区域展示

- 可选新增：`lib/widgets/chat_blocks/reasoning_section.dart`
  - 抽取共享 reasoning 展示组件

### 需要修改的测试文件

- 修改：`test/providers/chat_controller_tool_flow_test.dart`
  - 新增 reasoning delta 更新 assistant message 的测试

- 修改：`test/widgets/chat_message_list_test.dart`
  - 新增 completed assistant message 展示 reasoning 的测试
  - 新增 generating assistant message 展示 reasoning 的测试

- 可选修改：`test/services/assistant_stream_output_buffer_test.dart`
  - 若缓冲器接口变化，则新增双通道 flush 测试

## 实施步骤

### 任务 1：先用测试锁定 send coordinator 的 reasoning 行为

**文件：**

- 修改：`test/providers/chat_controller_tool_flow_test.dart`
- 参考：`lib/controllers/chat_send_coordinator.dart`

- [ ] **Step 1: 写一个失败测试，覆盖 assistantReasoningDelta 更新当前 assistant message**

测试要点：

- 构造 turn harness 事件序列：
  - `assistantReasoningDelta`
  - `assistantTextDelta`
  - `finalAnswer`
- 断言最终 assistant message：
  - `text` 正常
  - `reasoningContent` 包含 reasoning 增量

- [ ] **Step 1.1: 写一个失败测试，覆盖 `tool_use` reasoning 保持为独立 analysis 块**

测试要点：

- 构造事件序列：
  - `assistantReasoningDelta(scope=tool_use)`
  - `toolExecutionStarted`
  - `toolResult`
  - `finalAnswer`
- 断言：
  - timeline 中存在独立 analysis block
  - 该 block 位于第一个工具展示块之前
  - final answer 的 `reasoningContent` 不包含该段 tool-use thinking

- [ ] **Step 2: 运行单测，确认当前行为失败**

运行：

```bash
fvm flutter test test/providers/chat_controller_tool_flow_test.dart --plain-name "reasoning delta"
```

预期：

- 失败，原因是 reasoning 未写入 message

### 任务 2：实现事件分发器对 reasoning 的阶段化接入

**文件：**

- 修改：`lib/controllers/agent_event_processor.dart`
- 可能修改：`lib/services/assistant_stream_output_buffer.dart`

- [ ] **Step 3: 在事件分发器中按 scope 处理 `ChatEventType.assistantReasoningDelta`**

实现要求：

- `tool_use` reasoning：
  - 不创建 final-answer placeholder
  - 以独立 assistant analysis 消息落库
  - 相邻多段 delta 继续追加到同一条 reasoning message
- final-answer / response reasoning：
  - 继续写入 runtime draft 或当前 response message
  - 最终只合并到对应 final answer 消息

- [ ] **Step 4: 若现有缓冲器不适合 reasoning，最小化扩展为双通道**

实现要求：

- 不混淆正文与 reasoning
- flush 周期与正文保持一致或近似一致
- `finish()` 时两个通道都强制 flush

- [ ] **Step 5: 运行单测，确认阶段化 reasoning 逻辑通过**

运行：

```bash
fvm flutter test test/providers/chat_controller_tool_flow_test.dart --plain-name "reasoning delta"
```

预期：

- PASS

### 任务 3：先写 widget 测试，锁定 reasoning 的可见化展示

**文件：**

- 修改：`test/widgets/chat_message_list_test.dart`
- 参考：`lib/widgets/chat_message_list.dart`

- [ ] **Step 6: 写一个失败测试，覆盖 completed assistant message 展示 reasoning**

测试要点：

- assistant message 含 `reasoningContent`
- 页面能看到“思考过程”文案
- 页面能看到 reasoning 文本

- [ ] **Step 7: 写一个失败测试，覆盖 generating assistant message 展示 reasoning**

测试要点：

- generating assistant message 含正文与 `reasoningContent`
- `StreamingResponseBlock` 仍显示正文
- reasoning 区可见

- [ ] **Step 8: 运行 widget 测试，确认当前实现失败**

运行：

```bash
fvm flutter test test/widgets/chat_message_list_test.dart --plain-name "reasoning"
```

预期：

- 失败，原因是当前 block 不渲染 reasoning

### 任务 4：实现 reasoning UI 语义分层

**文件：**

- 修改：`lib/widgets/chat_message_list.dart`
- 修改：`lib/widgets/chat_blocks/streaming_response_block.dart`
- 修改：`lib/widgets/chat_blocks/final_response_block.dart`
- 可选新增：`lib/widgets/chat_blocks/reasoning_section.dart`

- [ ] **Step 9: 在 `chat_message_list.dart` 中把 `sourceMessage.reasoningContent` 透传到 block**

- [ ] **Step 10: 给 `StreamingResponseBlock` 增加 reasoning 展示区**

实现要求：

- 显示文案：`思考过程`
- reasoning 在正文之前
- 样式弱于正文
- 仅用于 response / final-answer reasoning，不承接 `tool_use` reasoning 的回填

- [ ] **Step 11: 给 `FinalResponseBlock` 增加 reasoning 展示区**

实现要求：

- 与 streaming 语义一致
- 不改变现有 final response 主层级

- [ ] **Step 12: 如有必要，抽取共享 `ReasoningSection` 组件**

约束：

- 仅当 streaming / final 存在明显重复时再抽取
- 不做超前组件化

- [ ] **Step 13: 运行 widget 测试，确认 reasoning UI 通过**

运行：

```bash
fvm flutter test test/widgets/chat_message_list_test.dart --plain-name "reasoning"
```

预期：

- PASS

### 任务 5：做受影响回归验证

**文件：**

- 修改：已有测试文件
- 验证：Anthropic continuation 相关测试

- [ ] **Step 14: 运行 LLM / continuation 回归测试**

运行：

```bash
fvm flutter test test/models/llm/configurable_http_llm_test.dart
```

预期：

- PASS
- Anthropic continuation preserving thinking 的测试仍通过

- [ ] **Step 15: 运行受影响的发送与消息列表测试**

运行：

```bash
fvm flutter test \
  test/providers/chat_controller_tool_flow_test.dart \
  test/widgets/chat_message_list_test.dart \
  test/pages/chat_page_test.dart
```

预期：

- PASS

- [ ] **Step 16: 运行静态检查**

运行：

```bash
fvm flutter analyze
```

预期：

- 不新增新的 analyze 问题
- 仓库内既有 `info` 级问题可保留，但不能新增本次改动引入的问题

## 实现注意事项

### 注意 1：不要破坏 Anthropic continuation

- `reasoningContent` 是 UI 聚合文本
- `providerState.content_blocks` 是协议续传原始结构
- 两者不能互相替代

### 注意 2：不要恢复 reasoning 开关

- 本次展示逻辑是 provider-driven
- 不是用户显式开启的模式

### 注意 3：不要引入新的 timeline message 类型

- `tool_use` reasoning 允许作为普通 assistant analysis 消息进入时间线
- 但不要为它再发明新的专用消息 role / contentType / 第二套状态机
- 仍然沿用当前 assistant message / block / projection 体系

### 注意 4：不要让 final answer 回退吸收 tool-use reasoning

- `tool_use` reasoning 一旦进入时间线，就应视为该阶段已经定稿的 UI 事实
- final answer 只能消费自身阶段的 reasoning
- 不允许通过 fallback 再把 `tool_use` reasoning 填回最终答复

## 建议提交粒度

- 提交 1：`test: cover reasoning deltas in send flow`
- 提交 2：`feat: surface assistant reasoning in message rendering`
- 提交 3：`test: add reasoning visibility widget coverage`

## 完成定义

满足以下条件即完成：

- `assistantReasoningDelta` 能更新当前 assistant message
- assistant message 的 `reasoningContent` 能在 UI 中看到
- `tool_use` reasoning 能在工具块前按时间顺序看到
- streaming / completed 两种状态都支持显示 reasoning
- Anthropic continuation 相关测试仍通过
- 受影响测试通过，analyze 不新增问题
