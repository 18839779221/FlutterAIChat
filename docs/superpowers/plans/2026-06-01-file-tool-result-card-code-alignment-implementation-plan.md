# File Tool Result Card Code Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `Write/Edit` 结果卡与现有 Markdown 代码块共享统一的技术内容阅读表面，并为写入预览与编辑 diff 预览接入 `flutter_highlight` 语法高亮。

**Architecture:** 本计划保持改造边界在展示层：新增文件路径语言推断 helper、共享高亮内容组件和文件工具结果卡 surface，随后分别收敛 `Write` 与 `Edit` 结果卡。`Write` 使用完整代码高亮预览，`Edit` 保持行级 diff 背景与前缀，再对代码文本列做语言高亮；tool result payload、workflow/proposed 卡片和 Markdown 主渲染链都不改。

**Tech Stack:** Flutter 3.35.7、`flutter_highlight`、现有 `TechnicalContentSurface` / `AppThemeSpec` / `AppTypography`、Flutter widget tests、`fvm flutter test`。

---

## 文件结构

- Create: `lib/widgets/shared/file_highlight_language.dart`
  - 根据 `filePath` 推断 `flutter_highlight` language id。
- Create: `lib/widgets/shared/highlighted_code_content.dart`
  - 收拢 `HighlightView`、高亮主题、代码字体和包裹策略。
- Create: `lib/widgets/tool_renderers/file_tool_result_surface.dart`
  - 定义 `WRITE/EDIT` 结果卡共享 header 和主体容器。
- Modify: `lib/widgets/markdown/code_widget.dart`
  - 改为复用共享高亮内容组件。
- Modify: `lib/widgets/tool_renderers/write_tool_result_card.dart`
  - 切到新的文件工具结果卡 surface，并把写入预览改成高亮代码块。
- Modify: `lib/widgets/tool_renderers/file_change_preview.dart`
  - 将 diff 文本列改为基于文件类型的语法高亮。
- Modify: `lib/widgets/tool_renderers/edit_tool_result_card.dart`
  - 接入新的文件工具结果卡 surface，并向 diff 预览传递 language 信息。
- Modify: `test/widgets/tool_renderers/write_tool_cards_test.dart`
  - 覆盖新的 header、副信息和高亮预览。
- Modify: `test/widgets/tool_renderers/edit_tool_cards_test.dart`
  - 覆盖新的 header、副信息、diff 语义和高亮文本列。
- Create: `test/widgets/shared/file_highlight_language_test.dart`
  - 覆盖文件路径到 highlight language 的映射。

## Task 1: 定义文件路径语言推断 helper

**Files:**
- Create: `test/widgets/shared/file_highlight_language_test.dart`
- Create: `lib/widgets/shared/file_highlight_language.dart`

- [ ] **Step 1: 先写 language 映射失败测试**

```dart
test('maps common file extensions to flutter_highlight language ids', () {
  expect(fileHighlightLanguageForPath('lib/main.dart'), 'dart');
  expect(fileHighlightLanguageForPath('docs/plan.md'), 'markdown');
  expect(fileHighlightLanguageForPath('config/app.yaml'), 'yaml');
  expect(fileHighlightLanguageForPath('scripts/run.sh'), 'bash');
});
```

- [ ] **Step 2: 增加未知扩展名回退失败测试**

```dart
test('falls back to plaintext for unsupported or missing extensions', () {
  expect(fileHighlightLanguageForPath('README'), 'plaintext');
  expect(fileHighlightLanguageForPath('tmp/data.unknownext'), 'plaintext');
});
```

- [ ] **Step 3: 写最小 helper 实现**

实现：

- 暴露 `String fileHighlightLanguageForPath(String filePath)`
- 内部基于扩展名做小型映射表
- 未命中回退 `plaintext`

- [ ] **Step 4: 运行 helper 测试，确认转绿**

Run:

```bash
fvm flutter test test/widgets/shared/file_highlight_language_test.dart
```

Expected:

- PASS

## Task 2: 抽取共享高亮内容组件并让 Markdown code block 复用

**Files:**
- Modify: `test/widgets/chat_blocks/chat_blocks_test.dart`
- Create: `lib/widgets/shared/highlighted_code_content.dart`
- Modify: `lib/widgets/markdown/code_widget.dart`

- [ ] **Step 1: 在现有 Markdown code block 测试上补一条失败断言，锁定共享高亮组件接入**

示例：

```dart
expect(find.byType(HighlightedCodeContent), findsOneWidget);
```

将断言加到已有 `code blocks use shared technical content surface` 一类测试附近。

- [ ] **Step 2: 运行针对性测试，确认红灯**

Run:

```bash
fvm flutter test test/widgets/chat_blocks/chat_blocks_test.dart
```

Expected:

- FAIL
- `HighlightedCodeContent` 尚不存在

- [ ] **Step 3: 新建共享高亮内容组件**

要求：

- 封装 `HighlightView`
- 封装亮色/暗色主题切换
- 允许外部传入 `code`、`language`
- 默认使用现有代码字体和字号
- 支持自动换行和横向滚动两种模式

- [ ] **Step 4: 修改 `CodeBlockWidget` 复用该组件**

保持：

- `TechnicalContentSurface`
- 语言标签
- copy 按钮
- 自动换行开关

只把实际高亮渲染部分替换为 `HighlightedCodeContent`。

- [ ] **Step 5: 运行 Markdown code block 测试，确认转绿**

Run:

```bash
fvm flutter test test/widgets/chat_blocks/chat_blocks_test.dart
```

Expected:

- PASS

## Task 3: 收敛 `Write result card` 到共享文件工具结果卡 surface

**Files:**
- Modify: `test/widgets/tool_renderers/write_tool_cards_test.dart`
- Create: `lib/widgets/tool_renderers/file_tool_result_surface.dart`
- Modify: `lib/widgets/tool_renderers/write_tool_result_card.dart`

- [ ] **Step 1: 为 `Write` 结果卡补失败测试，锁定新 header 与高亮预览**

至少覆盖：

- `WRITE` 标签存在
- 文件路径继续存在
- `新建文件` 或 `覆盖文件` 文案继续存在
- 预览区使用 `HighlightedCodeContent`

```dart
expect(find.text('WRITE'), findsOneWidget);
expect(find.byType(HighlightedCodeContent), findsOneWidget);
```

- [ ] **Step 2: 运行 `Write` 结果卡测试，确认红灯**

Run:

```bash
fvm flutter test test/widgets/tool_renderers/write_tool_cards_test.dart
```

Expected:

- FAIL
- 结果卡尚未切换到新结构

- [ ] **Step 3: 新建文件工具结果卡 surface**

要求：

- 接收工具标签、路径、主副信息、摘要、主体内容 slot
- 视觉上与技术内容 surface 同家族
- 但保留明确的 `WRITE/EDIT` 身份

- [ ] **Step 4: 修改 `WriteToolResultCard` 使用新 surface**

要求：

- `newContentPreview` 非空时展示高亮代码预览
- 继续保留长度变化与摘要
- 继续保留截断提示
- 详情区行为保持不变

- [ ] **Step 5: 运行 `Write` 结果卡测试，确认转绿**

Run:

```bash
fvm flutter test test/widgets/tool_renderers/write_tool_cards_test.dart
```

Expected:

- PASS

## Task 4: 升级 `Edit` diff 预览为“diff 背景 + 代码高亮”

**Files:**
- Modify: `test/widgets/tool_renderers/edit_tool_cards_test.dart`
- Modify: `lib/widgets/tool_renderers/file_change_preview.dart`
- Modify: `lib/widgets/tool_renderers/edit_tool_result_card.dart`

- [ ] **Step 1: 为 `Edit` 结果卡补失败测试，锁定新 header 与高亮 diff 文本列**

至少覆盖：

- `EDIT` 标签存在
- 文件路径继续存在
- `替换 N 处` 文案继续存在
- 结果卡中出现 `HighlightedCodeContent`
- 现有 diff 文本内容仍可见

```dart
expect(find.text('EDIT'), findsOneWidget);
expect(find.byType(HighlightedCodeContent), findsWidgets);
expect(find.textContaining('+ '), findsWidgets);
```

- [ ] **Step 2: 运行 `Edit` 结果卡测试，确认红灯**

Run:

```bash
fvm flutter test test/widgets/tool_renderers/edit_tool_cards_test.dart
```

Expected:

- FAIL
- diff 预览尚未使用高亮文本列

- [ ] **Step 3: 扩展 `FileChangePreview` 接口**

新增：

- `filePath` 或明确的 `language` 参数

要求：

- 根据文件类型推断语言
- 保留现有 `_FileChangeLine` 行模型和 diff 计算逻辑

- [ ] **Step 4: 将 `_PreviewLineRow` 的文本列改为高亮代码内容**

要求：

- 左侧行号列保留
- 中间 diff 前缀列单独保留
- 右侧代码文本列使用 `HighlightedCodeContent`
- added/removed/context 背景色逻辑保持不变

- [ ] **Step 5: 修改 `EditToolResultCard` 接入新 surface 和新 diff 预览参数**

要求：

- 使用与 `Write` 一致的结果卡 surface
- 将 `filePath` 传给 diff 预览
- 详情区行为保持不变

- [ ] **Step 6: 运行 `Edit` 结果卡测试，确认转绿**

Run:

```bash
fvm flutter test test/widgets/tool_renderers/edit_tool_cards_test.dart
```

Expected:

- PASS

## Task 5: 运行整组目标回归验证

**Files:**
- No code changes expected

- [ ] **Step 1: 运行共享 helper 与文件工具卡相关测试**

Run:

```bash
fvm flutter test \
  test/widgets/shared/file_highlight_language_test.dart \
  test/widgets/tool_renderers/write_tool_cards_test.dart \
  test/widgets/tool_renderers/edit_tool_cards_test.dart \
  test/widgets/chat_blocks/chat_blocks_test.dart
```

Expected:

- PASS

- [ ] **Step 2: 运行受影响文件的 analyze**

Run:

```bash
fvm flutter analyze \
  lib/widgets/shared/file_highlight_language.dart \
  lib/widgets/shared/highlighted_code_content.dart \
  lib/widgets/markdown/code_widget.dart \
  lib/widgets/tool_renderers/file_tool_result_surface.dart \
  lib/widgets/tool_renderers/write_tool_result_card.dart \
  lib/widgets/tool_renderers/file_change_preview.dart \
  lib/widgets/tool_renderers/edit_tool_result_card.dart \
  test/widgets/shared/file_highlight_language_test.dart \
  test/widgets/tool_renderers/write_tool_cards_test.dart \
  test/widgets/tool_renderers/edit_tool_cards_test.dart
```

Expected:

- exit 0

- [ ] **Step 3: 复核范围外能力未被误改**

人工检查：

- `workflow/proposed` 卡片未改
- tool result payload contract 未改
- Markdown 主渲染链未改

- [ ] **Step 4: 提交本次改动**

```bash
git add \
  docs/superpowers/specs/2026-06-01-file-tool-result-card-code-alignment-design.md \
  docs/superpowers/plans/2026-06-01-file-tool-result-card-code-alignment-implementation-plan.md \
  lib/widgets/shared/file_highlight_language.dart \
  lib/widgets/shared/highlighted_code_content.dart \
  lib/widgets/markdown/code_widget.dart \
  lib/widgets/tool_renderers/file_tool_result_surface.dart \
  lib/widgets/tool_renderers/write_tool_result_card.dart \
  lib/widgets/tool_renderers/file_change_preview.dart \
  lib/widgets/tool_renderers/edit_tool_result_card.dart \
  test/widgets/shared/file_highlight_language_test.dart \
  test/widgets/tool_renderers/write_tool_cards_test.dart \
  test/widgets/tool_renderers/edit_tool_cards_test.dart
git commit -m "feat: align file tool result cards with code surfaces"
```
