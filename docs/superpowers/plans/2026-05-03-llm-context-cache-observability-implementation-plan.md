# LLM 上下文缓存观测与基础命中优化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为现有 HTTP LLM 架构补齐上下文缓存观测、usage 标准化和最小 provider hints，帮助定位并改善缓存命中问题，同时保持现有多 provider 兼容性。

**Architecture:** 继续保留 `ConfigurableHttpLLM + ApiStyleAdapter` 结构，不引入 OpenAI/Anthropic SDK。先新增纯数据模型和 usage extractor，再把请求观测接入 `Logger.trace` 的现有 File Log 架构，最后把可选 cache hints 只接到明确支持的协议分支。默认策略只观测，不改请求行为。

**Tech Stack:** Flutter/Dart, `http`, `flutter_test`, 现有 `Logger`, 现有 `ApiStyleAdapter` / `ConfigurableHttpLLM` / adapter tests。

---

### Task 1: 新增缓存观测数据模型与 usage extractor

**Files:**
- Create: `lib/models/llm/llm_cache_strategy.dart`
- Create: `lib/models/llm/llm_cache_request_options.dart`
- Create: `lib/models/llm/llm_cache_usage.dart`
- Create: `lib/models/llm/llm_request_telemetry.dart`
- Create: `lib/models/llm/llm_usage_extractor.dart`
- Test: `test/models/llm/llm_usage_extractor_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
test('extracts OpenAI Responses cached tokens', () {
  final usage = LlmUsageExtractor.extract({
    'usage': {
      'input_tokens': 120,
      'output_tokens': 40,
      'input_tokens_details': {'cached_tokens': 96},
    },
  });

  expect(usage?.inputTokens, 120);
  expect(usage?.outputTokens, 40);
  expect(usage?.cachedInputTokens, 96);
});
```

Add one case each for OpenAI Chat Completions, Anthropic, DeepSeek-like cache fields, and missing usage.

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/models/llm/llm_usage_extractor_test.dart`
Expected: FAIL because `LlmUsageExtractor` and the new model files do not exist yet.

- [ ] **Step 3: Write minimal implementation**

Implement:

- `LlmCacheStrategy` with `disabled`, `observeOnly`, `providerHints`
- `LlmCacheRequestOptions` with `strategy`, `cacheKey`, `retention`, `markStableSystemPrefix`
- `LlmCacheUsage` with raw and normalized fields
- `LlmRequestTelemetry` with request timing / token / cache fields
- `LlmUsageExtractor.extract(Map<String, dynamic> payload)` returning normalized usage or null

Keep the extractor pure. Do not couple it to HTTP or logger code.

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/models/llm/llm_usage_extractor_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/llm/llm_cache_strategy.dart lib/models/llm/llm_cache_request_options.dart lib/models/llm/llm_cache_usage.dart lib/models/llm/llm_request_telemetry.dart lib/models/llm/llm_usage_extractor.dart test/models/llm/llm_usage_extractor_test.dart
git commit -m "feat: add llm cache usage normalization"
```

### Task 2: 扩展 LlmRequestOptions 并把缓存选项传进 adapter 接口

**Files:**
- Modify: `lib/models/llm/llm_request_options.dart`
- Modify: `lib/models/llm/adapters/api_style_adapter.dart`
- Modify: `lib/models/llm/adapters/chat_completions_adapter.dart`
- Modify: `lib/models/llm/adapters/responses_adapter.dart`
- Modify: `lib/models/llm/adapters/anthropic_messages_adapter.dart`
- Test: `test/models/llm/adapters/responses_adapter_test.dart`
- Test: `test/models/llm/adapters/anthropic_messages_adapter_test.dart`

- [ ] **Step 1: Write the failing test**

Add one test that verifies the default payload is unchanged when cache strategy is `observeOnly`, and one test that verifies `providerHints` can inject a known OpenAI-compatible cache key only when explicitly enabled.

For Anthropic, add a test that confirms the stable system prefix receives `cache_control` only when `markStableSystemPrefix` is true.

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
fvm flutter test test/models/llm/adapters/responses_adapter_test.dart test/models/llm/adapters/anthropic_messages_adapter_test.dart
```

Expected: FAIL because the adapter signatures and cache hint behavior are not implemented yet.

- [ ] **Step 3: Write minimal implementation**

Update `LlmRequestOptions` to carry the cache request object.

Extend `ApiStyleAdapter.buildChatPayload()` / `buildPlannerPayload()` so they accept the same cache options path already used for output token limits and reasoning control.

Implement provider-specific behavior only where the adapter already owns the protocol:

- OpenAI-compatible adapters may emit `prompt_cache_key` and optional retention when `providerHints` is active
- Anthropic adapter may annotate stable system/tool prefix blocks with `cache_control`
- Unknown providers stay on the default path and see no injected cache fields

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
fvm flutter test test/models/llm/adapters/responses_adapter_test.dart test/models/llm/adapters/anthropic_messages_adapter_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/llm/llm_request_options.dart lib/models/llm/adapters/api_style_adapter.dart lib/models/llm/adapters/chat_completions_adapter.dart lib/models/llm/adapters/responses_adapter.dart lib/models/llm/adapters/anthropic_messages_adapter.dart test/models/llm/adapters/responses_adapter_test.dart test/models/llm/adapters/anthropic_messages_adapter_test.dart
git commit -m "feat: add cache hints to llm adapters"
```

### Task 3: 把缓存请求观测接入 ConfigurableHttpLLM 的现有 trace 架构

**Files:**
- Modify: `lib/models/llm/configurable_http_llm.dart`
- Modify: `lib/utils/logger.dart` only if a small helper is required for formatting telemetry payloads, otherwise avoid touching it
- Test: `test/models/llm/configurable_http_llm_test.dart`

- [ ] **Step 1: Write the failing test**

Add one streaming planner test that verifies a trace entry is emitted for request start, first chunk, and done, and that the recorded payload contains cache usage when present in the fake response.

Add one non-stream planner test that verifies `llm.request.done` is emitted with usage data for a simple HTTP 200 JSON response.

Use the existing `_RecordingHttpClient` shape already in the test file so the test proves the real code path instead of a fake wrapper.

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/models/llm/configurable_http_llm_test.dart`
Expected: FAIL because the new trace payload and usage extraction are not wired yet.

- [ ] **Step 3: Write minimal implementation**

Inside `ConfigurableHttpLLM`:

- measure request start time, first stream chunk time, and total duration
- compute payload size and estimated input tokens using existing budget services
- extract usage through `LlmUsageExtractor`
- emit `Logger.trace('ConfigurableHttpLLM', 'llm.request.start', ...)`
- emit `Logger.trace('ConfigurableHttpLLM', 'llm.first_chunk', ...)`
- emit `Logger.trace('ConfigurableHttpLLM', 'llm.request.done', ...)`
- emit `Logger.trace('ConfigurableHttpLLM', 'llm.request.failed', ...)`

Do not write these values into `chat_events` or `chat_turn_step`. They are file-log diagnostics only.

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/models/llm/configurable_http_llm_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/llm/configurable_http_llm.dart test/models/llm/configurable_http_llm_test.dart
git commit -m "feat: trace llm request cache observability"
```

### Task 4: 复核缓存观测与现有 logging 架构的一致性

**Files:**
- Inspect: `docs/architecture/logging.md`
- Inspect: `docs/superpowers/specs/2026-05-03-llm-context-cache-observability-design.md`

- [ ] **Step 1: Verify the architectural boundary**

Confirm the new LLM cache observability remains inside the existing File Log / trace lane from `logging.md` and does not introduce a parallel logging system.

- [ ] **Step 2: Verify the anchor semantics**

Run:

```bash
rg -n "llm.request.start|llm.first_chunk|llm.request.done|llm.request.failed|turn.start|planner.start|planner.done|tool.start|interaction.awaiting_user" docs/architecture/logging.md docs/superpowers/specs/2026-05-03-llm-context-cache-observability-design.md
```

Expected: the plan and logging doc agree that the new LLM anchors are trace-level diagnostics and do not replace existing turn/planner/tool anchors.

- [ ] **Step 3: Verify no extra docs are needed**

Check that `README.md` and `AGENTS.md` do not need a new rule for this change because the logging architecture already points to `docs/architecture/logging.md`.

- [ ] **Step 4: Commit**

No file changes expected from this task unless the consistency check finds a real mismatch.

### Task 5: 端到端验证和回归收尾

**Files:**
- Inspect: all modified files from Tasks 1-4
- Test: `test/models/llm/llm_usage_extractor_test.dart`
- Test: `test/models/llm/adapters/responses_adapter_test.dart`
- Test: `test/models/llm/adapters/anthropic_messages_adapter_test.dart`
- Test: `test/models/llm/configurable_http_llm_test.dart`

- [ ] **Step 1: Run the focused test bundle**

Run:

```bash
fvm flutter test test/models/llm/llm_usage_extractor_test.dart test/models/llm/adapters/responses_adapter_test.dart test/models/llm/adapters/anthropic_messages_adapter_test.dart test/models/llm/configurable_http_llm_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run static analysis on touched files**

Run:

```bash
fvm flutter analyze lib/models/llm/llm_usage_extractor.dart lib/models/llm/llm_request_telemetry.dart lib/models/llm/configurable_http_llm.dart lib/models/llm/adapters/chat_completions_adapter.dart lib/models/llm/adapters/responses_adapter.dart lib/models/llm/adapters/anthropic_messages_adapter.dart test/models/llm/llm_usage_extractor_test.dart test/models/llm/configurable_http_llm_test.dart
```

Expected: no new warnings or errors in touched files.

- [ ] **Step 3: Confirm logging architecture compatibility**

Check the new trace entries against `docs/architecture/logging.md`:

- no new log files
- no transcript pollution
- no ledger pollution
- no raw prompt leakage
- no bypass of `Logger`

- [ ] **Step 4: Final commit**

If all previous commits are kept separate, leave them. If the branch policy prefers a single final commit, squash only after the focused tests pass.
