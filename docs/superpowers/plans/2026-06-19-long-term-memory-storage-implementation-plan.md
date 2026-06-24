# Long-Term Memory Storage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立长期记忆的存储层，让 Agent 使用现有通用文件工具维护 `/memories/MEMORY.md` 和 topic memory files；自动加载、召回和抽取随后补齐，但本阶段先保留它们依赖的 prompt 与格式契约。

**Architecture:** 复用当前 file-native sandbox 和通用文件工具。`/memories` 被定义为全局长期记忆目录，不属于当前 workspace；`Write` 写入 `/memories/...` 时跳过 workspace 自动迁移，`Delete` 对 `/memories` 提供受保护的全局例外，prompt guidance 负责固定记忆格式和维护流程。

**Tech Stack:** Flutter 3.35.7（优先 `fvm flutter`）、Dart、现有 tool runtime、file sandbox、PromptBuilderService、Flutter test

---

## 相关设计

- Spec: `docs/superpowers/specs/2026-06-19-long-term-memory-storage-design.md`
- Reference: `/Users/skka/vsSpace/Claude-Code/docs/12-long-term-memory.zh-CN.md`
- Related: `docs/architecture/file-sandbox-architecture.md`
- Related: `docs/superpowers/specs/2026-06-02-agent-file-access-sandbox-unification-design.md`
- Related: `docs/superpowers/specs/2026-06-02-workspace-v1-file-container-design.md`
- Related: `docs/superpowers/specs/2026-06-03-delete-tool-design.md`

## 文件结构与职责

### 需要修改

- `lib/tools/handlers/write_tool_handler.dart`
  - 识别 `/memories/...`
  - 对 memory path 跳过 default workspace long-lived output 迁移
  - 保持 tool result 返回 `/memories/...`

- `lib/tools/handlers/delete_tool_handler.dart`
  - 允许删除 `/memories` 下具体 topic file 或子目录
  - 拒绝删除 `/memories` 根目录
  - 拒绝删除 `/memories/MEMORY.md`
  - 保留当前 workspace 删除规则

- `lib/services/prompt/prompt_catalog.dart`
  - 新增长期记忆存储 guidance section
  - 尽量保留参考 prompt 的存储规则
  - 删除或适配不适合当前 app 的内容

- `lib/services/prompt/prompt_builder_service.dart`
  - 在非 summary stage 注入长期记忆存储 guidance
  - summary stage 不注入

- `README.md`
  - 说明 `/memories` 是长期记忆存储目录
  - 明确第一阶段先交付存储，自动加载 / 召回 / 抽取是紧邻后续环节

- `docs/architecture/file-sandbox-architecture.md`
  - 说明 `/memories` 是全局长期记忆目录，不属于当前 workspace
  - 说明通用文件工具可维护记忆，但有根目录保护

- `AGENTS.md`
  - 补充长期记忆存储规则和 `/memories` 边界

### 需要新增或修改测试

- `test/tools/handlers/write_tool_handler_test.dart`
  - 增加 memory write 路径测试

- `test/tools/handlers/delete_tool_handler_test.dart`
  - 增加 memory delete 例外和保护测试

- `test/services/prompt/prompt_builder_service_test.dart`
  - 如果已有 prompt builder 测试则修改；否则新增

## 行为约定

### `/memories` 路径

`/memories` 是全局长期记忆目录。

允许：

- `/memories/MEMORY.md`
- `/memories/user/*.md`
- `/memories/feedback/*.md`
- `/memories/project/*.md`
- `/memories/reference/*.md`

不要求 runtime 强制只允许四个子目录；第一阶段依赖 prompt guidance 约束格式。

### `Write`

当 `file_path` 解析后的 agent path 位于 `/memories/...`：

- 直接写入该路径。
- 不调用 `ensureWorkspaceForLongLivedOutput`。
- 不返回 `workspaceChangeReminder`。
- 不把文件改写到 `/workspaces/<id>/...`。

### `Delete`

当前 workspace 路径行为保持不变。

新增 memory path 行为：

- `/memories/user/foo.md`：允许。
- `/memories/feedback/foo.md`：允许。
- `/memories/project/foo.md`：允许。
- `/memories/reference/foo.md`：允许。
- `/memories`：拒绝，错误码 `cannot_delete_memory_root`。
- `/memories/`：拒绝，错误码 `cannot_delete_memory_root`。
- `/memories/MEMORY.md`：拒绝，错误码 `cannot_delete_memory_index`。

所有 `Delete` 仍保持 `requiresConfirmation = true`。

### Prompt

非 summary stage 注入长期记忆存储 guidance。

必须包含：

- `/memories` 是 file-based persistent memory directory。
- 用户明确要求 remember 时保存。
- 用户明确要求 forget 时查找并移除相关 entry。
- 四种 type：`user`、`feedback`、`project`、`reference`。
- 保存两步：topic file + `MEMORY.md` pointer。
- frontmatter 格式。
- `MEMORY.md` 是索引，不是正文仓库。
- 不保存代码结构、git 历史、debug fix recipe、已在 `AGENTS.md` / docs 中记录的内容、当前会话临时状态。

必须适配：

- 参考文档中的 `<memoryDir>` 改为 `/memories`。
- `CLAUDE.md` 改为 `AGENTS.md` 和项目文档。
- `MEMORY.md is always loaded...` 保留为系统目标契约；当前任务可先不实现自动加载，但 prompt 不应因此削弱这条规则。

本阶段暂不注入：

- memory extraction subagent。
- Claude Code 专属工具权限和 turn budget。
- team memory / `TEAMMEM`。
- 记忆访问、推荐前验证、ignore memory 等使用层规则。

说明：使用层规则不是删除，而是等自动加载 / 召回实现时进入对应 runtime context。

## Task 1: 用测试固定 `Write /memories` 不触发 workspace 迁移

**Files:**
- Modify: `test/tools/handlers/write_tool_handler_test.dart`
- Modify: `lib/tools/handlers/write_tool_handler.dart`

- [ ] **Step 1: 写失败测试，覆盖 memory path 不迁移 workspace**

在 `WriteToolHandler` 测试中新增用例：

```dart
test('writes memory files without promoting default workspace', () async {
  var workspacePromotionCalled = false;

  final result = await handler.execute(
    ToolExecutionContext(
      groupId: 1,
      toolName: 'Write',
      arguments: const {
        'file_path': '/memories/user/collaboration-style.md',
        'content': 'memory',
      },
      history: const <ChatMessage>[],
      now: DateTime(2026, 6, 19),
      cwd: '/',
      workspace: const ResolvedWorkspace(
        workspaceId: '.default',
        isDefault: true,
        fileRoot: '/workspaces/.default',
      ),
      hostAdapters: ToolHostAdapters(
        fileTools: fileTools,
        workspace: WorkspaceToolHostAdapters(
          resolveWorkspaceForGroup: (_) async => const ResolvedWorkspace(
            workspaceId: '.default',
            isDefault: true,
            fileRoot: '/workspaces/.default',
          ),
          ensureWorkspaceForLongLivedOutput: (_) async {
            workspacePromotionCalled = true;
            return const WorkspaceTransitionResult(...);
          },
        ),
      ),
    ),
  );

  expect(result.status, ToolExecutionStatus.success);
  expect(workspacePromotionCalled, isFalse);
  expect(result.data['filePath'], '/memories/user/collaboration-style.md');
  expect(result.data.containsKey('workspaceChangeReminder'), isFalse);
});
```

如现有 test helper 不方便构造 `WorkspaceTransitionResult`，可以提取一个 `_buildFileToolAdapters()` helper，并让 promotion callback `throw StateError('should_not_promote_memory')`。

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/tools/handlers/write_tool_handler_test.dart
```

Expected: FAIL，当前 `WriteToolHandler` 会对 default workspace 下不存在的新文件尝试 promotion。

- [ ] **Step 3: 最小实现 memory path 判断**

在 `WriteToolHandler` 中新增私有判断：

```dart
bool _isMemoryPath(String agentPath) {
  final normalized = _normalizeAgentPath(agentPath);
  return normalized == '/memories' || normalized.startsWith('/memories/');
}
```

在 default workspace promotion 前判断 `effectiveResolution.agentPath`：

```dart
final isMemoryPath = _isMemoryPath(effectiveResolution.agentPath ?? '');
if (context.workspace?.isDefault == true && !isMemoryPath) {
  ...
}
```

- [ ] **Step 4: 运行测试确认通过**

Run:

```bash
fvm flutter test test/tools/handlers/write_tool_handler_test.dart
```

Expected: PASS。

## Task 2: 用测试固定 `Delete /memories` 的允许与保护规则

**Files:**
- Modify: `test/tools/handlers/delete_tool_handler_test.dart`
- Modify: `lib/tools/handlers/delete_tool_handler.dart`

- [ ] **Step 1: 写失败测试，允许删除具体 memory topic file**

新增测试：

```dart
test('execute allows deleting a memory topic file outside workspace', () async {
  await File('${rootService.rootPath}/memories/user/style.md')
      .create(recursive: true);

  final result = await handler.execute(
    ToolExecutionContext(
      groupId: 1,
      toolName: 'Delete',
      arguments: const {'file_path': '/memories/user/style.md'},
      history: const <ChatMessage>[],
      now: DateTime(2026, 6, 19),
      cwd: '/workspaces/ws_current',
      workspace: const ResolvedWorkspace(
        workspaceId: 'ws_current',
        isDefault: false,
        fileRoot: '/workspaces/ws_current',
      ),
      hostAdapters: ToolHostAdapters(fileTools: fileTools),
    ),
  );

  expect(result.status, ToolExecutionStatus.success);
  expect(result.summary, '已删除路径：/memories/user/style.md');
});
```

- [ ] **Step 2: 写失败测试，拒绝删除 memory 根目录**

新增测试：

```dart
test('execute rejects deleting the memory root', () async {
  final result = await handler.execute(
    contextForDelete('/memories'),
  );

  expect(result.status, ToolExecutionStatus.failure);
  expect(result.errorMessage, 'cannot_delete_memory_root');
});
```

同时覆盖 `/memories/`。

- [ ] **Step 3: 写失败测试，拒绝删除 MEMORY.md 索引文件**

新增测试：

```dart
test('execute rejects deleting the memory index file', () async {
  await File('${rootService.rootPath}/memories/MEMORY.md')
      .create(recursive: true);

  final result = await handler.execute(
    contextForDelete('/memories/MEMORY.md'),
  );

  expect(result.status, ToolExecutionStatus.failure);
  expect(result.errorMessage, 'cannot_delete_memory_index');
});
```

- [ ] **Step 4: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/tools/handlers/delete_tool_handler_test.dart
```

Expected: FAIL，当前 `Delete` 会将 `/memories/...` 判定为 `path_outside_workspace`。

- [ ] **Step 5: 最小实现 memory delete 例外**

在 `DeleteToolHandler` 中加入顺序：

1. normalize path。
2. 如果是 memory root，返回 `cannot_delete_memory_root`。
3. 如果是 memory index，返回 `cannot_delete_memory_index`。
4. 如果是其他 memory path，跳过 workspace boundary check，进入 delete。
5. 非 memory path 保持当前 workspace 校验。

建议 helper：

```dart
bool _isMemoryPath(String agentPath) { ... }
bool _isMemoryRoot(String agentPath) { ... }
bool _isMemoryIndex(String agentPath) { ... }
```

- [ ] **Step 6: 运行测试确认通过**

Run:

```bash
fvm flutter test test/tools/handlers/delete_tool_handler_test.dart
```

Expected: PASS。

## Task 3: 注入长期记忆存储 prompt guidance

**Files:**
- Modify: `lib/services/prompt/prompt_catalog.dart`
- Modify: `lib/services/prompt/prompt_builder_service.dart`
- Test: `test/services/prompt/prompt_builder_service_test.dart`

- [ ] **Step 1: 查找现有 prompt builder 测试**

Run:

```bash
rg -n "PromptBuilderService|PromptCatalog|buildSystemPrompt" test/services test/models test
```

Expected: 找到现有 prompt 测试则复用；没有则新增 `test/services/prompt/prompt_builder_service_test.dart`。

- [ ] **Step 2: 写失败测试，planner prompt 包含 memory storage guidance**

测试断言：

```dart
final prompt = const PromptBuilderService().buildSystemPrompt(
  stage: PromptStage.planner,
);

expect(prompt, contains('/memories'));
expect(prompt, contains('MEMORY.md'));
expect(prompt, contains('type: {{user, feedback, project, reference}}'));
expect(prompt, contains('What NOT to save in memory'));
expect(prompt, contains('AGENTS.md'));
expect(prompt, contains('MEMORY.md is always loaded'));
```

- [ ] **Step 3: 写失败测试，summary prompt 不包含 memory storage guidance**

测试断言：

```dart
final prompt = const PromptBuilderService().buildSystemPrompt(
  stage: PromptStage.summary,
);

expect(prompt, isNot(contains('/memories')));
expect(prompt, isNot(contains('MEMORY.md')));
```

- [ ] **Step 4: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/services/prompt/prompt_builder_service_test.dart
```

Expected: FAIL，当前 prompt 没有长期记忆存储 guidance。

- [ ] **Step 5: 新增 PromptCatalog section**

在 `PromptCatalog` 增加：

```dart
String longTermMemoryStorage(PromptLocale locale) { ... }
```

英文内容优先落完整版本；中文内容保持结构对齐。

英文内容从 spec 的 Prompt Guidance 提炼，保留：

- `# auto memory`
- `/memories`
- types
- save process
- frontmatter
- not save list
- memory vs plan/tasks
- `MEMORY.md is always loaded into your conversation context`

中文内容可翻译，但结构必须和英文一致。

- [ ] **Step 6: 在 PromptBuilderService 非 summary stage 注入**

在非 summary 分支加入：

```dart
sections.add(_catalog.longTermMemoryStorage(locale));
```

位置建议在 `usingTools` 之后、`faithfulReporting` 之前，原因是它依赖通用文件工具规则。

- [ ] **Step 7: 运行测试确认通过**

Run:

```bash
fvm flutter test test/services/prompt/prompt_builder_service_test.dart
```

Expected: PASS。

## Task 4: 更新文件沙盒和项目文档

**Files:**
- Modify: `README.md`
- Modify: `docs/architecture/file-sandbox-architecture.md`
- Modify: `AGENTS.md`

- [ ] **Step 1: 更新 README**

在功能特点或文件沙盒章节补充：

```markdown
- 长期记忆存储层：`/memories` 作为全局 file-based memory 目录，当前阶段通过通用文件工具维护 `MEMORY.md` 和 topic files；自动加载、选择性召回和后台抽取作为紧邻后续环节补齐。
```

在 Supported Tools 附近可补充文件工具能维护 `/memories`。

- [ ] **Step 2: 更新 file sandbox 架构文档**

在 `/memories` 描述处补充：

```markdown
- `memories` 存放长期记忆存储层内容，是全局 agent 资产，不属于当前 workspace。
```

在文件工具边界补充：

```markdown
- `/memories` 可由通用文件工具维护，但删除时必须保护 `/memories` 根目录和 `/memories/MEMORY.md`。
```

- [ ] **Step 3: 更新 AGENTS.md**

在 Implementation Notes 附近补充：

```markdown
- 长期记忆存储层使用 `/memories/MEMORY.md` 加 topic Markdown files；当前阶段通过通用文件工具维护，不新增专用 memory tool。
- `/memories` 是全局长期记忆目录，不属于当前 workspace；`Write /memories/...` 不应触发 workspace 自动迁移。
- `Delete` 可删除具体 memory topic file，但不得删除 `/memories` 根目录或 `/memories/MEMORY.md`。
```

- [ ] **Step 4: 检查文档措辞准确表达“存储先行，使用层紧随其后”**

Run:

```bash
rg -n "自动召回|自动加载|always loaded|使用层|long-term memory|长期记忆" README.md AGENTS.md docs/architecture/file-sandbox-architecture.md docs/superpowers/specs/2026-06-19-long-term-memory-storage-design.md
```

Expected: 所有相关描述都表达为“当前实现先做存储，自动加载 / 召回 / 抽取是紧邻后续环节”，不要写成长期不支持。

## Task 5: 聚焦回归验证

**Files:**
- No production files expected beyond prior tasks

- [ ] **Step 1: 运行文件工具 handler 测试**

Run:

```bash
fvm flutter test test/tools/handlers/write_tool_handler_test.dart test/tools/handlers/delete_tool_handler_test.dart
```

Expected: PASS。

- [ ] **Step 2: 运行 prompt builder 测试**

Run:

```bash
fvm flutter test test/services/prompt/prompt_builder_service_test.dart
```

Expected: PASS。

- [ ] **Step 3: 运行默认 registry 测试，确认文件工具暴露未回退**

Run:

```bash
fvm flutter test test/tools/default_tool_runtime_registry_test.dart
```

Expected: PASS。

- [ ] **Step 4: 运行 analyze**

Run:

```bash
fvm flutter analyze
```

Expected: No analyzer errors。

## Task 6: 手动行为检查

**Files:**
- No code edits expected

- [ ] **Step 1: 通过已有 debug/test flow 构造 remember 请求**

示例用户请求：

```text
请记住：我希望这个项目里 Android 真机调试总是优先用 debug 覆盖安装脚本。
```

Expected planner 行为：

- 读取或创建 `/memories/MEMORY.md`。
- 写入合适 topic file，例如 `/memories/feedback/android-debug-install.md`。
- 更新 `MEMORY.md` 索引。
- 不写入 `/workspaces/<id>/...`。

- [ ] **Step 2: 构造 forget 请求**

示例用户请求：

```text
忘掉刚才关于 Android 真机调试安装脚本的长期记忆。
```

Expected planner 行为：

- 查找 `/memories` 中相关 topic file。
- 删除具体 topic file。
- 编辑 `/memories/MEMORY.md` 移除索引。
- 不删除 `/memories` 根目录。
- 不删除 `/memories/MEMORY.md` 整个文件。

- [ ] **Step 3: 导出或查看文件沙盒**

如果平台支持查看 app-private files，确认：

```text
/memories/MEMORY.md
/memories/feedback/android-debug-install.md
```

或确认 forget 后 topic file 消失且 index 更新。

## 最终验收清单

- [ ] `Write /memories/...` 不触发 workspace promotion。
- [ ] `Delete /memories/<type>/<topic>.md` 可以执行。
- [ ] `Delete /memories` 被拒绝。
- [ ] `Delete /memories/MEMORY.md` 被拒绝。
- [ ] 当前 workspace 删除规则没有回退。
- [ ] prompt guidance 包含长期记忆存储格式和不应保存内容。
- [ ] summary stage 不包含长期记忆存储 guidance。
- [ ] README / AGENTS / file sandbox 文档说明第一阶段先做存储层，并为自动加载 / 召回 / 抽取预留契约。
- [ ] `fvm flutter analyze` 无错误。
- [ ] 聚焦测试全部通过。

## 暂不执行项

本计划完成后仍待后续计划补齐：

- 自动抽取最近消息形成记忆。
- 自动读取 `MEMORY.md`。
- 相关记忆筛选。
- 使用记忆回答前的现状验证。
- UI 记忆管理。

这些应作为后续独立 spec / plan，但本计划中的 prompt 和文件格式已经为它们预留契约。
