# LLM 上下文缓存观测与基础命中优化设计

## 背景

当前 App 通过 `ConfigurableHttpLLM` 和三套协议适配器直接调用上游模型接口：

- `ChatCompletionsAdapter`
- `ResponsesAdapter`
- `AnthropicMessagesAdapter`

这套结构已经能覆盖 OpenAI-compatible Chat Completions、OpenAI Responses、Anthropic Messages 等协议，也能服务 DeepSeek、MiniMax 等自定义 `baseUrl` 场景。

用户反馈是：同一个 `baseUrl` 在本 App 中回复明显更慢，怀疑上下文缓存没有命中。当前代码事实是：

- 请求 payload 由各协议 adapter 手写 JSON 生成；
- `LlmRequestOptions` 只有 `maxOutputTokens` 与 `allowReasoning`；
- 没有统一缓存策略模型；
- 没有标准化读取 provider usage 中的缓存字段；
- file log 中没有首 token 延迟、总耗时、缓存命中 token 等稳定观测字段；
- Session 上下文已经由 `SessionContextService` 统一构建，但还没有面向 provider prompt cache 的稳定前缀边界。

因此，现在无法可靠回答：

- 当前请求是否命中上游 prompt/context cache；
- 如果没有命中，是 provider 不支持、payload 前缀不稳定、输入太短、还是参数未启用；
- 慢是首包慢、流式输出慢、工具循环多、还是网络重试导致。

## 结论

本轮不引入 Anthropic/OpenAI SDK。

原因：

- 缓存命中由服务端根据请求内容、缓存参数和稳定前缀决定，不由 SDK 本身决定；
- Flutter/Dart 没有适合作为核心依赖的官方 OpenAI / Anthropic SDK；
- 当前项目已经有多 provider HTTP adapter 架构，引入 SDK 会绕开既有协议边界；
- OpenAI / Anthropic 的缓存参数本质是 JSON payload 字段，当前 adapter 可以精确控制；
- 对 DeepSeek、MiniMax 等 OpenAI-compatible 自定义 `baseUrl`，SDK 反而可能降低兼容性。

本轮采用“保留 HTTP adapter，补齐缓存观测与轻量 provider hints”的方向。

## 目标

本次设计目标：

- 为每次 LLM 请求补齐缓存相关可观测性；
- 标准化不同 provider 的 usage 缓存字段；
- 在不破坏兼容性的前提下支持基础缓存参数；
- 识别和记录 prompt 前缀稳定性风险；
- 为后续更精细的 Anthropic `cache_control` 和 OpenAI `prompt_cache_key` 策略留接口；
- 默认不向未知兼容 provider 注入可能不支持的私有字段。

## 非目标

本轮不做：

- 不引入 OpenAI / Anthropic SDK；
- 不重写 LLM 请求架构；
- 不改变 SessionContextService 的核心上下文压缩策略；
- 不把 provider usage 当作唯一 token 预算来源；
- 不默认为所有 provider 注入缓存参数；
- 不做 UI 设置页的大型重构；
- 不把缓存优化做成硬编码 provider 名称路由。

## 当前实现事实

### 1. 请求入口

`ConfigurableHttpLLM.planTurnDecision()` 构建 planner 请求，并根据协议选择 streaming planner。

`_runSideModelTextTask()` 构建 summary、webpage processing 等旁路请求。

这两个入口都应进入同一套请求观测逻辑。

### 2. 协议适配层

`ApiStyleAdapter` 当前负责：

- headers；
- chat payload；
- planner payload；
- 非流式 response 文本解析。

它还没有负责：

- cache hint 注入；
- usage 抽取；
- 请求指标摘要。

### 3. Session 上下文

`SessionContextService` 当前 planner 可见上下文顺序为：

1. runtime user context；
2. history summary；
3. recent completed turns；
4. current turn transcript。

这能保证上下文来源正确，但不天然保证 provider prompt cache 的稳定前缀最大化。`runtime user context` 可能含当前日期等变化信息，放在最前面会降低后续静态 prompt 的缓存复用机会。

本轮先观测并记录风险，不直接重排上下文层级。

## 方案选择

### 方案 A：保留 HTTP adapter，新增缓存观测与 hints

采用。

做法：

- 增加统一 `LlmCacheTelemetry` / `LlmRequestTelemetry` 数据模型；
- 在 `ConfigurableHttpLLM` 请求入口记录开始、首 chunk、完成、失败；
- 从 provider response usage 中标准化缓存字段；
- 在 `LlmRequestOptions` 中新增缓存策略字段；
- adapter 根据 `ApiStyle` 和配置决定是否注入 cache hints；
- 默认只观测，不改变请求 payload。

优点：

- 最小改动当前架构；
- 兼容自定义 `baseUrl`；
- 能直接回答“有没有命中缓存”；
- 后续可以逐步开启 provider-specific hints；
- 测试可用 fake HTTP 覆盖。

缺点：

- 需要自己维护不同 provider usage 字段映射；
- 需要谨慎处理 provider 私有参数兼容性。

### 方案 B：引入 OpenAI / Anthropic SDK

不采用。

原因：

- Flutter/Dart 官方 SDK 支持不足；
- SDK 不会自动解决 prefix cache miss；
- 多 provider 自定义 `baseUrl` 兼容性会更复杂；
- 当前 adapter 已经能表达需要的 JSON 字段；
- 会把现有协议边界拆成 SDK 与 HTTP 两套路径。

### 方案 C：只做 prompt 前缀重排

不采用为第一步。

原因：

- 没有 telemetry 时无法验证收益；
- 慢可能来自首包、输出、重试、工具循环，而不一定是 cache miss；
- 直接改 Session 上下文顺序有行为风险。

后续可基于 telemetry 决定是否重排稳定 prefix。

## 数据模型设计

### LlmCacheStrategy

新增枚举：

```dart
enum LlmCacheStrategy {
  disabled,
  observeOnly,
  providerHints,
}
```

语义：

- `disabled`：不注入缓存参数，也不标记请求为缓存候选；仍可记录 provider 返回 usage；
- `observeOnly`：默认值，只观测 usage 和前缀风险，不改变 payload；
- `providerHints`：允许已知协议 adapter 注入明确支持的缓存参数。

### LlmCacheRequestOptions

新增请求级缓存配置：

```dart
class LlmCacheRequestOptions {
  final LlmCacheStrategy strategy;
  final String? cacheKey;
  final String? retention;
  final bool markStableSystemPrefix;
}
```

字段含义：

- `strategy`：本次请求的缓存策略；
- `cacheKey`：provider 支持时用于提示缓存路由的稳定 key；
- `retention`：provider 支持时用于提示缓存保留时间；
- `markStableSystemPrefix`：允许 Anthropic 等协议为稳定 system/tool block 标注 cache control。

### LlmCacheUsage

新增标准化 usage 模型：

```dart
class LlmCacheUsage {
  final int? inputTokens;
  final int? outputTokens;
  final int? cachedInputTokens;
  final int? cacheReadInputTokens;
  final int? cacheWriteInputTokens;
  final int? cacheMissInputTokens;
  final Map<String, dynamic> rawUsage;
}
```

字段含义：

- `inputTokens`：provider 返回的输入 token；
- `outputTokens`：provider 返回的输出 token；
- `cachedInputTokens`：OpenAI-style 已缓存输入 token；
- `cacheReadInputTokens`：Anthropic-style cache read token；
- `cacheWriteInputTokens`：Anthropic-style cache write token；
- `cacheMissInputTokens`：DeepSeek-like cache miss token；
- `rawUsage`：保留原始 usage，便于临时排障。

### LlmRequestTelemetry

新增请求观测模型：

```dart
class LlmRequestTelemetry {
  final String label;
  final ApiStyle apiStyle;
  final String modelName;
  final LlmRequestPurpose purpose;
  final int estimatedInputTokens;
  final int messageCount;
  final int payloadBytes;
  final int? firstChunkMs;
  final int totalMs;
  final int attempt;
  final LlmCacheStrategy cacheStrategy;
  final LlmCacheUsage? cacheUsage;
}
```

字段用于写入 file log，不作为业务恢复状态源。

## Usage 抽取规则

新增一个小型纯函数服务，例如 `LlmUsageExtractor`。

它只负责从 response JSON 中提取 `usage` 并标准化，不负责请求发送。

需要支持的字段形态：

- OpenAI / Responses：
  - `usage.input_tokens`
  - `usage.output_tokens`
  - `usage.input_tokens_details.cached_tokens`
- OpenAI Chat Completions：
  - `usage.prompt_tokens`
  - `usage.completion_tokens`
  - `usage.prompt_tokens_details.cached_tokens`
- Anthropic：
  - `usage.input_tokens`
  - `usage.output_tokens`
  - `usage.cache_read_input_tokens`
  - `usage.cache_creation_input_tokens`
- DeepSeek-like：
  - `usage.prompt_cache_hit_tokens`
  - `usage.prompt_cache_miss_tokens`

如果 provider 没有返回 usage，记录 `cacheUsage=null`，不能当作失败。

## 请求参数策略

### 默认策略

默认使用 `observeOnly`：

- 不向 payload 注入缓存参数；
- 记录 payload 字节数、估算输入 token、usage 缓存字段；
- 记录是否存在明显 cache prefix 风险。

### OpenAI-compatible hints

仅当 `strategy == providerHints` 且配置明确开启时：

- Responses / Chat Completions adapter 可以注入 `prompt_cache_key`；
- 如果配置了 retention，再注入 provider 支持的 `prompt_cache_retention`；
- 未明确开启时不注入，避免 DeepSeek、MiniMax 等兼容接口拒绝未知字段。

### Anthropic cache control

仅当 `strategy == providerHints` 且 `markStableSystemPrefix == true`：

- 将稳定 system prompt 转成 Anthropic content block；
- 在稳定 block 上添加 `cache_control`；
- runtime date、current turn、用户消息不标 cache；
- tools schema 是否标 cache 作为后续小步增强，先以 system prefix 为主。

## 日志设计

遵守 `docs/architecture/logging.md`，所有正式观测走 `Logger.trace`。

新增锚点：

- `llm.request.start`
- `llm.first_chunk`
- `llm.request.done`
- `llm.request.failed`

推荐字段：

- `label`
- `apiStyle`
- `model`
- `purpose`
- `estimatedInputTokens`
- `messageCount`
- `payloadBytes`
- `cacheStrategy`
- `firstChunkMs`
- `totalMs`
- `inputTokens`
- `outputTokens`
- `cachedInputTokens`
- `cacheReadInputTokens`
- `cacheWriteInputTokens`
- `cacheMissInputTokens`
- `attempt`

日志不记录完整 prompt，不记录 API key，不记录完整 payload。

## 前缀稳定性观测

新增轻量检查，不改变请求内容：

- system prompt hash；
- tools schema hash；
- runtime user context hash；
- snapshot summary hash；
- recent turns token 估算；
- current turn token 估算。

日志只记录 hash 和长度，不记录原文。

如果 runtime user context 出现在最前且每轮变化，可记录 `prefixRisk=dynamic_runtime_context_before_stable_prompt`。

这个风险记录只用于分析，不作为运行时决策。

## 测试设计

新增或扩展测试：

- `test/models/llm/llm_usage_extractor_test.dart`
  - 覆盖 OpenAI Responses usage；
  - 覆盖 OpenAI Chat Completions usage；
  - 覆盖 Anthropic usage；
  - 覆盖 DeepSeek-like usage；
  - 覆盖无 usage。
- `test/models/llm/configurable_http_llm_test.dart`
  - streaming planner 记录首 chunk 与完成；
  - non-stream planner 记录完成 usage；
  - providerHints 默认不注入；
  - 开启 providerHints 后只对明确协议注入。
- adapter tests
  - Anthropic `cache_control` 只标稳定 system block；
  - current turn 不被标 cache。

## 验证方式

本轮完成后，判断缓存问题是否可观测的标准是：

- 本地 `logs/app.log` 能看到每次 LLM 请求的 `llm.request.done`；
- 对支持 usage 的 provider，日志能看到缓存 token 字段；
- 对不支持 usage 的 provider，日志能明确显示 usage 缺失而不是静默；
- 同一会话连续两轮请求可比较 `cachedInputTokens` 或 `cacheReadInputTokens`；
- 能区分首 chunk 慢和总耗时慢。

## 风险与缓解

### provider 私有参数不兼容

缓解：

- 默认 `observeOnly`；
- `providerHints` 必须显式开启；
- 未知 provider 不按名称猜测注入字段。

### 日志泄露 prompt 内容

缓解：

- 只记录 hash、长度、token 估算；
- 不记录完整 payload；
- 继续禁止记录 API key。

### usage 字段不稳定

缓解：

- 保留 `rawUsage` 供调试；
- 标准字段缺失时允许为 null；
- 测试覆盖多种字段形态。

### Anthropic system 结构调整影响现有行为

缓解：

- 第一阶段只观测；
- 真正启用 `cache_control` 时单独覆盖 adapter 测试；
- 不对 current turn 和动态 runtime context 标 cache。

## 后续演进

本轮完成后可以继续：

- 根据 telemetry 决定是否重排 SessionContextService 的 cacheable prefix；
- 在设置页增加“缓存观测 / provider hints”开关；
- 在 Debug 面板展示最近 N 次 LLM 请求缓存命中率；
- 对工具 schema、base prompt、runtime sections 建立稳定 section registry；
- 为 live provider contract tests 增加缓存 usage 验证。
