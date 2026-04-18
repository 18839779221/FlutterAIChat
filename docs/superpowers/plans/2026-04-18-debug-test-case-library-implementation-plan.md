# Debug 测试案例库实现计划

> **给执行型 agent：** 必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans` 按任务逐步执行本计划。步骤使用复选框 `- [ ]` 进行跟踪。

**目标：** 新增一个基于 JSON 的 Debug 测试案例库，同时驱动 Debug `Cases` 选择器和空状态精选案例。

**架构：** 引入一个轻量的 debug case 模型和 asset loader，通过 Riverpod 暴露成单一数据源，再由聊天页与空状态共同消费。Debug 模式下保持最小 UI，同时为未来自动化元数据扩展预留空间，但本阶段不引入断言。

**技术栈：** Flutter、Riverpod、基于 asset 的 JSON 读取、Widget 测试

---

### 任务 1：新增 JSON 案例数据源与读取层

**涉及文件：**
- 新建：`assets/debug/test_cases.json`
- 新建：`lib/models/debug/debug_test_case.dart`
- 新建：`lib/services/debug_test_case_loader.dart`
- 修改：`pubspec.yaml`
- 测试：`test/services/debug_test_case_loader_test.dart`

- [ ] **步骤 1：先写失败测试**

创建 `test/services/debug_test_case_loader_test.dart`，验证 JSON 解析、`enabled` 过滤与 featured 案例提取行为。

- [ ] **步骤 2：运行测试并确认失败**

运行：`fvm flutter test test/services/debug_test_case_loader_test.dart`
预期：失败，因为模型和 loader 还不存在。

- [ ] **步骤 3：补充 asset 文件和模型**

创建初始案例清单 JSON，并新增 `DebugTestCase` 模型，对外部消费字段补充必要注释。

- [ ] **步骤 4：实现 loader**

新增一个聚焦的 loader 服务，从 `AssetBundle` 读取 JSON、解析根对象，并在过滤禁用条目后暴露 `allCases` 与 featured 子集。

- [ ] **步骤 5：重新运行 loader 测试**

运行：`fvm flutter test test/services/debug_test_case_loader_test.dart`
预期：通过。

- [ ] **步骤 6：提交**

```bash
git add assets/debug/test_cases.json lib/models/debug/debug_test_case.dart lib/services/debug_test_case_loader.dart pubspec.yaml test/services/debug_test_case_loader_test.dart
git commit -m "feat: add debug test case asset loader"
```

### 任务 2：将案例库接入 providers 与空状态

**涉及文件：**
- 修改：`lib/widgets/chat_empty_state.dart`
- 修改：`lib/providers/chat_ui_providers.dart`
- 修改：`lib/providers/chat_providers.dart`
- 测试：`test/widgets/chat_empty_state_test.dart`

- [ ] **步骤 1：先写空状态失败测试**

更新 `test/widgets/chat_empty_state_test.dart`，断言精选建议来自注入的案例数据，而不是旧的硬编码常量。

- [ ] **步骤 2：运行测试并确认失败**

运行：`fvm flutter test test/widgets/chat_empty_state_test.dart`
预期：失败，因为 `defaultChatEmptySuggestions` 仍然是硬编码。

- [ ] **步骤 3：补充 debug case 的 provider 接线**

通过现有 Riverpod 组合边界暴露 loader 和衍生出的 featured case provider。

- [ ] **步骤 4：更新空状态**

让 `ChatEmptyState` 消费注入的 suggestions，移除硬编码案例常量，同时保持现有视觉表现不变。

- [ ] **步骤 5：重新运行空状态测试**

运行：`fvm flutter test test/widgets/chat_empty_state_test.dart`
预期：通过。

- [ ] **步骤 6：提交**

```bash
git add lib/widgets/chat_empty_state.dart lib/providers/chat_ui_providers.dart lib/providers/chat_providers.dart test/widgets/chat_empty_state_test.dart
git commit -m "refactor: source empty state prompts from debug case library"
```

### 任务 3：为聊天页新增 Debug Cases 选择器

**涉及文件：**
- 新建：`lib/widgets/debug/debug_test_case_sheet.dart`
- 修改：`lib/pages/chat_page.dart`
- 修改：`lib/widgets/chat_input.dart`
- 测试：`test/pages/chat_page_test.dart`

- [ ] **步骤 1：先写失败的 Widget 测试**

为聊天页新增一个测试：在 Debug 模式下打开 `Cases` 选择器，点击某个案例，并验证聊天输入框被正确填充。

- [ ] **步骤 2：运行测试并确认失败**

运行：`fvm flutter test test/pages/chat_page_test.dart --plain-name "debug cases picker populates input"`
预期：失败，因为选择器还不存在。

- [ ] **步骤 3：实现选择器 UI**

新增一个极简底部面板 Widget，展示启用中的 case 标题、摘要和 prompt 预览。

- [ ] **步骤 4：把选择器接到聊天页**

仅在 `kDebugMode` 下显示 `Cases` 入口，打开面板后将选中的 prompt 写入共享 `TextEditingController`，并恢复输入焦点。

- [ ] **步骤 5：确认 Widget 测试通过**

运行：`fvm flutter test test/pages/chat_page_test.dart --plain-name "debug cases picker populates input"`
预期：通过。

- [ ] **步骤 6：提交**

```bash
git add lib/widgets/debug/debug_test_case_sheet.dart lib/pages/chat_page.dart lib/widgets/chat_input.dart test/pages/chat_page_test.dart
git commit -m "feat: add debug test case picker"
```

### 任务 4：移除旧 Markdown 数据源并刷新文档

**涉及文件：**
- 删除：`docs/agent-loop-e2e-test-cases.md`
- 修改：`README.md`

- [ ] **步骤 1：删除旧 Markdown 案例文档**

删除旧文档，确保仓库不再保留两套主数据源。

- [ ] **步骤 2：更新 README**

说明新的 JSON Debug 案例库位置，以及 Debug 用户如何打开 `Cases` 入口。

- [ ] **步骤 3：验证文档引用一致性**

运行：`rg -n "agent-loop-e2e-test-cases|test_cases.json|Cases" README.md docs lib test`
预期：旧 Markdown 路径已移除或只作为历史提及；新 JSON 数据源有明确文档说明。

- [ ] **步骤 4：提交**

```bash
git add README.md docs/agent-loop-e2e-test-cases.md
git commit -m "docs: document json-backed debug test cases"
```

### 任务 5：最终验证

**涉及文件：**
- 修改：无

- [ ] **步骤 1：运行聚焦测试**

运行：

```bash
fvm flutter test test/services/debug_test_case_loader_test.dart
fvm flutter test test/widgets/chat_empty_state_test.dart
fvm flutter test test/pages/chat_page_test.dart --plain-name "debug cases picker populates input"
```

预期：通过。

- [ ] **步骤 2：必要时运行聚焦 analyze**

运行：`fvm flutter analyze lib/models/debug lib/services/debug_test_case_loader.dart lib/widgets/debug lib/pages/chat_page.dart lib/widgets/chat_empty_state.dart`
预期：本次修改涉及文件没有新增问题。

- [ ] **步骤 3：整理验证证据**

在宣称完成前，记录实际执行过的命令及其结果。
