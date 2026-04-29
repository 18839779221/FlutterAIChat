# Inline Artifact Visualizer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有 agent loop、append-only transcript 和 tool ledger 架构上，新增回答增强型 inline artifact 能力，让模型可以通过 `create_artifact` 在回复中嵌入可交互 HTML/SVG，并在同一 turn 内通过现有 `Read/Edit/Write` 持续改写同一 artifact 文件、原位刷新卡片，同时支持跨 turn 快照保留、stale 标记、重启恢复与 group 切换重建。

**Architecture:** 以正式 tool 原生化方案落地：新增 `create_artifact` tool handler、artifact registry 持久化表、artifact 文件存储服务、artifact resolver/read-model builder 和专属 UI block renderer。`Write/Edit` 保持纯文件工具 contract，不显式返回 `artifactId`；artifact 联动只通过“registry 记录的 `sourcePath` + turn ledger/tool result 路径命中”在 projection 层推断，避免污染 `TurnHarness`、`ToolOrchestratorService` 和通用 file tool 语义。

**Tech Stack:** Flutter 3.29.2、Dart、sqflite、Riverpod、webview_flutter（或现有 WebView 依赖）、flutter_test、现有 `ToolRuntimeRegistry` / `ChatTurnStep` / `ChatBlockBuilder` / `ChatMessageList` 主链路。

---

## 文件地图

### 新增文件

- `lib/models/artifact/artifact_type.dart`
- `lib/models/artifact/artifact_record.dart`
- `lib/models/artifact/artifact_create_result.dart`
- `lib/models/artifact/artifact_turn_projection.dart`
- `lib/repositories/artifact_repository.dart`
- `lib/services/artifact/artifact_source_sanitizer.dart`
- `lib/services/artifact/artifact_file_storage_service.dart`
- `lib/services/artifact/artifact_registry_service.dart`
- `lib/services/artifact/artifact_turn_resolver.dart`
- `lib/tools/handlers/create_artifact_tool_handler.dart`
- `lib/widgets/chat_blocks/artifact_block.dart`
- `lib/widgets/chat_blocks/artifact_preview_surface.dart`
- `lib/pages/artifact_detail_page.dart`
- `test/repositories/artifact_repository_test.dart`
- `test/services/artifact/artifact_source_sanitizer_test.dart`
- `test/services/artifact/artifact_file_storage_service_test.dart`
- `test/services/artifact/artifact_turn_resolver_test.dart`
- `test/tools/handlers/create_artifact_tool_handler_test.dart`
- `test/widgets/chat_blocks/artifact_block_test.dart`

### 修改文件

- `lib/database/database_helper.dart`
- `lib/storage/chat_storage.dart`
- `lib/models/agent/chat_turn_step.dart`
- `lib/repositories/chat_turn_step_repository.dart`
- `lib/models/tool/tool_result.dart`
- `lib/models/chat/assistant_turn_block.dart`
- `lib/services/chat_block_builder.dart`
- `lib/services/tool_ui_renderer_registry.dart`
- `lib/widgets/chat_message_list.dart`
- `lib/widgets/chat_blocks/chat_blocks.dart`（如存在统一导出）
- `lib/tools/default_tool_runtime_registry.dart`
- `lib/providers/chat_dependency_providers.dart`
- `lib/providers/chat_providers.dart`
- `lib/main.dart`
- `test/services/chat_block_builder_test.dart`
- `test/widgets/chat_blocks/chat_blocks_test.dart`
- `test/services/session_context_projector_test.dart`（仅补回归断言）
- `README.md`
- `AGENTS.md`
- `docs/architecture/session-context-management.md`
- `docs/architecture/logging.md`

### 参考文件

- `docs/superpowers/specs/2026-04-30-inline-artifact-visualizer-design.md`
- `lib/services/session_context_projector.dart`
- `lib/tools/handlers/write_tool_handler.dart`
- `lib/tools/handlers/edit_tool_handler.dart`
- `lib/services/chat_block_builder.dart`
- `lib/widgets/chat_message_list.dart`

---

## Task 1: 新增 Artifact 持久化模型与数据库表

**Files:**
- Create: `lib/models/artifact/artifact_type.dart`
- Create: `lib/models/artifact/artifact_record.dart`
- Create: `lib/repositories/artifact_repository.dart`
- Modify: `lib/storage/chat_storage.dart`
- Modify: `lib/database/database_helper.dart`
- Test: `test/repositories/artifact_repository_test.dart`

- [ ] **Step 1: 阅读现有 turn step / snapshot 持久化模式**

阅读：

- `lib/database/database_helper.dart`
- `lib/storage/chat_storage.dart`
- `lib/repositories/chat_turn_step_repository.dart`
- `lib/repositories/session_context_snapshot_repository.dart`

目标：确认数据库升级、repository 封装和 `ChatStorage` 接口的现有模式。

- [ ] **Step 2: 先写 artifact repository 失败测试**

在 `test/repositories/artifact_repository_test.dart` 增加测试，覆盖：

- 创建 artifact registry 记录
- 通过 `groupId + artifactId` 查询
- 通过 `sourcePath` 查询
- 更新 `lastUpdatedAt`

示例：

```dart
test('stores and loads artifact registry by group and artifact id', () async {
  final repository = ArtifactRepository(storage);

  await repository.upsertRecord(
    ArtifactRecord(
      artifactId: 'portfolio-pie',
      groupId: 7,
      title: '投资组合饼图',
      type: ArtifactType.html,
      sourcePath: 'artifacts/7/portfolio-pie.html',
      originTurnId: 42,
      createdAt: DateTime(2026, 4, 30, 10),
      lastUpdatedAt: DateTime(2026, 4, 30, 10),
    ),
  );

  final record = await repository.findByGroupAndArtifactId(
    groupId: 7,
    artifactId: 'portfolio-pie',
  );

  expect(record, isNotNull);
  expect(record!.sourcePath, 'artifacts/7/portfolio-pie.html');
});
```

- [ ] **Step 3: 运行测试确认失败**

Run:

```bash
fvm flutter test test/repositories/artifact_repository_test.dart
```

Expected: FAIL，因为 model / repository / storage / table 尚不存在。

- [ ] **Step 4: 定义 artifact 基础模型**

在 `lib/models/artifact/` 下新增：

- `ArtifactType`
- `ArtifactRecord`

字段至少包括：

- `artifactId`
- `groupId`
- `title`
- `type`
- `sourcePath`
- `originTurnId`
- `createdAt`
- `lastUpdatedAt`

为字段添加简洁注释，说明它们是 registry 真相来源，而不是展示快照。

- [ ] **Step 5: 扩展 ChatStorage 接口**

在 `lib/storage/chat_storage.dart` 增加最小接口：

- `insertOrReplaceArtifactRecord(...)`
- `getArtifactRecord(...)`
- `getArtifactRecordByPath(...)`
- `listArtifactRecordsForGroup(...)`
- `updateArtifactRecord(...)`

保持命名与现有 storage 风格一致。

- [ ] **Step 6: 在 DatabaseHelper 中新增 artifact_registry 表与升级逻辑**

要求：

- 数据库版本从 `11` 升到 `12`
- `onCreate` 创建 `artifact_registry`
- `onUpgrade` 处理 `oldVersion < 12`
- 建立唯一索引：
  - `(group_id, artifact_id)`
  - `(group_id, source_path)`

建议表结构：

```sql
CREATE TABLE artifact_registry (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  group_id INTEGER NOT NULL,
  artifact_id TEXT NOT NULL,
  title TEXT NOT NULL,
  type TEXT NOT NULL,
  source_path TEXT NOT NULL,
  origin_turn_id INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  last_updated_at INTEGER NOT NULL
)
```

- [ ] **Step 7: 实现 ArtifactRepository**

实现：

- upsert
- 按 `groupId + artifactId` 查询
- 按 `groupId + sourcePath` 查询
- group 下列出全部 artifact

保持 API 小而聚焦，不承载 UI 或 resolver 逻辑。

- [ ] **Step 8: 重新运行 repository 测试**

Run:

```bash
fvm flutter test test/repositories/artifact_repository_test.dart
```

Expected: PASS。

- [ ] **Step 9: Commit**

```bash
git add \
  lib/models/artifact/artifact_type.dart \
  lib/models/artifact/artifact_record.dart \
  lib/repositories/artifact_repository.dart \
  lib/storage/chat_storage.dart \
  lib/database/database_helper.dart \
  test/repositories/artifact_repository_test.dart
git commit -m "feat: add artifact registry persistence"
```

---

## Task 2: 新增 Artifact 文件存储与 source 预处理

**Files:**
- Create: `lib/services/artifact/artifact_source_sanitizer.dart`
- Create: `lib/services/artifact/artifact_file_storage_service.dart`
- Create: `lib/models/artifact/artifact_create_result.dart`
- Test: `test/services/artifact/artifact_source_sanitizer_test.dart`
- Test: `test/services/artifact/artifact_file_storage_service_test.dart`

- [ ] **Step 1: 写 sanitizer 失败测试**

覆盖：

- 保留自包含 inline `<style>` / `<script>`
- 剥离 `<script src="...">`
- 剥离外链 `<link rel="stylesheet" href="https://...">`
- 对超大 `source` 报错

- [ ] **Step 2: 写 storage 失败测试**

覆盖：

- 按 `{groupId}/{artifactId}.html` 生成稳定相对路径
- 初次写入文件成功
- 再次写入相同 artifact 时覆盖同一路径
- 读回最新 source

- [ ] **Step 3: 运行两组测试确认失败**

Run:

```bash
fvm flutter test test/services/artifact/artifact_source_sanitizer_test.dart
fvm flutter test test/services/artifact/artifact_file_storage_service_test.dart
```

Expected: FAIL，因为 service 尚不存在。

- [ ] **Step 4: 实现 ArtifactSourceSanitizer**

要求：

- 只做轻量预扫描，不做完整 HTML parser
- 支持移除明显外链脚本与外链样式
- 如 `source` 为空、超限或类型不匹配，返回结构化失败
- 保留 `warnings`

为返回结构定义小型结果对象，避免只返回裸字符串。

- [ ] **Step 5: 实现 ArtifactFileStorageService**

职责：

- 计算 artifact 相对路径
- 将 sanitizer 输出写入 app documents 目录下的 artifact 文件
- 提供读取当前 source 的能力

建议最小 API：

- `saveArtifactSource(...)`
- `overwriteArtifactSource(...)`
- `readArtifactSource(...)`
- `resolveRelativeArtifactPath(...)`

先只做原生平台实现，必要时在 service 内为 Web 保留 `UnsupportedError` 或 stub 分支，不扩大范围。

- [ ] **Step 6: 定义 create 结果模型**

在 `artifact_create_result.dart` 定义：

- `artifactId`
- `title`
- `type`
- `sourcePath`
- `bytes`
- `warnings`

供 tool result 和 resolver 复用。

- [ ] **Step 7: 重新运行两组测试**

Run:

```bash
fvm flutter test test/services/artifact/artifact_source_sanitizer_test.dart
fvm flutter test test/services/artifact/artifact_file_storage_service_test.dart
```

Expected: PASS。

- [ ] **Step 8: Commit**

```bash
git add \
  lib/services/artifact/artifact_source_sanitizer.dart \
  lib/services/artifact/artifact_file_storage_service.dart \
  lib/models/artifact/artifact_create_result.dart \
  test/services/artifact/artifact_source_sanitizer_test.dart \
  test/services/artifact/artifact_file_storage_service_test.dart
git commit -m "feat: add artifact source sanitizer and file storage"
```

---

## Task 3: 注册 `create_artifact` ToolDefinition 与 handler

**Files:**
- Create: `lib/tools/handlers/create_artifact_tool_handler.dart`
- Modify: `lib/tools/default_tool_runtime_registry.dart`
- Modify: `lib/models/tool/tool_result.dart`
- Test: `test/tools/handlers/create_artifact_tool_handler_test.dart`

- [ ] **Step 1: 写 handler 失败测试**

至少覆盖：

- 参数校验：缺少 `id` / `type` / `title` / `source` 时报错
- 成功时写文件、创建 registry 记录、返回 `sourcePath`
- tool result 不包含 summary-style artifact 回投

示例：

```dart
test('create_artifact stores source and returns editable sourcePath', () async {
  final handler = buildHandler(...);

  final result = await handler.execute(
    ToolExecutionContext(
      groupId: 7,
      toolName: 'create_artifact',
      arguments: {
        'id': 'portfolio-pie',
        'type': 'html',
        'title': '投资组合饼图',
        'source': '<div>hello</div>',
      },
      history: const [],
      now: DateTime(2026, 4, 30, 10),
      hostAdapters: const ToolHostAdapters(),
    ),
  );

  expect(result.status, ToolExecutionStatus.success);
  expect(result.data['sourcePath'], contains('portfolio-pie.html'));
});
```

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
fvm flutter test test/tools/handlers/create_artifact_tool_handler_test.dart
```

Expected: FAIL，因为 handler 未实现、registry 未接入。

- [ ] **Step 3: 实现 ToolDefinition**

在 handler 内定义正式 `ToolDefinition`：

- name: `create_artifact`
- type: `html | svg`
- 要求完整 `source`
- descriptionForModel 明确：
  - 用于在回答中发布 inline artifact
  - 创建成功后优先用 `Read/Edit/Write` 修改返回的 `sourcePath`
  - 该工具默认服务于说明、图表、表格、可交互解释页面
  - 关注布局、可读性、基础视觉质量

- [ ] **Step 4: 实现参数 normalize**

要求：

- `id` kebab-case
- `title` 非空
- `type` 仅支持 `html` / `svg`
- `source` 为非空字符串

不在这里实现 UI 或上下文投影逻辑。

- [ ] **Step 5: 实现 execute**

执行顺序：

1. sanitize `source`
2. 写 artifact 文件
3. upsert registry 记录
4. 返回 `ToolResult.success`

`ToolResult.data` 至少包含：

- `artifactId`
- `title`
- `type`
- `sourcePath`
- `bytes`
- `warnings`

`toolResultText` 建议使用真实结果，例如：

`已创建 artifact：portfolio-pie`

并附上 `sourcePath`，但不要再构造额外 summary 回传层。

- [ ] **Step 6: 注册到默认 runtime registry**

在 `buildDefaultToolRuntimeRegistry(...)` 中接入 `CreateArtifactToolHandler(...)`。

需要通过构造参数把 storage / registry service 依赖注入进去；避免 handler 自己 new 全局对象。

- [ ] **Step 7: 重新运行 handler 测试**

Run:

```bash
fvm flutter test test/tools/handlers/create_artifact_tool_handler_test.dart
```

Expected: PASS。

- [ ] **Step 8: Commit**

```bash
git add \
  lib/tools/handlers/create_artifact_tool_handler.dart \
  lib/tools/default_tool_runtime_registry.dart \
  lib/models/tool/tool_result.dart \
  test/tools/handlers/create_artifact_tool_handler_test.dart
git commit -m "feat: add create artifact tool handler"
```

---

## Task 4: 构建 Artifact resolver，按 turn 推断同 turn 刷新与跨 turn stale

**Files:**
- Create: `lib/models/artifact/artifact_turn_projection.dart`
- Create: `lib/services/artifact/artifact_registry_service.dart`
- Create: `lib/services/artifact/artifact_turn_resolver.dart`
- Modify: `lib/models/agent/chat_turn_step.dart`
- Test: `test/services/artifact/artifact_turn_resolver_test.dart`

- [ ] **Step 1: 先写 resolver 失败测试**

至少覆盖 3 类场景：

1. 同一 turn：`create_artifact` + `Edit` 命中同一路径，只投影一张 artifact 卡片，source 为最新文件内容
2. 跨 turn：新 turn 再次修改同一路径，生成新卡片，旧卡片标 stale
3. 非 artifact 文件编辑：不影响任何 artifact 投影

示例思路：

```dart
test('resolves same-turn edit as refresh of the same artifact block', () async {
  final projection = await resolver.resolveForTurn(
    groupId: 7,
    turnId: 'turn-1',
    steps: [...createArtifactStep, ...editStep],
  );

  expect(projection.artifacts, hasLength(1));
  expect(projection.artifacts.single.isStale, isFalse);
});
```

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
fvm flutter test test/services/artifact/artifact_turn_resolver_test.dart
```

Expected: FAIL，因为 resolver 与 projection model 尚不存在。

- [ ] **Step 3: 为 ChatTurnStep 增补最小 helper**

只加最小只读 helper，不改主 schema，例如：

- `isCreateArtifactStep`
- `resolvedFilePathFromResult`

要求：

- 从 `ToolResult.data` 中尽量稳定提取 `filePath` / `sourcePath`
- 不把 artifact-aware 逻辑塞进通用 step model

- [ ] **Step 4: 实现 ArtifactRegistryService**

职责：

- 封装 repository 查询
- 按 `groupId + sourcePath` 查 artifact
- 按 `artifactId` / group 查询记录

保持它是 registry 访问封装，不做 UI 或 block 构造。

- [ ] **Step 5: 实现 ArtifactTurnProjection / Resolver**

resolver 输入应支持：

- groupId
- 当前 turn 的 step 列表
- 历史 artifact registry
- 读取当前 source 的能力

输出至少包含：

- `artifactId`
- `title`
- `type`
- `sourcePath`
- `source`
- `originTurnId`
- `isStale`
- `lastUpdatedTurnId`

规则：

- 同 turn 内多次命中同一 artifact 文件，只产出一条 projection
- 其 source 取当前文件最新内容
- 跨 turn 若检测到后续 turn 命中同一路径，旧 projection 标 stale

- [ ] **Step 6: 重新运行 resolver 测试**

Run:

```bash
fvm flutter test test/services/artifact/artifact_turn_resolver_test.dart
```

Expected: PASS。

- [ ] **Step 7: Commit**

```bash
git add \
  lib/models/artifact/artifact_turn_projection.dart \
  lib/services/artifact/artifact_registry_service.dart \
  lib/services/artifact/artifact_turn_resolver.dart \
  lib/models/agent/chat_turn_step.dart \
  test/services/artifact/artifact_turn_resolver_test.dart
git commit -m "feat: add artifact turn resolver"
```

---

## Task 5: 扩展 ChatBlockBuilder，把 artifact 作为 assistant turn 的专属 block 投影出来

**Files:**
- Modify: `lib/models/chat/assistant_turn_block.dart`
- Modify: `lib/services/chat_block_builder.dart`
- Modify: `test/services/chat_block_builder_test.dart`

- [ ] **Step 1: 为 ChatBlockBuilder 写失败测试**

覆盖：

- `create_artifact` tool result 可投影成 artifact block
- 同一 turn 内后续 `Edit/Write` 命中 artifact 文件时，不新增第二张 artifact block
- 跨 turn 的旧 block 可带 `stale` payload

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
fvm flutter test test/services/chat_block_builder_test.dart
```

Expected: FAIL，因为当前 builder 不理解 artifact projection。

- [ ] **Step 3: 为 AssistantTurnBlock 增加 artifact block 类型与 typed payload**

建议新增：

- `AssistantTurnBlockType.artifact`
- 可选 `artifactProjection` 字段

不要复用 `toolWorkflow` 或 `toolResultSummary` 伪装，避免 renderer 层再做脆弱推断。

- [ ] **Step 4: 在 ChatBlockBuilder 中接入 resolver**

实现方式建议：

- 让 builder 依赖注入一个 artifact resolver
- 在构建某个 assistant turn blocks 时，根据该 turn 的相关 steps/messages 派生 artifact projection
- 将 artifact block 插入在正确的 assistant turn 文档顺序中

要求：

- tool transcript 仍保留原始 workflow / result block
- artifact block 是回答增强型内容块，不替代真实 tool ledger
- 同 turn 内只出现一张当前 artifact block

- [ ] **Step 5: 保持普通非 artifact tool 行为不变**

验证：

- 原有 `Write/Edit/web_search/fetch_webpage` block 测试不应回归
- 没有 artifact 命中的会话不出现新 block

- [ ] **Step 6: 重新运行 builder 测试**

Run:

```bash
fvm flutter test test/services/chat_block_builder_test.dart
```

Expected: PASS。

- [ ] **Step 7: Commit**

```bash
git add \
  lib/models/chat/assistant_turn_block.dart \
  lib/services/chat_block_builder.dart \
  test/services/chat_block_builder_test.dart
git commit -m "feat: project artifact blocks into assistant turns"
```

---

## Task 6: 新增 Artifact UI block、预览面与详情页

**Files:**
- Create: `lib/widgets/chat_blocks/artifact_block.dart`
- Create: `lib/widgets/chat_blocks/artifact_preview_surface.dart`
- Create: `lib/pages/artifact_detail_page.dart`
- Modify: `lib/widgets/chat_message_list.dart`
- Modify: `lib/services/tool_ui_renderer_registry.dart`（如需要 block-level helper）
- Test: `test/widgets/chat_blocks/artifact_block_test.dart`
- Test: `test/widgets/chat_blocks/chat_blocks_test.dart`

- [ ] **Step 1: 写 artifact block 失败测试**

覆盖：

- 渲染标题
- 显示 stale 提示
- 提供查看源码/全屏入口
- 预览失败时显示 fallback 文案

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
fvm flutter test test/widgets/chat_blocks/artifact_block_test.dart
```

Expected: FAIL，因为 widget 尚不存在。

- [ ] **Step 3: 实现 ArtifactPreviewSurface**

职责：

- 加载当前 source
- 在原生平台使用 WebView / HTML 预览
- 加载失败时显示 fallback

安全要求：

- 不注册 JS bridge
- 不支持二次调工具/模型
- 默认阻断外链与主框架跳转

首期先保证“完整 source 一次性加载”，不要实现 partial streaming 渲染。

- [ ] **Step 4: 实现 ArtifactBlock**

至少展示：

- title
- 可选 stale badge
- preview surface
- 查看源码动作
- 打开详情页动作

视觉上应把它当作 assistant 回答中的一部分，而非工具结果卡片。

- [ ] **Step 5: 实现 ArtifactDetailPage**

最小能力：

- 全屏预览
- 源码查看入口
- 关闭返回

首期不做复杂版本切换器；跨 turn “版本感”先由时间线体现。

- [ ] **Step 6: 在 ChatMessageList / timeline 渲染链中接入 artifact block**

要求：

- 仅对 `AssistantTurnBlockType.artifact` 使用专属 UI
- 不破坏现有 analysis / finalResponse / toolWorkflow / toolResultSummary 渲染

- [ ] **Step 7: 重新运行 widget 测试**

Run:

```bash
fvm flutter test test/widgets/chat_blocks/artifact_block_test.dart
fvm flutter test test/widgets/chat_blocks/chat_blocks_test.dart
```

Expected: PASS。

- [ ] **Step 8: Commit**

```bash
git add \
  lib/widgets/chat_blocks/artifact_block.dart \
  lib/widgets/chat_blocks/artifact_preview_surface.dart \
  lib/pages/artifact_detail_page.dart \
  lib/widgets/chat_message_list.dart \
  test/widgets/chat_blocks/artifact_block_test.dart \
  test/widgets/chat_blocks/chat_blocks_test.dart
git commit -m "feat: render inline artifact blocks"
```

---

## Task 7: 接入依赖注入、group 作用域重建与恢复路径

**Files:**
- Modify: `lib/providers/chat_dependency_providers.dart`
- Modify: `lib/providers/chat_providers.dart`
- Modify: `lib/main.dart`
- Modify: `lib/widgets/chat_message_list.dart`
- Modify: `test/services/session_context_projector_test.dart`
- Create or Modify: `test/services/artifact/artifact_turn_resolver_test.dart`

- [ ] **Step 1: 写失败测试，覆盖 group 切换与重启式重建语义**

至少覆盖：

- 切换 group 后 resolver 只返回当前 group 的 artifact
- 重新构建 builder / provider 后，仍能从 registry + steps 重建 artifact block

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
fvm flutter test test/services/artifact/artifact_turn_resolver_test.dart
```

Expected: FAIL，当前 provider 组合与重建路径尚未打通。

- [ ] **Step 3: 在 provider 组合入口注册 artifact 依赖**

建议 provider：

- `artifactRepositoryProvider`
- `artifactFileStorageServiceProvider`
- `artifactRegistryServiceProvider`
- `artifactTurnResolverProvider`

保持按 `groupId` 查询时显式传参，不做全局 mutable session cache。

- [ ] **Step 4: 确保 ChatMessageList / block 构建在 group 变化时重新投影**

要求：

- 切换 `currentGroupProvider` 后，artifact block 重新基于新 group 数据构建
- 不保留上一个 group 的 artifact runtime 结果

- [ ] **Step 5: 补一条 SessionContextProjector 回归断言**

虽然 artifact 不引入 summary 回投，但要确认：

- `create_artifact` 和后续 `Write/Edit` 仍以真实 tool transcript 进入上下文
- 没有新增 artifact 专属二次总结文本

- [ ] **Step 6: 重新运行相关测试**

Run:

```bash
fvm flutter test test/services/artifact/artifact_turn_resolver_test.dart
fvm flutter test test/services/session_context_projector_test.dart
```

Expected: PASS。

- [ ] **Step 7: Commit**

```bash
git add \
  lib/providers/chat_dependency_providers.dart \
  lib/providers/chat_providers.dart \
  lib/main.dart \
  lib/widgets/chat_message_list.dart \
  test/services/artifact/artifact_turn_resolver_test.dart \
  test/services/session_context_projector_test.dart
git commit -m "feat: rebuild artifacts by group-scoped resolver"
```

---

## Task 8: 运行集成验证并补文档

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `docs/architecture/session-context-management.md`
- Modify: `docs/architecture/logging.md`

- [ ] **Step 1: 更新 README**

补充：

- Inline artifact / visualizer 能力简介
- 首发平台范围
- 与 `Read/Edit/Write` 的协作方式

- [ ] **Step 2: 更新 AGENTS.md**

补充工程约束：

- `create_artifact` 的定位
- artifact 只允许局部联动，不污染主 loop
- 同 turn / 跨 turn 展示语义
- 重启和 group 切换后的重建原则

- [ ] **Step 3: 更新 session context 与 logging 文档**

说明：

- artifact 不引入 summary 回投
- tool transcript fidelity 仍然成立
- artifact save / render fallback / restore 的日志点

- [ ] **Step 4: 运行针对性自动化测试**

Run:

```bash
fvm flutter test test/repositories/artifact_repository_test.dart
fvm flutter test test/services/artifact/artifact_source_sanitizer_test.dart
fvm flutter test test/services/artifact/artifact_file_storage_service_test.dart
fvm flutter test test/services/artifact/artifact_turn_resolver_test.dart
fvm flutter test test/tools/handlers/create_artifact_tool_handler_test.dart
fvm flutter test test/services/chat_block_builder_test.dart
fvm flutter test test/widgets/chat_blocks/artifact_block_test.dart
fvm flutter test test/widgets/chat_blocks/chat_blocks_test.dart
fvm flutter test test/services/session_context_projector_test.dart
```

Expected: PASS。

- [ ] **Step 5: 运行静态检查**

Run:

```bash
fvm flutter analyze
```

Expected: PASS。

- [ ] **Step 6: 手动验证原生平台主流程**

优先验证：

1. 模型创建一个图表或表格 artifact
2. 同一 turn 内通过 `Edit/Write` 持续修改，观察原位刷新
3. 下一 turn 继续编辑同一 artifact，观察新卡片与旧卡片 stale 状态
4. 退出 App 重进，验证恢复为最后成功落盘状态
5. 切换 group 再切回，验证不串台

建议命令：

```bash
fvm flutter run
```

如需 Android 真机安装，按仓库约定使用：

```bash
bash scripts/android_install_debug.sh
```

- [ ] **Step 7: Commit**

```bash
git add README.md AGENTS.md docs/architecture/session-context-management.md docs/architecture/logging.md
git commit -m "docs: document inline artifact visualizer"
```

---

## 交付检查清单

- [ ] `create_artifact` 已注册到默认 runtime registry
- [ ] artifact registry 表已落库并完成升级
- [ ] artifact 文件可按稳定路径写入与读取
- [ ] `Write/Edit` contract 未增加 artifact 专属字段
- [ ] 同一 turn 内 artifact block 原位刷新
- [ ] 跨 turn 渲染新 block，旧 block 显示 stale
- [ ] App 重启后可从持久化状态恢复
- [ ] group 切换后 artifact runtime context 不串台
- [ ] planner / session context 未引入 artifact summary 回投
- [ ] 文档、测试、分析通过

## 风险与注意事项

- 不要把 artifact 联动实现到 `ToolOrchestratorService` 或 `TurnHarness` 中；联动必须停留在 registry / resolver / block projection 层。
- `Write/Edit` 结果中的 `filePath` 字段来源可能并不完全一致，实现 helper 时先统一解析逻辑，再让 resolver 使用。
- 同 turn “自动刷新”不要依赖内存中的当前卡片引用，必须能由 `groupId + registry + step ledger + 当前文件内容` 重建。
- Web 平台不要为了追求“完整联动”而扭曲原生首发设计；首期可显式降级。
- 首期先做“一次性加载完整 source”的预览，不把 partial streaming / incremental render 一起做掉。
