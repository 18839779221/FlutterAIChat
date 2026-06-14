# Responses Continuation 专属拼接 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不升级 `openai_dart`、不改动 `chat/completions` / `anthropic/messages` 的前提下，为 `responses` 风格引入专属 continuation builder，避免把 raw `output` 直接错误拼回 request `input`。

**Architecture:** 保留当前 `SessionContextService -> RawAssistantCarrier -> SdkResponsesAdapter -> OpenAiResponsesRuntime` 的总链路，不改数据库和上层 turn loop。仅在 `SdkResponsesAdapter` 内部将 `responses` planner replay 从 verbatim raw splice 改为 canonical continuation item 构造；历史 raw snapshot 继续保留，用于 UI / 调试 / 后续演进。

**Tech Stack:** Flutter, Dart, flutter_test, `openai_dart 5.0.0`, 当前 Responses SDK-first adapter/runtime

---

## 文件地图

**核心实现**

- Modify: `lib/models/llm/adapters/sdk_responses_adapter.dart`

**适配器测试**

- Modify: `test/models/llm/adapters/responses_roundtrip_test.dart`

**高层回归测试**

- Modify: `test/models/llm/configurable_http_llm_test.dart`

**文档**

- Create: `docs/superpowers/specs/2026-06-14-responses-continuation-specialization-design.md`
- Create: `docs/superpowers/plans/2026-06-14-responses-continuation-specialization-implementation-plan.md`

### Task 1: 固化当前 `responses` continuation 崩溃测试

**Files:**
- Modify: `test/models/llm/adapters/responses_roundtrip_test.dart`
- Modify: `test/models/llm/configurable_http_llm_test.dart`

- [ ] **Step 1: 在 `responses_roundtrip_test.dart` 写失败测试**

新增一个 `SdkResponsesAdapter.buildPlannerPayloadFromCarriers()` 场景：

- `RawAssistantCarrier.rawJson['output']` 包含：
  - `reasoning`
  - `message`
  - `function_call`
- 再追加一个 `SyntheticCarrier.toolResult`

断言：

- payload `input` 中不包含 `type=reasoning`
- 仍包含 `message`
- 仍包含 `function_call`
- 仍包含 `function_call_output`

- [ ] **Step 2: 在 `configurable_http_llm_test.dart` 写失败测试**

新增一个 `responses` planner continuation 场景，模拟：

- 上一轮 `providerState.raw_assistant_message.output` 中存在 `reasoning`
- 本轮继续 planner 请求

断言：

- `adapter.buildPlannerRequestSpecFromCarriers(...)` 不抛 `FormatException`
- 最终 request body 不包含 `type=reasoning`

- [ ] **Step 3: 运行聚焦测试，确认当前实现失败**

Run:

```bash
flutter test test/models/llm/adapters/responses_roundtrip_test.dart test/models/llm/configurable_http_llm_test.dart
```

Expected:

- FAIL
- 失败点集中在 `reasoning` 仍进入 `input` 或 `CreateResponseRequest.fromJson` 抛异常

- [ ] **Step 4: 提交测试基线**

```bash
git add test/models/llm/adapters/responses_roundtrip_test.dart test/models/llm/configurable_http_llm_test.dart
git commit -m "test: cover responses continuation builder"
```

### Task 2: 在 `SdkResponsesAdapter` 中实现专属 continuation builder

**Files:**
- Modify: `lib/models/llm/adapters/sdk_responses_adapter.dart`
- Modify: `test/models/llm/adapters/responses_roundtrip_test.dart`

- [ ] **Step 1: 新增 `responses` raw output item 解释函数**

在 `SdkResponsesAdapter` 中增加专用 helper，例如：

```dart
Iterable<Map<String, dynamic>> _buildReplayableInputItemsFromRawOutput(
  Map<String, dynamic> rawJson,
)
```

职责：

- 读取 `rawJson['output']`
- 仅把 continuation 所需的 canonical items 转成 request input items

- [ ] **Step 2: 实现 `message` continuation 映射**

将 raw output 中的 assistant `message` 转成 request input item：

```json
{
  "type": "message",
  "role": "assistant",
  "content": [
    {"type": "output_text", "text": "..."}
  ]
}
```

要求：

- 仅保留 `output_text`
- 丢弃非文本输出部分
- 空文本 message 不进入结果

- [ ] **Step 3: 实现 `function_call` continuation 映射**

将 raw output 中的 `function_call` 转成 request input item：

```json
{
  "type": "function_call",
  "call_id": "call_1",
  "name": "search",
  "arguments": "{\"q\":\"x\"}"
}
```

要求：

- `call_id`、`name`、`arguments` 缺失时丢弃该 item
- 保持当前 tool pairing 语义不变

- [ ] **Step 4: 显式跳过 `reasoning` 与未知 item**

规则：

- `reasoning`：跳过，不进入 request `input`
- 未知 `type`：跳过，并打 debug log

要求：

- 不抛异常
- 不影响其他 item 的 replay

- [ ] **Step 5: 将 `RawAssistantCarrier` 分支接到新 builder**

修改 `buildPlannerPayloadFromCarriers()` 中：

```dart
case RawAssistantCarrier(:final rawJson):
```

不再直接：

```dart
input.add(Map<String, dynamic>.from(item));
```

而是：

```dart
input.addAll(_buildReplayableInputItemsFromRawOutput(rawJson));
```

- [ ] **Step 6: 运行适配器聚焦测试**

Run:

```bash
flutter test test/models/llm/adapters/responses_roundtrip_test.dart
```

Expected:

- PASS

- [ ] **Step 7: 提交实现**

```bash
git add lib/models/llm/adapters/sdk_responses_adapter.dart test/models/llm/adapters/responses_roundtrip_test.dart
git commit -m "feat: specialize responses continuation builder"
```

### Task 3: 回归 `ConfigurableHttpLLM` 的 responses planner 链路

**Files:**
- Modify: `test/models/llm/configurable_http_llm_test.dart`

- [ ] **Step 1: 扩展高层回归断言**

确保 `responses` planner continuation 在有历史 `reasoning` snapshot 时：

- 不再抛 `FormatException`
- request body 中不包含 `type=reasoning`
- 若存在历史 `function_call` + `toolResult`，仍能保留 tool continuation 链

- [ ] **Step 2: 运行高层聚焦测试**

Run:

```bash
flutter test test/models/llm/configurable_http_llm_test.dart
```

Expected:

- PASS

- [ ] **Step 3: 提交回归测试**

```bash
git add test/models/llm/configurable_http_llm_test.dart
git commit -m "test: verify responses planner replay stability"
```

### Task 4: 运行最小验证并检查非目标未被波及

**Files:**
- No code changes expected

- [ ] **Step 1: 运行本轮全部相关测试**

Run:

```bash
flutter test test/models/llm/adapters/responses_roundtrip_test.dart test/models/llm/configurable_http_llm_test.dart
```

Expected:

- PASS

- [ ] **Step 2: 运行聚焦 analyze**

Run:

```bash
flutter analyze lib/models/llm/adapters/sdk_responses_adapter.dart test/models/llm/adapters/responses_roundtrip_test.dart test/models/llm/configurable_http_llm_test.dart
```

Expected:

- PASS

- [ ] **Step 3: 检查非目标未被改动**

确认：

- 未修改 `pubspec.yaml` / `pubspec.lock`
- 未修改 `sdk_chat_completions_adapter.dart`
- 未修改 `sdk_anthropic_messages_adapter.dart`

- [ ] **Step 4: 提交收尾**

```bash
git add lib/models/llm/adapters/sdk_responses_adapter.dart test/models/llm/adapters/responses_roundtrip_test.dart test/models/llm/configurable_http_llm_test.dart docs/superpowers/specs/2026-06-14-responses-continuation-specialization-design.md docs/superpowers/plans/2026-06-14-responses-continuation-specialization-implementation-plan.md
git commit -m "docs: plan responses continuation specialization"
```

## 备注

本计划刻意不包含以下动作：

- 不升级 `openai_dart`
- 不引入统一 replay strategy 抽象
- 不接入 `previous_response_id`
- 不改造 `chat/completions` / `anthropic/messages`

如果在执行中发现当前 SDK 即使在“仅 replay `message + function_call + function_call_output`”的前提下仍存在新的 request-model 阻塞，应停止实现，回到证据分析，再决定是否需要单独评估 SDK 升级。
