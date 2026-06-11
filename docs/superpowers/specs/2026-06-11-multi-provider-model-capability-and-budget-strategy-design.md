# 多 Provider 模型能力与 Token/Context 预算策略设计

## 摘要

当前项目的 token/context 预算仍以 [`ModelBudgetRegistry`](/Users/zyb_wl/flutterSpace/FlutterAIChat/lib/services/model_budget_registry.dart) 内置静态表为主数据源，这在模型窗口普遍提升到 `200K`、`1M`，且不同 provider / gateway / openai-compatible 平台能力差异越来越大的情况下，已经明显不够用。

本设计将当前“静态预算表中心”的方案升级为“模型能力解析链中心”的方案：

- 显式区分“模型事实”与“产品策略”
- 优先读取 provider 官方可得的模型元数据
- provider 无法提供时回退到外部模型目录
- 再回退到本地 built-in fallback
- 仍保留显式本地 override 作为最高优先级人工兜底

新方案的核心不是“把所有预算都动态化”，而是：

> 让 `max context` / `max input` / `max output` 这些模型事实，尽量来自外部真实能力；再由应用自己的预算策略，把这些事实转成 compaction 判断与 provider 请求里的 `maxOutputTokens`。

## 背景

当前实现存在三个结构性问题：

### 1. `ModelBudgetRegistry` 主要依赖内置静态 profile

当前 [`ModelBudgetRegistry`](/Users/zyb_wl/flutterSpace/FlutterAIChat/lib/services/model_budget_registry.dart) 只支持：

- exact match
- family match
- fallback

虽然保留了 `runtimeOverrides` 扩展点，但应用实际注入的是默认 `ModelBudgetRegistry()`，当前主链路并没有真正接入 provider metadata、模型目录或用户侧 override。

### 2. 模型能力事实与产品预算策略被混在一起

当前 `ModelBudgetProfile` 同时承担两类职责：

- 模型上限事实
  - `maxContextTokens`
  - `providerInputCap`
- 产品策略
  - `reservedOutputTokens`
  - `reasoningReserveTokens`
  - `safetyMarginTokens`
  - `compactionConfig`

这种混合在“完全手配静态表”阶段还可以接受，但一旦引入 provider metadata 或模型目录，就会出现语义问题：

- provider 能告诉我们模型的最大 input / output / context
- provider 不会替我们决定“本产品 planner 要预留多少输出”
- provider 更不会替我们决定“压缩触发 buffer 应该是多少”

因此这两层必须拆开。

### 3. 当前 `maxOutputTokens` 分配策略无法利用更真实的模型上限

当前 [`ConfigurableHttpLLM`](/Users/zyb_wl/flutterSpace/FlutterAIChat/lib/models/llm/configurable_http_llm.dart) 中：

- `planner` 请求使用 `reservedOutputTokens`
- `summary` / `webpageProcessing` / `sideTask` 使用 `reservedOutputTokens + reasoningReserveTokens`

这套规则本身不是问题，问题在于它依赖的 profile 上限过旧、过粗，而且 `responses` adapter 当前甚至没有显式下发 `max_output_tokens`。

## 本轮明确决策

### 1. 模型能力事实与产品预算策略分层

新架构中：

- `模型能力事实` 由解析链提供
- `产品预算策略` 由本应用自己维护

模型能力事实至少包括：

- `contextWindowTotal`
- `maxInputTokens`
- `maxOutputTokens`
- `capabilities`
- `source`

产品预算策略至少包括：

- `reservedOutputTokens`
- `reasoningReserveTokens`
- `safetyMarginTokens`
- `autoCompactBufferTokens`
- `compressionTriggerRatio`

### 2. 不做“完全在线动态化”

本轮不是把预算系统改成“每次请求前都联网查 provider”。

原因有三点：

1. 多 provider 场景下，各家元数据接口并不统一
2. 某些 provider 根本不给 context / input / output 上限
3. 移动端应用不能把“预算计算依赖实时联网取模型能力”作为前提

因此本轮采用：

> 显式缓存的多源解析链，而不是每次实时查询。

### 3. 本地显式 override 仍然保留，而且优先级最高

虽然我们整体方向是“provider metadata 优先”，但这里需要纠正一个容易混淆的表述：

- 自动来源的优先级，应尽量 `provider metadata > catalog > built-in fallback`
- 但人工显式配置的 `local override` 必须高于所有自动来源

理由很直接：

- private gateway
- openai-compatible 私有部署
- 某些代理平台对同名模型做人为限流 / 限窗
- 团队需要临时降窗、封顶、禁用 1M

这些场景都要求人工 override 能强制生效。

### 4. 当前项目中的 `ModelBudgetRegistry` 不再做主事实源

改造后，`ModelBudgetRegistry` 不再承担“模型能力主事实源”的职责，而是收缩为：

- built-in fallback 数据承载层
- policy default 承载层
- capability resolution 失败时的最后兜底

### 5. 本轮不做 session memory

本设计只处理模型能力解析、context/input/output 预算和 compaction / provider request 的衔接，不涉及：

- session memory
- cross-session memory
- messagesToKeep

## 目标

本轮目标如下：

- 让 `max context` / `max input` / `max output` 尽量来自真实模型能力，而不是过时静态表
- 保持多 provider 兼容，不把某一家 provider 的接口当成通用前提
- 把“模型能力事实”与“产品策略预算”彻底拆开
- 让 compaction、UI usage ratio、provider `maxOutputTokens` 使用同一套能力解析结果
- 为后续支持更多 provider / catalog / override 留出清晰扩展点

## 非目标

本轮不包含以下内容：

- 不实现跨 session memory
- 不重做 summary prompt 结构
- 不重做 active-turn auto-compaction restart
- 不引入“每次请求前联网探测模型能力”的强依赖
- 不让用户在普通聊天主流程中手动维护复杂 token 参数
- 不把 provider metadata 原样暴露给所有 UI

## 外部参考与结论

本轮设计参考了几类主流产品：

### 1. 配置驱动类

以 Continue / Cline 为代表。

特点：

- `contextLength` / `maxTokens` 作为模型配置字段显式配置
- 更偏“用户/产品手动声明”
- 不依赖统一 provider metadata

适用于：

- IDE 插件
- 高度可配置的 power-user 工具

局限：

- 事实更新依赖人工维护
- 对多 provider / 多 gateway 场景不够稳

### 2. 模型目录驱动类

以 OpenCode / Models.dev 为代表。

特点：

- 通过统一模型目录拿 canonical 模型规格
- 对多 provider 产品更友好
- provider 无统一接口时也能提供较高覆盖率

适用于：

- 多 provider Agent
- openai-compatible / gateway 较多的产品

局限：

- 目录可能滞后
- 某个具体 gateway 的真实限制未必与 canonical 模型一致

### 3. 混合策略类

以本地 Claude Code 的实现最有参考价值。

它会：

- 先尝试读取缓存的 provider model capability
- 再看 beta/header / model suffix / feature flag / env override
- 最后回到本地默认值

这说明成熟产品并不是“纯写死”或“纯动态获取”二选一，而是：

> 自动能力来源 + 本地 fallback + 人工 override 的混合解析链。

本项目也应采用这一方向。

## 核心概念分层

## 1. 模型能力事实层

这是“模型实际上支持什么”的事实描述，不包含任何产品策略。

建议新增统一结构 `ResolvedModelCapability`：

```text
ResolvedModelCapability
- providerId
- providerStyle
- baseUrlFingerprint
- modelId
- canonicalModelId?
- displayName?
- contextWindowTotal?
- maxInputTokens?
- maxOutputTokens?
- supportsReasoning?
- rawCapabilities
- source
- fetchedAt
- expiresAt
```

字段说明：

- `providerId`
  - 当前实际配置中的 provider 标识，例如本地 settings 中的 provider entry id
- `providerStyle`
  - `responses` / `chatCompletions` / `anthropicMessages` 等协议风格
- `baseUrlFingerprint`
  - 用于区分“同名模型在不同网关/endpoint 下能力不同”
- `modelId`
  - 当前请求实际使用的模型名
- `canonicalModelId`
  - 若来自 catalog，可映射到统一 canonical id
- `contextWindowTotal`
  - 总上下文窗口上限
- `maxInputTokens`
  - provider 若显式给出单次输入上限，则记录；否则可为空
- `maxOutputTokens`
  - provider 若显式给出输出上限，则记录
- `rawCapabilities`
  - 原始 provider / catalog 返回字段，供调试和后续扩展使用
- `source`
  - `localOverride` / `providerMetadata` / `catalog` / `builtInFallback`

### 2. 产品预算策略层

这是“本应用决定如何消费模型能力”的策略描述。

建议保留或演进当前 `ModelBudgetProfile`，但让它只表达策略，不再同时扮演主事实源：

```text
BudgetPolicyProfile
- reservedOutputTokens
- reasoningReserveTokens
- safetyMarginTokens
- autoCompactBufferTokens
- compressionTriggerRatio
- purposeOverrides?
```

说明：

- `reservedOutputTokens`
  - planner 主请求要给可见输出预留多少
- `reasoningReserveTokens`
  - summary / side task / reasoning-heavy 场景额外预留多少
- `safetyMarginTokens`
  - 总是保留不用的安全头寸
- `autoCompactBufferTokens`
  - 自动压缩正式阈值缓冲

### 3. 运行时派生预算层

运行时真正参与 compaction / request 构造的预算，是“事实 + 策略”计算后的结果。

建议新增或显式化 `ResolvedModelBudget`：

```text
ResolvedModelBudget
- capability
- policy
- effectiveContextWindow
- effectiveInputBudget
- plannerMaxOutputTokens
- summaryMaxOutputTokens
- sideTaskMaxOutputTokens
```

## 数据源优先级

统一优先级定义如下：

1. `local override`
2. `provider metadata`
3. `catalog`
4. `built-in fallback`

### 1. `local override`

显式本地 override 是最高优先级，用于：

- private deployment
- openai-compatible 自定义网关
- provider 实际限制与公开规格不一致
- 团队运维临时降档

override 应允许单独覆盖：

- `contextWindowTotal`
- `maxInputTokens`
- `maxOutputTokens`
- strategy policy 部分字段

但未提供的字段应继续向下游来源回退，不要求 override 一次性写全所有字段。

### 2. `provider metadata`

若 provider 官方或 SDK 能稳定给出模型上限，应优先采用。

当前已知适合接入的 provider 类型：

- Anthropic models API
- Gemini models API
- 后续若其他 provider / SDK 能稳定返回 input/output/context 上限，也可纳入

这里的重点不是“支持的 provider 越多越好”，而是：

> 只接入我们能稳定验证、字段语义明确的 provider metadata。

### 3. `catalog`

当 provider metadata 不可得、不可用或字段不全时，回退到 catalog。

本轮推荐 catalog 方案：

- `Models.dev` 或等价模型目录

catalog 适合解决：

- OpenAI Models API 未返回 context/input/output 上限
- openai-compatible 平台协议相同但能力字段缺失
- 某些第三方 provider 缺少统一 capability endpoint

### 4. `built-in fallback`

当以上来源都失败时，回退到内置保守默认值。

这一层不追求“最新最全”，只追求：

- 可离线工作
- 保守安全
- 不让产品彻底失去预算能力

## 解析与缓存架构

建议新增三个角色：

### 1. `ModelCapabilityResolver`

负责解析当前运行时模型能力。

输入：

- `providerId`
- `providerStyle`
- `baseUrl`
- `modelId`

输出：

- `ResolvedModelCapability`

职责：

- 调用本地 override
- 查 provider metadata cache
- 必要时触发 provider metadata fetch
- 查 catalog cache
- 必要时触发 catalog fetch
- fallback 到 built-in

### 2. `ModelCapabilityCache`

负责缓存 provider metadata 与 catalog 结果。

缓存 key 建议至少包含：

- `providerId`
- `providerStyle`
- `baseUrlFingerprint`
- `modelId`

原因：

- 同名模型在不同 provider 下能力可能不同
- 同一 providerStyle 的不同 base URL 可能是不同 gateway
- 不能只拿 `modelId` 做 cache key

### 3. `BudgetPolicyRegistry`

负责提供产品策略默认值。

它不再直接回答“这个模型窗口是多少”，而是回答：

- 对这个模型 / family，我们默认预留多少输出
- 是否需要更多 reasoning reserve
- safety margin 和 compaction buffer 多大

这可以由当前 `ModelBudgetRegistry` 演进而来，也可以在重构时拆成新类。

## 缓存策略

### 1. provider metadata cache

建议：

- 持久化到本地
- TTL 较短，例如 `24h`
- 用户切换 provider/model 时可后台刷新
- 请求失败时继续使用未过期旧缓存
- 无缓存且刷新失败时回退下游来源

### 2. catalog cache

建议：

- 持久化到本地
- TTL 较长，例如 `7d`
- 可按需拉取单模型，避免全量目录强依赖
- 请求失败时继续使用旧缓存

### 3. fallback cache 行为

built-in fallback 不需要远程刷新。

### 4. 冷启动行为

冷启动时不要求阻塞主聊天流程等待模型能力联网刷新。

允许：

1. 先按 cache / fallback 给出 `ResolvedModelBudget`
2. 后台刷新 provider metadata / catalog
3. 下一轮请求再自然收敛到更真实的能力值

## 与现有预算体系的衔接

## 1. `SessionTokenBudgetService`

[`SessionTokenBudgetService`](/Users/zyb_wl/flutterSpace/FlutterAIChat/lib/services/session_token_budget_service.dart) 继续作为：

- compaction 正式预算计算器
- planner-visible input usage ratio 计算器

但其输入不应再是“直接从静态 registry resolve 出来的粗粒度 profile”，而应是：

```text
ResolvedModelBudget = ResolvedModelCapability + BudgetPolicyProfile
```

### 2. `effectiveInputBudget`

正式输入预算仍按当前已对齐公式：

```text
effectiveInputBudget =
  min(
    maxInputTokens 或 +inf,
    contextWindowTotal
      - reservedOutputTokens
      - reasoningReserveTokens
      - safetyMarginTokens
  )
```

这里需要注意两个边界：

- 若 provider/capability 没有 `maxInputTokens`，退化为总窗口减预留
- 若 provider 明确给出 input cap，则必须参与正式预算

### 3. `maxOutputTokens` 下发

provider request 中真正下发的 `maxOutputTokens`，不应再直接来自粗糙 family 表，而应来自：

```text
requestMaxOutputTokens =
  min(
    capability.maxOutputTokens 或 +inf,
    policyForPurpose(requestPurpose)
  )
```

其中：

- `planner`
  - 默认使用 `reservedOutputTokens`
- `summary` / `webpageProcessing` / `sideTask`
  - 默认使用 `reservedOutputTokens + reasoningReserveTokens`

这样可以保证两点：

1. 应用不会请求超过 provider 模型输出上限的值
2. 应用仍能维持自己的产品侧策略

### 4. `responses` adapter 对齐

本轮实现时应顺手修正一个已确认的问题：

- `chatCompletions` 已下发 `max_completion_tokens`
- `anthropicMessages` 已下发 `max_tokens`
- `responses` 当前未显式下发 `max_output_tokens`

新预算体系落地时，`responses` 必须补齐这一能力。

## 与现有上下文压缩/UI 的衔接

### 1. 压缩触发口径继续统一到 `plannerInputUsageRatio`

这一轮不改变已对齐的 compaction 方向：

- 自动压缩正式判定继续看 `plannerInputUsageRatio`
- `effectiveInputBudget` 仍是正式分母之一

改变的是“这个预算建立在哪些事实上”：

- 以前：主要依赖静态 family/profile
- 以后：依赖 `ResolvedModelCapability`

### 2. UI 可视化继续区分主指标与诊断值

主展示指标仍建议保持：

- `plannerInputUsageRatio`

诊断值可额外展示：

- `contextWindowTotal`
- `maxInputTokens`
- `effectiveInputBudget`
- `capability source`

但不应让普通用户理解成本变高。

### 3. `web_search` 等工具膨胀问题不会由本设计单独解决

本设计只解决“预算事实源过时/粗糙”的问题。

`web_search`、`fetch_webpage` 等在活跃 turn 内引发的上下文膨胀，仍应依赖：

- summary-only auto-compaction restart
- 更真实的 effective input budget

而不是在本设计里额外引入新的工具结果裁剪策略。

## Provider 接入优先级建议

为了控制实现复杂度，本轮推荐以下顺序：

### Phase 1

- 本地 override
- Anthropic provider metadata
- Gemini provider metadata
- catalog fallback
- built-in fallback

理由：

- Anthropic / Gemini 官方能力字段更明确
- OpenAI 当前 Models API 不能作为统一上限事实源依赖
- 多数 openai-compatible 场景先通过 catalog + local override 覆盖更现实

### Phase 2

- 补更多 provider / SDK capability 接口
- 补更多 openai-compatible 平台特例
- 允许 debug 页查看 capability 解析链来源

## 配置与存储建议

建议新增本地持久化结构，至少记录：

```text
model_capability_cache
- provider_id
- provider_style
- base_url_fingerprint
- model_id
- source
- context_window_total
- max_input_tokens
- max_output_tokens
- raw_json
- fetched_at
- expires_at
```

建议新增本地 override 结构，至少支持：

```text
model_capability_overrides
- provider_id?
- provider_style?
- base_url_pattern?
- model_pattern
- context_window_total?
- max_input_tokens?
- max_output_tokens?
- reserved_output_tokens?
- reasoning_reserve_tokens?
- safety_margin_tokens?
- auto_compact_buffer_tokens?
- updated_at
```

说明：

- capability override 与 policy override 可放同一张表，但语义上必须区分
- V1 也可以先不做独立表，先从本地 defaults/config 读入
- 但抽象层必须先设计好，避免以后再大改调用方

## 失败与回退策略

### 1. provider metadata fetch 失败

处理方式：

- 记录日志
- 使用未过期旧缓存
- 若无缓存则回退 catalog

### 2. catalog fetch 失败

处理方式：

- 记录日志
- 使用未过期旧缓存
- 若无缓存则回退 built-in fallback

### 3. 能力字段不完整

常见情况：

- 只有 `contextWindowTotal`
- 没有 `maxInputTokens`
- 没有 `maxOutputTokens`

处理原则：

- 缺失字段只对该字段回退
- 不因为单字段缺失而整体丢弃该来源

例如：

- provider 给了 `maxInputTokens`
- catalog 给了 `maxOutputTokens`
- fallback 给了 `contextWindowTotal`

允许多来源按字段合并，但最终应记录每个字段的实际来源，便于调试。

## 对当前代码结构的影响

建议重构方向如下：

### 1. 新增 `ModelCapabilityResolver`

负责能力解析链。

### 2. `ModelBudgetRegistry` 收缩为 fallback + policy registry

不再作为主事实源。

### 3. `SessionTokenBudgetService` 改为消费 `ResolvedModelBudget`

而不是直接按 `modelName` 查静态 profile。

### 4. `ConfigurableHttpLLM` 统一从解析后的 budget 构造 `LlmRequestOptions`

这样：

- compaction
- planner input usage
- provider `maxOutputTokens`

都从同一份解析结果出发。

## 风险

### 1. 来源冲突导致行为更难解释

如果不记录字段来源，用户会很难理解“为什么今天是 1M，明天又变 200K”。

因此必须保留：

- resolution source
- fetched time
- override hit 情况

### 2. 目录数据与 gateway 实际限制不一致

因此 catalog 不能高于 local override，也不能无条件覆盖 provider metadata。

### 3. 预算事实更新后，压缩触发点可能明显变化

这是预期变化，不应视为回归。

但需要：

- 在 inspector/debug 信息里可见
- 回归测试覆盖典型模型

## 验收标准

完成该方向后，系统应满足：

1. 同一模型在不同 provider/baseUrl 下可以解析出不同 capability
2. provider metadata 可用时，不再盲目依赖 built-in family 默认值
3. provider metadata 不可用时，catalog 可以接管大部分多 provider 场景
4. catalog 不可用时，built-in fallback 仍能保证产品可用
5. `SessionTokenBudgetService` 与 `ConfigurableHttpLLM` 使用同一份解析后 budget
6. provider request 的 `maxOutputTokens` 不会超过模型输出上限
7. `responses` / `chatCompletions` / `anthropicMessages` 三条主链路都能正确下发输出上限

## 与当前方向的关系

本设计不是替代最近的 summary-only auto-compaction restart 方案，而是为它提供更真实的预算地基。

两者关系如下：

- summary-only auto-compaction restart
  - 解决“活跃 turn 内上下文膨胀后如何压缩续跑”
- 本设计
  - 解决“压缩与 request budget 建立在哪些真实能力事实上”

因此建议实现顺序为：

1. 先落模型能力解析链与预算地基
2. 再让 auto-compaction / inspector / provider request 全部切到新预算来源

## 本轮建议

本轮 spec 通过后，下一步 implementation plan 应按以下顺序拆解：

1. 引入 capability 数据模型与 resolver/cache 抽象
2. 接入 local override 与 built-in fallback
3. 接入 Anthropic / Gemini provider metadata
4. 接入 catalog fallback
5. 重构 `ModelBudgetRegistry` 为 policy/fallback 层
6. 改造 `SessionTokenBudgetService`
7. 改造 `ConfigurableHttpLLM` 与三个主 adapter
8. 更新 inspector / debug / regression tests
