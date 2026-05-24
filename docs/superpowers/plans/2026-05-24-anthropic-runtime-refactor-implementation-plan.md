# Anthropic Messages Runtime 改造 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `anthropic messages` 从共享 `HttpJsonProtocolRuntime` 迁移到独立的 Anthropic runtime 边界，并让非流与 planner streaming 都进入统一 runtime 主链路，保持现有 transcript/tool-loop 语义不变。

**Architecture:** 保持 `AnthropicMessagesAdapter` 与 `AnthropicMessagesToolLoopAdapter` 为语义层；新增 `AnthropicMessagesRuntime + AnthropicStreamEventAdapter` 作为执行层；`AnthropicMessagesRuntime` 的非流执行底层使用 `anthropic_sdk_dart`，planner streaming 使用 “HTTP SSE -> 最小兼容归一化 -> SDK typed event -> stream adapter” 主路径；`ConfigurableHttpLLM` 继续只做高层编排与 runtime dispatch。

**Tech Stack:** Flutter 3.35.7, Dart, `http`, `anthropic_sdk_dart`, `flutter_test`, existing planner/tool-loop/live integration suites

---

## Task 1: 建立 Anthropic 专属 streaming adapter

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/models/llm/runtime/anthropic_stream_event_adapter.dart`
- Test: `test/models/llm/runtime/anthropic_stream_event_adapter_test.dart`
- Modify: `lib/models/llm/api_stream_parser.dart`（如需要仅保留过渡调用或抽出 helper）

- [ ] **Step 1: 先写失败测试，覆盖 anthropic planner streaming 关键语义**

至少覆盖：

```dart
test('adapts anthropic tool_use chunks into planner tool call deltas');
test('preserves whitespace in anthropic input_json_delta chunks');
test('captures thinking signature into provider state');
test('ignores ping/keepalive chunks without terminating the stream');
```

- [ ] **Step 2: 跑测试确认失败**

Run:
```bash
flutter test test/models/llm/runtime/anthropic_stream_event_adapter_test.dart
```

- [ ] **Step 3: 写最小实现**

实现要求：

- 解析 anthropic SSE 行
- 输出 `StreamingPlannerChunk`
- 保持现有 keepalive / trailing garbage 容错语义
- thinking signature 继续进入 snapshot providerState

- [ ] **Step 4: 跑测试确认通过**

Run:
```bash
flutter test test/models/llm/runtime/anthropic_stream_event_adapter_test.dart
```

## Task 2: 建立 Anthropic 专属 runtime

**Files:**
- Create: `lib/models/llm/runtime/anthropic_messages_runtime.dart`
- Test: `test/models/llm/runtime/anthropic_messages_runtime_test.dart`
- Modify: `lib/models/llm/runtime/http_json_protocol_runtime.dart`（按需要收缩为通用 helper 或保持兜底）

- [ ] **Step 1: 先写失败测试，覆盖非流/流式/非 SSE fallback**

至少覆盖：

```dart
test('executes anthropic json request through dedicated runtime');
test('streams anthropic planner chunks through dedicated runtime');
test('falls back to non-stream json when response is not text/event-stream');
```

- [ ] **Step 2: 跑测试确认失败**

Run:
```bash
flutter test test/models/llm/runtime/anthropic_messages_runtime_test.dart
```

- [ ] **Step 3: 写最小实现**

实现要求：

- runtime 接收 `JsonProtocolRequestSpec`
- 使用 `anthropic_sdk_dart` 的 `AnthropicClient` / `client.messages.create(...)`
- 非流请求走 anthropic endpoint
- 流式请求保留原始 HTTP + SSE + anthropic parser 的兼容主路径
- `AnthropicStreamEventAdapter` 作为 anthropic typed streaming 到统一 planner chunk 的正式边界
- 非 SSE 情况返回 `nonStreamingFallbackJson`

- [ ] **Step 4: 跑测试确认通过**

Run:
```bash
flutter test test/models/llm/runtime/anthropic_messages_runtime_test.dart
```

## Task 3: 将 registry 中的 anthropic 路径切到专属 runtime

**Files:**
- Modify: `lib/models/llm/configurable_http_llm.dart`
- Modify: `test/models/llm/configurable_http_llm_test.dart`

- [ ] **Step 1: 先写失败测试，验证 anthropic planner / side-task 调用走专属 runtime**

至少覆盖：

```dart
test('anthropic planner streaming uses anthropic runtime');
test('anthropic summary path uses anthropic runtime execute');
```

- [ ] **Step 2: 跑测试确认失败**

Run:
```bash
flutter test test/models/llm/configurable_http_llm_test.dart
```

- [ ] **Step 3: 写最小实现**

实现要求：

- runtime registry 中的 anthropic 项替换为 `AnthropicMessagesRuntime`
- 不把 anthropic transport 分支重新写回 `ConfigurableHttpLLM`
- 继续保留统一 trace / retry / timeout / accumulator 接线

- [ ] **Step 4: 跑测试确认通过**

Run:
```bash
flutter test test/models/llm/configurable_http_llm_test.dart
```

## Task 4: 保护 Anthropic 语义层 roundtrip 不回归

**Files:**
- Modify: `test/models/llm/adapters/anthropic_messages_adapter_test.dart`
- Modify: `test/models/llm/adapters/anthropic_messages_roundtrip_test.dart`
- Modify: `test/services/agent_planner_service_test.dart`（如需要补充更贴近 runtime 的场景）

- [ ] **Step 1: 补失败测试，确认新的 runtime 拆分不影响 raw assistant / continuation 语义**

重点覆盖：

- thinking + text + tool_use raw assistant 还原
- ask-user continuation transcript 回放
- tool_result 分组续写

- [ ] **Step 2: 跑相关测试**

Run:
```bash
flutter test test/models/llm/adapters/anthropic_messages_adapter_test.dart test/models/llm/adapters/anthropic_messages_roundtrip_test.dart test/services/agent_planner_service_test.dart
```

- [ ] **Step 3: 仅做必要修复**

要求：

- 优先修复 runtime boundary 对语义层的接口影响
- 不引入新的 anthropic 特判 prompt patch
- 不修改 turn ledger / transcript 结构

- [ ] **Step 4: 复跑相关测试确认通过**

Run:
```bash
flutter test test/models/llm/adapters/anthropic_messages_adapter_test.dart test/models/llm/adapters/anthropic_messages_roundtrip_test.dart test/services/agent_planner_service_test.dart
```

## Task 5: 跑 Anthropic 核心回归与 live 验证

**Files:**
- Modify: `README.md`（如需要补充 anthropic runtime 结构）
- Modify: `AGENTS.md`（如需要补充 anthropic runtime 约束）

- [ ] **Step 1: 跑核心单测回归**

Run:
```bash
flutter test test/models/llm/runtime test/models/llm/configurable_http_llm_test.dart test/models/llm/adapters/anthropic_messages_adapter_test.dart test/models/llm/adapters/anthropic_messages_roundtrip_test.dart
```

- [ ] **Step 2: 跑 anthropic headless live 集成测试**

Run:
```bash
HEADLESS_LIVE_PROVIDER_ANTHROPIC=deepseek-anthropic flutter test --tags live-headless-agent test/integration/chat_send_live/chat_send_live_anthropic_test.dart
```

可选再跑：

```bash
HEADLESS_LIVE_PROVIDER_ANTHROPIC=minimax-anthropic flutter test --tags live-headless-agent test/integration/chat_send_live/chat_send_live_anthropic_test.dart
```

说明：

- `deepseek-anthropic` 作为 anthropic style 的强能力验证 provider，继续覆盖 structured ask-user resume。
- `minimax-anthropic` 主要用于验证 anthropic style 的 continuation、tool round-trip、mixed success/failure 等链路。
- 如果 `minimax-anthropic` 在 ask-user 场景回退为普通 assistant 文本提问，应视为具体 provider 的交互工具遵循度差异，而不是 `TurnHarness` / transcript / provider adapter 公共架构回归。
- 同理，如果某些 anthropic-compatible provider 在写操作场景不稳定产出 `assistantToolConfirmation`，应把它视为 provider 的 structured interaction 能力差异；公共架构仍以 shared confirmation checkpoint 为标准语义。
- 该“structured checkpoint 可选、续链契约刚性”表达应优先沉到共享 live assertion/helper 层，而不是散落为各 API style 各自的测试分支。
- 更进一步，live 测试应把这类差异沉成 provider capability matrix（如 `required` / `opportunistic`），而不是继续扩散为多个布尔特判。
- provider selection 与 provider capability matrix 应分离：前者负责挑选 provider，后者负责声明该 provider 在 live 交互 checkpoint 上的预期。
- capability matrix 不应只记录“出过问题的 provider”；当前默认 / 首选 provider 也应显式登记，这样矩阵才是完整声明而不是例外清单。

- [ ] **Step 3: 如有必要更新 README / AGENTS**

更新方向：

- anthropic 也已进入独立 runtime 边界
- live 验证建议继续使用 headless live suites

- [ ] **Step 4: 复跑最终验证**

Run:
```bash
flutter test test/models/llm
```

## 完成标准

- `ApiStyle.anthropicMessages` 不再依赖共享 `HttpJsonProtocolRuntime` 作为主实现
- `ConfigurableHttpLLM` 不新增 anthropic transport / SSE 特判
- anthropic roundtrip / continuation / ask-user 语义保持不变
- anthropic live headless suite 至少有一个真实 provider 验证通过
- spec/plan 与当前 anthropic runtime 稳态一致，不误导后续把兼容归一化层理解成旧 raw parser 主路径
