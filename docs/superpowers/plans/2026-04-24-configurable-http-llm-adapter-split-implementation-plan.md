# ConfigurableHttpLLM Adapter 拆分实现计划

## 目标

基于 `docs/superpowers/specs/2026-04-24-configurable-http-llm-adapter-split-design.md`，把三种 `ApiStyle` 的 payload 构建 / planner 解析 / header 组装下沉到 `ApiStyleAdapter` 实现，让 `ConfigurableHttpLLM` 只保留传输 + 路由职责。

## 代码结构与职责

### 需要修改的文件

- 修改：`lib/models/llm/configurable_http_llm.dart`
  - 删除 `_buildPayloadForStyle` / `_buildPlannerPayloadForStyle` / `_parsePlannerChoiceForStyle` / `_buildHeaders` 及所有下沉到 adapter 的 `_build*` / `_parse*` / `_extract*` / `_normalizePlannerContinuationItems` / `_shouldUseResponsesContinuationInputOnly` / `_HistoricalToolTranscriptState`
  - `chatStream` / `validateApiKey` / `summarizeConversation` / `structureSummaryCard` / `planNextAction` / `planNextToolChoice` / `planTurnDecision` / `_sendTextRequest` 改为通过 `_adapters[apiStyle]` 获取 adapter 调用

### 需要新增的文件

- 新增：`lib/models/llm/adapters/api_style_adapter.dart`
  - `abstract class ApiStyleAdapter`
- 新增：`lib/models/llm/adapters/chat_completions_adapter.dart`
- 新增：`lib/models/llm/adapters/responses_adapter.dart`
- 新增：`lib/models/llm/adapters/anthropic_messages_adapter.dart`
- 新增：`lib/models/llm/adapters/historical_tool_transcript_state.dart`
- 新增：`lib/models/llm/adapters/adapter_utils.dart`

### 需要修改/新增的测试文件

- 修改：`test/models/llm/configurable_http_llm_test.dart`
  - 补齐三种 `ApiStyle` 的 golden payload 断言（chat / planner）
- 新增：`test/models/llm/adapters/chat_completions_adapter_test.dart`
- 新增：`test/models/llm/adapters/responses_adapter_test.dart`
- 新增：`test/models/llm/adapters/anthropic_messages_adapter_test.dart`

## 实施步骤

### 任务 1：先用 golden 测试锁定 payload 字节级行为

**文件：**

- 修改：`test/models/llm/configurable_http_llm_test.dart`

- [ ] **Step 1: 审视现有测试覆盖**

梳理现有 1999 行测试，列出哪些 `ApiStyle × (chat | planner) × (with tools | without tools) × (with continuation | without continuation)` 组合已被断言，哪些缺失。

- [ ] **Step 2: 补齐缺失的 golden 断言**

对每个缺失组合：给定一组固定的 `ChatMessage` + `ChatConfig` + `availableTools` + `continuationItems`，断言 `jsonEncode(payload)` 等于预期字符串或预期 Map 结构。要点：

- 覆盖 `modelContextType == assistantToolUse / userToolResult` 的历史消息重标识
- 覆盖 Anthropic 的 `_normalizePlannerContinuationItems` 在 `providerState.content_blocks` 存在 / 不存在两种情况
- 覆盖 Responses 的 `_shouldUseResponsesContinuationInputOnly` 路径（`previous_response_id` 非空 + continuation 非空）

- [ ] **Step 3: 运行全部 configurable_http_llm_test，确保当前主干绿**

运行：

```bash
fvm flutter test test/models/llm/configurable_http_llm_test.dart
```

预期：

- PASS（这些是锁行为基线）

### 任务 2：引入 ApiStyleAdapter 抽象与工具文件

**文件：**

- 新增：`lib/models/llm/adapters/api_style_adapter.dart`
- 新增：`lib/models/llm/adapters/adapter_utils.dart`
- 新增：`lib/models/llm/adapters/historical_tool_transcript_state.dart`

- [ ] **Step 4: 写出 `ApiStyleAdapter` 接口**

字段与方法按 design 方案中的签名定义。先不实现。

- [ ] **Step 5: 写出 `adapter_utils.dart` 工具函数**

把 `_normalizeText` / `_decodeToolArguments` / `modelContextTypeOf` / `toolNameOf` / `toolArgumentsOf` 作为公开顶层函数写出。此时 `configurable_http_llm.dart` 还未引用它们。

- [ ] **Step 6: 写出 `HistoricalToolTranscriptState`**

把 `_HistoricalToolTranscriptState` / `_HistoricalToolInvocation` 原样复制为公开类。

- [ ] **Step 7: 运行 analyze，确认新增文件无警告**

运行：

```bash
fvm flutter analyze
```

预期：

- 零 warning / error

### 任务 3：提取 ChatCompletionsAdapter

**文件：**

- 新增：`lib/models/llm/adapters/chat_completions_adapter.dart`
- 新增：`test/models/llm/adapters/chat_completions_adapter_test.dart`
- 修改：`lib/models/llm/configurable_http_llm.dart`

- [ ] **Step 8: 从 ConfigurableHttpLLM 复制 ChatCompletions 专属方法到 adapter**

搬入：`_buildChatCompletionsPayload` / `_buildChatCompletionsMessage` / `_buildPlannerChatCompletionsPayload` / `_buildChatCompletionsContinuationMessages` / `_parsePlannerChatCompletionsChoice` / `_parseChatCompletionsToolCall` / `_extractChatCompletionsMessageText`。

实现 `ApiStyleAdapter` 的 5 个方法。`buildHeaders` 返回 `Authorization: Bearer ${apiKey}` + `Content-Type: application/json`。`extractNonStreamText` 读 `choices[0].message.content`。

- [ ] **Step 9: 写 adapter 单测**

对每个方法写一条正向 + 至少一条边界测试（null 容错、空列表）。

- [ ] **Step 10: 在 ConfigurableHttpLLM 中把 ChatCompletions 分支委托到 adapter**

`_buildPayloadForStyle(chatCompletions, ...)` → `adapter.buildChatPayload(...)`
`_buildPlannerPayloadForStyle(chatCompletions, ...)` → `adapter.buildPlannerPayload(...)`
`_parsePlannerChoiceForStyle(chatCompletions, ...)` → `adapter.parsePlannerChoice(...)`
`_buildHeaders(config, chatCompletions)` → `adapter.buildHeaders(config)`

**保留**旧的私有方法直到任务 6 清理，避免一次性大改。

- [ ] **Step 11: 运行测试**

运行：

```bash
fvm flutter test test/models/llm/
```

预期：

- PASS（包括 golden 基线 + 新 adapter 测试）

### 任务 4：提取 ResponsesAdapter

**文件：**

- 新增：`lib/models/llm/adapters/responses_adapter.dart`
- 新增：`test/models/llm/adapters/responses_adapter_test.dart`
- 修改：`lib/models/llm/configurable_http_llm.dart`

- [ ] **Step 12: 复制 Responses 专属方法到 adapter**

搬入：`_buildResponsesPayload` / `_buildResponsesInputItem` / `_buildPlannerResponsesPayload` / `_buildResponsesContinuationInputItems` / `_shouldUseResponsesContinuationInputOnly` / `_parsePlannerResponsesChoice` / `_parseResponsesToolCall` / `_extractResponsesMessageText`。

`buildHeaders` 同 ChatCompletions。`extractNonStreamText` 从 `content` 数组抽取。

- [ ] **Step 13: 写 adapter 单测**

覆盖 `previous_response_id` 路径、continuation-only 路径、各种 `output` type。

- [ ] **Step 14: 在 ConfigurableHttpLLM 中委托 Responses 分支**

- [ ] **Step 15: 运行测试**

```bash
fvm flutter test test/models/llm/
```

预期：PASS

### 任务 5：提取 AnthropicMessagesAdapter

**文件：**

- 新增：`lib/models/llm/adapters/anthropic_messages_adapter.dart`
- 新增：`test/models/llm/adapters/anthropic_messages_adapter_test.dart`
- 修改：`lib/models/llm/configurable_http_llm.dart`

- [ ] **Step 16: 复制 Anthropic 专属方法到 adapter**

搬入：`_buildAnthropicMessagesPayload` / `_buildAnthropicMessage` / `_buildPlannerAnthropicMessagesPayload` / `_normalizePlannerContinuationItems` / `_parsePlannerAnthropicChoice` / `_extractAnthropicContentText`。

`buildHeaders` 返回 `x-api-key` / `anthropic-version: 2023-06-01` / `Content-Type: application/json`。

`buildPlannerPayload` 的签名包含 `providerState` 参数 —— Anthropic 是目前唯一会读它的 adapter，其他 adapter 直接忽略即可。

- [ ] **Step 17: 写 adapter 单测**

覆盖 `providerState.content_blocks` 注入路径、已有 assistant continuation 的短路路径。

- [ ] **Step 18: 在 ConfigurableHttpLLM 中委托 Anthropic 分支**

- [ ] **Step 19: 运行测试**

```bash
fvm flutter test test/models/llm/
```

预期：PASS

### 任务 6：清理 ConfigurableHttpLLM

**文件：**

- 修改：`lib/models/llm/configurable_http_llm.dart`

- [ ] **Step 20: 删除所有已下沉到 adapter 的私有方法**

包括 `_build*Payload` / `_build*Message` / `_build*InputItem` / `_build*ContinuationMessages` / `_build*ContinuationInputItems` / `_parse*Choice` / `_parse*ToolCall` / `_extract*Text` / `_normalizePlannerContinuationItems` / `_shouldUseResponsesContinuationInputOnly` / `_buildHeaders` / `_HistoricalToolTranscriptState` / `_HistoricalToolInvocation` / `_modelContextTypeOf` / `_toolNameOf` / `_toolArgumentsOf` / `_decodeToolArguments` / `_normalizeText`。

保留：`_validateRuntimeConfig` / `_resolveModelName` / `_sendTextRequest`（改为调用 adapter.extractNonStreamText）/ `_previewBody` / `_summarizePlannerPayload` / `_toProviderStyle` / `_resolvePreviousResponseId`（或下沉到 Responses adapter —— 按实际耦合决定）。

- [ ] **Step 21: 运行全量测试 + analyze**

```bash
fvm flutter test
fvm flutter analyze
```

预期：

- 全部 PASS
- `configurable_http_llm.dart` 降到 ~500 行（通过 `wc -l` 验证）

### 任务 7：真机冒烟

**文件：** 无代码改动

- [ ] **Step 22: 三种 provider 冒烟**

用户手动验证（或联调）：

- OpenAI Chat Completions：发一条普通消息 + 一次工具调用（带确认）
- OpenAI Responses：发一条普通消息 + 多工具串行
- Anthropic Messages：发一条普通消息 + 工具调用 + 用户确认后恢复

预期：

- 请求体与重构前字节级一致（抓包对比）
- UI 响应无视觉回归
- 日志无新的 warning / error

## 受影响回归面

- LLM payload / planner 解析：已由任务 1 的 golden 测试锁定
- Tool loop continuation：依赖上面三种 adapter 的 continuation 逻辑
- Reasoning visibility（另一条并行线）：如已落地则需确认 adapter 里不遗漏 reasoning 字段
