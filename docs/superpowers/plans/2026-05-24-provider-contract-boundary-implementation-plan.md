# Provider Contract 边界收口 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将三种 `ApiStyle` 的最终响应解析、raw assistant roundtrip 与能力声明统一收口到单一 provider contract 中，并让 `ConfigurableHttpLLM` 退回纯高层编排层。

**Architecture:** 扩展 `ApiStyleAdapter` 使其成为完整 provider contract，新增 capability 声明与统一 `parseDecision(...)` 入口；`ConfigurableHttpLLM` 删除 provider-specific parse/capability `switch`；runtime 层与 `StreamingDecisionAccumulator` 保持现有边界不变。

**Tech Stack:** Flutter 3.35.7, Dart, `flutter_test`, existing protocol runtime/adapters/live contract suites

---

### Task 1: 定义 provider contract 能力与统一决策解析入口

**Files:**
- Modify: `lib/models/llm/adapters/api_style_adapter.dart`
- Create: `lib/models/llm/adapters/provider_capabilities.dart`
- Test: `test/models/llm/adapters/api_style_adapter_contract_test.dart`

- [ ] **Step 1: 先写失败测试，锁定新的 contract 形状**

```dart
test('chat completions contract declares planner streaming support', () {
  final adapter = const SdkChatCompletionsAdapter();
  expect(adapter.capabilities.supportsPlannerStreaming, isTrue);
});

test('responses contract exposes parseDecision entrypoint', () {
  final adapter = const ResponsesAdapter();
  expect(
    adapter.parseDecision({'output': const []}),
    isNull,
  );
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `fvm flutter test test/models/llm/adapters/api_style_adapter_contract_test.dart`
Expected: FAIL because `capabilities` / `parseDecision` do not exist

- [ ] **Step 3: 写最小实现**

实现：
- `ProviderCapabilities` 值对象
- `ApiStyleAdapter.capabilities`
- `ApiStyleAdapter.parseDecision(Map<String, dynamic>)`

- [ ] **Step 4: 运行测试确认通过**

Run: `fvm flutter test test/models/llm/adapters/api_style_adapter_contract_test.dart`
Expected: PASS

- [ ] **Step 5: 提交这一小步**

```bash
git add lib/models/llm/adapters/api_style_adapter.dart lib/models/llm/adapters/provider_capabilities.dart test/models/llm/adapters/api_style_adapter_contract_test.dart
git commit -m "refactor: add provider contract capabilities"
```

### Task 2: 将三种 provider 的最终 decision 解析并回 contract

**Files:**
- Modify: `lib/models/llm/adapters/sdk_chat_completions_adapter.dart`
- Modify: `lib/models/llm/adapters/responses_adapter.dart`
- Modify: `lib/models/llm/adapters/anthropic_messages_adapter.dart`
- Modify: `lib/models/llm/tool_loop/openai_chat_completions_tool_loop_adapter.dart`
- Modify: `lib/models/llm/tool_loop/openai_responses_tool_loop_adapter.dart`
- Modify: `lib/models/llm/tool_loop/anthropic_messages_tool_loop_adapter.dart`
- Test: `test/models/llm/adapters/sdk_chat_completions_adapter_test.dart`
- Test: `test/models/llm/adapters/responses_adapter_test.dart`
- Test: `test/models/llm/adapters/anthropic_messages_adapter_test.dart`

- [ ] **Step 1: 先写失败测试，确认 adapter 直接产出 `ModelTurnDecision`**

```dart
test('chat completions adapter parses tool call decision directly', () {
  final decision = adapter.parseDecision(payload);
  expect(decision?.toolCalls.single.toolName, 'read_file');
});
```

- [ ] **Step 2: 为 responses 与 anthropic 补同类失败测试**

```dart
test('responses adapter parses function_call output directly', () {
  final decision = adapter.parseDecision(payload);
  expect(decision?.toolCalls, isNotEmpty);
});

test('anthropic adapter parses tool_use block directly', () {
  final decision = adapter.parseDecision(payload);
  expect(decision?.isTerminal, isFalse);
});
```

- [ ] **Step 3: 运行测试确认失败**

Run: `fvm flutter test test/models/llm/adapters/sdk_chat_completions_adapter_test.dart test/models/llm/adapters/responses_adapter_test.dart test/models/llm/adapters/anthropic_messages_adapter_test.dart`
Expected: FAIL because adapters do not yet expose `parseDecision`

- [ ] **Step 4: 写最小实现**

实现要求：
- 先用委托方式把现有 `*ToolLoopAdapter.parseDecision(...)` 接进各自 adapter
- 不在这一小步里重写 parse 逻辑
- 保留现有 roundtrip / parser 单测可复用路径

- [ ] **Step 5: 运行测试确认通过**

Run: `fvm flutter test test/models/llm/adapters/sdk_chat_completions_adapter_test.dart test/models/llm/adapters/responses_adapter_test.dart test/models/llm/adapters/anthropic_messages_adapter_test.dart`
Expected: PASS

- [ ] **Step 6: 提交这一小步**

```bash
git add lib/models/llm/adapters/sdk_chat_completions_adapter.dart lib/models/llm/adapters/responses_adapter.dart lib/models/llm/adapters/anthropic_messages_adapter.dart lib/models/llm/tool_loop/openai_chat_completions_tool_loop_adapter.dart lib/models/llm/tool_loop/openai_responses_tool_loop_adapter.dart lib/models/llm/tool_loop/anthropic_messages_tool_loop_adapter.dart test/models/llm/adapters/sdk_chat_completions_adapter_test.dart test/models/llm/adapters/responses_adapter_test.dart test/models/llm/adapters/anthropic_messages_adapter_test.dart
git commit -m "refactor: move provider decision parsing behind contracts"
```

### Task 3: 让 `ConfigurableHttpLLM` 改为只依赖 provider contract

**Files:**
- Modify: `lib/models/llm/configurable_http_llm.dart`
- Test: `test/models/llm/configurable_http_llm_test.dart`

- [ ] **Step 1: 先写失败测试，锁定 orchestration 只走 contract 能力**

```dart
test('planner streaming decision is gated by provider capabilities', () async {
  final adapter = FakeApiStyleAdapter(
    capabilities: const ProviderCapabilities(
      supportsPlannerStreaming: false,
      supportsParallelToolCalls: true,
    ),
  );
  // assert execute path is used instead of streamExecute
});
```

- [ ] **Step 2: 再写失败测试，锁定 non-stream/fallback 都走 `adapter.parseDecision(...)`**

```dart
test('planner fallback json is parsed through adapter contract', () async {
  // runtime returns fallback json, expect fake adapter.parseDecision called
});
```

- [ ] **Step 3: 运行测试确认失败**

Run: `fvm flutter test test/models/llm/configurable_http_llm_test.dart`
Expected: FAIL because `ConfigurableHttpLLM` still uses style switches

- [ ] **Step 4: 写最小实现**

实现要求：
- 删除 `_parseTurnDecisionForStyle(...)`
- 删除 `_shouldUseStreamingPlanner(...)`
- 删除直接持有的三个 provider-specific tool-loop adapter 字段
- 改为使用 `adapter.capabilities.supportsPlannerStreaming`
- non-stream 与 fallback JSON 统一走 `adapter.parseDecision(...)`

- [ ] **Step 5: 运行测试确认通过**

Run: `fvm flutter test test/models/llm/configurable_http_llm_test.dart`
Expected: PASS

- [ ] **Step 6: 提交这一小步**

```bash
git add lib/models/llm/configurable_http_llm.dart test/models/llm/configurable_http_llm_test.dart
git commit -m "refactor: make configurable llm depend on provider contracts"
```

### Task 4: 保护 streaming decision 与 raw assistant roundtrip 语义

**Files:**
- Modify: `test/models/llm/adapters/anthropic_messages_roundtrip_test.dart`
- Modify: `test/models/llm/adapters/sdk_chat_completions_adapter_test.dart`
- Modify: `test/models/llm/adapters/responses_adapter_test.dart`
- Modify: `test/models/llm/configurable_http_llm_live_test.dart`

- [ ] **Step 1: 先补失败测试，覆盖 streaming/non-streaming 一致性**

至少覆盖：

```dart
test('chat completions streaming snapshot replays equivalent raw assistant message');
test('responses fallback json parse matches streamed decision semantics');
test('anthropic tool_use decision preserves append-only replay state');
```

- [ ] **Step 2: 运行相关测试确认暴露差异**

Run: `fvm flutter test test/models/llm/adapters/anthropic_messages_roundtrip_test.dart test/models/llm/adapters/sdk_chat_completions_adapter_test.dart test/models/llm/adapters/responses_adapter_test.dart`
Expected: PASS or targeted FAILs that reveal semantic drift after Task 3

- [ ] **Step 3: 仅做必要修复**

修复原则：
- 优先修 contract 内部委托与 raw assistant replay 拼接
- 不改 turn ledger / transcript 结构
- 不新增 provider-specific prompt patch

- [ ] **Step 4: 复跑相关测试确认通过**

Run: `fvm flutter test test/models/llm/adapters/anthropic_messages_roundtrip_test.dart test/models/llm/adapters/sdk_chat_completions_adapter_test.dart test/models/llm/adapters/responses_adapter_test.dart`
Expected: PASS

- [ ] **Step 5: 提交这一小步**

```bash
git add test/models/llm/adapters/anthropic_messages_roundtrip_test.dart test/models/llm/adapters/sdk_chat_completions_adapter_test.dart test/models/llm/adapters/responses_adapter_test.dart test/models/llm/configurable_http_llm_live_test.dart
git commit -m "test: lock provider contract roundtrip semantics"
```

### Task 5: 跑 provider contract 回归与真实风格验证

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`

- [ ] **Step 1: 运行本地 contract 回归**

Run: `fvm flutter test test/models/llm/configurable_http_llm_test.dart test/models/llm`
Expected: PASS

- [ ] **Step 2: 运行针对 touched styles 的真实 provider contract tests**

Run:
```bash
bash scripts/run_live_llm_contract_tests.sh minimax-openai
```

再运行：

```bash
bash scripts/run_live_llm_contract_tests.sh minimax-openai minimax-anthropic
```

或按需使用：

```bash
LIVE_LLM_PROVIDER_IDS=minimax-openai fvm flutter test --tags live-llm test/models/llm/configurable_http_llm_live_test.dart
LIVE_LLM_PROVIDER_IDS=minimax-anthropic fvm flutter test --tags live-llm test/models/llm/configurable_http_llm_live_test.dart
```

- [ ] **Step 3: 如结构说明已变化，更新 README / AGENTS**

更新方向：
- provider adapter 现在是完整 provider contract
- `ConfigurableHttpLLM` 是 orchestration layer
- 新增 capability-driven planner streaming 规则

- [ ] **Step 4: 复跑最终验证**

Run:
```bash
fvm flutter analyze
fvm flutter test
```
Expected: PASS

## 完成标准

- `ApiStyleAdapter` 已成为完整 provider contract，而不是只承担半套语义
- `ConfigurableHttpLLM` 不再保留 provider-specific parse/capability `switch`
- 三种 API style 的最终 decision parse 都通过 contract 暴露
- streaming snapshot 与 non-stream fallback 的 raw assistant roundtrip 语义保持一致
- mocked tests 与至少一个真实 provider live contract test 通过
