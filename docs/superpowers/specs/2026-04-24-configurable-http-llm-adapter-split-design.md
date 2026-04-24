# ConfigurableHttpLLM Adapter 拆分设计

## 背景

`lib/models/llm/configurable_http_llm.dart` 已膨胀至 1576 行，单个 `ConfigurableHttpLLM` 类承担了至少四类职责：

1. 对外 `BaseLLM` 接口实现（`chatStream` / `validateApiKey` / `summarizeConversation` / `structureSummaryCard` / `planNextAction` / `planNextToolChoice` / `planTurnDecision`）
2. 按 `ApiStyle` 路由的 **chat payload** 构建（`_buildPayloadForStyle` 及三个 `_build*Payload`）
3. 按 `ApiStyle` 路由的 **planner payload** 构建与 **continuation item 规范化**（`_buildPlannerPayloadForStyle` / `_buildPlannerChatCompletionsPayload` / `_buildPlannerResponsesPayload` / `_buildPlannerAnthropicMessagesPayload` / `_buildChatCompletionsContinuationMessages` / `_buildResponsesContinuationInputItems` / `_normalizePlannerContinuationItems`）
4. 按 `ApiStyle` 路由的 **planner 响应解析**（`_parsePlannerChoiceForStyle` 及三个 `_parsePlanner*Choice`、子解析 `_parseChatCompletionsToolCall` / `_parseResponsesToolCall`、文本抽取 `_extractChatCompletionsMessageText` / `_extractResponsesMessageText` / `_extractAnthropicContentText`）

并夹带历史消息中 tool use / tool result 的重标识状态机 `_HistoricalToolTranscriptState`（文件私有），以及通用工具 `_decodeToolArguments` / `_normalizeText`。

近期规划中至少有两条主线会继续往这个类里加逻辑：

- anthropic-compatible append-only continuation（`docs/superpowers/specs/2026-04-24-anthropic-compatible-append-only-continuation-design.md`）
- reasoning visibility（`docs/superpowers/specs/2026-04-24-reasoning-visibility-design.md`）

若不先拆，后续每次改动都要在 1500+ 行的类里同步多个 switch，职责边界会继续恶化。

## 目标

1. 引入 **`ApiStyleAdapter` 抽象**：每个 `ApiStyle` 一个实现，持有自家 payload 构建与 planner 响应解析的全部协议差异。
2. `ConfigurableHttpLLM` 收敛到 **传输 + 路由** 角色：config 校验、header 组装、HTTP 发送、超时/错误处理、按 `ApiStyle → adapter` 分发，不再持有任何协议字段。
3. 历史 tool transcript 重建（当前的 `_HistoricalToolTranscriptState`）下沉到使用它的 adapter 内部，不再是跨协议共享工具。
4. 拆分过程不改变任何对外可观测行为：请求 URL、headers、body JSON、planner 响应解析结果与拆分前字节级一致。

## 非目标

- 不修改 `BaseLLM` 接口签名
- 不修改 `ApiStreamParser` / `ApiProtocolResolver`
- 不调整 tool loop / planner 的上层语义
- 不新增 provider / ApiStyle
- 不改 `LLMConfig` / `ChatConfig` / `ChatMessage` 数据结构
- 不引入 DI 框架或新的注入容器

## 现状分析

### 现有能力

- `ApiProtocolResolver.resolveStyle(apiUrl)` 已经集中完成了 URL → `ApiStyle` 的判定
- `ApiStreamParser.parse(response, apiStyle)` 已经按 `ApiStyle` 分发了流式响应解析
- 三个 `*ToolLoopAdapter`（`OpenAIChatCompletionsToolLoopAdapter` / `OpenAIResponsesToolLoopAdapter` / `AnthropicMessagesToolLoopAdapter`）已经承担了 `planTurnDecision` 的响应解析
- `test/models/llm/configurable_http_llm_test.dart` 已覆盖大量 payload 结构断言（1999 行），可以作为行为锁定基线

### 现有缺口

1. **chat payload 构建**和**planner payload 构建**没有对应的 "adapter" 概念，完全集中在 `ConfigurableHttpLLM` 内部的 switch 分支里
2. **planner 响应解析**与 `planTurnDecision` 用的 tool loop adapter 不对称——后者已抽出，前者仍留在大类里
3. `_HistoricalToolTranscriptState` 被三种风格共用但每种风格用不同 `_idPrefix`（`call_ctx_` / `fc_ctx_` / `toolu_ctx_`），其实各自独立的状态并不需要共享
4. `_normalizePlannerContinuationItems` 本质是 Anthropic 专属逻辑（首行 `if (apiStyle != ApiStyle.anthropicMessages ...)`），却堆在顶层
5. `_sendTextRequest` 里手写了三种 `ApiStyle` 各自的响应解包（`choices[0].message.content` / `content` array），跟同一个类里已有的 planner 文本抽取重复

## 设计方案

### Adapter 抽象

```dart
abstract class ApiStyleAdapter {
  ApiStyle get style;

  Map<String, String> buildHeaders(LLMConfig runtimeConfig);

  Map<String, dynamic> buildChatPayload({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required String modelName,
    required bool stream,
  });

  Map<String, dynamic> buildPlannerPayload({
    required List<ChatMessage> messages,
    required ChatConfig config,
    required String modelName,
    required List<PlannerToolOption> availableTools,
    required bool parallelToolCalls,
    String? previousResponseId,
    List<Map<String, dynamic>> continuationItems,
    Map<String, dynamic>? providerState,
  });

  PlannerToolChoice? parsePlannerChoice(Map<String, dynamic> payload);

  /// 用于 _sendTextRequest 的非流式响应解包
  String extractNonStreamText(Map<String, dynamic> payload);
}
```

`headers` 放在 adapter 是为了让 Anthropic 专属的 `x-api-key` / `anthropic-version` 和 OpenAI 家的 `Authorization: Bearer` 也归位。

### Adapter 实现

- `lib/models/llm/adapters/chat_completions_adapter.dart`
  - 吸收 `_buildChatCompletionsPayload` / `_buildChatCompletionsMessage` / `_buildPlannerChatCompletionsPayload` / `_buildChatCompletionsContinuationMessages` / `_parsePlannerChatCompletionsChoice` / `_parseChatCompletionsToolCall` / `_extractChatCompletionsMessageText`
  - 内部持有 `_HistoricalToolTranscriptState`（`call_ctx_` 前缀）工厂方法
  - `buildHeaders`：`Authorization: Bearer ${apiKey}` + `Content-Type: application/json`

- `lib/models/llm/adapters/responses_adapter.dart`
  - 吸收 `_buildResponsesPayload` / `_buildResponsesInputItem` / `_buildPlannerResponsesPayload` / `_buildResponsesContinuationInputItems` / `_shouldUseResponsesContinuationInputOnly` / `_parsePlannerResponsesChoice` / `_parseResponsesToolCall` / `_extractResponsesMessageText`
  - 历史 transcript 前缀 `fc_ctx_`

- `lib/models/llm/adapters/anthropic_messages_adapter.dart`
  - 吸收 `_buildAnthropicMessagesPayload` / `_buildAnthropicMessage` / `_buildPlannerAnthropicMessagesPayload` / `_normalizePlannerContinuationItems` / `_parsePlannerAnthropicChoice` / `_extractAnthropicContentText`
  - 历史 transcript 前缀 `toolu_ctx_`
  - `buildHeaders`：`x-api-key` / `anthropic-version: 2023-06-01` / `Content-Type: application/json`

### 通用工具归位

`lib/models/llm/adapters/adapter_utils.dart`：

- `String? normalizeText(dynamic value)`（原 `_normalizeText`）
- `Map<String, dynamic>? decodeToolArguments(dynamic rawArguments)`（原 `_decodeToolArguments`）
- `String? modelContextTypeOf(ChatMessage message)` / `String? toolNameOf(ChatMessage message)` / `Map<String, dynamic>? toolArgumentsOf(ChatMessage message)`
  - 三个方法读 `ChatMessage.payloadJson`，三个 adapter 构建 tool use / tool result 时都用

`HistoricalToolTranscriptState` 提升为公开但命名空间限定（`lib/models/llm/adapters/historical_tool_transcript_state.dart`），adapter 自己持有实例。

### ConfigurableHttpLLM 的最终形态

```dart
class ConfigurableHttpLLM implements BaseLLM {
  final AppSettingsRepository _settingsRepository;
  final ApiProtocolResolver _protocolResolver;
  final ApiStreamParser _streamParser;
  final http.Client _httpClient;
  final Map<ApiStyle, ApiStyleAdapter> _adapters;
  final OpenAIChatCompletionsToolLoopAdapter _chatCompletionsToolLoopAdapter;
  final OpenAIResponsesToolLoopAdapter _responsesToolLoopAdapter;
  final AnthropicMessagesToolLoopAdapter _anthropicMessagesToolLoopAdapter;
  final PromptBuilderService _promptBuilder;
  final Duration _requestTimeout;
  final Duration _plannerRequestTimeout;
  // ...
}
```

每个对外方法的实现骨架：

```dart
Future<PlannerToolChoice?> planNextToolChoice(...) async {
  final runtimeConfig = await _settingsRepository.getLlmConfig();
  _validateRuntimeConfig(runtimeConfig);
  final apiStyle = _protocolResolver.resolveStyle(runtimeConfig.apiUrl);
  final adapter = _adapters[apiStyle]!;
  final payload = adapter.buildPlannerPayload(...);
  final response = await _httpClient.post(
    _protocolResolver.buildRequestUri(runtimeConfig.apiUrl, apiStyle),
    headers: adapter.buildHeaders(runtimeConfig),
    body: jsonEncode(payload),
  ).timeout(_plannerRequestTimeout);
  // ...
  return adapter.parsePlannerChoice(decoded);
}
```

预期行数：`configurable_http_llm.dart` 降到 ~500 行；三个 adapter 各 200~350 行；adapter_utils ~80 行。

### 构造注入

默认路径构造常量 adapters：

```dart
ConfigurableHttpLLM({
  required AppSettingsRepository settingsRepository,
  Map<ApiStyle, ApiStyleAdapter>? adapters,
  ...
}) : _adapters = adapters ?? _defaultAdapters;

static final Map<ApiStyle, ApiStyleAdapter> _defaultAdapters = {
  ApiStyle.chatCompletions: const ChatCompletionsAdapter(),
  ApiStyle.responses: const ResponsesAdapter(),
  ApiStyle.anthropicMessages: const AnthropicMessagesAdapter(),
};
```

测试中可以替换 adapter 来隔离协议逻辑。

## 兼容 / 迁移风险

1. **字节级 payload 一致性**。重构的核心风险是 payload JSON 序列化顺序 / 字段省略差异。对策：
   - 先补齐 `configurable_http_llm_test.dart` 对三种风格 chat / planner payload 的 golden 断言
   - 再迁移代码。迁移过程中不修改任何字段值
2. **`_HistoricalToolTranscriptState` id 前缀**必须与历史数据对齐。虽然这些 id 只在单次请求里使用、不落库，但对齐原前缀可减少回归面。
3. **planner 响应解析容错**。原实现的 early return / null fallback 语义在 adapter 抽取后必须保留。对策：行为锁定测试覆盖所有 null-return 分支。
4. **Anthropic continuation 的 providerState 规范化**。`_normalizePlannerContinuationItems` 对 providerState 里 `content_blocks` 的处理是现有 Anthropic tool loop 能工作的关键，迁移到 adapter 时路径要保持。
5. **性能**。对象分配多了 1~2 层（adapter 方法调用），可忽略。

## 验证路径

- 全量 `flutter test`，重点 `test/models/llm/configurable_http_llm_test.dart`
- `flutter analyze` 零 warning
- 真机冒烟：
  - OpenAI Chat Completions：普通对话 + 单工具调用
  - OpenAI Responses：普通对话 + 多工具串行
  - Anthropic Messages：普通对话 + 工具调用 + 确认恢复
