# Agent 文件访问沙盒统一 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把项目内分散的文件访问路径统一到平台私有 app sandbox 下的单一 `agent` root，同时让 agent 侧保持 file-native 的绝对路径 `/...` 与相对路径语义，并彻底隔离宿主真实路径。

**Architecture:** 保留现有文件工具与业务模块的 file-native 心智模型，但新增统一路径解析层，让 `Read/Write/Edit/LS/Glob/Grep`、artifact、skills、attachments、调试页全部通过同一套 agent 路径解析和 host 路径映射工作。实现上不引入新的显式 namespace 协议，而是通过平台私有 `agent` root、agent 路径归一化、默认读写策略和 host-only 路径解析收口所有文件访问。

**Tech Stack:** Flutter 3.35.7（优先 `fvm flutter`）、Dart、path/path_provider、flutter_test、现有 file tool service/handler 架构、现有 artifact/skills/attachments 服务

---

## 相关设计

- Spec: `docs/superpowers/specs/2026-06-02-agent-file-access-sandbox-unification-design.md`
- Baseline plan: `docs/superpowers/plans/2026-04-13-sandbox-file-tools-implementation-plan.md`

## 文件结构与职责

### 需要新增

- `lib/services/file_tools/agent_path.dart`
  - 定义 agent 路径值对象与基础校验，明确区分 agent 绝对路径和宿主真实路径。

- `lib/services/file_tools/agent_path_resolver.dart`
  - 接收 `rawPath + cwd`，输出归一化后的 agent 绝对路径、相对路径和 host 真实路径。

- `test/services/file_tools/agent_path_resolver_test.dart`
  - 覆盖 `/...` 绝对路径、相对路径、`.`、`..`、多重 `/`、越界拒绝。

### 需要修改

- `lib/services/file_tools/file_tool_root_service.dart`
  - 从“接受相对路径直接拼接 root”升级为“围绕单一 agent root 提供 host 路径解析”。

- `lib/services/file_tools/file_tool_path_policy.dart`
  - 从“只接受 sandbox 相对路径”升级为“接受 agent 绝对路径和相对路径，并要求显式 `cwd`”。

- `lib/services/file_tools/file_tool_discovery_service.dart`
  - 统一基于 agent 路径工作，返回 agent 绝对路径。

- `lib/services/file_tools/file_tool_write_service.dart`
  - 统一接收 agent 绝对路径或标准相对路径解析结果，保持 session guard 以 agent 路径作为 key。

- `lib/services/file_tools/file_tool_session_guard.dart`
  - 改用 agent 绝对路径作为 seen file 的稳定 key。

- `lib/services/default_file_tool_adapters_native.dart`
  - 把平台私有 `agent` root 作为统一文件沙盒根，提前创建 `artifacts/skills/attachments/memories/tmp` 子树。

- `lib/tools/handlers/read_tool_handler.dart`
  - 支持 `/...` agent 绝对路径和相对路径。

- `lib/tools/handlers/write_tool_handler.dart`
  - 支持 `/...` agent 绝对路径和相对路径，并在返回结果中统一使用 agent 绝对路径。

- `lib/tools/handlers/edit_tool_handler.dart`
  - 同上。

- `lib/tools/handlers/ls_tool_handler.dart`
  - 支持 `/...` agent 绝对路径和相对路径。

- `lib/tools/handlers/glob_tool_handler.dart`
  - 同上。

- `lib/tools/handlers/grep_tool_handler.dart`
  - 同上。

- `lib/services/artifact/artifact_file_storage_service.dart`
  - 不再独立持有 `inline_artifacts` 真实 root，改为基于统一 agent root 的 `/artifacts/...`。

- `lib/services/skills/skill_storage_service.dart`
  - 不再独立持有 `skills` 真实 root，改为基于统一 agent root 的 `/skills/...`。

- `lib/services/attachments/chat_attachment_storage_service.dart`
  - 导入后只保存 `/attachments/...` agent 路径，真实宿主路径只保留在导入瞬间。

- `lib/services/attachments/chat_attachment_payload_codec.dart`
  - 序列化上传载荷时消费 agent 路径语义，不依赖长期保存的宿主真实路径。

- `lib/models/chat/chat_attachment.dart`
  - 明确哪些字段是 agent 路径，哪些字段若仍保留只允许 host-only 使用。

- `lib/services/tool_result_context_projector.dart`
  - 统一只投影 agent 路径，不投影宿主真实路径。

- `lib/tools/handlers/skill_tool_handler.dart`
  - skill 返回路径统一为 agent 路径，去掉宿主目录暴露。

- `lib/services/skills/explicit_skill_invocation_parser.dart`
  - invoked skill context 中只使用 agent 路径。

- `lib/services/skills/skill_runtime_service.dart`
  - 读取 skill 正文时走统一 agent root。

- `lib/pages/webview_debug_page.dart`
  - 调试页不再自己扫描真实 artifact root，改为走统一访问层或 artifact service。

- `lib/main.dart`
  - 用统一 agent root 初始化 file tools、artifact storage、skill storage、attachment storage。

- `test/tools/handlers/read_tool_handler_test.dart`
- `test/tools/handlers/write_tool_handler_test.dart`
- `test/tools/handlers/edit_tool_handler_test.dart`
- `test/tools/handlers/ls_tool_handler_test.dart`
- `test/tools/handlers/glob_tool_handler_test.dart`
- `test/tools/handlers/grep_tool_handler_test.dart`
  - 更新为 agent 绝对路径和相对路径双模式。

- `test/services/file_tools/file_tool_path_policy_test.dart`
- `test/services/file_tools/file_tool_discovery_service_test.dart`
- `test/services/file_tools/file_tool_write_service_test.dart`
  - 更新到新路径模型。

- `README.md`
  - 补充统一 agent 文件沙盒说明。

- `AGENTS.md`
  - 补充 agent 文件系统根 `/`、平台私有 app sandbox root、禁止真实路径外泄等规则。

## Task 1: 建立 agent 路径模型与统一解析层

**Files:**
- Create: `lib/services/file_tools/agent_path.dart`
- Create: `lib/services/file_tools/agent_path_resolver.dart`
- Modify: `lib/services/file_tools/file_tool_root_service.dart`
- Modify: `lib/services/file_tools/file_tool_path_policy.dart`
- Test: `test/services/file_tools/agent_path_resolver_test.dart`
- Test: `test/services/file_tools/file_tool_path_policy_test.dart`

- [ ] **Step 1: 写失败测试，定义 agent 路径解析契约**

在 `test/services/file_tools/agent_path_resolver_test.dart` 新增测试，覆盖：

```dart
expect(resolve('/artifacts/42/a.html', cwd: '/').agentAbsolutePath, '/artifacts/42/a.html');
expect(resolve('artifacts/42/a.html', cwd: '/').agentAbsolutePath, '/artifacts/42/a.html');
expect(resolve('./a.html', cwd: '/artifacts/42').agentAbsolutePath, '/artifacts/42/a.html');
expect(resolve('../43/b.html', cwd: '/artifacts/42').agentAbsolutePath, '/artifacts/43/b.html');
expect(resolve('////artifacts//42///a.html', cwd: '/').agentAbsolutePath, '/artifacts/42/a.html');
expect(() => resolve('../../etc/passwd', cwd: '/'), throwsA(isA<AgentPathEscapeException>()));
```

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/services/file_tools/agent_path_resolver_test.dart
```

Expected: FAIL，因为新文件和解析器还不存在。

- [ ] **Step 3: 实现 agent 路径值对象与解析器**

实现要求：

- `AgentPath` 表达归一化后的 agent 绝对路径，例如 `/artifacts/42/a.html`
- `AgentPathResolution` 同时包含：
  - `agentAbsolutePath`
  - `relativePathFromRoot`
  - `hostAbsolutePath`
- 明确区分 agent 路径和 host 路径，不要把宿主路径塞回 `filePath`
- `cwd` 必须参与相对路径解析，首版默认调用方统一传 `/`

- [ ] **Step 4: 改造 FileToolRootService 与 FileToolPathPolicy**

要求：

- `FileToolRootService` 只负责“平台私有 app sandbox 下的 `agent` root”
- `FileToolPathPolicy` 接受 `/...` 绝对路径和相对路径
- 拒绝空路径、NUL、逃出 `/` 的 `..`
- 默认目录路径 `.` 在 `cwd=/` 时归一化为 `/`

- [ ] **Step 5: 运行服务层测试**

Run:

```bash
fvm flutter test test/services/file_tools/agent_path_resolver_test.dart
fvm flutter test test/services/file_tools/file_tool_path_policy_test.dart
```

Expected: PASS。

## Task 2: 把文件工具统一到 agent 绝对路径模型

**Files:**
- Modify: `lib/services/file_tools/file_tool_discovery_service.dart`
- Modify: `lib/services/file_tools/file_tool_session_guard.dart`
- Modify: `lib/services/file_tools/file_tool_write_service.dart`
- Modify: `lib/tools/handlers/read_tool_handler.dart`
- Modify: `lib/tools/handlers/write_tool_handler.dart`
- Modify: `lib/tools/handlers/edit_tool_handler.dart`
- Modify: `lib/tools/handlers/ls_tool_handler.dart`
- Modify: `lib/tools/handlers/glob_tool_handler.dart`
- Modify: `lib/tools/handlers/grep_tool_handler.dart`
- Test: `test/services/file_tools/file_tool_discovery_service_test.dart`
- Test: `test/services/file_tools/file_tool_write_service_test.dart`
- Test: `test/tools/handlers/read_tool_handler_test.dart`
- Test: `test/tools/handlers/write_tool_handler_test.dart`
- Test: `test/tools/handlers/edit_tool_handler_test.dart`
- Test: `test/tools/handlers/ls_tool_handler_test.dart`
- Test: `test/tools/handlers/glob_tool_handler_test.dart`
- Test: `test/tools/handlers/grep_tool_handler_test.dart`

- [ ] **Step 1: 先改 handler 测试为 agent 绝对路径输出**

为 `Read/Write/Edit/LS/Glob/Grep` 增加双模式测试：

- 输入 `/artifacts/42/a.txt`
- 输入 `artifacts/42/a.txt`
- 结果中的 `filePath` / `path` / `matches` / `entries` 统一断言为 `/...` 绝对路径

- [ ] **Step 2: 运行相关测试并确认失败**

Run:

```bash
fvm flutter test test/tools/handlers/read_tool_handler_test.dart
fvm flutter test test/tools/handlers/write_tool_handler_test.dart
fvm flutter test test/tools/handlers/edit_tool_handler_test.dart
fvm flutter test test/tools/handlers/ls_tool_handler_test.dart
fvm flutter test test/tools/handlers/glob_tool_handler_test.dart
fvm flutter test test/tools/handlers/grep_tool_handler_test.dart
```

Expected: FAIL，因为当前实现仍主要按相对路径工作。

- [ ] **Step 3: 改造 discovery / write / session guard**

要求：

- `list/glob/grep` 返回的每个路径都是 agent 绝对路径
- `FileToolSessionGuard` 的 map key 改为 agent 绝对路径
- `FileToolWriteService` 接受解析结果或稳定的 agent 绝对路径 key，不再依赖裸相对路径

- [ ] **Step 4: 改造各 handler**

要求：

- `Read/Write/Edit` 对外 schema 描述改为“支持 agent 绝对路径和相对路径”
- `LS/Glob/Grep` 同上
- handler 内统一以 `cwd='/'` 起步，除非未来显式引入工作目录
- tool result 中永远回写 agent 绝对路径

- [ ] **Step 5: 运行文件工具相关测试**

Run:

```bash
fvm flutter test test/services/file_tools/file_tool_discovery_service_test.dart
fvm flutter test test/services/file_tools/file_tool_write_service_test.dart
fvm flutter test test/tools/handlers/read_tool_handler_test.dart
fvm flutter test test/tools/handlers/write_tool_handler_test.dart
fvm flutter test test/tools/handlers/edit_tool_handler_test.dart
fvm flutter test test/tools/handlers/ls_tool_handler_test.dart
fvm flutter test test/tools/handlers/glob_tool_handler_test.dart
fvm flutter test test/tools/handlers/grep_tool_handler_test.dart
```

Expected: PASS。

## Task 3: 把平台私有 `agent` root 扩展为统一物理文件沙盒

**Files:**
- Modify: `lib/services/default_file_tool_adapters_native.dart`
- Modify: `lib/main.dart`
- Test: `test/services/file_tools/file_tool_root_service_test.dart`（如不存在则新增）

- [ ] **Step 1: 写失败测试，要求统一 root 预创建子目录**

测试应验证平台私有 `agent` root 下会创建：

```text
artifacts/
skills/
attachments/persisted/
attachments/thumbs/
memories/
tmp/
```

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/services/file_tools/file_tool_root_service_test.dart
```

Expected: FAIL，因为当前只创建 `memories/artifacts/tmp`。

- [ ] **Step 3: 修改默认 adapter 与 main 启动装配**

要求：

- 统一把 artifact / skills / attachments / file tools 都绑定到同一个平台私有 `agent` root
- 不再让 `main.dart` 自己单独拼 `inline_artifacts` 或 `skills`
- root 只在一处创建与分发

- [ ] **Step 4: 运行 root / 启动相关测试**

Run:

```bash
fvm flutter test test/services/file_tools/file_tool_root_service_test.dart
```

Expected: PASS。

## Task 4: 迁移 artifact 存储到 `/artifacts/...`

**Files:**
- Modify: `lib/services/artifact/artifact_file_storage_service.dart`
- Modify: `lib/services/artifact/artifact_turn_resolver.dart`
- Modify: `lib/main.dart`
- Test: `test/services/artifact/artifact_file_storage_service_test.dart`（如不存在则新增）
- Test: `test/services/artifact/artifact_turn_resolver_test.dart`（如不存在则新增）

- [ ] **Step 1: 写失败测试，固定 artifact 的 agent 路径契约**

断言：

```dart
expect(result.sourcePath, '/artifacts/123/abc.html');
```

并验证读取时不再依赖独立 `inline_artifacts` root。

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/services/artifact/artifact_file_storage_service_test.dart
fvm flutter test test/services/artifact/artifact_turn_resolver_test.dart
```

Expected: FAIL，因为当前是相对路径且 root 独立。

- [ ] **Step 3: 修改 artifact storage / resolver**

要求：

- `sourcePath` 统一输出 agent 绝对路径 `/artifacts/...`
- 读写统一通过 agent root
- `ArtifactTurnResolver` 读回 source 时不再自己拼旧 root

- [ ] **Step 4: 运行 artifact 测试**

Run:

```bash
fvm flutter test test/services/artifact/artifact_file_storage_service_test.dart
fvm flutter test test/services/artifact/artifact_turn_resolver_test.dart
```

Expected: PASS。

## Task 5: 迁移 skills 存储与 skill context 到 `/skills/...`

**Files:**
- Modify: `lib/services/skills/skill_storage_service.dart`
- Modify: `lib/services/skills/skill_runtime_service.dart`
- Modify: `lib/services/skills/skill_index_service.dart`
- Modify: `lib/services/skills/explicit_skill_invocation_parser.dart`
- Modify: `lib/tools/handlers/skill_tool_handler.dart`
- Modify: `lib/services/tool_result_context_projector.dart`
- Modify: `lib/models/skill/invoked_skill_context.dart`
- Test: `test/services/skills/skill_storage_service_test.dart`（如不存在则新增）
- Test: `test/tools/handlers/skill_tool_handler_test.dart`
- Test: `test/services/session_context_service_skills_test.dart`

- [ ] **Step 1: 写失败测试，禁止 skill context 暴露宿主真实路径**

断言：

- invoked skill path 为 `/skills/installed/.../SKILL.md`
- `ToolResultContextProjector` 投影文本不出现宿主绝对路径

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/tools/handlers/skill_tool_handler_test.dart
fvm flutter test test/services/session_context_service_skills_test.dart
```

Expected: FAIL，因为当前 `qualifiedPath/baseDirectory` 仍是宿主路径。

- [ ] **Step 3: 改造 skill storage / runtime / projection**

要求：

- installed skills 全部位于 `/skills/installed/...`
- skill 索引内部可解析宿主路径，但对 agent 只输出 agent 路径
- `InvokedSkillContext` 去掉对宿主真实目录的依赖，必要时拆成 agent-visible 字段和 host-only 内部数据

- [ ] **Step 4: 运行 skills 测试**

Run:

```bash
fvm flutter test test/tools/handlers/skill_tool_handler_test.dart
fvm flutter test test/services/session_context_service_skills_test.dart
```

Expected: PASS。

## Task 6: 迁移 attachments 到 `/attachments/...` 并清除长期真实路径

**Files:**
- Modify: `lib/services/attachments/chat_attachment_storage_service.dart`
- Modify: `lib/services/attachments/chat_attachment_payload_codec.dart`
- Modify: `lib/models/chat/chat_attachment.dart`
- Modify: `lib/widgets/chat_message_image_attachments.dart`
- Modify: `lib/widgets/chat_input_attachment_strip.dart`
- Modify: `lib/widgets/chat_attachment_image_preview_dialog.dart`
- Test: `test/services/attachments/chat_attachment_storage_service_test.dart`（如不存在则新增）
- Test: `test/services/attachments/chat_attachment_payload_codec_test.dart`（如不存在则新增）

- [ ] **Step 1: 写失败测试，要求导入后只保存 agent 路径**

断言：

- `attachment.localPath == '/attachments/persisted/<id>_<name>'`
- `attachment.thumbnailPath == '/attachments/thumbs/<id>_<name>'`
- 持久化模型不再保存外部真实路径作为长期字段

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/services/attachments/chat_attachment_storage_service_test.dart
fvm flutter test test/services/attachments/chat_attachment_payload_codec_test.dart
```

Expected: FAIL，因为当前保存的是宿主真实路径。

- [ ] **Step 3: 改造 attachment storage / payload codec / UI 读取**

要求：

- 导入瞬间可以读取外部真实路径
- 导入完成后模型只保存 `/attachments/...` agent 路径
- 需要展示图片的 UI 先通过统一访问层把 agent 路径解析回 host 路径再构造 `File(...)`
- provider payload 仍能生成上游要求的数据，不依赖长期保存的宿主路径字符串

- [ ] **Step 4: 运行 attachment 测试**

Run:

```bash
fvm flutter test test/services/attachments/chat_attachment_storage_service_test.dart
fvm flutter test test/services/attachments/chat_attachment_payload_codec_test.dart
```

Expected: PASS。

## Task 7: 清理调试页与 tool context 中的真实路径外泄

**Files:**
- Modify: `lib/pages/webview_debug_page.dart`
- Modify: `lib/services/tool_result_context_projector.dart`
- Test: `test/services/tool_result_context_projector_test.dart`（如不存在则新增）
- Test: `test/widgets/pages/webview_debug_page_test.dart`（如不存在则新增）

- [ ] **Step 1: 写失败测试，验证投影文本只包含 agent 路径**

断言：

- `Read/Write/Edit/create_artifact/skill` 投影文本中的 path 为 `/...`
- 文本不包含平台宿主真实根目录片段

- [ ] **Step 2: 写失败测试，验证调试页不直接扫描真实 artifact root**

断言调试页通过注入的 service 或访问层列出 `/artifacts/...`，而不是自己 `Directory(...).list()`

- [ ] **Step 3: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/services/tool_result_context_projector_test.dart
fvm flutter test test/widgets/pages/webview_debug_page_test.dart
```

Expected: FAIL。

- [ ] **Step 4: 改造投影与调试页**

要求：

- `ToolResultContextProjector` 统一消费 agent 路径
- `WebviewDebugPage` 通过统一访问层或 artifact service 枚举与读取 `/artifacts/...`
- 不再直接拼平台真实目录

- [ ] **Step 5: 运行相关测试**

Run:

```bash
fvm flutter test test/services/tool_result_context_projector_test.dart
fvm flutter test test/widgets/pages/webview_debug_page_test.dart
```

Expected: PASS。

## Task 8: 文档与总体验证

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `docs/architecture/project-architecture-overview.md`（如设计已影响架构说明）

- [ ] **Step 1: 更新 README**

补充：

- agent 文件系统根 `/`
- 平台私有 app sandbox 下的统一 `agent` root
- 绝对路径与相对路径语义

- [ ] **Step 2: 更新 AGENTS.md**

补充规则：

- agent 可见路径统一为 `/...` 或相对路径
- 禁止在 tool result / skill context / planner context 暴露宿主真实路径
- attachments 导入后只能持有内部 agent 路径

- [ ] **Step 3: 运行聚焦测试集**

Run:

```bash
fvm flutter test test/services/file_tools
fvm flutter test test/tools/handlers/read_tool_handler_test.dart
fvm flutter test test/tools/handlers/write_tool_handler_test.dart
fvm flutter test test/tools/handlers/edit_tool_handler_test.dart
fvm flutter test test/tools/handlers/ls_tool_handler_test.dart
fvm flutter test test/tools/handlers/glob_tool_handler_test.dart
fvm flutter test test/tools/handlers/grep_tool_handler_test.dart
fvm flutter test test/services/session_context_service_skills_test.dart
fvm flutter test test/services/attachments
```

Expected: PASS。

- [ ] **Step 4: 运行静态检查**

Run:

```bash
fvm flutter analyze
```

Expected: PASS，或只剩已知与本改造无关的预存问题；如果有预存噪音，需要在交付说明中明确列出。

- [ ] **Step 5: 提交**

```bash
git add README.md AGENTS.md docs/superpowers/specs/2026-06-02-agent-file-access-sandbox-unification-design.md docs/superpowers/plans/2026-06-02-agent-file-access-sandbox-unification-implementation-plan.md lib test
git commit -m "refactor: unify agent file access sandbox"
```
