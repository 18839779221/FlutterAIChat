# Provider-Native Append-Only Continuation 实现计划

我正在使用 writing-plans skill 来创建 implementation plan。

## 目标

基于 `docs/superpowers/specs/2026-04-24-anthropic-compatible-append-only-continuation-design.md`，将 Anthropic-compatible、OpenAI Responses、OpenAI Chat Completions 的 continuation 改为 provider-native append-only history 模型，避免 transcript 投影与 provider-native continuation 重复拼接。

## 涉及文件与职责

### 需要修改

- `lib/models/chat_turn.dart`
  - 承载 `providerStateJson` 中新的 raw history 字段访问

- `lib/services/agent_planner_service.dart`
  - 不再为当前活跃 turn 从 step ledger 重组 provider-native 尾部 tool loop
  - 改为优先消费 raw history，仅在兼容回退路径里补 continuation items

- `lib/models/llm/configurable_http_llm.dart`
  - Anthropic-compatible / OpenAI planner 请求优先使用 raw history
  - 避免 projected transcript 与 provider continuation 双重拼接

- `lib/models/llm/tool_loop/anthropic_messages_tool_loop_adapter.dart`
  - 解析 decision 时记录原始 assistant provider message

- `lib/models/llm/tool_loop/`
  - 如 OpenAI continuation 需要额外 adapter / helper，统一补 provider-native raw history 记录能力

- `lib/services/turn_harness.dart`
  - 在成功 / 失败 / 中断 / 拒绝路径里维护 append-only raw history
  - 必要时补 provider-native error result

### 需要新增或补充测试

- `test/models/llm/configurable_http_llm_test.dart`
  - Anthropic / OpenAI continuation 使用 raw history，不重复拼接 transcript 尾部 tool loop
  - 并行 tool_use + tool_result 顺序测试

- `test/services/agent_planner_service_test.dart`
  - providerContinuationItems / raw history 的生成与消费测试

- `test/services/turn_harness_test.dart`
  - failure / interruption / denial 时补 provider-native error result

## 执行步骤

### 任务 1：先用测试锁定“当前逻辑会重复拼接尾部 tool loop”

- [ ] Step 1: 在 `test/models/llm/configurable_http_llm_test.dart` 增加失败测试
  - 构造 projected transcript 中已有 assistantToolUse + userToolResult
  - 分别覆盖 anthropic / chat completions / responses continuation
  - 断言请求中不应重复出现同一轮尾部 tool loop

- [ ] Step 2: 运行该单测并确认失败

运行：

```bash
fvm flutter test test/models/llm/configurable_http_llm_test.dart --plain-name "continuation"
```

### 任务 2：为各 provider turn 引入 raw history continuation 读取路径

- [ ] Step 3: 在 `anthropic_messages_tool_loop_adapter.dart` 中确保保留原始 assistant provider message

- [ ] Step 4: 在 `configurable_http_llm.dart` 中新增 provider-native raw history 优先路径
  - 若 providerState 含 `raw_message_history`
  - 直接用该数组作为 continuation 基础
  - 不再将当前 turn 尾部 projected tool loop 混入
  - OpenAI Responses / Chat Completions 也采用同一原则

- [ ] Step 5: 运行失败测试，确认通过

### 任务 3：在 harness 层维护 append-only raw history

- [ ] Step 6: 在 `turn_harness.dart` 中为 provider-native continuation turn 记录 assistant / output 原始 message

- [ ] Step 7: 工具成功后 append provider-native result raw item / message

- [ ] Step 8: 工具失败 / 拒绝 / 中断 / 超时时 append provider-native error result raw item / message

- [ ] Step 9: 为上述路径补测试

运行：

```bash
fvm flutter test test/services/turn_harness_test.dart --plain-name "tool_result"
```

### 任务 4：支持同一轮多个并行工具调用

- [ ] Step 10: 在 Anthropic continuation 生成逻辑中支持一条 assistant message 对应多个 tool_use

- [ ] Step 11: 在 OpenAI / Anthropic continuation 容器中支持多个结果 block / item

- [ ] Step 12: 补并行 tool_use/tool_result 顺序测试

### 任务 5：回归验证

- [ ] Step 13: 跑 LLM continuation 测试

```bash
fvm flutter test test/models/llm/configurable_http_llm_test.dart
```

- [ ] Step 14: 跑 planner / harness 回归测试

```bash
fvm flutter test \
  test/services/agent_planner_service_test.dart \
  test/services/turn_harness_test.dart
```

- [ ] Step 15: 跑受影响页面与发送链路测试

```bash
fvm flutter test \
  test/providers/chat_controller_tool_flow_test.dart \
  test/widgets/chat_message_list_test.dart \
  test/pages/chat_page_test.dart
```

- [ ] Step 16: 运行 analyze

```bash
fvm flutter analyze
```

## 关键约束

- 不支持当前 active turn 中途换 provider
- 当前 turn continuation 的尾部不再走 transcript 再投影
- 必须保留 `tool_use_id` 作为唯一配对锚点
- failure path 必须补齐 provider-native error result，不能留下悬空调用

## 完成定义

- MiniMax Anthropic-compatible `400 tool call result does not follow tool call` 被修复
- Anthropic / DeepSeek 的 thinking continuation 不回归
- OpenAI Responses / Chat Completions 也切到 append-only raw history continuation 思路
- append-only raw history 生效
- 当前 turn tool loop 不再重复拼接
