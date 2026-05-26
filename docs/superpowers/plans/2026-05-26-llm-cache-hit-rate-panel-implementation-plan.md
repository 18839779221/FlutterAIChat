# LLM Cache Hit Rate Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为项目新增一个可视化的 LLM 缓存命中率面板，第一版挂载到 `Debug Turn Inspector`，默认展示全局最近 N 次请求的 token 级命中率与请求级命中率。

**Architecture:** 保持现有 `File Log -> service/projection -> debug UI` 分层，不把缓存统计写入 transcript 或 ledger。新增独立 `LlmCacheStatsService` 从 `logs/app.log` 解析 `llm.request.done`，再由 `DebugTurnInspectorProjectionService` 组装成 `Cache` tab 投影，最后由 `DebugTurnInspectorSheet` 负责展示。

**Tech Stack:** Flutter/Dart, `flutter_test`, 现有 `Logger` / `logs/app.log`, `DebugTurnInspectorProjectionService`, `DebugTurnInspectorSheet`, Riverpod provider 覆盖测试。

---

### Task 1: 新增缓存统计读模型与日志解析 service

**Files:**
- Create: `lib/models/debug/llm_cache_request_record.dart`
- Create: `lib/models/debug/llm_cache_stats_summary.dart`
- Create: `lib/models/debug/llm_cache_stats_bucket.dart`
- Create: `lib/models/debug/debug_cache_panel_projection.dart`
- Create: `lib/services/debug/llm_cache_stats_service.dart`
- Test: `test/services/debug/llm_cache_stats_service_test.dart`

- [ ] **Step 1: Write the failing tests**

在 `test/services/debug/llm_cache_stats_service_test.dart` 增加覆盖：

```dart
test('parses recent llm.request.done entries and computes hit rates', () async {
  final service = LlmCacheStatsService();
  final projection = await service.readFromLines([
    '2026-05-26T10:00:00.000+08:00 INFO [trace] [ConfigurableHttpLLM] llm.request.done apiStyle=responses inputTokens=100 cachedInputTokens=60 totalMs=900',
    '2026-05-26T10:00:01.000+08:00 INFO [trace] [ConfigurableHttpLLM] llm.request.done apiStyle=chatCompletions inputTokens=50 totalMs=700',
  ], sampleSize: 50);

  expect(projection.summary.totalRequests, 2);
  expect(projection.summary.requestsWithUsage, 2);
  expect(projection.summary.hitRequests, 1);
  expect(projection.summary.totalInputTokens, 150);
  expect(projection.summary.hitInputTokens, 60);
});
```

再补这些 case：

- `cacheReadInputTokens` 也计入命中；
- 坏行会被忽略；
- 没有 usage 时 `requestsWithUsage` 为 0；
- 只保留最近 N 条有效请求；
- 能按 `apiStyle` 分桶。

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
fvm flutter test test/services/debug/llm_cache_stats_service_test.dart
```

Expected: FAIL because the new models and `LlmCacheStatsService` do not exist yet.

- [ ] **Step 3: Write minimal implementation**

实现：

- `LlmCacheRequestRecord`
- `LlmCacheStatsSummary`
- `LlmCacheStatsBucket`
- `DebugCachePanelProjection`
- `LlmCacheStatsService`

`LlmCacheStatsService` 需要：

- 读取日志文件路径；
- 支持直接从 `List<String>` 解析，方便测试；
- 只识别 `[trace] [ConfigurableHttpLLM] llm.request.done`；
- 解析 `key=value` 字段；
- 兼容 `cachedInputTokens` 与 `cacheReadInputTokens`；
- 计算 `requestHitRate` 与 `tokenHitRate`；
- 生成 `by apiStyle` 分桶；
- 支持最近 N 条样本截断；
- 当日志文件不存在或无有效样本时返回 warning / empty projection。

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
fvm flutter test test/services/debug/llm_cache_stats_service_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/debug/llm_cache_request_record.dart lib/models/debug/llm_cache_stats_summary.dart lib/models/debug/llm_cache_stats_bucket.dart lib/models/debug/debug_cache_panel_projection.dart lib/services/debug/llm_cache_stats_service.dart test/services/debug/llm_cache_stats_service_test.dart
git commit -m "feat: add llm cache stats service"
```

### Task 2: 把缓存面板投影接入 DebugTurnInspectorProjectionService

**Files:**
- Modify: `lib/models/debug/debug_turn_inspector_projection.dart`
- Modify: `lib/services/debug/debug_turn_inspector_projection_service.dart`
- Test: `test/services/debug_turn_inspector_projection_service_test.dart`

- [ ] **Step 1: Write the failing tests**

在 `test/services/debug_turn_inspector_projection_service_test.dart` 增加一组测试，验证：

- projection 新增 `cachePanel` 字段；
- 当注入 fake `LlmCacheStatsService` 时，`build()` 能把缓存面板投影挂出来；
- 即使缓存统计为空，也不影响 overview/timeline/context；
- `warningMessage` 能透传到投影。

示例断言：

```dart
expect(projection.cachePanel, isNotNull);
expect(projection.cachePanel!.summary.totalRequests, 3);
expect(projection.cachePanel!.bucketsByApiStyle.single.key, 'responses');
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
fvm flutter test test/services/debug_turn_inspector_projection_service_test.dart
```

Expected: FAIL because `DebugTurnInspectorProjection` does not yet carry cache panel data.

- [ ] **Step 3: Write minimal implementation**

修改：

- `DebugTurnInspectorProjection` 新增 `DebugCachePanelProjection? cachePanel`
- `copyWithSelectedTurn()` 保持该字段
- `DebugTurnInspectorProjectionService` 新增可注入的 `LlmCacheStatsService`
- `build()` 时调用 service 读取默认最近 N 次请求统计
- 把结果挂到 projection

注意：

- service 读取失败不能让整个 debug inspector 构建失败；
- 失败时返回带 warning 的 cache panel 或空 panel；
- 不要把缓存统计混进 timelineEntries 或 contextSections。

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
fvm flutter test test/services/debug_turn_inspector_projection_service_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/debug/debug_turn_inspector_projection.dart lib/services/debug/debug_turn_inspector_projection_service.dart test/services/debug_turn_inspector_projection_service_test.dart
git commit -m "feat: project cache stats into debug inspector"
```

### Task 3: 给 DebugTurnInspectorSheet 增加 Cache Tab 与面板 UI

**Files:**
- Modify: `lib/widgets/debug/debug_turn_inspector_sheet.dart`
- Test: `test/widgets/debug/debug_turn_inspector_sheet_test.dart`

- [ ] **Step 1: Write the failing widget tests**

在 `test/widgets/debug/debug_turn_inspector_sheet_test.dart` 增加覆盖：

- 出现新的 `Cache` tab；
- 进入 `Cache` tab 后能看到：
  - `Token Hit Rate`
  - `Request Hit Rate`
  - `By API Style`
  - `Recent Requests`
- 当 `warningMessage` 不为空时，显示 warning 文案；
- 当 `recentRequests` 为空时，显示空状态。

示例：

```dart
expect(find.text('Cache'), findsOneWidget);
await tester.tap(find.text('Cache'));
await tester.pumpAndSettle();
expect(find.text('Token Hit Rate'), findsOneWidget);
expect(find.text('Request Hit Rate'), findsOneWidget);
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
fvm flutter test test/widgets/debug/debug_turn_inspector_sheet_test.dart
```

Expected: FAIL because the sheet still has only three tabs and no cache UI.

- [ ] **Step 3: Write minimal implementation**

在 `DebugTurnInspectorSheet` 中：

- 把 `TabController` 长度从 3 改为 4；
- 增加 `Cache` tab；
- 新增 `_buildCacheTab(...)` 或类似私有方法；
- 采用现有 debug 面板的只读风格，尽量复用简单卡片/section 结构；
- 展示：
  - summary 指标
  - `by apiStyle` 列表
  - recent requests 列表
  - warning / empty 状态

注意：

- 保持页面仍然只有一个垂直滚动拥有者；
- 避免在每个小卡片内部再放纵向滚动；
- 保持现有偏技术调试风格，不做额外视觉系统扩张。

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
fvm flutter test test/widgets/debug/debug_turn_inspector_sheet_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/debug/debug_turn_inspector_sheet.dart test/widgets/debug/debug_turn_inspector_sheet_test.dart
git commit -m "feat: add cache tab to debug inspector"
```

### Task 4: 接入真实日志路径与缺省行为校验

**Files:**
- Modify: `lib/services/debug/llm_cache_stats_service.dart`
- Inspect: `lib/utils/logger.dart`
- Test: `test/services/debug/llm_cache_stats_service_test.dart`

- [ ] **Step 1: Add a failing test for missing log file**

补一条测试，验证在日志路径不存在时：

- service 不抛异常；
- 返回空 summary；
- `warningMessage` 提示日志缺失。

另补一条测试，验证当 `Logger.logFilePath` 为 `null` 时，面板能给出“当前平台无本地日志文件”的提示。

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
fvm flutter test test/services/debug/llm_cache_stats_service_test.dart
```

Expected: FAIL because the service does not yet handle all missing-log cases.

- [ ] **Step 3: Write minimal implementation**

完善 service：

- 默认读取 `Logger.logFilePath`
- 支持测试注入覆盖路径或行数据
- 缺日志文件 / Web 无日志文件时返回可读 warning
- 不因为坏行或空文件抛异常

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
fvm flutter test test/services/debug/llm_cache_stats_service_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/debug/llm_cache_stats_service.dart test/services/debug/llm_cache_stats_service_test.dart
git commit -m "feat: harden cache stats log loading"
```

### Task 5: 验证计划中的回归范围

**Files:**
- Inspect: modified files from Tasks 1-4
- Test: `test/services/debug/llm_cache_stats_service_test.dart`
- Test: `test/services/debug_turn_inspector_projection_service_test.dart`
- Test: `test/widgets/debug/debug_turn_inspector_sheet_test.dart`

- [ ] **Step 1: Run focused regression tests**

Run:

```bash
fvm flutter test test/services/debug/llm_cache_stats_service_test.dart test/services/debug_turn_inspector_projection_service_test.dart test/widgets/debug/debug_turn_inspector_sheet_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run analyzer on touched files if needed**

Run:

```bash
fvm flutter analyze lib/services/debug lib/models/debug lib/widgets/debug test/services/debug_turn_inspector_projection_service_test.dart test/widgets/debug/debug_turn_inspector_sheet_test.dart
```

Expected: PASS or only pre-existing unrelated warnings. If analyzer output is noisy, record exactly which warnings are pre-existing before proceeding.

- [ ] **Step 3: Manual sanity check of UI wiring**

确认：

- `Debug Turn Inspector` 可以打开；
- 新 `Cache` tab 能切换；
- 没有日志时 UI 显示 warning；
- 有假数据 / 真日志时 metrics 与最近请求列表可读。

- [ ] **Step 4: Commit final integration if needed**

```bash
git add lib/models/debug lib/services/debug lib/widgets/debug test/services/debug_turn_inspector_projection_service_test.dart test/widgets/debug/debug_turn_inspector_sheet_test.dart test/services/debug/llm_cache_stats_service_test.dart
git commit -m "feat: add llm cache hit rate debug panel"
```
