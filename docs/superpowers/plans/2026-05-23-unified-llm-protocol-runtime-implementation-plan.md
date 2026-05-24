# 统一 LLM 协议运行时内核 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `chat completions` 与 `responses` 迁移到统一 SDK-first 协议运行时内核，同时把 `anthropic messages` 接入同一 runtime 抽象边界，为下一轮 anthropic 改造清理执行链路。

**Architecture:** 引入 `ProtocolRequestSpec + ProtocolExecutionRuntime + ProtocolStreamEventAdapter` 三层边界。`ConfigurableHttpLLM` 退回为高层编排器；`chat completions` 和 `responses` 通过 `openai_dart` runtime 执行；`anthropic` 先以 HTTP-native runtime 接入同一 registry。

**Tech Stack:** Flutter 3.35.7, Dart, `openai_dart`, `flutter_test`, existing planner/tool-loop runtime

---

### Task 1: 统一 runtime 抽象骨架

**Files:**
- Create: `lib/models/llm/runtime/protocol_request_spec.dart`
- Create: `lib/models/llm/runtime/protocol_execution_runtime.dart`
- Create: `lib/models/llm/runtime/protocol_runtime_registry.dart`
- Test: `test/models/llm/runtime/protocol_runtime_registry_test.dart`

- [ ] **Step 1: 写失败测试，定义 runtime registry 的选择行为**

```dart
test('registry resolves chat completions runtime for chat style', () {
  final registry = ProtocolRuntimeRegistry(
    runtimes: {
      ApiStyle.chatCompletions: fakeChatRuntime,
      ApiStyle.responses: fakeResponsesRuntime,
      ApiStyle.anthropicMessages: fakeAnthropicRuntime,
    },
  );

  expect(
    registry.runtimeFor(ApiStyle.chatCompletions),
    same(fakeChatRuntime),
  );
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `fvm flutter test test/models/llm/runtime/protocol_runtime_registry_test.dart`
Expected: FAIL with missing runtime classes

- [ ] **Step 3: 写最小实现**

实现：
- `ProtocolRequestSpec` sealed hierarchy
- `ProtocolExecutionRuntime` interface
- `ProtocolRuntimeRegistry.runtimeFor(ApiStyle)`

- [ ] **Step 4: 运行测试确认通过**

Run: `fvm flutter test test/models/llm/runtime/protocol_runtime_registry_test.dart`
Expected: PASS

- [ ] **Step 5: 提交这一小步**

```bash
git add lib/models/llm/runtime/protocol_request_spec.dart lib/models/llm/runtime/protocol_execution_runtime.dart lib/models/llm/runtime/protocol_runtime_registry.dart test/models/llm/runtime/protocol_runtime_registry_test.dart
git commit -m "feat: add llm protocol runtime abstractions"
```

### Task 2: adapter 输出 request spec 而不是直接绑死 JSON

**Files:**
- Modify: `lib/models/llm/adapters/api_style_adapter.dart`
- Modify: `lib/models/llm/adapters/sdk_chat_completions_adapter.dart`
- Modify: `lib/models/llm/adapters/responses_adapter.dart`
- Modify: `lib/models/llm/adapters/anthropic_messages_adapter.dart`
- Test: `test/models/llm/adapters/sdk_chat_completions_adapter_test.dart`
- Test: `test/models/llm/adapters/responses_adapter_test.dart`

- [ ] **Step 1: 为 chat completions request spec 写失败测试**

```dart
test('builds chat completions request spec with sdk request', () {
  final spec = adapter.buildPlannerRequestSpecFromCarriers(...);
  expect(spec, isA<ChatCompletionsRequestSpec>());
});
```

- [ ] **Step 2: 为 responses request spec 写失败测试**

```dart
test('builds responses request spec with create response request', () {
  final spec = adapter.buildPlannerRequestSpecFromCarriers(...);
  expect(spec, isA<ResponsesRequestSpec>());
});
```

- [ ] **Step 3: 运行测试确认失败**

Run: `fvm flutter test test/models/llm/adapters/sdk_chat_completions_adapter_test.dart test/models/llm/adapters/responses_adapter_test.dart`
Expected: FAIL because request spec methods/types do not exist

- [ ] **Step 4: 写最小实现**

实现：
- `ApiStyleAdapter` 新增 `buildChatRequestSpec` / `buildPlannerRequestSpecFromCarriers`
- `SdkChatCompletionsAdapter` 产出 typed `ChatCompletionCreateRequest`
- `ResponsesAdapter` 先升级为 `SdkResponsesAdapter` 或直接在现有文件中产出 typed `CreateResponseRequest`
- `AnthropicMessagesAdapter` 产出 `JsonProtocolRequestSpec`

- [ ] **Step 5: 运行测试确认通过**

Run: `fvm flutter test test/models/llm/adapters/sdk_chat_completions_adapter_test.dart test/models/llm/adapters/responses_adapter_test.dart`
Expected: PASS

- [ ] **Step 6: 提交这一小步**

```bash
git add lib/models/llm/adapters/api_style_adapter.dart lib/models/llm/adapters/sdk_chat_completions_adapter.dart lib/models/llm/adapters/responses_adapter.dart lib/models/llm/adapters/anthropic_messages_adapter.dart test/models/llm/adapters/sdk_chat_completions_adapter_test.dart test/models/llm/adapters/responses_adapter_test.dart
git commit -m "refactor: build typed protocol request specs"
```

### Task 3: chat completions SDK runtime

**Files:**
- Create: `lib/models/llm/runtime/openai_chat_completions_runtime.dart`
- Create: `lib/models/llm/runtime/chat_completions_stream_event_adapter.dart`
- Modify: `lib/models/llm/adapters/sdk_stream_adapter.dart`
- Test: `test/models/llm/runtime/openai_chat_completions_runtime_test.dart`

- [ ] **Step 1: 写失败测试，验证非流执行走 SDK client**

```dart
test('executes chat completions request through sdk runtime', () async {
  final result = await runtime.execute(spec, runtimeConfig);
  expect(result.rawResponseJson['choices'], isNotEmpty);
});
```

- [ ] **Step 2: 写失败测试，验证流式事件走 SDK event adapter**

```dart
test('adapts chat completions sdk stream events into planner chunks', () async {
  final chunks = await adapter.adapt(stream).toList();
  expect(chunks.where((c) => c.type == StreamingPlannerChunkType.contentDelta), isNotEmpty);
});
```

- [ ] **Step 3: 运行测试确认失败**

Run: `fvm flutter test test/models/llm/runtime/openai_chat_completions_runtime_test.dart`
Expected: FAIL because runtime classes do not exist

- [ ] **Step 4: 写最小实现**

实现：
- SDK client builder
- `execute()` 调 `client.chat.completions.create`
- `streamExecute()` 调 `client.chat.completions.createStream`
- typed event -> `StreamingPlannerChunk`

- [ ] **Step 5: 运行测试确认通过**

Run: `fvm flutter test test/models/llm/runtime/openai_chat_completions_runtime_test.dart`
Expected: PASS

- [ ] **Step 6: 提交这一小步**

```bash
git add lib/models/llm/runtime/openai_chat_completions_runtime.dart lib/models/llm/runtime/chat_completions_stream_event_adapter.dart lib/models/llm/adapters/sdk_stream_adapter.dart test/models/llm/runtime/openai_chat_completions_runtime_test.dart
git commit -m "feat: add sdk chat completions runtime"
```

### Task 4: responses SDK runtime

**Files:**
- Create: `lib/models/llm/runtime/openai_responses_runtime.dart`
- Create: `lib/models/llm/runtime/responses_stream_event_adapter.dart`
- Create: `lib/models/llm/adapters/sdk_responses_adapter.dart`
- Test: `test/models/llm/runtime/openai_responses_runtime_test.dart`
- Test: `test/models/llm/adapters/sdk_responses_adapter_test.dart`

- [ ] **Step 1: 写失败测试，验证 responses 请求走 typed request**

```dart
test('builds create response request for planner carriers', () {
  final spec = adapter.buildPlannerRequestSpecFromCarriers(...);
  expect(spec, isA<ResponsesRequestSpec>());
});
```

- [ ] **Step 2: 写失败测试，验证 responses streaming 走 SDK events**

```dart
test('adapts responses sdk events into planner chunks', () async {
  final chunks = await adapter.adapt(events).toList();
  expect(chunks, isNotEmpty);
});
```

- [ ] **Step 3: 运行测试确认失败**

Run: `fvm flutter test test/models/llm/runtime/openai_responses_runtime_test.dart test/models/llm/adapters/sdk_responses_adapter_test.dart`
Expected: FAIL because sdk responses runtime/adapter do not exist

- [ ] **Step 4: 写最小实现**

实现：
- `SdkResponsesAdapter`
- `OpenAiResponsesRuntime.execute`
- `OpenAiResponsesRuntime.streamExecute`
- `ResponsesStreamEventAdapter`

- [ ] **Step 5: 运行测试确认通过**

Run: `fvm flutter test test/models/llm/runtime/openai_responses_runtime_test.dart test/models/llm/adapters/sdk_responses_adapter_test.dart`
Expected: PASS

- [ ] **Step 6: 提交这一小步**

```bash
git add lib/models/llm/runtime/openai_responses_runtime.dart lib/models/llm/runtime/responses_stream_event_adapter.dart lib/models/llm/adapters/sdk_responses_adapter.dart test/models/llm/runtime/openai_responses_runtime_test.dart test/models/llm/adapters/sdk_responses_adapter_test.dart
git commit -m "feat: add sdk responses runtime"
```

### Task 5: anthropic 接入统一 runtime registry

**Files:**
- Create: `lib/models/llm/runtime/http_json_protocol_runtime.dart`
- Modify: `lib/models/llm/api_stream_parser.dart`
- Test: `test/models/llm/runtime/http_json_protocol_runtime_test.dart`

- [ ] **Step 1: 写失败测试，验证 anthropic 能通过 json runtime 执行**

```dart
test('executes json protocol runtime for anthropic request specs', () async {
  final result = await runtime.execute(spec, runtimeConfig);
  expect(result.rawResponseJson, isNotEmpty);
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `fvm flutter test test/models/llm/runtime/http_json_protocol_runtime_test.dart`
Expected: FAIL because json runtime does not exist

- [ ] **Step 3: 写最小实现**

实现：
- 用现有 `http.Client` 执行 `JsonProtocolRequestSpec`
- 把 anthropic streaming parser 作为临时 JSON runtime stream adapter

- [ ] **Step 4: 运行测试确认通过**

Run: `fvm flutter test test/models/llm/runtime/http_json_protocol_runtime_test.dart`
Expected: PASS

- [ ] **Step 5: 提交这一小步**

```bash
git add lib/models/llm/runtime/http_json_protocol_runtime.dart lib/models/llm/api_stream_parser.dart test/models/llm/runtime/http_json_protocol_runtime_test.dart
git commit -m "refactor: route anthropic through shared json runtime"
```

### Task 6: 收缩 ConfigurableHttpLLM 到高层编排器

**Files:**
- Modify: `lib/models/llm/configurable_http_llm.dart`
- Test: `test/models/llm/configurable_http_llm_test.dart`

- [ ] **Step 1: 写失败测试，验证 chat completions planner streaming 不再依赖 raw SSE parser 主路径**

```dart
test('chat completions planner streaming uses protocol runtime', () async {
  await llm.planTurnDecision(...);
  expect(fakeChatRuntime.streamExecuteCalls, 1);
});
```

- [ ] **Step 2: 写失败测试，验证 responses side-task 走 runtime.execute**

```dart
test('responses side task uses protocol runtime execute', () async {
  await llm.summarizeConversation(messages);
  expect(fakeResponsesRuntime.executeCalls, 1);
});
```

- [ ] **Step 3: 运行测试确认失败**

Run: `fvm flutter test test/models/llm/configurable_http_llm_test.dart`
Expected: FAIL because `ConfigurableHttpLLM` still performs inline HTTP/SSE work

- [ ] **Step 4: 写最小实现**

实现：
- runtime registry 注入
- planner 流式调用转到 `runtime.streamExecute`
- planner 非流 fallback 转到 `runtime.execute`
- side-task 调用转到 `runtime.execute`
- 保留统一 trace / retry / timeout / accumulator / raw assistant capture

- [ ] **Step 5: 运行测试确认通过**

Run: `fvm flutter test test/models/llm/configurable_http_llm_test.dart`
Expected: PASS

- [ ] **Step 6: 提交这一小步**

```bash
git add lib/models/llm/configurable_http_llm.dart test/models/llm/configurable_http_llm_test.dart
git commit -m "refactor: move llm execution to protocol runtimes"
```

### Task 7: 回归与 live 验证

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Test: `test/models/llm/configurable_http_llm_test.dart`
- Test: `test/models/llm/adapters/sdk_chat_completions_adapter_test.dart`
- Test: `test/models/llm/adapters/sdk_responses_adapter_test.dart`
- Test: `test/models/llm/runtime/`

- [ ] **Step 1: 更新文档描述新的 runtime 边界**

更新：
- `README.md`
- `AGENTS.md`

- [ ] **Step 2: 跑核心单测**

Run: `fvm flutter test test/models/llm/runtime test/models/llm/adapters/sdk_chat_completions_adapter_test.dart test/models/llm/adapters/sdk_responses_adapter_test.dart test/models/llm/configurable_http_llm_test.dart`
Expected: PASS

- [ ] **Step 3: 跑 responses mocked contract 套件**

Run: `fvm flutter test test/models/llm/configurable_http_llm_test.dart`
Expected: PASS

- [ ] **Step 4: 跑 live contract**

Run: `bash scripts/run_live_llm_contract_tests.sh minimax-openai`
Expected: PASS for chat completions style provider coverage

- [ ] **Step 5: 跑至少一个 responses provider live contract**

Run: `LIVE_LLM_PROVIDER_IDS=minimax-openai fvm flutter test --tags live-llm test/models/llm/configurable_http_llm_live_test.dart`
Expected: PASS if selected provider exercises responses-compatible path, otherwise switch to configured responses provider

- [ ] **Step 6: 提交收尾变更**

```bash
git add README.md AGENTS.md
git commit -m "docs: document unified llm protocol runtimes"
```
