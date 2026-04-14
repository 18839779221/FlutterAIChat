# 沙箱文件工具实施计划

> **给执行型 agent 的要求：** 必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans` 按任务逐项执行本计划。任务步骤使用 checkbox（`- [ ]`）语法跟踪。

**目标：** 为 App 私有目录增加一套贴近 Claude Code 习惯的沙箱文件工具，覆盖发现、读取、写入、编辑等主路径，同时保留强安全边界，并为 notebook/记忆文件等后续能力预留扩展空间。

**架构：** 保留现有 Flutter 侧 tool runtime、planner 和 handler 架构，在 App 私有目录下新增一个专用 sandbox 文件层。对外暴露一组中等粒度、与 Claude Code 命名接近的工具：`Read`、`Write`、`Edit`、`Glob`、`Grep`、`LS`。同时增加会话级文件版本守卫、结构化工具结果、按意图裁剪的 planner 暴露策略，并预留 `NotebookRead` / `NotebookEdit`、二进制文件读取和写后分析钩子。

**技术栈：** Flutter 3.29.2（优先使用 `fvm flutter`）、Dart、flutter_test、path/path_provider、现有 tool handler/runtime registry 架构、App 私有存储。

---

## 范围与阶段划分

### 当前执行边界（本轮）

- 先只实现文件工具本体、基础服务和独立测试
- 本轮不接入 `main.dart`、默认 tool runtime registry、planner 暴露策略或聊天主流程
- 等当前工作区里的多 tool call 改造稳定后，再做主流程组装
- 因此本轮优先落实：
  - 沙箱基础设施
  - 发现类工具
  - `Read`
  - 对应的独立 handler/service 测试
  - `Write` / `Edit` 的接线和主流程集成延后

### v1 范围

- `Read`
- `Write`
- `Edit`
- `Glob`
- `Grep`
- `LS`
- App 私有目录下的 sandbox root 管理
- 会话级文件版本守卫，用于写入安全校验
- planner 暴露与读写确认策略
- trace、测试、README / AGENTS 文档更新

### v1.5 预留在设计中，但延后实现

- `NotebookRead`
- `NotebookEdit`
- 图片 / PDF / 二进制读取分支
- 写后分析器钩子
  - Claude Code 使用 LSP；本项目 v1 只预留接口，不实现完整 LSP 流程
- `MultiEdit`

### 本计划明确不做

- 删除 / 移动 / 重命名工具
- 访问 sandbox root 之外的路径
- shell / code execution
- 任意用户目录上的 IDE 级编辑能力
- 如果浏览器存储语义拖慢交付，v1 不追求 web 平台完全对齐

## 与 Claude Code 对齐的设计原则

- 工具名尽量贴近 Claude Code：`Read`、`Write`、`Edit`、`Glob`、`Grep`、`LS`
- 只读类工具与写类工具明确分开，权限模型保持简单
- `Read` 不只是“拿到文件内容”，它还要建立“当前会话已经见过这个文件状态”的前置条件，为后续 `Write` / `Edit` 服务
- `Edit` 使用 `old_string -> new_string` 的精确替换语义，不做自由 patch
- `Write` 是整文件创建 / 覆盖，不做增量写
- `Glob` 与 `Grep` 是发现工具，用于减少盲读和盲改
- notebook 工具保留在整体计划里，避免这轮调研丢失，但不阻塞安全文本文件主路径

## 文件地图

### 核心沙箱基础设施

- 新增：`lib/services/file_tools/file_tool_root_service.dart`
- 新增：`lib/services/file_tools/file_tool_path_policy.dart`
- 新增：`lib/services/file_tools/file_tool_session_guard.dart`
- 新增：`lib/services/file_tools/file_tool_read_formatter.dart`
- 新增：`lib/services/file_tools/file_tool_budget_service.dart`
- 新增：`lib/services/file_tools/file_tool_discovery_service.dart`
- 新增：`lib/services/file_tools/file_tool_write_service.dart`
- 新增：`lib/services/file_tools/file_tool_post_write_hook.dart`
- 新增：`lib/services/file_tools/file_tool_models.dart`

### Tool Host Adapter 与 Runtime Wiring

- 修改：`lib/tools/adapters/tool_host_adapters.dart`
- 修改：`lib/services/tool_executor.dart`
- 新增：`lib/services/default_file_tool_adapters.dart`
- 修改：`lib/tools/default_tool_runtime_registry.dart`

### Tool Handlers

- 新增：`lib/tools/handlers/read_tool_handler.dart`
- 新增：`lib/tools/handlers/write_tool_handler.dart`
- 新增：`lib/tools/handlers/edit_tool_handler.dart`
- 新增：`lib/tools/handlers/glob_tool_handler.dart`
- 新增：`lib/tools/handlers/grep_tool_handler.dart`
- 新增：`lib/tools/handlers/ls_tool_handler.dart`
- 预留后续：`lib/tools/handlers/notebook_read_tool_handler.dart`
- 预留后续：`lib/tools/handlers/notebook_edit_tool_handler.dart`

### Planner / Policy / Metadata

- 修改：`lib/models/tool/tool_definition.dart`
- 修改：`lib/services/planner_tool_exposure_service.dart`
- 修改：`lib/services/planner_prompt_builder.dart`
- 修改：`lib/services/agent_planner_service.dart`
- 修改：`lib/services/tool_policy_service.dart`

### App 启动与依赖

- 修改：`lib/main.dart`
- 修改：`pubspec.yaml`

### 测试

- 新增：`test/services/file_tools/file_tool_path_policy_test.dart`
- 新增：`test/services/file_tools/file_tool_session_guard_test.dart`
- 新增：`test/services/file_tools/file_tool_read_formatter_test.dart`
- 新增：`test/services/file_tools/file_tool_discovery_service_test.dart`
- 新增：`test/services/file_tools/file_tool_write_service_test.dart`
- 新增：`test/tools/handlers/read_tool_handler_test.dart`
- 新增：`test/tools/handlers/write_tool_handler_test.dart`
- 新增：`test/tools/handlers/edit_tool_handler_test.dart`
- 新增：`test/tools/handlers/glob_tool_handler_test.dart`
- 新增：`test/tools/handlers/grep_tool_handler_test.dart`
- 新增：`test/tools/handlers/ls_tool_handler_test.dart`
- 修改：`test/tools/core/tool_runtime_registry_test.dart`
- 修改：`test/services/planner_tool_exposure_service_test.dart`
- 修改：`test/providers/chat_controller_tool_flow_test.dart`

### 文档

- 修改：`README.md`
- 修改：`AGENTS.md`
- 修改：`docs/feature_todo.md`

## Sandbox 目录布局

在 App 私有存储下创建专用子树：

- `agent/`
- `agent/memories/`
- `agent/artifacts/`
- `agent/tmp/`

规则：

- 所有工具路径都统一归一化到这个 sandbox root 下
- 为了贴近 Claude Code，模型侧字段仍使用 `file_path`，但 runtime 会把它视为 sandbox 相对路径
- 拒绝绝对路径、`..`、符号链接逃逸、空路径段，以及写入未放行目录
- `tmp/` 可以允许更宽松的覆盖策略
- `memories/` 与 `artifacts/` 的 summary 和 trace 应更清晰，因为它们更接近用户可见资产

## 工具契约

### `Read`

输入：

- `file_path` 必填
- `offset` 可选
- `limit` 可选

行为：

- 从 sandbox 中读取文本文件，支持 `offset` / `limit` 分页
- 返回带行号的内容，为后续 `Edit` 提供稳定坐标系
- 执行输出预算控制并标记截断
- 成功后在 session guard 中登记当前文件版本
- 预留未来的图片 / PDF / 二进制读取分支，但 v1 可以先对非文本文件返回结构化拒绝

### `Write`

输入：

- `file_path` 必填
- `content` 必填

行为：

- 创建新文件，或用完整内容覆盖现有文件
- 如果文件已存在，要求当前会话里已经成功 `Read` 过，并且文件版本未失效
- 返回旧内容与新内容的紧凑 diff 摘要
- 成功后刷新 session guard 中的文件版本
- 调用写后钩子接口，即使 v1 默认实现为空

### `Edit`

输入：

- `file_path` 必填
- `old_string` 必填
- `new_string` 必填
- `replace_all` 可选

行为：

- 要求文件已在当前会话中成功 `Read`
- 执行精确字符串替换
- `old_string` 不存在时失败
- `old_string` 匹配多个位置且未开启 `replace_all` 时失败
- 返回替换次数、目标文件路径、更新后的版本信息
- 成功后走与 `Write` 相同的写后钩子

### `Glob`

输入：

- `pattern` 必填
- `path` 可选

行为：

- 在 sandbox 相对路径空间中执行 glob 匹配
- 只返回命中的相对路径
- 不读取文件内容

### `Grep`

输入：

- `pattern` 必填
- `path` 可选
- `glob` 可选
- `output_mode` 可选
- `head_limit` 可选
- `multiline` 可选
- `case_insensitive` 可选
- `line_numbers` 可选

行为：

- 在 sandbox 文本文件内容中搜索
- v1 支持保守模式：
  - `files_with_matches`
  - `content`
  - `count`
- 返回结构化命中，而不是原始 shell 输出
- 对二进制文件或过大输出执行跳过与预算限制

### `LS`

输入：

- `path` 必填
- `ignore` 可选

行为：

- 列出 sandbox 相对目录下的直接子项
- 返回条目名称、类型，以及可选的大小信息
- 默认不递归

### 未来 `NotebookRead` / `NotebookEdit`

在设计里保留 Claude Code 风格的 notebook 工具命名，但只有当 App 明确支持导入和管理 notebook 资产后再实现。不要用原始 JSON `Read` / `Edit` 去冒充 notebook 语义。

## 权限与风险模型

### 只读类工具

- `Read`
- `Glob`
- `Grep`
- `LS`

策略：

- 默认不需要确认
- 只在当前平台启用了 sandbox 文件能力时暴露
- trace 中记录路径、结果数量、截断 / 跳过原因

### 写类工具

- `Write`
- `Edit`
- 未来 `NotebookEdit`

策略：

- 默认都需要确认
- 只有在用户已经见过这类工具和路径形态后，才允许考虑“信任此工具”
- 在 summary 上明确区分：
  - `Write`：整文件创建 / 覆盖
  - `Edit`：精确替换

## 会话守卫设计

实现一个受 Claude Code “写前必读”启发的会话级守卫：

- `Read` 成功后记录：
  - 归一化后的 `file_path`
  - 最近一次看到的 modified time
  - 可选的 hash / length 快照
  - 当前会话时间戳
- `Write` / `Edit` 执行前断言：
  - 如果文件已存在，则当前会话必须先读过
  - 当前文件版本仍和上次读取时一致
- 写成功后刷新已见状态

这是整份计划里价值最高的安全能力之一。它应该先于广泛开放写类工具交付。

## Planner 暴露策略

按意图暴露这些工具：

- 发现类意图：
  - `Glob`
  - `Grep`
  - `LS`
- 文件查看意图：
  - `Read`
- 显式修改意图：
  - `Write`
  - `Edit`

规则：

- 对模糊的“看下文件”请求，不默认暴露写类工具
- 当路径不明确时，优先走 `Glob/Grep/LS -> Read -> Edit/Write`
- 在模型侧描述里明确告诉 planner：
  - `Read` 与 `Grep` 分别适用于什么场景
  - 修改现有文件优先使用 `Edit`
  - 只有新建文件或整文件重写时才使用 `Write`

## Trace 与结果设计

对每次文件工具执行至少记录：

- 归一化后的 sandbox 路径
- 逻辑工具类别
- 结果数量 / 命中数 / 替换数
- 截断标记
- 确认决策
- 如果因为文件过期或未读而被拒绝，记录拒绝原因

工具结果要足够结构化，便于 planner 复用：

- `Read` 返回文件元信息和行窗口信息
- `Grep` 返回命中元数据，而不只是摘要文本
- `Write` / `Edit` 返回版本刷新信息和紧凑变更摘要

## 任务 1：搭建沙箱基础设施

**文件：**
- 新增：`lib/services/file_tools/file_tool_root_service.dart`
- 新增：`lib/services/file_tools/file_tool_path_policy.dart`
- 新增：`lib/services/file_tools/file_tool_session_guard.dart`
- 新增：`lib/services/file_tools/file_tool_models.dart`
- 修改：`lib/tools/adapters/tool_host_adapters.dart`
- 修改：`lib/services/tool_executor.dart`
- 修改：`lib/main.dart`
- 修改：`pubspec.yaml`
- 测试：`test/services/file_tools/file_tool_path_policy_test.dart`
- 测试：`test/services/file_tools/file_tool_session_guard_test.dart`

- [ ] **步骤 1：先写路径策略失败测试**

```dart
test('rejects parent directory traversal', () {
  final result = policy.normalizeSandboxPath('../secrets.txt');
  expect(result.isValid, isFalse);
});

test('accepts sandbox-relative memory path', () {
  final result = policy.normalizeSandboxPath('memories/user/profile.md');
  expect(result.relativePath, 'memories/user/profile.md');
});
```

- [ ] **步骤 2：先写 session guard 失败测试**

```dart
test('existing file cannot be edited before read', () async {
  expect(
    () => guard.assertWritable(filePath: 'memories/a.md', currentVersion: version),
    throwsA(isA<FileToolGuardException>()),
  );
});
```

- [ ] **步骤 3：运行聚焦测试，确认先失败**

运行：`fvm flutter test test/services/file_tools/file_tool_path_policy_test.dart test/services/file_tools/file_tool_session_guard_test.dart`

预期：FAIL，因为沙箱相关服务尚未存在。

- [ ] **步骤 4：实现 root/path/guard 模型与 adapter 契约**

新增：

- 基于 App 私有存储的 sandbox root 解析
- 路径归一化与校验
- 会话级文件版本登记表
- 给读写工具共享的文件元信息模型

- [ ] **步骤 5：通过 runtime 启动流程注入 host adapter**

把文件工具 adapter bundle 填入 `ToolHostAdapters`，在 `main.dart` 中初始化，并通过 `ToolExecutionContext` 透传给文件 handler。

- [ ] **步骤 6：重跑聚焦测试**

运行：`fvm flutter test test/services/file_tools/file_tool_path_policy_test.dart test/services/file_tools/file_tool_session_guard_test.dart`

预期：PASS。

- [ ] **步骤 7：提交**

```bash
git add pubspec.yaml lib/services/file_tools/file_tool_root_service.dart lib/services/file_tools/file_tool_path_policy.dart lib/services/file_tools/file_tool_session_guard.dart lib/services/file_tools/file_tool_models.dart lib/tools/adapters/tool_host_adapters.dart lib/services/tool_executor.dart lib/main.dart test/services/file_tools/file_tool_path_policy_test.dart test/services/file_tools/file_tool_session_guard_test.dart
git commit -m "feat: add sandbox file tool foundation"
```

## 任务 2：实现发现类工具（`LS`、`Glob`、`Grep`）

**文件：**
- 新增：`lib/services/file_tools/file_tool_discovery_service.dart`
- 新增：`lib/tools/handlers/ls_tool_handler.dart`
- 新增：`lib/tools/handlers/glob_tool_handler.dart`
- 新增：`lib/tools/handlers/grep_tool_handler.dart`
- 修改：`lib/tools/default_tool_runtime_registry.dart`
- 修改：`test/tools/core/tool_runtime_registry_test.dart`
- 测试：`test/services/file_tools/file_tool_discovery_service_test.dart`
- 测试：`test/tools/handlers/ls_tool_handler_test.dart`
- 测试：`test/tools/handlers/glob_tool_handler_test.dart`
- 测试：`test/tools/handlers/grep_tool_handler_test.dart`

- [ ] **步骤 1：先写发现类失败测试**

```dart
test('glob returns sandbox-relative matches only', () async {
  final result = await service.glob(pattern: '**/*.md', path: 'memories');
  expect(result, ['memories/user.md']);
});
```

- [ ] **步骤 2：先写 handler 元数据失败测试**

```dart
expect(globHandler.definition.requiresConfirmation, isFalse);
expect(grepHandler.definition.category, ToolCategory.retrieval);
```

- [ ] **步骤 3：运行聚焦测试，确认失败**

运行：`fvm flutter test test/services/file_tools/file_tool_discovery_service_test.dart test/tools/handlers/ls_tool_handler_test.dart test/tools/handlers/glob_tool_handler_test.dart test/tools/handlers/grep_tool_handler_test.dart test/tools/core/tool_runtime_registry_test.dart`

预期：FAIL，因为服务与 handler 尚未注册。

- [ ] **步骤 4：实现 discovery service 与三个 handler**

支持：

- 非递归目录列举
- glob 路径搜索
- 有输出预算控制的正则内容搜索

- [ ] **步骤 5：注册工具并补齐 planner 描述**

工具名必须严格使用：

- `LS`
- `Glob`
- `Grep`

- [ ] **步骤 6：重跑聚焦测试**

运行：`fvm flutter test test/services/file_tools/file_tool_discovery_service_test.dart test/tools/handlers/ls_tool_handler_test.dart test/tools/handlers/glob_tool_handler_test.dart test/tools/handlers/grep_tool_handler_test.dart test/tools/core/tool_runtime_registry_test.dart`

预期：PASS。

- [ ] **步骤 7：提交**

```bash
git add lib/services/file_tools/file_tool_discovery_service.dart lib/tools/handlers/ls_tool_handler.dart lib/tools/handlers/glob_tool_handler.dart lib/tools/handlers/grep_tool_handler.dart lib/tools/default_tool_runtime_registry.dart test/services/file_tools/file_tool_discovery_service_test.dart test/tools/handlers/ls_tool_handler_test.dart test/tools/handlers/glob_tool_handler_test.dart test/tools/handlers/grep_tool_handler_test.dart test/tools/core/tool_runtime_registry_test.dart
git commit -m "feat: add sandbox file discovery tools"
```

## 任务 3：实现 `Read`

**文件：**
- 新增：`lib/services/file_tools/file_tool_read_formatter.dart`
- 新增：`lib/services/file_tools/file_tool_budget_service.dart`
- 新增：`lib/tools/handlers/read_tool_handler.dart`
- 修改：`lib/tools/default_tool_runtime_registry.dart`
- 测试：`test/services/file_tools/file_tool_read_formatter_test.dart`
- 测试：`test/tools/handlers/read_tool_handler_test.dart`

- [ ] **步骤 1：先写 formatter 失败测试**

```dart
test('read output includes line numbers and offset window metadata', () {
  final result = formatter.format(
    filePath: 'tmp/demo.txt',
    lines: ['a', 'b'],
    startLine: 3,
  );
  expect(result.content, contains('     3\ta'));
});
```

- [ ] **步骤 2：先写 handler 关于分页与 guard 登记的失败测试**

```dart
test('read registers file version for later writes', () async {
  final result = await handler.execute(context);
  expect(result.data['fileVersion'], isNotNull);
  expect(guard.hasSeen('memories/a.md'), isTrue);
});
```

- [ ] **步骤 3：运行聚焦测试，确认失败**

运行：`fvm flutter test test/services/file_tools/file_tool_read_formatter_test.dart test/tools/handlers/read_tool_handler_test.dart`

预期：FAIL，因为 `Read` 及其 formatter 尚未实现。

- [ ] **步骤 4：实现 `Read` 语义**

支持：

- sandbox 相对 `file_path`
- 可选 `offset` 与 `limit`
- 带行号格式化
- 单行与总输出预算控制
- 带行窗口元信息的结构化结果
- 成功后调用 session guard 的 `markRead()`

- [ ] **步骤 5：注册 `Read` 并设置低风险 metadata**

模型侧描述要明确：当路径已知或已通过发现类工具定位到目标文件后，应优先用 `Read` 查看内容，再进入 `Edit` / `Write`。

- [ ] **步骤 6：重跑聚焦测试**

运行：`fvm flutter test test/services/file_tools/file_tool_read_formatter_test.dart test/tools/handlers/read_tool_handler_test.dart`

预期：PASS。

- [ ] **步骤 7：提交**

```bash
git add lib/services/file_tools/file_tool_read_formatter.dart lib/services/file_tools/file_tool_budget_service.dart lib/tools/handlers/read_tool_handler.dart lib/tools/default_tool_runtime_registry.dart test/services/file_tools/file_tool_read_formatter_test.dart test/tools/handlers/read_tool_handler_test.dart
git commit -m "feat: add sandbox read tool"
```

## 任务 4：实现 `Write` 与 `Edit`

**文件：**
- 新增：`lib/services/file_tools/file_tool_write_service.dart`
- 新增：`lib/services/file_tools/file_tool_post_write_hook.dart`
- 新增：`lib/tools/handlers/write_tool_handler.dart`
- 新增：`lib/tools/handlers/edit_tool_handler.dart`
- 修改：`lib/tools/default_tool_runtime_registry.dart`
- 测试：`test/services/file_tools/file_tool_write_service_test.dart`
- 测试：`test/tools/handlers/write_tool_handler_test.dart`
- 测试：`test/tools/handlers/edit_tool_handler_test.dart`

- [ ] **步骤 1：先写写入守卫失败测试**

```dart
test('write rejects overwriting an unread existing file', () async {
  final result = await handler.execute(context);
  expect(result.status, ToolExecutionStatus.failure);
  expect(result.errorMessage, 'stale_or_unread_file');
});
```

- [ ] **步骤 2：先写 Edit 唯一性失败测试**

```dart
test('edit fails when old_string matches multiple locations without replace_all', () async {
  final result = await handler.execute(context);
  expect(result.status, ToolExecutionStatus.failure);
  expect(result.errorMessage, 'ambiguous_old_string');
});
```

- [ ] **步骤 3：运行聚焦测试，确认失败**

运行：`fvm flutter test test/services/file_tools/file_tool_write_service_test.dart test/tools/handlers/write_tool_handler_test.dart test/tools/handlers/edit_tool_handler_test.dart`

预期：FAIL，因为 `Write` 与 `Edit` 尚未实现。

- [ ] **步骤 4：实现整文件写入语义**

支持：

- 新文件创建路径
- 现有文件覆盖路径，且需要 session guard 断言
- 在 tool result 中返回紧凑 diff 摘要
- 调用写后钩子

- [ ] **步骤 5：实现精确字符串替换语义**

支持：

- `old_string`
- `new_string`
- `replace_all`
- 唯一匹配失败处理
- 成功后刷新版本信息

- [ ] **步骤 6：注册 `Write` 与 `Edit`，并设为需要确认**

summary 要明确区分：

- 整文件覆盖
- 精确片段替换

- [ ] **步骤 7：重跑聚焦测试**

运行：`fvm flutter test test/services/file_tools/file_tool_write_service_test.dart test/tools/handlers/write_tool_handler_test.dart test/tools/handlers/edit_tool_handler_test.dart`

预期：PASS。

- [ ] **步骤 8：提交**

```bash
git add lib/services/file_tools/file_tool_write_service.dart lib/services/file_tools/file_tool_post_write_hook.dart lib/tools/handlers/write_tool_handler.dart lib/tools/handlers/edit_tool_handler.dart lib/tools/default_tool_runtime_registry.dart test/services/file_tools/file_tool_write_service_test.dart test/tools/handlers/write_tool_handler_test.dart test/tools/handlers/edit_tool_handler_test.dart
git commit -m "feat: add sandbox write and edit tools"
```

## 任务 5：Planner 暴露、策略与 UI 流程

**文件：**
- 修改：`lib/models/tool/tool_definition.dart`
- 修改：`lib/services/planner_tool_exposure_service.dart`
- 修改：`lib/services/planner_prompt_builder.dart`
- 修改：`lib/services/agent_planner_service.dart`
- 修改：`lib/services/tool_policy_service.dart`
- 修改：`test/services/planner_tool_exposure_service_test.dart`
- 修改：`test/providers/chat_controller_tool_flow_test.dart`
- 修改：`test/tools/core/tool_runtime_registry_test.dart`

- [ ] **步骤 1：先写 planner 暴露失败测试**

```dart
test('file-inspection intent exposes discovery tools and Read but hides Write/Edit', () {
  final visible = service.selectVisibleTools(
    userInput: '帮我看下 memory 目录里有哪些文件',
    allTools: tools,
  );
  expect(visible.map((tool) => tool.name), containsAll(['LS', 'Glob', 'Read']));
  expect(visible.map((tool) => tool.name), isNot(contains('Write')));
});
```

- [ ] **步骤 2：先写确认流程失败测试**

```dart
test('edit tool requires confirmation and preserves tool summary in chat flow', () async {
  // assert awaitingConfirmation state and tool invocation card content
});
```

- [ ] **步骤 3：运行聚焦测试，确认失败**

运行：`fvm flutter test test/services/planner_tool_exposure_service_test.dart test/providers/chat_controller_tool_flow_test.dart test/tools/core/tool_runtime_registry_test.dart`

预期：FAIL，因为文件工具的暴露与确认策略尚未接线。

- [ ] **步骤 4：实现文件意图暴露规则**

示例：

- “找某个文件 / 看目录” -> `LS`、`Glob`
- “搜某个关键字” -> `Grep`
- “打开文件 / 看内容” -> `Read`
- “修改 / 创建 / 覆盖文件” -> `Edit`、`Write`

- [ ] **步骤 5：更新 prompt 描述与 policy summary**

planner prompt 要明确教育模型：

- 路径不确定时先做 discovery
- 修改已有文件优先用 `Edit`
- 新建文件或整文件重写才用 `Write`

- [ ] **步骤 6：重跑聚焦测试**

运行：`fvm flutter test test/services/planner_tool_exposure_service_test.dart test/providers/chat_controller_tool_flow_test.dart test/tools/core/tool_runtime_registry_test.dart`

预期：PASS。

- [ ] **步骤 7：提交**

```bash
git add lib/models/tool/tool_definition.dart lib/services/planner_tool_exposure_service.dart lib/services/planner_prompt_builder.dart lib/services/agent_planner_service.dart lib/services/tool_policy_service.dart test/services/planner_tool_exposure_service_test.dart test/providers/chat_controller_tool_flow_test.dart test/tools/core/tool_runtime_registry_test.dart
git commit -m "feat: wire planner exposure for sandbox file tools"
```

## 任务 6：文档、Trace 与 backlog 保留

**文件：**
- 修改：`README.md`
- 修改：`AGENTS.md`
- 修改：`docs/feature_todo.md`

- [ ] **步骤 1：更新 README 能力与架构说明**

文档要补充：

- sandbox root 概念
- 文件工具家族
- 读写确认分层
- 当前 v1 范围与延后 notebook 支持

- [ ] **步骤 2：更新 AGENTS 实现约束**

补充：

- 文件工具只能操作 sandbox
- 写前必读约束
- `Read` 的分页要求
- 未来 notebook 工具说明

- [ ] **步骤 3：把延后项保留到 backlog**

补充这些 backlog：

- `NotebookRead`
- `NotebookEdit`
- 图片 / PDF / 二进制读取分支
- 写后分析器
- 可选 `MultiEdit`

- [ ] **步骤 4：跑回归验证**

运行：`fvm flutter test`

预期：PASS。

- [ ] **步骤 5：跑静态分析**

运行：`fvm flutter analyze`

预期：没有新增 analyzer error。

- [ ] **步骤 6：提交**

```bash
git add README.md AGENTS.md docs/feature_todo.md
git commit -m "docs: document sandbox file tool roadmap"
```

## 当前最高优先级切片

优先按这个顺序实现：

1. 任务 1：沙箱基础设施
2. 任务 2：发现类工具（`LS`、`Glob`、`Grep`）
3. 任务 3：`Read`

原因：

- 先建立安全探索路径
- 先把 session/version guard 打起来，后续写入才可信
- 先形成 Claude Code 风格的主工作流：discover -> inspect -> modify
- 即使 `Write` / `Edit` 还没上线，也能立即支撑记忆文件和产物文件的发现与读取

只有在这些完成并稳定后，才应广泛暴露 `Write` 与 `Edit`。

## 实施过程中需要澄清的开放问题

- web 平台在 v1 是否直接关闭文件工具，还是用 IndexedDB / OPFS 做同一套契约？
- 模型侧 `file_path` 是否需要包含 `agent/` 前缀，还是默认把 `agent/` 视为隐式根目录？
- `tmp/` 下的新生成临时文件，是否可以跳过严格的“已读后才能写”规则？
- 是否需要一个用户可见的设置项，用于控制 sandbox 文件工具是否启用？

## 推荐执行顺序

- 第 1 阶段：任务 1 + 任务 2 + 任务 3
- 第 2 阶段：任务 4
- 第 3 阶段：任务 5 + 任务 6
- 更后续的第 4 阶段：notebook 工具与写后分析器钩子
