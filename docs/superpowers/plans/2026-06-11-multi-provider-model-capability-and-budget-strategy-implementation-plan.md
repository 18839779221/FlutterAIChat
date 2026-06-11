# 多 Provider 模型能力与预算策略 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将当前以静态 `ModelBudgetRegistry` 为主的 token/context 策略升级为“local override + provider metadata + catalog + built-in fallback”的多源模型能力解析链，并让 compaction 与 provider `maxOutputTokens` 使用同一份运行时预算结果。

**Architecture:** 本实现保持现有 provider-first settings 与 session-context 架构不变，新增一层 `ModelCapabilityResolver` 负责解析模型事实，并把当前 `ModelBudgetRegistry` 下沉为 policy/fallback 层。运行时预算采取“同步读取 cache/fallback，异步后台刷新 metadata”的双层接口，避免把 session 构建、UI usage 计算和 planner 请求改成强依赖实时联网的异步链路。

**Tech Stack:** Flutter 3.35.7（优先 `fvm flutter`）、Dart、flutter_test、shared_preferences、http、现有 `ConfigurableHttpLLM` / `SessionTokenBudgetService` / Riverpod provider 架构。

---

## 文件地图

**新增**

- Create: `lib/models/llm/model_capability_source_kind.dart`
- Create: `lib/models/llm/model_capability_override.dart`
- Create: `lib/models/llm/resolved_model_capability.dart`
- Create: `lib/models/llm/resolved_model_budget.dart`
- Create: `lib/services/model_capability_resolver.dart`
- Create: `lib/services/model_capability_sources/provider_model_capability_source.dart`
- Create: `lib/services/model_capability_sources/anthropic_model_capability_source.dart`
- Create: `lib/services/model_capability_sources/gemini_model_capability_source.dart`
- Create: `lib/services/model_capability_sources/catalog_model_capability_source.dart`
- Create: `test/services/model_capability_resolver_test.dart`
- Create: `test/services/model_capability_sources/anthropic_model_capability_source_test.dart`
- Create: `test/services/model_capability_sources/gemini_model_capability_source_test.dart`
- Create: `test/services/model_capability_sources/catalog_model_capability_source_test.dart`
- Create: `test/models/llm/adapters/sdk_responses_adapter_test.dart`
- Create: `test/models/llm/adapters/sdk_anthropic_messages_adapter_test.dart`

**修改**

- Modify: `lib/models/llm/llm_provider_model.dart`
- Modify: `lib/models/llm/llm_provider_config.dart`
- Modify: `lib/models/llm/llm_config.dart`
- Modify: `lib/models/session/model_budget_profile.dart`
- Modify: `lib/repositories/llm_local_defaults.dart`
- Modify: `lib/repositories/app_settings_repository.dart`
- Modify: `lib/services/model_budget_registry.dart`
- Modify: `lib/services/session_token_budget_service.dart`
- Modify: `lib/services/session_context_service.dart`
- Modify: `lib/services/session_context_inspector_service.dart`
- Modify: `lib/models/llm/configurable_http_llm.dart`
- Modify: `lib/models/llm/adapters/sdk_chat_completions_adapter.dart`
- Modify: `lib/models/llm/adapters/sdk_anthropic_messages_adapter.dart`
- Modify: `lib/models/llm/adapters/sdk_responses_adapter.dart`
- Modify: `lib/providers/chat_dependency_providers.dart`
- Modify: `lib/models/llm/llm_factory.dart`
- Modify: `lib/main.dart`
- Modify: `docs/architecture/session-context-management.md`
- Modify: `docs/architecture/provider-adapter-runtime-and-live-matrix.md`
- Modify: `test/repositories/app_settings_repository_test.dart`
- Modify: `test/repositories/llm_local_defaults_test.dart`
- Modify: `test/services/model_budget_registry_test.dart`
- Modify: `test/services/session_token_budget_service_test.dart`
- Modify: `test/providers/chat_dependency_providers_test.dart`
- Modify: `test/models/llm/configurable_http_llm_test.dart`
- Modify: `test/models/llm/adapters/sdk_chat_completions_adapter_test.dart`

## Task 1: 扩展 provider/model 配置与本地持久化，承载 capability override 与 cache

**Files:**
- Create: `lib/models/llm/model_capability_source_kind.dart`
- Create: `lib/models/llm/model_capability_override.dart`
- Create: `lib/models/llm/resolved_model_capability.dart`
- Modify: `lib/models/llm/llm_provider_model.dart`
- Modify: `lib/models/llm/llm_provider_config.dart`
- Modify: `lib/models/llm/llm_config.dart`
- Modify: `lib/repositories/llm_local_defaults.dart`
- Modify: `lib/repositories/app_settings_repository.dart`
- Test: `test/repositories/llm_local_defaults_test.dart`
- Test: `test/repositories/app_settings_repository_test.dart`

- [ ] **Step 1: 先写 `llm_local_defaults` 失败测试，锁定 model override 解析**

```dart
test('parses model capability overrides from provider model entries', () {
  final defaults = LlmLocalDefaults.fromJson({
    'providers': [
      {
        'id': 'openai',
        'name': 'OpenAI',
        'apiKey': 'k',
        'baseUrl': 'https://api.openai.com/v1',
        'models': [
          {
            'id': 'gpt-5',
            'name': 'GPT-5',
            'contextWindowTotal': 1000000,
            'maxInputTokens': 256000,
            'maxOutputTokens': 32000,
          },
        ],
      },
    ],
  });

  final model = defaults.providers.single.models.single;
  expect(model.capabilityOverride?.contextWindowTotal, 1000000);
  expect(model.capabilityOverride?.maxInputTokens, 256000);
  expect(model.capabilityOverride?.maxOutputTokens, 32000);
});
```

- [ ] **Step 2: 运行 defaults 测试确认字段尚不存在**

Run: `fvm flutter test test/repositories/llm_local_defaults_test.dart`

Expected: FAIL，提示 `LlmProviderModel` 尚无 capability override 字段或解析逻辑。

- [ ] **Step 3: 先写 `AppSettingsRepository` 失败测试，锁定 runtime capability cache 持久化**

```dart
test('stores and retrieves resolved model capability cache entries', () async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final repository = AppSettingsRepository(
    preferences,
    localDefaultsLoader: () async => null,
  );

  await repository.saveModelCapabilityCache(
    const ResolvedModelCapability(
      providerId: 'anthropic',
      providerStyle: ApiStyle.anthropicMessages,
      baseUrlFingerprint: 'anthropic::v1',
      modelId: 'claude-sonnet-4-5',
      contextWindowTotal: 200000,
      maxInputTokens: 200000,
      maxOutputTokens: 32000,
      source: ModelCapabilitySourceKind.providerMetadata,
    ),
  );

  final cached = await repository.getModelCapabilityCache(
    providerId: 'anthropic',
    providerStyle: ApiStyle.anthropicMessages,
    baseUrlFingerprint: 'anthropic::v1',
    modelId: 'claude-sonnet-4-5',
  );

  expect(cached?.maxOutputTokens, 32000);
});
```

- [ ] **Step 4: 运行 repository 测试确认缓存 API 尚不存在**

Run: `fvm flutter test test/repositories/app_settings_repository_test.dart`

Expected: FAIL，提示 `saveModelCapabilityCache` / `getModelCapabilityCache` 等接口不存在。

- [ ] **Step 5: 扩展模型与 settings 持久化结构**

实现最小数据结构：

- `ModelCapabilitySourceKind`
- `ModelCapabilityOverride`
- `ResolvedModelCapability`

并在 `LlmProviderModel` 中新增可选字段：

```dart
final ModelCapabilityOverride? capabilityOverride;
```

`AppSettingsRepository` 新增两类能力：

- 读取当前选中 provider/model 对应的 `local override`
- 读写 `ResolvedModelCapability` cache

缓存 key 必须至少包含：

- `providerId`
- `providerStyle`
- `baseUrlFingerprint`
- `modelId`

- [ ] **Step 6: 让 `LLMConfig.additionalConfig` 携带选中 provider/model 的强类型关键信息**

在 `getLlmConfig()` 里继续保留现有 `additionalConfig`，但必须补齐后续 resolver 需要的字段：

- `llm.selected_provider_id`
- `llm.selected_model_id`
- `llm.selected_api_style`
- `llm.selected_base_url`

避免 resolver 再去反查全量 selection。

- [ ] **Step 7: 跑 settings 相关测试到绿**

Run:

```bash
fvm flutter test test/repositories/llm_local_defaults_test.dart
fvm flutter test test/repositories/app_settings_repository_test.dart
```

Expected: PASS。

- [ ] **Step 8: Commit**

```bash
git add lib/models/llm/model_capability_source_kind.dart lib/models/llm/model_capability_override.dart lib/models/llm/resolved_model_capability.dart lib/models/llm/llm_provider_model.dart lib/models/llm/llm_provider_config.dart lib/models/llm/llm_config.dart lib/repositories/llm_local_defaults.dart lib/repositories/app_settings_repository.dart test/repositories/llm_local_defaults_test.dart test/repositories/app_settings_repository_test.dart
git commit -m "feat: persist model capability overrides and cache"
```

## Task 2: 引入 resolver 核心层，并把 `ModelBudgetRegistry` 收缩为 policy/fallback

**Files:**
- Create: `lib/models/llm/resolved_model_budget.dart`
- Create: `lib/services/model_capability_resolver.dart`
- Modify: `lib/models/session/model_budget_profile.dart`
- Modify: `lib/services/model_budget_registry.dart`
- Test: `test/services/model_budget_registry_test.dart`
- Test: `test/services/model_capability_resolver_test.dart`

- [ ] **Step 1: 先写 `ModelCapabilityResolver` 失败测试，锁定优先级链**

```dart
test('prefers local override over provider metadata and fallback', () async {
  final resolver = ModelCapabilityResolver(
    settingsRepository: repository,
    budgetRegistry: ModelBudgetRegistry(
      profiles: {
        'gpt-5': const ModelBudgetProfile(
          modelId: 'gpt-5',
          maxContextTokens: 128000,
          reservedOutputTokens: 12000,
          reasoningReserveTokens: 8000,
          safetyMarginTokens: 4000,
          compactionConfig: ContextCompactionConfig(),
        ),
      },
    ),
    providerSources: const [],
    catalogSource: null,
  );

  final budget = await resolver.resolveForRuntime(
    const LLMConfig(
      apiKey: 'k',
      apiUrl: 'https://api.openai.com/v1',
      model: 'gpt-5',
      apiStyle: ApiStyle.responses,
      additionalConfig: {
        'llm.selected_provider_id': 'openai',
        'llm.selected_base_url': 'https://api.openai.com/v1',
      },
    ),
  );

  expect(budget.capability.source, ModelCapabilitySourceKind.localOverride);
});
```

- [ ] **Step 2: 运行 resolver 测试确认核心类型尚不存在**

Run: `fvm flutter test test/services/model_capability_resolver_test.dart`

Expected: FAIL，提示 `ResolvedModelBudget` / `ModelCapabilityResolver` 等类型不存在。

- [ ] **Step 3: 定义 `ResolvedModelBudget` 与双层 resolver 接口**

`ModelCapabilityResolver` 至少提供：

```dart
ResolvedModelBudget resolveCachedOrFallback(LLMConfig config);
Future<ResolvedModelBudget> resolveForRuntime(LLMConfig config);
Future<void> refreshInBackground(LLMConfig config);
```

约束：

- `resolveCachedOrFallback()` 必须同步 / 无联网依赖
- `resolveForRuntime()` 允许尝试 provider metadata / catalog
- UI / compaction 主路径优先使用 cached-or-fallback

- [ ] **Step 4: 重构 `ModelBudgetRegistry` 职责**

保留现有文件路径与大部分测试资产，但把职责改为：

- `resolvePolicy(modelName)`
- `resolveFallbackCapability(modelName)`

不再把“主事实源 + policy”混成一个 `resolve()`。

必要时可保留兼容 `resolve()`，但内部应标记为过渡 API，只供旧测试/旧调用点暂时复用。

- [ ] **Step 5: 用 fallback capability + policy 派生 `ResolvedModelBudget`**

至少实现：

```dart
effectiveInputBudget = min(
  capability.maxInputTokens ?? infinity,
  capability.contextWindowTotal
    - policy.reservedOutputTokens
    - policy.reasoningReserveTokens
    - policy.safetyMarginTokens,
)
```

以及：

- `plannerMaxOutputTokens`
- `summaryMaxOutputTokens`
- `sideTaskMaxOutputTokens`

- [ ] **Step 6: 跑 registry / resolver 测试到绿**

Run:

```bash
fvm flutter test test/services/model_budget_registry_test.dart
fvm flutter test test/services/model_capability_resolver_test.dart
```

Expected: PASS。

- [ ] **Step 7: Commit**

```bash
git add lib/models/llm/resolved_model_budget.dart lib/services/model_capability_resolver.dart lib/models/session/model_budget_profile.dart lib/services/model_budget_registry.dart test/services/model_budget_registry_test.dart test/services/model_capability_resolver_test.dart
git commit -m "refactor: separate model capability facts from budget policy"
```

## Task 3: 接入 Anthropic / Gemini provider metadata source

**Files:**
- Create: `lib/services/model_capability_sources/provider_model_capability_source.dart`
- Create: `lib/services/model_capability_sources/anthropic_model_capability_source.dart`
- Create: `lib/services/model_capability_sources/gemini_model_capability_source.dart`
- Modify: `lib/services/model_capability_resolver.dart`
- Test: `test/services/model_capability_sources/anthropic_model_capability_source_test.dart`
- Test: `test/services/model_capability_sources/gemini_model_capability_source_test.dart`
- Test: `test/services/model_capability_resolver_test.dart`

- [ ] **Step 1: 先写 Anthropic source 失败测试，锁定响应字段映射**

```dart
test('maps anthropic model metadata into resolved capability', () async {
  final source = AnthropicModelCapabilitySource(
    httpClient: _FakeHttpClient.json({
      'data': [
        {
          'id': 'claude-sonnet-4-5',
          'context_window': 200000,
          'max_output_tokens': 32000,
        },
      ],
    }),
  );

  final capability = await source.fetch(
    providerId: 'anthropic',
    modelId: 'claude-sonnet-4-5',
    baseUrl: 'https://api.anthropic.com/v1/messages',
  );

  expect(capability?.contextWindowTotal, 200000);
  expect(capability?.maxOutputTokens, 32000);
});
```

- [ ] **Step 2: 先写 Gemini source 失败测试，锁定 `inputTokenLimit/outputTokenLimit` 映射**

```dart
test('maps gemini getModel response into resolved capability', () async {
  final source = GeminiModelCapabilitySource(
    httpClient: _FakeHttpClient.json({
      'name': 'models/gemini-2.5-pro',
      'inputTokenLimit': 1048576,
      'outputTokenLimit': 65536,
    }),
  );

  final capability = await source.fetch(
    providerId: 'gemini',
    modelId: 'gemini-2.5-pro',
    baseUrl: 'https://generativelanguage.googleapis.com',
  );

  expect(capability?.maxInputTokens, 1048576);
  expect(capability?.maxOutputTokens, 65536);
});
```

- [ ] **Step 3: 运行 source 测试确认实现缺失**

Run:

```bash
fvm flutter test test/services/model_capability_sources/anthropic_model_capability_source_test.dart
fvm flutter test test/services/model_capability_sources/gemini_model_capability_source_test.dart
```

Expected: FAIL。

- [ ] **Step 4: 实现 source 抽象与最小 provider 适配**

抽象接口建议：

```dart
abstract class ProviderModelCapabilitySource {
  bool supports(LLMConfig config);
  Future<ResolvedModelCapability?> fetch(LLMConfig config);
}
```

约束：

- 只在语义明确的 provider 上启用
- 不支持的 provider 必须快速返回 `null`
- 字段缺失时允许部分填充，不做全有全无

- [ ] **Step 5: 把 source 接到 resolver 的 providerMetadata 分支**

resolver 逻辑要求：

- source 命中且 fetch 成功 -> 写 cache -> 返回 provider metadata 结果
- source 命中但失败 -> 继续 catalog / fallback
- source 不支持当前 config -> 直接跳过

- [ ] **Step 6: 跑 source + resolver 测试到绿**

Run:

```bash
fvm flutter test test/services/model_capability_sources/anthropic_model_capability_source_test.dart
fvm flutter test test/services/model_capability_sources/gemini_model_capability_source_test.dart
fvm flutter test test/services/model_capability_resolver_test.dart
```

Expected: PASS。

- [ ] **Step 7: Commit**

```bash
git add lib/services/model_capability_sources/provider_model_capability_source.dart lib/services/model_capability_sources/anthropic_model_capability_source.dart lib/services/model_capability_sources/gemini_model_capability_source.dart lib/services/model_capability_resolver.dart test/services/model_capability_sources/anthropic_model_capability_source_test.dart test/services/model_capability_sources/gemini_model_capability_source_test.dart test/services/model_capability_resolver_test.dart
git commit -m "feat: add provider model capability sources"
```

## Task 4: 接入 catalog fallback，并固定 `cache -> fallback -> background refresh` 行为

**Files:**
- Create: `lib/services/model_capability_sources/catalog_model_capability_source.dart`
- Modify: `lib/services/model_capability_resolver.dart`
- Modify: `lib/repositories/app_settings_repository.dart`
- Test: `test/services/model_capability_sources/catalog_model_capability_source_test.dart`
- Test: `test/services/model_capability_resolver_test.dart`

- [ ] **Step 1: 先写 catalog source 失败测试，锁定 canonical spec 映射**

```dart
test('maps catalog model spec into resolved capability', () async {
  final source = CatalogModelCapabilitySource(
    httpClient: _FakeHttpClient.json({
      'id': 'openai/gpt-5',
      'context_window': 1000000,
      'max_input_tokens': 256000,
      'max_output_tokens': 32000,
    }),
  );

  final capability = await source.fetch(
    providerId: 'openai',
    modelId: 'gpt-5',
    baseUrl: 'https://api.openai.com/v1',
  );

  expect(capability?.contextWindowTotal, 1000000);
  expect(capability?.maxInputTokens, 256000);
});
```

- [ ] **Step 2: 运行 catalog source 测试确认实现缺失**

Run: `fvm flutter test test/services/model_capability_sources/catalog_model_capability_source_test.dart`

Expected: FAIL。

- [ ] **Step 3: 实现 catalog source，并把 endpoint/details 收敛在单文件**

要求：

- catalog fetch 逻辑不要散落在 resolver
- source 内负责请求、字段映射、最小错误兜底
- 失败返回 `null`，不抛出阻断主流程的异常

- [ ] **Step 4: 实现 resolver 的严格顺序**

运行时解析顺序固定为：

1. `local override`
2. `provider metadata`
3. `catalog`
4. `built-in fallback`

同步读取时固定为：

1. `local override`
2. `cached provider/catalog result`
3. `built-in fallback`

并在 `resolveCachedOrFallback()` 中触发非阻塞后台刷新入口。

- [ ] **Step 5: 补失败测试，锁定“即使刷新失败也不阻塞主路径”**

新增 resolver 测试验证：

- 无 cache 且 provider/catalog 全失败时，仍有 built-in fallback
- 有旧 cache 时，刷新失败不清空旧值

- [ ] **Step 6: 跑 catalog / resolver 测试到绿**

Run:

```bash
fvm flutter test test/services/model_capability_sources/catalog_model_capability_source_test.dart
fvm flutter test test/services/model_capability_resolver_test.dart
```

Expected: PASS。

- [ ] **Step 7: Commit**

```bash
git add lib/services/model_capability_sources/catalog_model_capability_source.dart lib/services/model_capability_resolver.dart lib/repositories/app_settings_repository.dart test/services/model_capability_sources/catalog_model_capability_source_test.dart test/services/model_capability_resolver_test.dart
git commit -m "feat: add catalog-backed capability fallback"
```

## Task 5: 让 session 预算体系改为消费 `ResolvedModelBudget`

**Files:**
- Modify: `lib/services/session_token_budget_service.dart`
- Modify: `lib/services/session_context_service.dart`
- Modify: `lib/services/session_context_inspector_service.dart`
- Modify: `lib/providers/chat_dependency_providers.dart`
- Modify: `lib/main.dart`
- Modify: `lib/models/llm/llm_factory.dart`
- Test: `test/services/session_token_budget_service_test.dart`
- Test: `test/providers/chat_dependency_providers_test.dart`
- Test: `test/services/session_context_inspector_service_test.dart`

- [ ] **Step 1: 先写 budget service 失败测试，锁定同步读取 cached-or-fallback 行为**

```dart
test('derives planner budget from resolved model capability and policy', () {
  final resolver = _FakeModelCapabilityResolver(
    cachedBudget: ResolvedModelBudget(
      capability: const ResolvedModelCapability(
        providerId: 'openai',
        providerStyle: ApiStyle.responses,
        baseUrlFingerprint: 'openai::v1',
        modelId: 'gpt-5',
        contextWindowTotal: 1000000,
        maxInputTokens: 256000,
        maxOutputTokens: 32000,
        source: ModelCapabilitySourceKind.catalog,
      ),
      policy: const ModelBudgetProfile(
        modelId: 'gpt-5-policy',
        maxContextTokens: 0,
        reservedOutputTokens: 12000,
        reasoningReserveTokens: 8000,
        safetyMarginTokens: 4000,
        compactionConfig: ContextCompactionConfig(
          autoCompactBufferTokens: 4000,
        ),
      ),
    ),
  );

  final service = SessionTokenBudgetService(modelCapabilityResolver: resolver);
  final result = service.evaluatePlannerBudget(
    runtimeConfig: const LLMConfig(
      apiKey: 'k',
      apiUrl: 'https://api.openai.com/v1',
      model: 'gpt-5',
      apiStyle: ApiStyle.responses,
      additionalConfig: {
        'llm.selected_provider_id': 'openai',
        'llm.selected_base_url': 'https://api.openai.com/v1',
      },
    ),
    fixedPrefixTokens: 2000,
    summaryTokens: 1000,
    recentTurnsTokens: 4000,
    currentTurnTokens: 3000,
    toolSchemaTokens: 2000,
  );

  expect(result.effectiveInputBudget, 256000 - 12000 - 8000 - 4000);
});
```

- [ ] **Step 2: 运行 budget 测试确认当前接口仍只接受 `modelName`**

Run: `fvm flutter test test/services/session_token_budget_service_test.dart`

Expected: FAIL，因为 service 当前只按 `modelName` 解析静态 profile。

- [ ] **Step 3: 重构 `SessionTokenBudgetService` 输入**

最小改造方向：

- 保留旧 `modelName` API 仅作过渡
- 新增以 `LLMConfig` 或 `ResolvedModelBudget` 为输入的正式 API
- `resolveProfile` 过渡为 `resolveBudgetForRuntime` / `resolveCachedBudgetForRuntime`

### 约束

- session / inspector 主链路不得在每次读取时阻塞等待联网
- `SessionContextService` 和 `SessionContextInspectorService` 都使用同一个 resolver 实例

- [ ] **Step 4: 在 provider/main 工厂层接入共享 resolver**

需要新增 provider / main 注入：

- `modelCapabilityResolverProvider`
- `sessionTokenBudgetServiceProvider` 使用 resolver 而非裸 registry
- `LLMFactory` / `ConfigurableHttpLLM` 也拿到同一个 resolver

- [ ] **Step 5: 补失败测试，锁定 inspector 中 capability source 可见**

新增测试验证：

- inspector snapshot 中可访问 `effectiveInputBudget`
- 若 budget 来自 catalog / provider metadata，debug segment 或 snapshot metadata 至少能带出 source

- [ ] **Step 6: 跑 budget / provider 测试到绿**

Run:

```bash
fvm flutter test test/services/session_token_budget_service_test.dart
fvm flutter test test/providers/chat_dependency_providers_test.dart
fvm flutter test test/services/session_context_inspector_service_test.dart
```

Expected: PASS。

- [ ] **Step 7: Commit**

```bash
git add lib/services/session_token_budget_service.dart lib/services/session_context_service.dart lib/services/session_context_inspector_service.dart lib/providers/chat_dependency_providers.dart lib/main.dart lib/models/llm/llm_factory.dart test/services/session_token_budget_service_test.dart test/providers/chat_dependency_providers_test.dart test/services/session_context_inspector_service_test.dart
git commit -m "refactor: route session budgets through capability resolver"
```

## Task 6: 让 `ConfigurableHttpLLM` 与三条 provider 主链路使用同一份 budget

**Files:**
- Modify: `lib/models/llm/configurable_http_llm.dart`
- Modify: `lib/models/llm/adapters/sdk_chat_completions_adapter.dart`
- Modify: `lib/models/llm/adapters/sdk_anthropic_messages_adapter.dart`
- Modify: `lib/models/llm/adapters/sdk_responses_adapter.dart`
- Modify: `test/models/llm/configurable_http_llm_test.dart`
- Modify: `test/models/llm/adapters/sdk_chat_completions_adapter_test.dart`
- Create: `test/models/llm/adapters/sdk_responses_adapter_test.dart`
- Create: `test/models/llm/adapters/sdk_anthropic_messages_adapter_test.dart`

- [ ] **Step 1: 先写 `ConfigurableHttpLLM` 失败测试，锁定按 capability 上限 clamp 输出**

```dart
test('caps planner maxOutputTokens by resolved capability maxOutputTokens',
    () async {
  final llm = await _buildLlmWithCapabilityBudget(
    resolvedBudget: _resolvedBudget(
      contextWindowTotal: 1000000,
      maxInputTokens: 256000,
      maxOutputTokens: 4096,
      reservedOutputTokens: 12000,
      reasoningReserveTokens: 8000,
    ),
  );

  final options = llm.debugRequestOptionsForTest(
    purpose: LlmRequestPurpose.planner,
  );

  expect(options.maxOutputTokens, 4096);
});
```

- [ ] **Step 2: 写 `sdk_responses_adapter` 失败测试，锁定必须下发 `max_output_tokens`**

```dart
test('writes max_output_tokens into responses payload', () {
  const adapter = SdkResponsesAdapter();
  final payload = adapter.buildChatPayload(
    messages: [ChatMessage(text: '继续', role: MessageRole.user)],
    config: ChatConfig(systemPrompt: ''),
    modelName: 'gpt-5',
    stream: false,
    requestOptions: const LlmRequestOptions(maxOutputTokens: 4096),
  );

  expect(payload['max_output_tokens'], 4096);
});
```

- [ ] **Step 3: 写 `sdk_anthropic_messages_adapter` 失败测试，锁定默认值不再裸写 `4096`**

```dart
test('uses requestOptions maxOutputTokens for anthropic sdk payload', () {
  const adapter = SdkAnthropicMessagesAdapter();
  final payload = adapter.buildChatPayload(
    messages: [ChatMessage(text: 'hi', role: MessageRole.user)],
    config: ChatConfig(systemPrompt: ''),
    modelName: 'claude',
    stream: false,
    requestOptions: const LlmRequestOptions(maxOutputTokens: 12000),
  );

  expect(payload['max_tokens'], 12000);
});
```

- [ ] **Step 4: 运行聚焦测试确认当前行为不完整**

Run:

```bash
fvm flutter test test/models/llm/configurable_http_llm_test.dart
fvm flutter test test/models/llm/adapters/sdk_chat_completions_adapter_test.dart
fvm flutter test test/models/llm/adapters/sdk_responses_adapter_test.dart
fvm flutter test test/models/llm/adapters/sdk_anthropic_messages_adapter_test.dart
```

Expected: FAIL，至少 `responses` 分支会缺 `max_output_tokens`。

- [ ] **Step 5: 重构 `ConfigurableHttpLLM` 的 request option 组装**

要求：

- `_requestOptionsFor()` 不再仅看 `modelName`
- 改为基于 resolver 返回的 `ResolvedModelBudget`
- 真正下发值使用：

```text
min(capability.maxOutputTokens 或 +inf, policyForPurpose)
```

- [ ] **Step 6: 补齐三条 adapter 主链路**

确认：

- chat completions -> `max_completion_tokens`
- anthropic messages -> `max_tokens`
- responses -> `max_output_tokens`

且字段名都来自 `requestOptions.maxOutputTokens`，不再在 adapter 内随手写死默认值。

- [ ] **Step 7: 跑 LLM / adapter 测试到绿**

Run:

```bash
fvm flutter test test/models/llm/configurable_http_llm_test.dart
fvm flutter test test/models/llm/adapters/sdk_chat_completions_adapter_test.dart
fvm flutter test test/models/llm/adapters/sdk_responses_adapter_test.dart
fvm flutter test test/models/llm/adapters/sdk_anthropic_messages_adapter_test.dart
```

Expected: PASS。

- [ ] **Step 8: Commit**

```bash
git add lib/models/llm/configurable_http_llm.dart lib/models/llm/adapters/sdk_chat_completions_adapter.dart lib/models/llm/adapters/sdk_anthropic_messages_adapter.dart lib/models/llm/adapters/sdk_responses_adapter.dart test/models/llm/configurable_http_llm_test.dart test/models/llm/adapters/sdk_chat_completions_adapter_test.dart test/models/llm/adapters/sdk_responses_adapter_test.dart test/models/llm/adapters/sdk_anthropic_messages_adapter_test.dart
git commit -m "fix: align provider max output tokens with resolved budget"
```

## Task 7: 文档、回归与最终验证

**Files:**
- Modify: `docs/architecture/session-context-management.md`
- Modify: `docs/architecture/provider-adapter-runtime-and-live-matrix.md`
- Modify: `docs/superpowers/specs/2026-06-11-multi-provider-model-capability-and-budget-strategy-design.md`（若实现中发现必要勘误）

- [ ] **Step 1: 更新架构文档，明确 capability facts / budget policy 分层**

至少更新：

- `SessionTokenBudgetService` 现在依赖 capability resolver
- `ConfigurableHttpLLM` 的 `maxOutputTokens` 来自 resolved budget
- `provider metadata / catalog / local override / fallback` 的解析顺序

- [ ] **Step 2: 跑核心测试矩阵**

Run:

```bash
fvm flutter test test/repositories/app_settings_repository_test.dart
fvm flutter test test/repositories/llm_local_defaults_test.dart
fvm flutter test test/services/model_budget_registry_test.dart
fvm flutter test test/services/model_capability_resolver_test.dart
fvm flutter test test/services/model_capability_sources/anthropic_model_capability_source_test.dart
fvm flutter test test/services/model_capability_sources/gemini_model_capability_source_test.dart
fvm flutter test test/services/model_capability_sources/catalog_model_capability_source_test.dart
fvm flutter test test/services/session_token_budget_service_test.dart
fvm flutter test test/providers/chat_dependency_providers_test.dart
fvm flutter test test/models/llm/configurable_http_llm_test.dart
fvm flutter test test/models/llm/adapters/sdk_chat_completions_adapter_test.dart
fvm flutter test test/models/llm/adapters/sdk_responses_adapter_test.dart
fvm flutter test test/models/llm/adapters/sdk_anthropic_messages_adapter_test.dart
```

Expected: PASS。

- [ ] **Step 3: 运行聚焦 analyze**

Run:

```bash
fvm flutter analyze lib/models/llm lib/services lib/repositories test/models/llm test/services test/repositories
```

Expected: PASS，或仅剩与本改动无关的既有噪音；若有新告警，必须清掉。

- [ ] **Step 4: 若本地有凭据，执行最小 live provider 回归**

Run:

```bash
bash scripts/run_live_llm_contract_tests.sh minimax-openai
HEADLESS_LIVE_PROVIDER_RESPONSES=minimax-openai fvm flutter test --tags live-headless-agent test/integration/chat_send_live/chat_send_live_responses_test.dart
HEADLESS_LIVE_PROVIDER_ANTHROPIC=minimax-anthropic fvm flutter test --tags live-headless-agent test/integration/chat_send_live/chat_send_live_anthropic_test.dart
```

Expected: 至少覆盖 `responses` 与 `anthropic messages` 两条 API 风格各 1 个真实 provider。

- [ ] **Step 5: Commit**

```bash
git add docs/architecture/session-context-management.md docs/architecture/provider-adapter-runtime-and-live-matrix.md
git commit -m "docs: document model capability resolution strategy"
```

## 实施注意事项

- `SessionTokenBudgetService` 不能被改造成“每次都 await 网络”的服务；主链路必须先用 cache/fallback 可用。
- `ModelBudgetRegistry` 的旧 `resolve()` 若保留兼容接口，必须在实现里明确标注为过渡层，避免后续新代码继续依赖它当主事实源。
- `responses` adapter 补 `max_output_tokens` 时，不要顺手改动其他 payload 语义，避免把这次重构扩大成 responses 协议回归。
- local override 先落在现有 provider/model settings JSON 里即可；V1 不要为了 override 单独引入新 UI 或数据库表。
- provider metadata / catalog 的部分字段允许缺省并做字段级回退，不要做“只要缺一个字段就整条来源作废”的全有全无逻辑。
