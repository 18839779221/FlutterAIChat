# 运行时 UserContext 与日期感知实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 planner 与 final answer 建立稳定的运行时 `userContext` 注入机制，引入基于持久化日期基线的跨天提醒，并重写 WebSearch 工具描述以强化当前年份与来源输出约束。

**Architecture:** 保持现有 `system prompt`、`session context`、`tool definition` 三层边界不变，在其上新增一层独立的 runtime user context。`currentDate` 与 `AGENTS.md` 占位通过 synthetic user message 注入给 planner / final answer；跨天提醒在发送前按 session 级持久化 marker 决定是否插入；WebSearch 的时间感知通过工具定义层的动态描述补强，而不是散落在 planner prompt 文本中。

**Tech Stack:** Flutter 3.29.2（优先 `fvm flutter`）、Dart、sqflite、flutter_riverpod、flutter_test、现有 SessionContextService / TurnHarness / ToolHandler 架构。

---

## 文件地图

**新增模型与服务**

- Create: `lib/models/session/session_runtime_marker.dart`
- Create: `lib/models/prompt/runtime_user_context_snapshot.dart`
- Create: `lib/services/prompt/runtime_user_context_service.dart`
- Create: `lib/services/prompt/user_context_message_builder.dart`
- Create: `lib/services/session_runtime_marker_service.dart`
- Create: `lib/repositories/session_runtime_marker_repository.dart`

**存储层**

- Modify: `lib/storage/chat_storage.dart`
- Modify: `lib/database/database_helper.dart`
- Modify: `lib/storage/web_chat_storage.dart`

**主链路接入**

- Modify: `lib/services/session_context_service.dart`
- Modify: `lib/services/transcript_builder_service.dart`
- Modify: `lib/services/turn_harness.dart`
- Modify: `lib/controllers/chat_send_coordinator.dart`
- Modify: `lib/providers/chat_dependency_providers.dart`
- Modify: `lib/main.dart`

**工具定义**

- Modify: `lib/tools/handlers/web_search_tool_handler.dart`
- Modify: `test/tools/handlers/web_search_tool_handler_test.dart`
- Modify: `test/tools/core/tool_runtime_registry_test.dart`

**测试**

- Create: `test/services/prompt/runtime_user_context_service_test.dart`
- Create: `test/services/prompt/user_context_message_builder_test.dart`
- Create: `test/repositories/session_runtime_marker_repository_test.dart`
- Modify: `test/database/database_helper_test.dart`
- Modify: `test/services/session_context_service_test.dart`
- Modify: `test/services/transcript_builder_service_test.dart`
- Modify: `test/controllers/chat_send_coordinator_test.dart`
- Modify: `test/providers/chat_dependency_providers_test.dart`

**文档**

- Modify: `README.md`
- Modify: `AGENTS.md`
- Reference: `docs/superpowers/specs/2026-04-24-runtime-user-context-and-date-awareness-design.md`

## 任务 1：建立 Runtime UserContext 基础设施

**Files:**
- Create: `lib/models/prompt/runtime_user_context_snapshot.dart`
- Create: `lib/services/prompt/runtime_user_context_service.dart`
- Create: `lib/services/prompt/user_context_message_builder.dart`
- Test: `test/services/prompt/runtime_user_context_service_test.dart`
- Test: `test/services/prompt/user_context_message_builder_test.dart`

- [ ] **Step 1: 先写 RuntimeUserContextService 的失败测试**

```dart
test('builds runtime user context with current date and optional AGENTS text', () {
  final service = RuntimeUserContextService(
    nowProvider: () => DateTime(2026, 4, 24, 9, 30),
    agentsMdProvider: () async => 'Project rule: prefer AGENTS.md naming.',
  );

  final snapshot = await service.buildSnapshot();

  expect(snapshot.currentDateText, contains('2026-04-24'));
  expect(snapshot.agentsMdText, contains('AGENTS.md'));
});
```

- [ ] **Step 2: 再写 UserContextMessageBuilder 的失败测试**

```dart
test('renders snapshot into synthetic user reminder message', () {
  const builder = UserContextMessageBuilder();
  final message = builder.buildMessage(
    snapshot: const RuntimeUserContextSnapshot(
      currentDateText: "Today's date is 2026-04-24.",
      agentsMdText: 'Project instructions here.',
    ),
  );

  expect(message.role, MessageRole.user);
  expect(message.text, contains('<system-reminder>'));
  expect(message.text, contains('# currentDate'));
  expect(message.text, contains('# agentsMd'));
});
```

- [ ] **Step 3: 运行聚焦测试，确认类型与服务尚不存在**

Run: `fvm flutter test test/services/prompt/runtime_user_context_service_test.dart test/services/prompt/user_context_message_builder_test.dart`

Expected: FAIL，提示缺少 snapshot model、service 或 builder。

- [ ] **Step 4: 定义 RuntimeUserContextSnapshot**

在 `lib/models/prompt/runtime_user_context_snapshot.dart` 中新增轻量模型，字段至少包含：

- `currentDateText`
- `agentsMdText`
- `additionalSections`

为字段补充简洁注释，说明它们只服务于运行时注入层，而不是长期 session 历史。

- [ ] **Step 5: 实现 RuntimeUserContextService**

职责：

- 提供当前日期文本
- 提供 `currentMonthYear` 文本，供后续 WebSearch 描述复用
- 暂时从一个可替换 provider 返回 `AGENTS.md` 文本，占位即可

建议接口：

```dart
Future<RuntimeUserContextSnapshot> buildSnapshot()
String buildCurrentMonthYearLabel()
```

- [ ] **Step 6: 实现 UserContextMessageBuilder**

将 snapshot 渲染为统一的 synthetic user message，格式需满足：

- 外层使用 `<system-reminder>`
- 明确区分 `# agentsMd` 与 `# currentDate`
- 带上“仅在相关时使用，不要主动复述”的提醒

- [ ] **Step 7: 重新运行聚焦测试**

Run: `fvm flutter test test/services/prompt/runtime_user_context_service_test.dart test/services/prompt/user_context_message_builder_test.dart`

Expected: PASS。

- [ ] **Step 8: Commit**

```bash
git add lib/models/prompt/runtime_user_context_snapshot.dart lib/services/prompt/runtime_user_context_service.dart lib/services/prompt/user_context_message_builder.dart test/services/prompt/runtime_user_context_service_test.dart test/services/prompt/user_context_message_builder_test.dart
git commit -m "feat: add runtime user context builders"
```

## 任务 2：建立 session 级日期注入基线存储

**Files:**
- Create: `lib/models/session/session_runtime_marker.dart`
- Create: `lib/repositories/session_runtime_marker_repository.dart`
- Modify: `lib/storage/chat_storage.dart`
- Modify: `lib/database/database_helper.dart`
- Modify: `lib/storage/web_chat_storage.dart`
- Test: `test/repositories/session_runtime_marker_repository_test.dart`
- Test: `test/database/database_helper_test.dart`

- [ ] **Step 1: 先写 marker repository 失败测试**

```dart
test('persists and reloads latest injected date for a group', () async {
  final storage = DatabaseHelper(databaseName: 'session_runtime_marker_test.db');
  final repository = SessionRuntimeMarkerRepository(storage);
  final groupId = await storage.insertGroup(_group('Date Aware Session'));

  await repository.upsertLatest(
    SessionRuntimeMarker(
      groupId: groupId,
      lastInjectedDate: '2026-04-24',
    ),
  );

  final marker = await repository.getLatestByGroup(groupId);

  expect(marker, isNotNull);
  expect(marker!.lastInjectedDate, '2026-04-24');
});
```

- [ ] **Step 2: 运行存储层测试，确认当前接口缺失**

Run: `fvm flutter test test/repositories/session_runtime_marker_repository_test.dart test/database/database_helper_test.dart`

Expected: FAIL，提示缺少 marker model、repository、存储接口或表结构。

- [ ] **Step 3: 定义 SessionRuntimeMarker 模型**

字段至少包含：

- `id`
- `groupId`
- `lastInjectedDate`
- `updatedAt`

其中 `lastInjectedDate` 建议统一使用 `yyyy-MM-dd`，避免把时区与时分秒混入跨天判断。

- [ ] **Step 4: 扩展 ChatStorage 接口**

新增：

- `insertSessionRuntimeMarker`
- `getLatestSessionRuntimeMarkerByGroup`
- `updateSessionRuntimeMarker`

保持命名与 snapshot 存储接口风格一致。

- [ ] **Step 5: 在 DatabaseHelper 中新增表与 CRUD**

新增 `session_runtime_markers` 表，字段建议为：

- `id INTEGER PRIMARY KEY AUTOINCREMENT`
- `group_id INTEGER NOT NULL`
- `last_injected_date TEXT NOT NULL`
- `updated_at INTEGER NOT NULL`

同时补升级路径与 CRUD。

- [ ] **Step 6: 在 WebChatStorage 中补齐实现**

字段语义需与原生存储一致；如果使用 JSON 列表或 Map 存储，需保证读取“某 group 最新 marker”逻辑稳定。

- [ ] **Step 7: 实现 SessionRuntimeMarkerRepository**

封装：

- 读取 group 最近 marker
- upsert 最新日期基线

不要把跨天判断逻辑写进 repository，repository 只负责持久化。

- [ ] **Step 8: 重新运行存储层测试**

Run: `fvm flutter test test/repositories/session_runtime_marker_repository_test.dart test/database/database_helper_test.dart`

Expected: PASS。

- [ ] **Step 9: Commit**

```bash
git add lib/models/session/session_runtime_marker.dart lib/repositories/session_runtime_marker_repository.dart lib/storage/chat_storage.dart lib/database/database_helper.dart lib/storage/web_chat_storage.dart test/repositories/session_runtime_marker_repository_test.dart test/database/database_helper_test.dart
git commit -m "feat: add session runtime marker storage"
```

## 任务 3：实现发送前跨天判断与 reminder 注入服务

**Files:**
- Create: `lib/services/session_runtime_marker_service.dart`
- Modify: `lib/controllers/chat_send_coordinator.dart`
- Modify: `test/controllers/chat_send_coordinator_test.dart`

- [ ] **Step 1: 先写发送前跨天提醒失败测试**

```dart
test('injects date changed reminder before current user message when day changed', () async {
  final markerRepository = FakeSessionRuntimeMarkerRepository(
    initialMarker: SessionRuntimeMarker(groupId: 1, lastInjectedDate: '2026-04-24'),
  );
  final service = SessionRuntimeMarkerService(
    repository: markerRepository,
    nowProvider: () => DateTime(2026, 4, 25, 8, 0),
  );

  final reminder = await service.buildDateChangeReminderIfNeeded(groupId: 1);

  expect(reminder, isNotNull);
  expect(reminder!.text, contains("Today's date is now 2026-04-25"));
});
```

- [ ] **Step 2: 运行 coordinator 聚焦测试**

Run: `fvm flutter test test/controllers/chat_send_coordinator_test.dart`

Expected: FAIL，因为当前发送流程不会读取任何持久化日期基线，也不会注入 reminder。

- [ ] **Step 3: 实现 SessionRuntimeMarkerService**

职责：

- 读取当前 group 最近注入日期
- 计算今天的 `yyyy-MM-dd`
- 若缺少基线则只建立基线，不返回 reminder
- 若日期变化则返回 reminder message，并更新基线

建议接口：

```dart
Future<ChatMessage?> buildDateChangeReminderIfNeeded({required int groupId})
Future<void> ensureInitialInjectedDate({required int groupId})
```

- [ ] **Step 4: 在 ChatSendCoordinator.sendMessage 中接入发送前判断**

约束：

- 仅在已经确定 `groupId` 后执行
- reminder 不加入用户可见 timeline
- reminder 应进入后续 agent loop 上下文
- 发送失败时不应错误推进日期基线

- [ ] **Step 5: 为 reminder 注入顺序补测试**

补充测试覆盖：

- 首次发送建立基线但不注入 reminder
- 同一天再次发送不注入 reminder
- 跨天发送时 reminder 位于当前 user message 之前
- App 重启后从持久化 marker 恢复后仍可正确判断

- [ ] **Step 6: 重新运行 coordinator 聚焦测试**

Run: `fvm flutter test test/controllers/chat_send_coordinator_test.dart`

Expected: PASS。

- [ ] **Step 7: Commit**

```bash
git add lib/services/session_runtime_marker_service.dart lib/controllers/chat_send_coordinator.dart test/controllers/chat_send_coordinator_test.dart
git commit -m "feat: inject date change reminder before send"
```

## 任务 4：把 userContext 注入 planner 与 final answer

**Files:**
- Modify: `lib/services/session_context_service.dart`
- Modify: `lib/services/transcript_builder_service.dart`
- Modify: `lib/providers/chat_dependency_providers.dart`
- Modify: `lib/main.dart`
- Modify: `test/services/session_context_service_test.dart`
- Modify: `test/services/transcript_builder_service_test.dart`
- Modify: `test/providers/chat_dependency_providers_test.dart`

- [ ] **Step 1: 先写 planner 注入失败测试**

```dart
test('buildPlannerMessages prepends runtime user context before session context', () async {
  final messages = await service.buildPlannerMessages(
    groupId: 1,
    currentTurnId: 10,
    currentTurnTranscript: [_userMessageEvent('latest Claude news')],
    config: _chatConfig(),
  );

  expect(messages.first.role, MessageRole.user);
  expect(messages.first.text, contains('# currentDate'));
});
```

- [ ] **Step 2: 再写 final answer 注入失败测试**

```dart
test('buildFinalAnswerMessages includes runtime user context before transcript messages', () async {
  final messages = await service.buildFinalAnswerMessages(
    groupId: 1,
    turn: _turn('今天的新闻是什么'),
    transcript: [_userMessageEvent('今天的新闻是什么')],
    systemPrompt: 'final prompt',
  );

  expect(messages[1].role, MessageRole.user);
  expect(messages[1].text, contains('# currentDate'));
});
```

- [ ] **Step 3: 运行 session/final-answer 聚焦测试**

Run: `fvm flutter test test/services/session_context_service_test.dart test/services/transcript_builder_service_test.dart test/providers/chat_dependency_providers_test.dart`

Expected: FAIL，因为当前两个入口都还没有 runtime user context 层。

- [ ] **Step 4: 给 SessionContextService 注入 RuntimeUserContextService / UserContextMessageBuilder**

要求：

- `userContext` 位于历史摘要和 recent turns 之前
- 如果发送前阶段已经产生了 date reminder，则 planner 入口也能把这条 reminder 放在真实 user message 之前
- 不把这些提醒写入 snapshot summary

- [ ] **Step 5: 给 TranscriptBuilderService 增加 final-answer 入口的 userContext 注入**

要求：

- 顺序为 `system prompt -> userContext -> date reminder（如果有） -> transcript projected messages`
- 不改变 summary 入口

- [ ] **Step 6: 更新 provider 与 main.dart 依赖注入**

新增 provider：

- `runtimeUserContextServiceProvider`
- `userContextMessageBuilderProvider`
- `sessionRuntimeMarkerRepositoryProvider`
- `sessionRuntimeMarkerServiceProvider`

并把相关依赖传入 `SessionContextService` 与 `TranscriptBuilderService`。

- [ ] **Step 7: 补充 summary 不注入的回归测试**

确认 summary 相关路径仍然只使用原有 prompt/message 结构，不引入 `currentDate` 或日期提醒。

- [ ] **Step 8: 重新运行聚焦测试**

Run: `fvm flutter test test/services/session_context_service_test.dart test/services/transcript_builder_service_test.dart test/providers/chat_dependency_providers_test.dart`

Expected: PASS。

- [ ] **Step 9: Commit**

```bash
git add lib/services/session_context_service.dart lib/services/transcript_builder_service.dart lib/providers/chat_dependency_providers.dart lib/main.dart test/services/session_context_service_test.dart test/services/transcript_builder_service_test.dart test/providers/chat_dependency_providers_test.dart
git commit -m "feat: inject runtime user context into planner and final answer"
```

## 任务 5：重写 WebSearch 工具描述并注入当前月份年份

**Files:**
- Modify: `lib/tools/handlers/web_search_tool_handler.dart`
- Modify: `test/tools/handlers/web_search_tool_handler_test.dart`
- Modify: `test/tools/core/tool_runtime_registry_test.dart`

- [ ] **Step 1: 先写 WebSearch 描述失败测试**

```dart
test('web search description includes current month-year and sources requirement', () {
  final handler = WebSearchToolHandler(
    webSearcher: _noopWebSearch,
    currentMonthYearProvider: () => 'April 2026',
  );

  final description = handler.definition.descriptionForModel;

  expect(description, contains('Sources:'));
  expect(description, contains('April 2026'));
  expect(description, contains('You MUST use this year'));
});
```

- [ ] **Step 2: 运行 WebSearch handler 聚焦测试**

Run: `fvm flutter test test/tools/handlers/web_search_tool_handler_test.dart test/tools/core/tool_runtime_registry_test.dart`

Expected: FAIL，因为当前 description 是静态 `const ToolDefinition`，也没有当前年月注入。

- [ ] **Step 3: 将 WebSearchToolHandler.definition 改为运行时构建**

要求：

- 复用你确认过的模版语义
- 注入当前 `currentMonthYear`
- 明确：
  - 搜最近信息/文档/新闻/时事必须使用当前年份
  - 回答末尾必须带 `Sources:`
  - 如果用户已给 URL 优先 `fetch_webpage`
  - 如果问题只依赖当前聊天历史优先 `search_chat_history`

- [ ] **Step 4: 保持参数 schema 不变，避免连带破坏工具执行**

只改 planner-facing / localized description 与需要的运行时 provider，不改现有 `query` / `maxResults` 执行契约。

- [ ] **Step 5: 补充中英文描述断言**

测试应覆盖：

- 英文描述含 `Sources:` 约束
- 描述中出现当前月份年份
- 中文描述仍表达“当前年份”“最新信息”的强约束

- [ ] **Step 6: 重新运行 WebSearch handler 聚焦测试**

Run: `fvm flutter test test/tools/handlers/web_search_tool_handler_test.dart test/tools/core/tool_runtime_registry_test.dart`

Expected: PASS。

- [ ] **Step 7: Commit**

```bash
git add lib/tools/handlers/web_search_tool_handler.dart test/tools/handlers/web_search_tool_handler_test.dart test/tools/core/tool_runtime_registry_test.dart
git commit -m "feat: strengthen web search prompt with current year guidance"
```

## 任务 6：文档与全量验证

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Reference: `docs/superpowers/specs/2026-04-24-runtime-user-context-and-date-awareness-design.md`

- [ ] **Step 1: 更新 README 的 prompt/context 架构说明**

补充：

- `userContext messages`
- 日期变化 reminder
- WebSearch 当前年份约束

- [ ] **Step 2: 更新 AGENTS.md 的实现约束**

补充：

- planner / final answer 使用 runtime user context
- 跨天提醒不进入 UI timeline
- WebSearch 处理“最新/最近”查询时必须使用当前年份

- [ ] **Step 3: 运行目标测试集**

Run:

```bash
fvm flutter test \
  test/services/prompt/runtime_user_context_service_test.dart \
  test/services/prompt/user_context_message_builder_test.dart \
  test/repositories/session_runtime_marker_repository_test.dart \
  test/database/database_helper_test.dart \
  test/services/session_context_service_test.dart \
  test/services/transcript_builder_service_test.dart \
  test/controllers/chat_send_coordinator_test.dart \
  test/providers/chat_dependency_providers_test.dart \
  test/tools/handlers/web_search_tool_handler_test.dart \
  test/tools/core/tool_runtime_registry_test.dart
```

Expected: PASS。

- [ ] **Step 4: 运行静态检查**

Run: `fvm flutter analyze`

Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add README.md AGENTS.md
git commit -m "docs: document runtime user context and date awareness"
```

## 备注

- 本计划不包含 `AGENTS.md` 编辑入口设计。
- 本计划不包含把日期提醒显示到用户可见消息时间线。
- 本计划不包含复杂 prompt cache / dynamic boundary 机制。
- 本轮如需查看“运行时实际注入了什么”，优先补日志或调试视图，不要把 reminder 回写到 transcript。
