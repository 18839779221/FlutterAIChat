# Delete Tool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为现有文件工具体系新增 `Delete`，支持删除单个文件和递归删除目录，并将删除范围严格限制在当前 workspace 内且禁止删除 workspace 根目录本身。

**Architecture:** 保持现有 tool runtime、planner 暴露、file sandbox 和 workspace V1 文件容器架构不变。实现上新增 `DeleteToolHandler`，并把底层删除能力并入现有 `FileToolWriteService`，由 handler 负责参数归一化、当前 workspace 边界校验和 `ToolResult` 封装，避免引入平行删除 service。

**Tech Stack:** Flutter 3.35.7（优先 `fvm flutter`）、Dart、现有 tool runtime、`FileToolWriteService`、workspace file container、Flutter test

---

## 相关设计

- Spec: `docs/superpowers/specs/2026-06-03-delete-tool-design.md`
- Related: `docs/superpowers/specs/2026-06-02-workspace-v1-file-container-design.md`
- Related: `docs/architecture/file-sandbox-architecture.md`

## 文件结构与职责

### 需要新增

- `lib/tools/handlers/delete_tool_handler.dart`
  - 定义 `Delete` 的 `ToolDefinition`
  - 归一化 `file_path`
  - 校验当前 workspace 边界
  - 拒绝删除 workspace 根目录
  - 调用底层删除服务并返回统一 `ToolResult`

- `test/tools/handlers/delete_tool_handler_test.dart`
  - 覆盖 schema、planner 描述、本地化描述、确认策略、路径校验和成功/失败结果

### 需要修改

- `lib/services/file_tools/file_tool_write_service.dart`
  - 增加统一删除入口
  - 支持文件删除与目录递归删除
  - 统计删除计数和目标类型
  - 删除后让 session guard 不再保留可写前提

- `lib/services/file_tools/file_tool_host_adapters.dart`
  - 如有必要仅补充注释，不新增平行 service 字段，继续复用 `writeService`

- `lib/tools/default_tool_runtime_registry.dart`
  - 注册 `DeleteToolHandler()`

- `test/services/file_tools/file_tool_write_service_test.dart`
  - 新增删除成功/失败用例

- `test/tools/default_tool_runtime_registry_test.dart`
  - 断言默认 runtime 已暴露 `Delete`

- `test/services/planner_tool_exposure_service_test.dart`
  - 断言文件工具集合中包含 `Delete`

- `test/integration/chat_send_live/scenarios/file_ops_real_workspace_scenario.dart`
  - 扩展示例文案，覆盖“删除前应确认”的真实 workspace 文件场景

- `README.md`
  - 如果仓库已有文件工具能力说明，补充 `Delete`

- `AGENTS.md`
  - 如果需要长期约束，补充 `Delete` 只允许当前 workspace 删除的规则

## 接口约定

### Tool 名称与描述

- `name`: `Delete`
- `title`: `Delete`
- `localizedTitle`: `删除文件`
- `requiresConfirmation = true`
- `isConcurrencySafe = false`

`descriptionForModel` 固定为 spec 中确认过的版本，强调：

- 仅在用户明确要求删除时使用
- 支持单文件删除与目录递归删除
- 必须特别谨慎
- 目录删除前要确认内容
- 禁止删除当前 workspace 之外内容
- 禁止删除当前 workspace 根目录本身

### 入参

```json
{
  "file_path": "/workspaces/ws_xxx/artifacts/old"
}
```

仅保留：

- `file_path: string`

### 成功结果

```json
{
  "filePath": "/workspaces/ws_xxx/artifacts/old",
  "message": "已删除路径：/workspaces/ws_xxx/artifacts/old",
  "deletedType": "directory",
  "deletedFileCount": 3,
  "deletedDirectoryCount": 2,
  "hadChildren": true
}
```

### 失败错误码

- `invalid_file_path`
- `path_outside_workspace`
- `cannot_delete_workspace_root`
- `file_not_found`
- `unsupported_tool`

## Task 1: 为 Delete handler 定义 planner-facing 契约

**Files:**
- Create: `lib/tools/handlers/delete_tool_handler.dart`
- Test: `test/tools/handlers/delete_tool_handler_test.dart`

- [ ] **Step 1: 写失败测试，定义 Delete 的 ToolDefinition**

新增测试，断言：

```dart
final handler = DeleteToolHandler();
expect(handler.definition.name, 'Delete');
expect(handler.definition.requiresConfirmation, true);
expect(handler.definition.isConcurrencySafe, false);
expect(handler.definition.resolvedArgumentSchema.required, ['file_path']);
expect(
  handler.definition.localizedDescriptionForModel?.chinese,
  contains('任何删除当前 workspace 之外内容'),
);
```

- [ ] **Step 2: 写失败测试，定义参数归一化**

新增测试，断言：

```dart
final resolution = await handler.normalizeArguments(
  rawArguments: {'file_path': '  artifacts/old.txt  '},
  userMessage: '删除这个文件',
  history: const [],
  now: DateTime(2026, 6, 3),
);

expect(resolution.isValid, true);
expect(resolution.normalizedArguments['file_path'], 'artifacts/old.txt');
```

同时为缺失 `file_path` 写失败断言。

- [ ] **Step 3: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/tools/handlers/delete_tool_handler_test.dart
```

Expected: FAIL，因为 handler 尚未实现。

- [ ] **Step 4: 最小实现 DeleteToolHandler 的 definition 与 normalize**

要求：

- 新建 `DeleteToolHandler`
- 定义 `ToolDefinition`
- 定义中英文 planner 描述
- 声明 `requiresConfirmation = true`
- `file_path` 去空白并保留现有文件工具参数风格

- [ ] **Step 5: 运行测试确认通过**

Run:

```bash
fvm flutter test test/tools/handlers/delete_tool_handler_test.dart
```

Expected: PASS。

## Task 2: 先用 TDD 为底层删除服务补齐行为

**Files:**
- Modify: `lib/services/file_tools/file_tool_write_service.dart`
- Test: `test/services/file_tools/file_tool_write_service_test.dart`

- [ ] **Step 1: 写失败测试，定义单文件删除**

新增测试，准备 sandbox 文件后断言：

```dart
final outcome = await service.deletePath(relativePath: 'workspaces/ws_1/artifacts/a.txt');

expect(outcome.filePath, '/workspaces/ws_1/artifacts/a.txt');
expect(outcome.deletedType, 'file');
expect(outcome.deletedFileCount, 1);
expect(outcome.deletedDirectoryCount, 0);
expect(file.existsSync(), false);
```

- [ ] **Step 2: 运行单文件删除测试确认失败**

Run:

```bash
fvm flutter test test/services/file_tools/file_tool_write_service_test.dart --plain-name "deletePath deletes a single file"
```

Expected: FAIL，因为 `deletePath` 尚不存在。

- [ ] **Step 3: 写失败测试，定义空目录删除**

断言：

```dart
expect(outcome.deletedType, 'directory');
expect(outcome.deletedFileCount, 0);
expect(outcome.deletedDirectoryCount, 1);
expect(outcome.hadChildren, false);
```

- [ ] **Step 4: 运行空目录删除测试确认失败**

Run:

```bash
fvm flutter test test/services/file_tools/file_tool_write_service_test.dart --plain-name "deletePath deletes an empty directory"
```

Expected: FAIL。

- [ ] **Step 5: 写失败测试，定义非空目录递归删除**

准备嵌套目录树并断言：

```dart
expect(outcome.deletedType, 'directory');
expect(outcome.deletedFileCount, 3);
expect(outcome.deletedDirectoryCount, 2);
expect(outcome.hadChildren, true);
expect(root.existsSync(), false);
```

- [ ] **Step 6: 运行递归删除测试确认失败**

Run:

```bash
fvm flutter test test/services/file_tools/file_tool_write_service_test.dart --plain-name "deletePath recursively deletes a populated directory"
```

Expected: FAIL。

- [ ] **Step 7: 写失败测试，定义不存在目标失败**

断言：

```dart
expect(
  () => service.deletePath(relativePath: 'workspaces/ws_1/missing.txt'),
  throwsA(isA<FileToolWriteException>().having((e) => e.code, 'code', 'file_not_found')),
);
```

- [ ] **Step 8: 运行不存在目标测试确认失败**

Run:

```bash
fvm flutter test test/services/file_tools/file_tool_write_service_test.dart --plain-name "deletePath throws file_not_found for missing targets"
```

Expected: FAIL。

- [ ] **Step 9: 最小实现 deletePath 与 outcome 字段**

要求：

- 在 `FileToolWriteService` 中新增 `deletePath`
- 新增删除结果类型字段，保持 `toJson()` 可序列化
- 支持文件与目录
- 目录先统计、后删除
- 缺失目标抛 `file_not_found`

- [ ] **Step 10: 运行删除服务测试确认通过**

Run:

```bash
fvm flutter test test/services/file_tools/file_tool_write_service_test.dart
```

Expected: PASS。

## Task 3: 为 handler 增加 workspace 边界与根目录保护

**Files:**
- Modify: `lib/tools/handlers/delete_tool_handler.dart`
- Test: `test/tools/handlers/delete_tool_handler_test.dart`

- [ ] **Step 1: 写失败测试，定义 workspace 外路径失败**

构造当前 workspace 为 `/workspaces/ws_current`，工具参数指向其他 workspace，断言：

```dart
expect(result.status, ToolExecutionStatus.failure);
expect(result.errorMessage, 'path_outside_workspace');
```

- [ ] **Step 2: 运行 workspace 外路径测试确认失败**

Run:

```bash
fvm flutter test test/tools/handlers/delete_tool_handler_test.dart --plain-name "execute rejects paths outside current workspace"
```

Expected: FAIL。

- [ ] **Step 3: 写失败测试，定义 workspace 根目录删除失败**

断言：

```dart
expect(result.status, ToolExecutionStatus.failure);
expect(result.errorMessage, 'cannot_delete_workspace_root');
```

- [ ] **Step 4: 运行根目录保护测试确认失败**

Run:

```bash
fvm flutter test test/tools/handlers/delete_tool_handler_test.dart --plain-name "execute rejects deleting the current workspace root"
```

Expected: FAIL。

- [ ] **Step 5: 写失败测试，定义成功结果摘要**

断言：

```dart
expect(result.summary, '已删除路径：/workspaces/ws_current/artifacts/old');
expect(result.data?['deletedType'], 'directory');
expect(result.data?['deletedFileCount'], 3);
```

- [ ] **Step 6: 运行成功结果测试确认失败**

Run:

```bash
fvm flutter test test/tools/handlers/delete_tool_handler_test.dart --plain-name "execute returns structured delete result"
```

Expected: FAIL。

- [ ] **Step 7: 最小实现 handler.execute**

要求：

- 复用 `pathPolicy.normalizeSandboxPath`
- 基于 `context.workspace.fileRoot` 做当前 workspace 前缀校验
- 拒绝删除当前 workspace 根目录本身
- 调用 `writeService.deletePath`
- 将 service outcome 映射为 `ToolResult`

- [ ] **Step 8: 运行 handler 测试确认通过**

Run:

```bash
fvm flutter test test/tools/handlers/delete_tool_handler_test.dart
```

Expected: PASS。

## Task 4: 注册 Delete 并补齐 planner/tool exposure 覆盖

**Files:**
- Modify: `lib/tools/default_tool_runtime_registry.dart`
- Modify: `test/tools/default_tool_runtime_registry_test.dart`
- Modify: `test/services/planner_tool_exposure_service_test.dart`

- [ ] **Step 1: 写失败测试，断言默认 runtime 包含 Delete**

新增测试，断言：

```dart
expect(
  registry.getAllDefinitions().map((tool) => tool.name),
  contains('Delete'),
);
```

- [ ] **Step 2: 写失败测试，断言 planner exposure 文件工具集合包含 Delete**

新增测试，断言：

```dart
expect(
  visible.map((tool) => tool.definition.name),
  contains('Delete'),
);
```

- [ ] **Step 3: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/tools/default_tool_runtime_registry_test.dart
fvm flutter test test/services/planner_tool_exposure_service_test.dart
```

Expected: FAIL，因为 runtime 尚未注册 `Delete`。

- [ ] **Step 4: 注册 DeleteToolHandler**

要求：

- 在默认 registry 中加入 `DeleteToolHandler()`
- 位置与 `Read` / `Write` / `Edit` 相邻

- [ ] **Step 5: 运行测试确认通过**

Run:

```bash
fvm flutter test test/tools/default_tool_runtime_registry_test.dart
fvm flutter test test/services/planner_tool_exposure_service_test.dart
```

Expected: PASS。

## Task 5: 更新真实 workspace 文件场景与文档

**Files:**
- Modify: `test/integration/chat_send_live/scenarios/file_ops_real_workspace_scenario.dart`
- Modify: `README.md`
- Modify: `AGENTS.md`

- [ ] **Step 1: 修改 live scenario 文案**

将场景扩展为：

- 先列目录
- 再读文件
- 再搜索
- 最后提出删除某个文件或目录，并明确“真正删除前先按正常流程等待确认”

- [ ] **Step 2: 更新 README 中的文件工具说明**

补充：

- `Delete` 已加入文件工具集合
- 目录删除为递归删除
- 删除只允许当前 workspace 内路径

- [ ] **Step 3: 更新 AGENTS.md 中的长期实现约束**

补充：

- `Delete` 只允许当前 workspace 删除
- 禁止删除 workspace 根目录本身

- [ ] **Step 4: 运行针对性验证**

Run:

```bash
fvm flutter test test/integration/chat_send_live/scenarios/file_ops_real_workspace_scenario.dart
```

Expected: PASS；若该文件仅为 scenario 定义且无直接测试入口，则改为运行引用它的最小上游测试并在提交说明中注明。

## Task 6: 最终验证与提交

**Files:**
- Modify: 与本计划相关的全部实现与测试文件

- [ ] **Step 1: 运行删除链路最小验证集**

Run:

```bash
fvm flutter test test/services/file_tools/file_tool_write_service_test.dart
fvm flutter test test/tools/handlers/delete_tool_handler_test.dart
fvm flutter test test/tools/default_tool_runtime_registry_test.dart
fvm flutter test test/services/planner_tool_exposure_service_test.dart
```

Expected: PASS。

- [ ] **Step 2: 运行更高一层回归**

Run:

```bash
fvm flutter test test/services/tool_executor_test.dart
fvm flutter test test/services/tool_call_service_test.dart
```

Expected: PASS；如果出现与 `Delete` 无关的既有失败，记录后单独说明，不要混淆为本次回归。

- [ ] **Step 3: 检查工作区变更范围**

Run:

```bash
git status --short
git diff --stat
```

确认只包含：

- `Delete` 实现
- 相关测试
- 必要文档更新

- [ ] **Step 4: 提交**

```bash
git add lib/tools/handlers/delete_tool_handler.dart \
  lib/services/file_tools/file_tool_write_service.dart \
  lib/tools/default_tool_runtime_registry.dart \
  test/tools/handlers/delete_tool_handler_test.dart \
  test/services/file_tools/file_tool_write_service_test.dart \
  test/tools/default_tool_runtime_registry_test.dart \
  test/services/planner_tool_exposure_service_test.dart \
  test/integration/chat_send_live/scenarios/file_ops_real_workspace_scenario.dart \
  README.md AGENTS.md
git commit -m "feat: add delete file tool"
```

- [ ] **Step 5: 推送**

```bash
git push
```

## 备注

- 删除逻辑必须继续只暴露 agent path，不能泄漏 host 路径。
- 目录递归删除不应通过 planner 额外参数控制，避免误用。
- 若 `file_tool_write_service_test.dart` 现有结构不适合增加删除 outcome 字段，可在本任务内做最小重构，但不要顺手改 unrelated 行为。
