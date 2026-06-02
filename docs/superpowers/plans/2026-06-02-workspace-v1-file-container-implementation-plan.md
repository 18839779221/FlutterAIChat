# Workspace V1 文件容器 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 chat 引入可空 `workspaceId`、`.default` 默认 workspace、按 workspace 分区的文件归属，以及复用现有 runtime context 机制的 workspace 注入与切换提醒。

**Architecture:** 保持 `chat group / turn / transcript / session context` 继续作为主语义边界，只把 workspace 作为文件容器接入。实现上通过 `chat_groups.workspace_id`、统一的 `/workspaces/<id>/...` 目录约定、自动创建触发器以及 runtime user context / runtime reminder 两条注入链路完成落地，不新增独立 workspace 表或 workspace 文件索引表。

**Tech Stack:** Flutter 3.35.7（优先 `fvm flutter`）、Dart、sqflite、本地文件服务、现有 `SessionContextService` / `RuntimeUserContextService` / file tools / artifact / attachment 服务

---

## 相关设计

- Spec: `docs/superpowers/specs/2026-06-02-workspace-v1-file-container-design.md`
- Related: `docs/superpowers/specs/2026-06-02-agent-file-access-sandbox-unification-design.md`
- Related: `docs/superpowers/specs/2026-04-24-runtime-user-context-and-date-awareness-design.md`

## 文件结构与职责

### 需要修改

- `lib/models/chat_group.dart`
  - 为 `ChatGroup` 增加 `workspaceId`。

- `lib/database/database_helper.dart`
  - 为 `chat_groups` 增加 `workspace_id` 字段、迁移逻辑和读写支持。

- `lib/controllers/chat_send_coordinator.dart`
  - 在发送链路中为 workspace 自动创建和 runtime reminder 预留触发点。

- `lib/services/prompt/runtime_user_context_service.dart`
  - 读取当前 group 的 workspace 并生成常驻 `currentWorkspace` section。

- `lib/models/prompt/runtime_user_context_snapshot.dart`
  - 如有必要，补充 workspace section 字段或继续复用 `additionalSections`。

- `lib/services/prompt/user_context_message_builder.dart`
  - 保持简洁模板，但允许注入 workspace section。

- `lib/services/session_runtime_marker_service.dart`
  - 扩展 runtime context key，支持 workspace 变化 reminder。

- `lib/services/session_context_service.dart`
  - 从当前 turn runtime context 中抽取 workspace change reminder。

- `lib/services/file_tools/*`
  - 把默认文件根从全局目录语义推进到 `/workspaces/<id>/...`。

- `lib/services/artifact/artifact_file_storage_service.dart`
  - 让 artifact 默认写入当前 workspace 的 `artifacts/`。

- `lib/services/attachments/chat_attachment_storage_service.dart`
  - 让归档附件默认写入当前 workspace 的 `attachments/`。

- `lib/tools/handlers/write_tool_handler.dart`
  - 复用 `filePreviouslyExisted` 区分新建文件与覆盖文件。

- `lib/tools/handlers/edit_tool_handler.dart`
  - 保持“不触发 workspace 创建”。

- `lib/controllers/chat_session_coordinator.dart`
  - 新建 chat / 选择已有 workspace 的 UI 接入点。

- `lib/providers/*workspace*` 或相关 provider 文件
  - 暴露当前 group 的 workspace 解析结果与轻量 UI 状态。

- `README.md`
  - 补充 workspace V1 文件容器说明。

- `AGENTS.md`
  - 补充 workspace 文件归属、`.default` 和 runtime 注入约束。

### 需要新增

- `lib/services/workspace/workspace_id_generator.dart`
  - 生成 `.default` 以外的自动 workspace 名：`ws_<yyyyMMdd>_<6位随机串>`。

- `lib/services/workspace/workspace_binding_service.dart`
  - 负责：
    - 将 `NULL workspace_id` 解析为 `.default`
    - 自动创建 workspaceId
    - 更新 chat group 绑定
    - 生成 workspace change reminder 文本

- `lib/models/workspace/resolved_workspace.dart`
  - 封装运行时使用的 workspace 解析结果，例如：
    - `workspaceId`
    - `isDefault`
    - `fileRoot`

- `test/services/workspace/workspace_id_generator_test.dart`
- `test/services/workspace/workspace_binding_service_test.dart`
- `test/services/prompt/runtime_user_context_service_test.dart`
- `test/services/session_context_service_test.dart`
- `test/controllers/chat_send_coordinator_workspace_test.dart`
  - 覆盖命名规则、解析规则、runtime 注入、自动创建触发与非触发行为。

## Task 1: 为 ChatGroup 和数据库增加 workspaceId

**Files:**
- Modify: `lib/models/chat_group.dart`
- Modify: `lib/database/database_helper.dart`
- Test: `test/models/chat_group_test.dart`
- Test: `test/database/database_helper_group_workspace_test.dart`

- [ ] **Step 1: 写失败测试，定义 ChatGroup 的 workspaceId 契约**

新增测试，断言：

```dart
final group = ChatGroup(
  title: 'Test',
  lockedProviderStyle: ChatTurnProviderStyle.responses,
  workspaceId: 'ws_20260602_a3k9qx',
);

expect(group.toMap()['workspace_id'], 'ws_20260602_a3k9qx');
expect(ChatGroup.fromMap({...group.toMap(), 'id': 1}).workspaceId, 'ws_20260602_a3k9qx');
```

- [ ] **Step 2: 写数据库迁移失败测试**

断言：

- 新建库时 `chat_groups` 包含 `workspace_id`
- 从旧版本升级后 `workspace_id` 存在
- 旧记录 `workspace_id` 可为 `NULL`

- [ ] **Step 3: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/models/chat_group_test.dart
fvm flutter test test/database/database_helper_group_workspace_test.dart
```

Expected: FAIL，因为字段与迁移尚未实现。

- [ ] **Step 4: 最小实现 ChatGroup 与 chat_groups.workspace_id**

要求：

- `ChatGroup` 增加 `workspaceId`
- `toMap/fromMap/copyWith` 全部支持
- `chat_groups` 新建表包含 `workspace_id TEXT`
- 增加数据库版本迁移，安全为旧库补列

- [ ] **Step 5: 运行测试确认通过**

Run:

```bash
fvm flutter test test/models/chat_group_test.dart
fvm flutter test test/database/database_helper_group_workspace_test.dart
```

Expected: PASS。

## Task 2: 实现 workspace 解析与命名规则

**Files:**
- Create: `lib/models/workspace/resolved_workspace.dart`
- Create: `lib/services/workspace/workspace_id_generator.dart`
- Create: `lib/services/workspace/workspace_binding_service.dart`
- Test: `test/services/workspace/workspace_id_generator_test.dart`
- Test: `test/services/workspace/workspace_binding_service_test.dart`

- [ ] **Step 1: 写失败测试，定义 workspaceId 生成规则**

测试断言：

```dart
expect(generator.defaultWorkspaceId, '.default');
expect(generator.generateAutoWorkspaceId(now: DateTime(2026, 6, 2)), matches(r'^ws_20260602_[a-z0-9]{6}$'));
```

- [ ] **Step 2: 写失败测试，定义 resolved workspace 规则**

测试断言：

```dart
expect(service.resolveWorkspaceId(null).workspaceId, '.default');
expect(service.resolveWorkspaceId(null).isDefault, true);
expect(service.resolveWorkspaceId('ws_20260602_a3k9qx').fileRoot, '/workspaces/ws_20260602_a3k9qx');
```

- [ ] **Step 3: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/services/workspace/workspace_id_generator_test.dart
fvm flutter test test/services/workspace/workspace_binding_service_test.dart
```

Expected: FAIL，因为新服务还不存在。

- [ ] **Step 4: 实现 workspaceId 生成与解析服务**

要求：

- `.default` 为固定默认 workspace
- 自动命名规则为 `ws_<yyyyMMdd>_<6位小写字母数字随机串>`
- 运行时 `NULL` 一律解析为 `.default`
- 提供统一 `fileRoot`，例如 `/workspaces/.default`

- [ ] **Step 5: 运行测试确认通过**

Run:

```bash
fvm flutter test test/services/workspace/workspace_id_generator_test.dart
fvm flutter test test/services/workspace/workspace_binding_service_test.dart
```

Expected: PASS。

## Task 3: 为 runtime user context 增加 currentWorkspace 注入

**Files:**
- Modify: `lib/services/prompt/runtime_user_context_service.dart`
- Modify: `lib/services/prompt/user_context_message_builder.dart`
- Modify: `lib/services/session_context_service.dart`
- Test: `test/services/prompt/runtime_user_context_service_test.dart`
- Test: `test/services/session_context_service_test.dart`

- [ ] **Step 1: 写失败测试，定义常驻 workspace 注入格式**

测试断言：

- `.default` 时出现：

```text
# currentWorkspace
Current workspace: .default (default workspace).
File root: /workspaces/.default
```

- 普通 workspace 时出现：

```text
# currentWorkspace
Current workspace: ws_20260602_a3k9qx.
File root: /workspaces/ws_20260602_a3k9qx
```

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/services/prompt/runtime_user_context_service_test.dart
fvm flutter test test/services/session_context_service_test.dart
```

Expected: FAIL，因为当前 runtime user context 还没有 workspace section。

- [ ] **Step 3: 最小实现 currentWorkspace section**

要求：

- 复用现有 `additionalSections`
- 文案保持简洁
- `.default` 额外带 `(default workspace)`
- 不列文件清单

- [ ] **Step 4: 运行测试确认通过**

Run:

```bash
fvm flutter test test/services/prompt/runtime_user_context_service_test.dart
fvm flutter test test/services/session_context_service_test.dart
```

Expected: PASS。

## Task 4: 为 turn runtime context 增加 workspace changed reminder

**Files:**
- Modify: `lib/services/session_runtime_marker_service.dart`
- Modify: `lib/services/session_context_service.dart`
- Modify: `lib/controllers/chat_send_coordinator.dart`
- Test: `test/services/session_runtime_marker_service_test.dart`
- Test: `test/controllers/chat_send_coordinator_workspace_test.dart`

- [ ] **Step 1: 写失败测试，定义 workspace reminder 注入与抽取规则**

测试断言：

- 当 chat 从 `.default` 切到 `ws_20260602_a3k9qx` 时，当前 turn runtime context 里出现：

```text
<system-reminder>
The current chat is now using workspace ws_20260602_a3k9qx.
New files for this chat should be created under /workspaces/ws_20260602_a3k9qx.
</system-reminder>
```

- `SessionContextService` 能像日期 reminder 一样把它投影进 current turn context

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/services/session_runtime_marker_service_test.dart
fvm flutter test test/controllers/chat_send_coordinator_workspace_test.dart
```

Expected: FAIL，因为当前 runtime marker 只支持日期提醒。

- [ ] **Step 3: 最小实现 workspace runtime reminder**

要求：

- 在 `runtime_context` 中新增 workspace 相关 key
- reminder 只在 workspace 变化时写入
- 继续保持不持久化为 transcript 事件

- [ ] **Step 4: 运行测试确认通过**

Run:

```bash
fvm flutter test test/services/session_runtime_marker_service_test.dart
fvm flutter test test/controllers/chat_send_coordinator_workspace_test.dart
```

Expected: PASS。

## Task 5: 定义自动创建触发器与 chat 绑定升级

**Files:**
- Modify: `lib/controllers/chat_send_coordinator.dart`
- Modify: `lib/services/workspace/workspace_binding_service.dart`
- Modify: `lib/tools/handlers/write_tool_handler.dart`
- Modify: `lib/services/file_tools/file_tool_write_service.dart`
- Test: `test/controllers/chat_send_coordinator_workspace_test.dart`
- Test: `test/tools/handlers/write_tool_handler_test.dart`

- [ ] **Step 1: 写失败测试，定义自动创建与非触发行为**

测试至少覆盖：

- `create_artifact` 触发 `.default -> ws_xxx`
- `Write` 新建文件时触发 `.default -> ws_xxx`
- `Write` 覆盖已有文件时不触发
- `Edit` 不触发

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/controllers/chat_send_coordinator_workspace_test.dart
fvm flutter test test/tools/handlers/write_tool_handler_test.dart
```

Expected: FAIL，因为自动创建规则尚未实现。

- [ ] **Step 3: 最小实现自动创建顺序**

要求：

1. 检查当前 group 是否仍为 `.default`
2. 生成新 workspaceId
3. 更新 `chat_groups.workspace_id`
4. 本次文件直接写入新 workspace
5. 为当前 turn 注入 workspace change reminder

并明确：

- 不允许先写 `.default` 再迁移
- `Write` 必须依据 `filePreviouslyExisted` 判断是否属于“新建文件”

- [ ] **Step 4: 运行测试确认通过**

Run:

```bash
fvm flutter test test/controllers/chat_send_coordinator_workspace_test.dart
fvm flutter test test/tools/handlers/write_tool_handler_test.dart
```

Expected: PASS。

## Task 6: 把 artifact / attachment / tmp 默认归属到 workspace 目录

**Files:**
- Modify: `lib/services/artifact/artifact_file_storage_service.dart`
- Modify: `lib/services/attachments/chat_attachment_storage_service.dart`
- Modify: `lib/services/file_tools/*`
- Test: `test/services/artifact/artifact_file_storage_service_test.dart`
- Test: `test/services/attachments/chat_attachment_storage_service_test.dart`

- [ ] **Step 1: 写失败测试，定义 workspace 路径归属**

测试断言：

- 默认 workspace artifact 路径位于 `/workspaces/.default/artifacts/...`
- 显式 workspace artifact 路径位于 `/workspaces/ws_.../artifacts/...`
- 归档附件位于对应 workspace 的 `attachments/...`

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/services/artifact/artifact_file_storage_service_test.dart
fvm flutter test test/services/attachments/chat_attachment_storage_service_test.dart
```

Expected: FAIL，因为当前实现还不是 workspace 分区目录。

- [ ] **Step 3: 最小实现 workspace 目录布局**

要求：

- 固定目录布局：

```text
/workspaces/<id>/artifacts
/workspaces/<id>/attachments
/workspaces/<id>/tmp
```

- 由统一 workspace 解析服务提供路径拼装
- 不在业务层分散拼接 workspace 目录

- [ ] **Step 4: 运行测试确认通过**

Run:

```bash
fvm flutter test test/services/artifact/artifact_file_storage_service_test.dart
fvm flutter test test/services/attachments/chat_attachment_storage_service_test.dart
```

Expected: PASS。

## Task 7: 最小 UI 浮现与文档补充

**Files:**
- Modify: `lib/controllers/chat_session_coordinator.dart`
- Modify: `lib/providers/chat_collection_providers.dart`
- Modify: `lib/pages/*` 或相关 chat 页面文件
- Modify: `README.md`
- Modify: `AGENTS.md`
- Test: `test/widgets/*workspace*_test.dart`

- [ ] **Step 1: 写失败测试，定义最小 UI 行为**

测试目标：

- chat 页可看到当前 workspace 轻量标识
- 自动创建后出现一次轻提示
- 新建 chat 或 chat 设置可选择已有 workspace

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/widgets
```

Expected: FAIL，在相关 workspace UI 测试尚未实现的前提下。

- [ ] **Step 3: 实现最小 UI，不扩 scope**

要求：

- 只做轻量浮现
- 不实现 workspace 首页
- 不实现 workspace 时间线
- 不实现 workspace 文件中心

- [ ] **Step 4: 更新 README 与 AGENTS.md**

文档至少说明：

- `workspaceId` 可空但运行时解析为 `.default`
- 文件默认位于 `/workspaces/<id>/...`
- workspace 只共享文件，不共享 session context
- current workspace 通过 runtime context 注入模型

- [ ] **Step 5: 运行相关测试确认通过**

Run:

```bash
fvm flutter test test/widgets
```

Expected: 相关 workspace UI 测试 PASS；若全量 widget tests 过重，可收窄到新增测试文件。

## Task 8: 串联验证与提交

**Files:**
- Verify only

- [ ] **Step 1: 运行目标测试集**

Run:

```bash
fvm flutter test test/models/chat_group_test.dart
fvm flutter test test/database/database_helper_group_workspace_test.dart
fvm flutter test test/services/workspace/workspace_id_generator_test.dart
fvm flutter test test/services/workspace/workspace_binding_service_test.dart
fvm flutter test test/services/prompt/runtime_user_context_service_test.dart
fvm flutter test test/services/session_runtime_marker_service_test.dart
fvm flutter test test/services/session_context_service_test.dart
fvm flutter test test/services/artifact/artifact_file_storage_service_test.dart
fvm flutter test test/services/attachments/chat_attachment_storage_service_test.dart
fvm flutter test test/controllers/chat_send_coordinator_workspace_test.dart
```

Expected: PASS。

- [ ] **Step 2: 运行最小 analyze**

Run:

```bash
fvm flutter analyze
```

Expected: 无新的 error；若存在 repo 既有 info/warning，需与本次改动区分记录。

- [ ] **Step 3: 提交实现**

```bash
git add lib/models/chat_group.dart \
  lib/database/database_helper.dart \
  lib/services/workspace \
  lib/services/prompt/runtime_user_context_service.dart \
  lib/services/prompt/user_context_message_builder.dart \
  lib/services/session_runtime_marker_service.dart \
  lib/services/session_context_service.dart \
  lib/services/artifact \
  lib/services/attachments \
  lib/controllers/chat_send_coordinator.dart \
  README.md AGENTS.md test
git commit -m "feat: add workspace v1 file container flow"
```

- [ ] **Step 4: 记录验证结果**

在提交说明或开发记录中注明：

- `.default` 行为已验证
- `create_artifact` / 新建文件 `Write` 自动创建已验证
- workspace runtime 注入已验证
- 文件路径已落到 `/workspaces/<id>/...`
