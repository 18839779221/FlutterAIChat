# LLM 缓存命中率面板设计

## 背景

项目当前已经具备 LLM 请求级缓存观测的底层基建：

- `ConfigurableHttpLLM` 会为请求输出 `llm.request.start`、`llm.first_chunk`、`llm.request.done` 等 trace；
- `LlmUsageExtractor` 能从不同 provider 的 `usage` 中提取缓存相关字段；
- `logs/app.log` 是项目当前阶段排障与 trace 观测的主入口；
- `Debug Turn Inspector` 已经作为只读调试面板存在，能够展示 turn overview、timeline 与 context。

但当前仍缺少一个可以直接回答“最近请求缓存命中率如何”的可视化面板。现状问题主要有：

- 只能逐条查日志，无法快速看到总体命中率；
- 无法区分“请求级命中率”和“token 级命中率”；
- 不能快速比较不同 `apiStyle`、provider、model 的缓存表现；
- 虽然已有 Debug 面板，但还没有缓存统计这一层只读聚合视图。

用户当前诉求不是“现在到底有没有命中”或“是否开启了缓存 hints”，而是先做出一个**能够展示缓存命中率的面板**，用于后续分析和对比。

## 目标

本次设计目标：

- 在现有项目中新增一个可见的缓存命中率面板；
- 第一版优先挂载到 `Debug Turn Inspector`；
- 主指标展示 **Token 级命中率**；
- 同时展示 **请求级命中率** 作为辅助指标；
- 默认统计范围为 **全局最近 N 次 LLM 请求**；
- 保留后续复用到设置页 / 全局 Debug 区域的扩展边界；
- 保持现有 `Transcript / Ledger / File Log` 边界，不把缓存统计写入用户时间线或 turn 状态真相。

## 非目标

本轮不做：

- 不改变现有 cache strategy 开关行为；
- 不要求第一版支持开启或配置 provider hints；
- 不把缓存统计持久化到数据库；
- 不新增日志上传、远端 observability 平台或专门 metrics 存储；
- 不做复杂筛选器、排序器、导出功能；
- 不在第一版同时完成设置页全局面板。

## 当前实现事实

### 1. 缓存观测数据来源

当前真实可依赖的数据源是 `logs/app.log` 中的 trace：

- `llm.request.done`

这类日志已经能包含以下字段中的一部分：

- `apiStyle`
- `model`
- `purpose`
- `cacheStrategy`
- `inputTokens`
- `cachedInputTokens`
- `cacheReadInputTokens`
- `cacheWriteInputTokens`
- `cacheMissInputTokens`
- `totalMs`
- `firstChunkMs`

第一版缓存命中率面板应只依赖这一条稳定日志事实，不直接依赖 transcript、timeline message 或临时 UI 状态。

### 2. 现有 Debug 面板

`DebugTurnInspector` 当前已有三块内容：

- `Overview`
- `Timeline`
- `Context`

它本质上是开发调试期的只读面板，适合作为第一版缓存统计展示入口，因为：

- 已经存在调试入口，不必新造一套独立页面；
- 与当前日志/trace 诊断目标一致；
- 第一版可以快速验证指标设计是否合理；
- 后续如需升级为全局页面，可直接复用统计 service。

### 3. 现有架构边界

根据 `docs/architecture/logging.md`：

- File Log 是排障主入口；
- 不应把内部缓存 telemetry 写回 transcript；
- 不应把缓存统计结果当作 ledger 真相；
- UI 面板应消费调试读模型，而不是反向定义底层日志结构。

因此第一版应遵守：

- 统计来源是 `logs/app.log`；
- 统计聚合逻辑在 service 层；
- `DebugTurnInspector` 只展示聚合结果；
- 不新增新的数据库表。

## 方案选择

### 方案 A：直接在 `DebugTurnInspector` 中解析日志文件

不采用。

优点：

- 实现路径最短；
- 不需要额外 service 抽象。

缺点：

- UI 直接承担日志解析，职责过重；
- 后续迁移到设置页或其他调试页面时难复用；
- 日志格式调整会直接影响 widget；
- 测试边界差，不利于独立验证统计口径。

### 方案 B：新增缓存统计 service，`DebugTurnInspector` 作为第一版入口

采用。

做法：

- 新增一个独立的 `LlmCacheStatsService`；
- 由它读取 `logs/app.log`，过滤 `llm.request.done`，解析并聚合缓存统计；
- 新增独立的数据模型，供 UI 只读消费；
- `DebugTurnInspector` 增加一个 `Cache` tab，展示统计结果；
- 后续设置页或全局 Debug 页面复用同一 service。

优点：

- 统计逻辑与 UI 解耦；
- 符合现有 service / projection 分层；
- 后续扩展到全局面板几乎无需重写底层；
- 易于测试日志解析与命中率计算。

缺点：

- 相比直接在 widget 中解析，多一层读模型抽象；
- 需要明确定义日志解析容错行为。

### 方案 C：新增数据库持久化统计表

不采用。

原因：

- 当前项目的缓存观测真相在 File Log，不在 DB；
- 第一版没有必要引入新的存储层；
- 会把调试型指标错误提升为业务级持久化资产；
- 与当前 logging 架构边界不一致。

## 设计概览

第一版采用：

- **数据来源：** `logs/app.log`
- **聚合层：** `LlmCacheStatsService`
- **UI 挂载点：** `Debug Turn Inspector` 新增 `Cache` tab
- **默认统计范围：** 全局最近 N 次 LLM 请求
- **默认主指标：** Token 级命中率
- **默认辅助指标：** 请求级命中率

整体链路如下：

1. `ConfigurableHttpLLM` 已输出 `llm.request.done`
2. `LlmCacheStatsService` 读取并解析日志
3. service 聚合全局最近 N 次请求统计
4. `DebugTurnInspectorProjectionService` 组装 `Cache` tab 所需读模型
5. `DebugTurnInspectorSheet` 展示总览指标、分组摘要与最近请求明细

## 数据模型设计

### 1. 单条请求读模型

新增轻量只读模型，例如：

```dart
class LlmCacheRequestRecord {
  final DateTime timestamp;
  final String? apiStyle;
  final String? modelName;
  final String? purpose;
  final String? cacheStrategy;
  final int? inputTokens;
  final int? cachedInputTokens;
  final int? cacheReadInputTokens;
  final int? cacheWriteInputTokens;
  final int? cacheMissInputTokens;
  final int? totalMs;
  final int? firstChunkMs;
}
```

用途：

- 表示从一条 `llm.request.done` 日志中解析出的请求事实；
- 保留必要字段用于统计和列表展示；
- 不承担 provider 原始 payload 还原职责。

### 2. 聚合摘要模型

新增面板级聚合模型，例如：

```dart
class LlmCacheStatsSummary {
  final int totalRequests;
  final int requestsWithUsage;
  final int hitRequests;
  final int totalInputTokens;
  final int hitInputTokens;
  final double requestHitRate;
  final double tokenHitRate;
}
```

统计口径：

- `hitRequests`：
  - `cachedInputTokens > 0` 视为命中；
  - `cacheReadInputTokens > 0` 视为命中；
  - 两者任一满足即可视为该请求命中。
- `hitInputTokens`：
  - 优先累加 `cachedInputTokens + cacheReadInputTokens`；
  - 不存在时按 0 处理；
  - 不把 `cacheWriteInputTokens` 计入命中 token。
- `requestHitRate = hitRequests / requestsWithUsage`
- `tokenHitRate = hitInputTokens / totalInputTokens`

### 3. 分组统计模型

为 `apiStyle` 等维度预留分组结构，例如：

```dart
class LlmCacheStatsBucket {
  final String key;
  final LlmCacheStatsSummary summary;
}
```

第一版至少支持：

- `by apiStyle`

后续可扩展：

- `by model`
- `by cacheStrategy`
- `by purpose`

### 4. 面板投影模型

为 `DebugTurnInspector` 新增只读投影字段，例如：

```dart
class DebugCachePanelProjection {
  final int sampleSize;
  final LlmCacheStatsSummary summary;
  final List<LlmCacheStatsBucket> bucketsByApiStyle;
  final List<LlmCacheRequestRecord> recentRequests;
  final String? sourceLogPath;
  final String? warningMessage;
}
```

用途：

- 作为 `Cache` tab 的唯一数据输入；
- 保持 UI 简单，不让 widget 再参与统计计算。

## 统计口径设计

### 1. 请求级命中率

定义：

- 分母：`requestsWithUsage`
- 分子：命中缓存的请求数

意义：

- 回答“有多少请求明确命中了缓存”

注意：

- 如果 provider 没有返回 usage，则不进入该指标分母；
- 不能把“无 usage”直接当成 miss。

### 2. Token 级命中率

定义：

- 分母：`totalInputTokens`
- 分子：`cachedInputTokens + cacheReadInputTokens`

意义：

- 回答“输入 token 里有多少比例来自缓存”

这是本次第一版默认主指标，因为它更能反映真实缓存收益大小。

### 3. 样本范围

第一版默认：

- **全局最近 N 次请求**

原因：

- 便于跨 turn、跨 group、跨 provider 对比；
- 比“当前 turn”更接近用户真实想看的全局命中率；
- 同时为后续设置页全局面板打基础。

`N` 建议为固定值，例如 100 或 200。第一版不要求用户手动输入。

## 日志解析策略

### 1. 只解析稳定锚点

第一版只解析：

- `[trace] [ConfigurableHttpLLM] llm.request.done`

不解析：

- `llm.request.start`
- `llm.first_chunk`
- 其他 runtime / temp 日志

原因：

- `llm.request.done` 已经足够支撑命中率统计；
- 可避免多事件拼装一条请求，降低复杂度；
- 第一版优先稳定和容错。

### 2. 解析容错

service 必须容忍以下情况：

- 日志文件不存在；
- 某些字段缺失；
- 某行不是合法缓存统计日志；
- 某字段值不可解析为整数；
- 历史旧日志不含缓存字段。

容错原则：

- 忽略坏行，不中断整个统计；
- 对无法统计的字段按 `null` 或 0 处理；
- UI 展示警告信息而不是崩溃。

### 3. 性能边界

第一版不做复杂索引。

推荐策略：

- 读取日志后按行倒序扫描；
- 只收集最近 N 条符合条件的 `llm.request.done`；
- 避免全文件完整解析后再截断。

这样可以控制大日志文件下的面板刷新成本。

## UI 设计

### 1. 挂载位置

第一版挂在 `Debug Turn Inspector` 中，新增：

- `Cache`

tab 顺序可调整为：

- `Overview`
- `Timeline`
- `Context`
- `Cache`

或将 `Cache` 放在更靠前位置。第一版不要求改变现有其他 tab 的职责。

### 2. `Cache` tab 展示内容

建议从上到下分三层：

#### 总览区

展示：

- `Token Hit Rate`
- `Request Hit Rate`
- `Requests`
- `Requests With Usage`
- `Hit Input Tokens / Total Input Tokens`

#### 分组区

第一版展示：

- `By API Style`

每个分组展示：

- 样本数
- Token 级命中率
- 请求级命中率

#### 最近请求列表

展示最近若干条请求明细：

- 时间
- `apiStyle`
- `model`
- `purpose`
- `inputTokens`
- `cached/hit tokens`
- `totalMs`

用途：

- 让用户既能看汇总，也能快速抽样排查异常请求。

### 3. 空状态与警告

当没有日志文件或没有可解析请求时，展示：

- 空状态说明
- 日志路径
- 可能原因提示

当只有请求但没有 usage 时，展示：

- “当前样本中无可用 usage，无法计算完整命中率”

而不是简单显示 0%，避免误导。

## 架构边界

### 1. 统计逻辑归属

缓存命中率统计属于：

- File Log 驱动的调试读模型

不属于：

- Transcript
- ChatTurn / ChatTurnStep ledger
- Provider runtime state 持久化

### 2. UI 边界

`DebugTurnInspectorSheet` 只负责展示：

- 不直接解析日志；
- 不直接定义命中率口径；
- 不在 widget 中进行聚合计算。

这些逻辑都应由 service / projection 提供。

### 3. 后续复用边界

后续如果要在设置页 / 全局 Debug 区做全局缓存面板，应复用：

- `LlmCacheStatsService`
- 统计读模型
- 日志解析逻辑

而不是在第二个页面重新实现一套。

## 测试策略

### 1. service 单元测试

重点验证：

- 能正确识别 `llm.request.done`
- 能解析 `cachedInputTokens`
- 能解析 `cacheReadInputTokens`
- 能忽略坏行
- 能计算请求级命中率
- 能计算 token 级命中率
- 能按最近 N 条截断
- 能按 `apiStyle` 分桶

### 2. projection 测试

验证：

- `DebugTurnInspectorProjectionService` 能生成 `Cache` tab 所需投影；
- 日志为空、日志缺失、无 usage 时投影内容正确；
- 不影响原有 overview/timeline/context 投影。

### 3. widget 测试

验证：

- `DebugTurnInspectorSheet` 出现 `Cache` tab；
- summary 指标能正确渲染；
- 空状态 / warning 文案能渲染；
- 最近请求列表能展示关键字段。

## 风险与取舍

### 1. 日志格式演进风险

如果后续 `Logger.trace` 输出格式变化，解析器可能失效。

缓解方式：

- 第一版只依赖稳定锚点；
- 使用尽量保守的 key=value 解析；
- 为坏行与旧行保留容错。

### 2. 日志文件过大

大文件下全量解析可能慢。

缓解方式：

- 第一版只扫描最近 N 条有效请求；
- 优先倒序截取；
- 如仍不够，再追加更细粒度优化。

### 3. provider usage 不统一

不同 provider 并不保证都返回 usage。

缓解方式：

- 把“无 usage”视为不可统计，而不是 miss；
- UI 明确显示 `requestsWithUsage`。

## 实施建议

第一版建议拆为三步：

1. 新增缓存统计 service 与读模型
2. 把统计投影接入 `DebugTurnInspectorProjectionService`
3. 给 `DebugTurnInspectorSheet` 增加 `Cache` tab 与基础展示

这样既能快速落地，又能保证后续迁移到设置页时不推翻第一版实现。
