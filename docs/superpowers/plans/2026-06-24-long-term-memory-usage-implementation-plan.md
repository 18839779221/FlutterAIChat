# Long-Term Memory Usage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `/memories/MEMORY.md` 和少量相关 topic memory files 注入 runtime user context，让长期记忆存储层开始影响后续 planner/final answer，同时保持记忆只是线索而非当前事实。

**Architecture:** 新增独立 `MemoryRuntimeContextService` 负责读取 memory index、解析索引链接、按当前 user input 选择 topic file 并生成 runtime context section。`RuntimeUserContextService` 通过可选 `userInput` 调用该服务，把 memory section 放入 `additionalSections`；`SessionContextService` 从 current turn 传入 user input。该上下文不进入 session summary、timeline、workspace 或数据库。

**Tech Stack:** Flutter 3.35.7（本机 active `flutter` 已是 3.35.7 时可用 `flutter`）、Dart、现有 file sandbox、RuntimeUserContextService、SessionContextService、Flutter test

---

## 相关设计

- Spec: `docs/superpowers/specs/2026-06-24-long-term-memory-usage-design.md`
- Storage Spec: `docs/superpowers/specs/2026-06-19-long-term-memory-storage-design.md`
- Storage Plan: `docs/superpowers/plans/2026-06-19-long-term-memory-storage-implementation-plan.md`
- Related: `docs/architecture/session-context-management.md`
- Related: `docs/architecture/file-sandbox-architecture.md`

## 文件结构与职责

### 新增

- `lib/services/memory/memory_runtime_context_service.dart`
  - 读取 `/memories/MEMORY.md`
  - 解析 Markdown link
  - 根据 user input 选择最多 5 条相关 topic file
  - 读取 topic file 并裁剪
  - 处理 ignore memory
  - 输出 runtime context section

- `test/services/memory/memory_runtime_context_service_test.dart`
  - 覆盖 index loading、topic selection、ignore、path guard、truncation

### 修改

- `lib/services/prompt/runtime_user_context_service.dart`
  - 注入 `MemoryRuntimeContextService`
  - `buildSnapshot({int? groupId, String? userInput})`
  - 将 memory section 加入 `additionalSections`

- `lib/services/session_context_service.dart`
  - 在调用 `buildSnapshot` 时传入 `currentTurn?.userInput`

- `lib/main.dart` 或 dependency provider wiring
  - 构造生产用 `MemoryRuntimeContextService`
  - 使用 file tool root 或 host service reader 读取 `/memories`

- `lib/bootstrap/runtime_host_services.dart` 或相关 host service
  - 如果当前没有暴露 file root reader，需要补一个只读 reader 给 memory runtime service

- `test/services/prompt/runtime_user_context_service_test.dart`
  - 覆盖 memory section 注入与 ignore

- `test/services/session_context_service_test.dart` 或最贴近的 session context 测试
  - 覆盖 current turn user input 传递给 runtime memory context

- `test/services/prompt/user_context_message_builder_test.dart`
  - 如现有测试不足，补充 memory section 渲染

- `README.md`
  - 把长期记忆描述从“存储层”更新为“存储 + 使用层，自动抽取后续补齐”

- `AGENTS.md`
  - 补充 memory 使用层边界：runtime user context、ignore memory、记忆事实需验证

- `docs/architecture/session-context-management.md`
  - 说明 memory context 属于 runtime user context，不进入 summary snapshot

## 行为约定

### MemoryRuntimeContextService API

建议接口：

```dart
typedef MemoryFileReader = Future<String?> Function(String agentPath);

class MemoryRuntimeContextService {
  const MemoryRuntimeContextService({
    required MemoryFileReader readFile,
    int maxIndexLines = 200,
    int maxRecalledMemories = 5,
    int maxTopicChars = 3000,
    int maxTotalTopicChars = 10000,
  });

  Future<String> buildContextSection({
    String? userInput,
  });
}
```

返回：

- 空字符串：没有可注入 memory context。
- 非空字符串：完整 `# memoryIndex` / `# recalledMemories` sections。

### Ignore Memory

`userInput` 命中以下语义时返回空：

- `ignore memory`
- `do not use memory`
- `don't use memory`
- `不要使用记忆`
- `忽略记忆`
- `别参考记忆`

### Markdown Link 解析

只解析常见索引格式：

```markdown
- [Title](feedback/android-debug-install.md) — one-line hook
```

解析结果：

- `title`：索引行中方括号里的标题文本
- `relative path`：链接目标的相对路径，例如 `feedback/android-debug-install.md`
- `agent path`：归一化后的 `/memories/feedback/android-debug-install.md`
- `hook`：索引行中链接后面的短提示文本，也就是一行摘要，不是 frontmatter 字段
- `frontmatter description`：topic 文件 frontmatter 里的 `description:` 字段，供 selector 和调试输出参考

如果 path 已经是 `/memories/...`，保持归一化。

拒绝：

- `../`
- 绝对 host path
- 非 `/memories` agent path
- 空 path

### 相关性选择

第一版不做关键词打分，不做 embedding 回退，而是走 `side` 辅助选择：

- 先把 `MEMORY.md` 索引行和 topic frontmatter 整理成候选清单。
- 候选清单只暴露 `title / hook / path / name / description / type` 这类可见信号。
- 交给 `side` 辅助模型判断哪些 topic file “明确相关”。
- 返回结果最多 5 条。
- 如果 `side` 返回空或失败，只保留 `# memoryIndex`，不退回关键词规则。

如果用户明确要求“回忆 / 查看 / 检查记忆 / 你记得什么”，可降低相关性门槛，但仍不全量灌入全部 topic 正文。

### 输出 section

只注入 index：

```text
# memoryIndex
MEMORY.md is always loaded into your conversation context. Use it as an index, not as complete memory content.

<index content>
```

注入 topic：

```text
# recalledMemories
Memory records are context clues, not current truth. If a recalled memory names a file path, function, flag, or current repo state, verify the current state before recommending action based on it. If memory conflicts with current files or tool results, trust the current observation.

## /memories/feedback/android-debug-install.md
<topic content>
```

## Task 1: 新增 MemoryRuntimeContextService 的 index loading

**Files:**
- Create: `lib/services/memory/memory_runtime_context_service.dart`
- Create: `test/services/memory/memory_runtime_context_service_test.dart`

- [ ] **Step 1: 写失败测试，MEMORY.md 不存在时返回空**

```dart
test('returns empty context when memory index is missing', () async {
  final service = MemoryRuntimeContextService(
    readFile: (_) async => null,
  );

  final section = await service.buildContextSection(userInput: 'hello');

  expect(section, isEmpty);
});
```

- [ ] **Step 2: 写失败测试，加载 MEMORY.md 索引**

```dart
test('loads memory index as runtime context', () async {
  final service = MemoryRuntimeContextService(
    readFile: (path) async {
      if (path == '/memories/MEMORY.md') {
        return '- [Android debug](feedback/android-debug.md) — debug install preference';
      }
      return null;
    },
  );

  final section = await service.buildContextSection(userInput: 'hello');

  expect(section, contains('# memoryIndex'));
  expect(section, contains('MEMORY.md is always loaded'));
  expect(section, contains('[Android debug](feedback/android-debug.md)'));
});
```

- [ ] **Step 3: 运行测试确认失败**

Run:

```bash
flutter test test/services/memory/memory_runtime_context_service_test.dart
```

Expected: FAIL，因为 service 尚不存在。

- [ ] **Step 4: 最小实现 index loading**

实现：

- `MemoryFileReader`
- `MemoryRuntimeContextService`
- `buildContextSection`
- 读取 `/memories/MEMORY.md`
- 空或缺失返回 `''`
- 非空返回 `# memoryIndex`

- [ ] **Step 5: 运行测试确认通过**

Run:

```bash
flutter test test/services/memory/memory_runtime_context_service_test.dart
```

Expected: PASS。

## Task 2: 实现 ignore memory 与 index 裁剪

**Files:**
- Modify: `lib/services/memory/memory_runtime_context_service.dart`
- Modify: `test/services/memory/memory_runtime_context_service_test.dart`

- [ ] **Step 1: 写失败测试，ignore memory 返回空**

```dart
test('returns empty context when user asks to ignore memory', () async {
  final service = MemoryRuntimeContextService(
    readFile: (_) async => '- [A](user/a.md) — hook',
  );

  expect(
    await service.buildContextSection(userInput: 'Please do not use memory'),
    isEmpty,
  );
  expect(
    await service.buildContextSection(userInput: '不要使用记忆'),
    isEmpty,
  );
});
```

- [ ] **Step 2: 写失败测试，index 最多保留 200 行**

生成 205 行，断言只包含前 200 行且不含第 201 行。

- [ ] **Step 3: 运行测试确认失败**

Run:

```bash
flutter test test/services/memory/memory_runtime_context_service_test.dart
```

Expected: FAIL。

- [ ] **Step 4: 实现 ignore 和裁剪**

实现：

- `_shouldIgnoreMemory(String? userInput)`
- `_trimIndex(String index)`

- [ ] **Step 5: 运行测试确认通过**

Run:

```bash
flutter test test/services/memory/memory_runtime_context_service_test.dart
```

Expected: PASS。

## Task 3: 实现 topic link 解析和相关性召回

**Files:**
- Modify: `lib/services/memory/memory_runtime_context_service.dart`
- Modify: `test/services/memory/memory_runtime_context_service_test.dart`

- [ ] **Step 1: 写失败测试，根据 user input 召回相关 topic**

```dart
test('recalls matching topic files from memory index', () async {
  final service = MemoryRuntimeContextService(
    readFile: (path) async {
      return switch (path) {
        '/memories/MEMORY.md' =>
          '- [Android debug](feedback/android-debug.md) — debug install preference\n'
          '- [Theme](project/theme.md) — visual direction',
        '/memories/feedback/android-debug.md' => 'Android debug memory body',
        _ => null,
      };
    },
  );

  final section = await service.buildContextSection(
    userInput: 'Android debug install',
  );

  expect(section, contains('# recalledMemories'));
  expect(section, contains('/memories/feedback/android-debug.md'));
  expect(section, contains('Android debug memory body'));
  expect(section, isNot(contains('/memories/project/theme.md')));
});
```

- [ ] **Step 2: 写失败测试，跳过逃出 `/memories` 的 path**

索引含 `../secrets.md`、`/workspaces/ws/a.md`，断言不会读取这些路径。

- [ ] **Step 3: 写失败测试，最多召回 5 条**

构造 6 条都相关，断言只读 5 条。

- [ ] **Step 4: 运行测试确认失败**

Run:

```bash
flutter test test/services/memory/memory_runtime_context_service_test.dart
```

Expected: FAIL。

- [ ] **Step 5: 实现 link parser、path guard、scoring**

实现建议：

- `_parseIndexEntries(String index)`
- `_normalizeMemoryPath(String rawPath)`
- `_scoreEntry(MemoryIndexEntry entry, String userInput)`
- `_tokenize(String text)`

不要引入外部依赖。

- [ ] **Step 6: 运行测试确认通过**

Run:

```bash
flutter test test/services/memory/memory_runtime_context_service_test.dart
```

Expected: PASS。

## Task 4: 实现 topic 内容预算与信任边界文案

**Files:**
- Modify: `lib/services/memory/memory_runtime_context_service.dart`
- Modify: `test/services/memory/memory_runtime_context_service_test.dart`

- [ ] **Step 1: 写失败测试，topic 超长时截断**

用 `maxTopicChars: 20` 构造正文，断言包含 `[memory truncated]`。

- [ ] **Step 2: 写失败测试，包含记忆信任边界**

断言 recalled section 包含：

```text
Memory records are context clues, not current truth.
verify the current state
```

- [ ] **Step 3: 运行测试确认失败**

Run:

```bash
flutter test test/services/memory/memory_runtime_context_service_test.dart
```

Expected: FAIL。

- [ ] **Step 4: 实现 topic truncation 和 trust guidance**

实现：

- `_trimTopicContent`
- `_buildRecalledMemoriesSection`
- 总量 `maxTotalTopicChars`

- [ ] **Step 5: 运行测试确认通过**

Run:

```bash
flutter test test/services/memory/memory_runtime_context_service_test.dart
```

Expected: PASS。

## Task 5: 接入 RuntimeUserContextService

**Files:**
- Modify: `lib/services/prompt/runtime_user_context_service.dart`
- Modify: `test/services/prompt/runtime_user_context_service_test.dart`

- [ ] **Step 1: 写失败测试，runtime snapshot 注入 memory section**

```dart
test('injects memory runtime section when available', () async {
  final service = RuntimeUserContextService(
    platformContextProvider: () => const [],
    memoryContextBuilder: ({userInput}) async =>
      '# memoryIndex\n- [A](user/a.md) — hook',
  );

  final snapshot = await service.buildSnapshot(
    groupId: 1,
    userInput: 'hello',
  );

  expect(snapshot.additionalSections.join('\n'), contains('# memoryIndex'));
});
```

可用 typedef：

```dart
typedef RuntimeMemoryContextBuilder = Future<String> Function({
  String? userInput,
});
```

- [ ] **Step 2: 写失败测试，ignore memory 不影响其他 runtime sections**

memory builder 返回空，断言 currentWorkspace 仍存在。

- [ ] **Step 3: 运行测试确认失败**

Run:

```bash
flutter test test/services/prompt/runtime_user_context_service_test.dart
```

Expected: FAIL。

- [ ] **Step 4: 实现 RuntimeUserContextService 接入**

修改：

- 构造函数新增 `RuntimeMemoryContextBuilder? memoryContextBuilder`
- `buildSnapshot({int? groupId, String? userInput})`
- build additionalSections 时插入 memory section，建议放在 currentWorkspace 之后、runtimePlatform 之前或之后均可，保持稳定测试即可。

- [ ] **Step 5: 运行测试确认通过**

Run:

```bash
flutter test test/services/prompt/runtime_user_context_service_test.dart
```

Expected: PASS。

## Task 6: SessionContextService 传递 current user input

**Files:**
- Modify: `lib/services/session_context_service.dart`
- Modify: closest existing session context test, likely `test/services/session_context_service_test.dart` or a focused runtime context test

- [ ] **Step 1: 查找现有可复用测试**

Run:

```bash
rg -n "buildPlannerContextState|buildPlannerMessages|runtimeUserContextService|currentTurn" test/services
```

- [ ] **Step 2: 写失败测试，currentTurn.userInput 传给 runtime memory context**

使用 fake `RuntimeUserContextService` 或注入 memory builder 捕获 `userInput`。

期望：

```dart
expect(capturedUserInput, 'current user asks about android debug');
```

- [ ] **Step 3: 运行测试确认失败**

Run selected focused test.

Expected: FAIL。

- [ ] **Step 4: 修改 SessionContextService 调用**

把：

```dart
await _runtimeUserContextService.buildSnapshot(groupId: groupId)
```

改为：

```dart
await _runtimeUserContextService.buildSnapshot(
  groupId: groupId,
  userInput: currentTurn?.userInput,
)
```

- [ ] **Step 5: 运行测试确认通过**

Run selected focused test.

Expected: PASS。

## Task 7: 生产 wiring

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/bootstrap/runtime_host_services.dart` if needed
- Possibly modify: `lib/bootstrap/app_runtime.dart` only if dependency storage requires it

- [ ] **Step 1: 查找 hostServices file tool 可用入口**

Run:

```bash
sed -n '1,220p' lib/bootstrap/runtime_host_services.dart
rg -n "fileToolAdapters|FileToolRootService|rootService" lib/bootstrap lib/main.dart
```

- [ ] **Step 2: 写或更新 wiring 测试**

如果项目没有 main wiring 测试，可跳过单独 wiring test，但必须通过 runtime user context service 单测覆盖核心逻辑。

- [ ] **Step 3: 实现生产 reader**

建议在 `_initializeRuntime` 中：

```dart
final memoryRuntimeContextService = MemoryRuntimeContextService(
  readFile: (agentPath) async {
    final fileTools = hostServices.fileToolAdapters;
    if (fileTools == null) return null;
    final resolution = fileTools.pathPolicy.normalizeSandboxPath(
      agentPath,
      cwd: '/',
    );
    if (!resolution.isValid || resolution.relativePath == null) return null;
    final file = fileTools.rootService.resolveFile(resolution.relativePath!);
    if (!await file.exists()) return null;
    return file.readAsString();
  },
);
```

然后传给 `RuntimeUserContextService` provider / `SessionContextService` construction。

- [ ] **Step 4: 运行相关测试**

Run:

```bash
flutter test test/services/prompt/runtime_user_context_service_test.dart test/services/memory/memory_runtime_context_service_test.dart
```

Expected: PASS。

## Task 8: 更新 user context builder 测试和文档

**Files:**
- Modify: `test/services/prompt/user_context_message_builder_test.dart`
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `docs/architecture/session-context-management.md`
- Modify: `docs/architecture/file-sandbox-architecture.md` if needed

- [ ] **Step 1: 补 user context message 测试**

断言 `additionalSections` 中的 `# memoryIndex` 正常进入 synthetic user reminder。

- [ ] **Step 2: 更新 README**

把“长期记忆存储层”改成：

```markdown
- 长期记忆：`/memories` 作为全局 file-based memory 目录，运行时自动加载 `MEMORY.md` 索引并按当前输入选择少量 topic files；后台自动抽取作为后续环节补齐
```

- [ ] **Step 3: 更新 AGENTS.md**

补充：

```markdown
- Long-term memory usage belongs in runtime user context, not session summary, transcript ownership, or workspace ownership.
- If the user asks to ignore memory, runtime must proceed as if `/memories/MEMORY.md` were empty for that turn.
- Memory records are context clues, not current truth; verify recalled file/function/flag/repo-state claims before acting on them.
```

- [ ] **Step 4: 更新 session context 架构文档**

说明 memory context 位于 runtime user context 层，不进入 snapshot summary。

## Task 9: 聚焦验证

**Files:**
- No additional edits expected

- [ ] **Step 1: 运行 memory tests**

Run:

```bash
flutter test test/services/memory/memory_runtime_context_service_test.dart
```

Expected: PASS。

- [ ] **Step 2: 运行 runtime user context tests**

Run:

```bash
flutter test test/services/prompt/runtime_user_context_service_test.dart test/services/prompt/user_context_message_builder_test.dart
```

Expected: PASS。

- [ ] **Step 3: 运行 session context focused tests**

Run selected session context test from Task 6.

Expected: PASS。

- [ ] **Step 4: 运行 existing prompt and file tool focused tests**

Run:

```bash
flutter test test/services/prompt/prompt_builder_service_test.dart test/tools/handlers/write_tool_handler_test.dart test/tools/handlers/delete_tool_handler_test.dart
```

Expected: PASS。

- [ ] **Step 5: 运行 analyze**

Run:

```bash
flutter analyze
```

Expected: If repository-wide existing warnings remain, report them separately and confirm no new warnings from changed files.

## 暂不执行项

本计划完成后仍待后续计划补齐：

- 后台自动抽取最近消息形成记忆。
- LLM-based memory selection。
- embedding search。
- surfaced memory marker。
- UI 记忆管理。
