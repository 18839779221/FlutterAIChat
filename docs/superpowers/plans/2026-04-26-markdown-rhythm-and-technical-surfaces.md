# Markdown Rhythm And Technical Surfaces Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 统一 Markdown 的阅读节奏，并让 fenced code、命令块、Edit/Write tool 文件预览收敛为同一类技术内容块。

**Architecture:** 保留现有双 Markdown 渲染路径，但抽出共享技术内容表面层，让 `CodeBlockWidget`、`markdown_widget` 路径中的 pre、`FileChangePreview` 复用同一视觉基础。同步微调普通 Markdown 与表格 Markdown 的 spacing token，减少长回答中的松紧跳变。

**Tech Stack:** Flutter、flutter_markdown、markdown_widget、flutter_test

---

我是 using the writing-plans skill to create the implementation plan.

## 文件结构

### Create

- `lib/widgets/technical_content_surface.dart`
  - 定义共享技术内容块表面、可选 header 区和统一 decoration 规则。

### Modify

- `lib/widgets/markdown/flutter_markdown_impl.dart`
  - 调整普通 Markdown 的段落/标题/列表/引用/分割线节奏 token。
- `lib/widgets/markdown/markdown_widget_impl.dart`
  - 调整表格 Markdown 路径的节奏 token，并让 pre 复用统一 code block。
- `lib/widgets/markdown/code_widget.dart`
  - 将 fenced code 改造成统一技术内容块。
- `lib/widgets/tool_renderers/file_change_preview.dart`
  - 让 diff/file preview 使用统一技术内容块表面。
- `test/widgets/chat_blocks/chat_blocks_test.dart`
  - 更新 Markdown 节奏与统一技术内容块相关测试。
- `test/widgets/tool_renderers/write_tool_cards_test.dart`
  - 验证 write preview 复用统一技术内容块。
- `test/widgets/tool_renderers/edit_tool_cards_test.dart`
  - 视需要补充 edit preview 相关断言。

## Task 1: 冻结测试并确认当前失败点

**Files:**
- Modify: `test/widgets/chat_blocks/chat_blocks_test.dart`
- Modify: `test/widgets/tool_renderers/write_tool_cards_test.dart`
- Test: `test/widgets/chat_blocks/chat_blocks_test.dart`
- Test: `test/widgets/tool_renderers/write_tool_cards_test.dart`

- [ ] **Step 1: 写失败测试，表达新的节奏和共享技术内容块预期**

补充或调整以下断言：

- Markdown `blockSpacing` 不再维持当前偏紧的值
- list indent 与标题 padding 体现更松节奏
- `CodeBlockWidget` 使用共享 `TechnicalContentSurface`
- write preview 使用共享 `TechnicalContentSurface`

- [ ] **Step 2: 运行失败测试，确认测试因功能未实现而失败**

Run:

```bash
flutter test test/widgets/chat_blocks/chat_blocks_test.dart
flutter test test/widgets/tool_renderers/write_tool_cards_test.dart
```

Expected:

- 至少出现关于 `TechnicalContentSurface` 缺失或样式断言不满足的失败

- [ ] **Step 3: 提交测试草稿**

```bash
git add test/widgets/chat_blocks/chat_blocks_test.dart test/widgets/tool_renderers/write_tool_cards_test.dart
git commit -m "test: lock markdown rhythm goals"
```

## Task 2: 新增共享技术内容块表面层

**Files:**
- Create: `lib/widgets/technical_content_surface.dart`
- Test: `test/widgets/chat_blocks/chat_blocks_test.dart`

- [ ] **Step 1: 为共享技术内容块写最小接口**

新增 widget，至少支持：

- 外层表面 decoration
- 可选 header
- 内部 child
- 基于主题的统一背景/分隔/标签颜色

- [ ] **Step 2: 运行相关测试，确认仍失败但编译通过**

Run:

```bash
flutter test test/widgets/chat_blocks/chat_blocks_test.dart
```

Expected:

- 编译通过
- 样式或使用位置相关断言仍失败

- [ ] **Step 3: 只做最小实现，不提前改其他业务组件**

要求：

- 不引入与 Markdown 无关的通用 UI 抽象
- 仅服务本轮技术内容块统一目标

- [ ] **Step 4: 格式化新文件**

Run:

```bash
dart format lib/widgets/technical_content_surface.dart
```

- [ ] **Step 5: 提交共享层**

```bash
git add lib/widgets/technical_content_surface.dart
git commit -m "feat: add technical content surface"
```

## Task 3: 统一 fenced code 与表格路径 pre

**Files:**
- Modify: `lib/widgets/markdown/code_widget.dart`
- Modify: `lib/widgets/markdown/markdown_widget_impl.dart`
- Test: `test/widgets/chat_blocks/chat_blocks_test.dart`

- [ ] **Step 1: 让 `CodeBlockWidget` 复用 `TechnicalContentSurface`**

实现要求：

- 改为浅色文档嵌入式外壳
- 保留语言标签、复制、自动换行
- header 语气与工具预览一致

- [ ] **Step 2: 让 `markdown_widget_impl.dart` 的 pre 不再使用另一套独立样式**

推荐做法：

- 用 `PreConfig.builder` 直接复用 `CodeBlockWidget`

- [ ] **Step 3: 运行 widget test 验证 code block 使用共享 surface**

Run:

```bash
flutter test test/widgets/chat_blocks/chat_blocks_test.dart
```

Expected:

- `code blocks use shared technical content surface` 通过

- [ ] **Step 4: 手动检查代码块不会退化成深色终端风**

检查点：

- light mode 下代码块不再明显深色
- header 与内容区层级克制

- [ ] **Step 5: 提交 code block 统一改动**

```bash
git add lib/widgets/markdown/code_widget.dart lib/widgets/markdown/markdown_widget_impl.dart test/widgets/chat_blocks/chat_blocks_test.dart
git commit -m "feat: unify markdown code surfaces"
```

## Task 4: 统一 FileChangePreview 与 Edit/Write 预览

**Files:**
- Modify: `lib/widgets/tool_renderers/file_change_preview.dart`
- Modify: `test/widgets/tool_renderers/write_tool_cards_test.dart`
- Modify: `test/widgets/tool_renderers/edit_tool_cards_test.dart`

- [ ] **Step 1: 用 `TechnicalContentSurface` 重包 `FileChangePreview`**

实现要求：

- 外壳与 code block 同一家族
- diff 行语义色保留
- 行号、字体、行高与 code block 更接近

- [ ] **Step 2: 为 write/edit preview 补统一 surface 断言**

至少覆盖：

- write workflow expanded preview
- edit workflow expanded preview 或 result preview

- [ ] **Step 3: 运行 tool renderer 相关测试**

Run:

```bash
flutter test test/widgets/tool_renderers/write_tool_cards_test.dart
flutter test test/widgets/tool_renderers/edit_tool_cards_test.dart
```

Expected:

- 新旧断言全部通过

- [ ] **Step 4: 提交 preview 统一改动**

```bash
git add lib/widgets/tool_renderers/file_change_preview.dart test/widgets/tool_renderers/write_tool_cards_test.dart test/widgets/tool_renderers/edit_tool_cards_test.dart
git commit -m "feat: unify file preview surfaces"
```

## Task 5: 放松并拉齐 Markdown 主节奏

**Files:**
- Modify: `lib/widgets/markdown/flutter_markdown_impl.dart`
- Modify: `lib/widgets/markdown/markdown_widget_impl.dart`
- Test: `test/widgets/chat_blocks/chat_blocks_test.dart`

- [ ] **Step 1: 先改普通 Markdown 路径节奏 token**

调整点：

- `blockSpacing`
- `listIndent`
- `h1/h2/h3` padding
- blockquote padding/margin/观感
- 分割线存在感

- [ ] **Step 2: 再改含表格 Markdown 路径的对应 token**

对齐点：

- `PConfig`
- `H1/H2/H3`
- `ListConfig`
- `BlockquoteConfig`
- table wrapper margin

- [ ] **Step 3: 运行 Markdown 相关测试**

Run:

```bash
flutter test test/widgets/chat_blocks/chat_blocks_test.dart
flutter test test/widgets/chat_timeline/stable_markdown_block_test.dart
```

Expected:

- 两组测试全部通过

- [ ] **Step 4: 用 analyze 确认没有新 lint**

Run:

```bash
flutter analyze lib/widgets/markdown/flutter_markdown_impl.dart lib/widgets/markdown/markdown_widget_impl.dart lib/widgets/markdown/code_widget.dart lib/widgets/tool_renderers/file_change_preview.dart lib/widgets/technical_content_surface.dart test/widgets/chat_blocks/chat_blocks_test.dart test/widgets/tool_renderers/write_tool_cards_test.dart test/widgets/tool_renderers/edit_tool_cards_test.dart
```

Expected:

- `No issues found!`

- [ ] **Step 5: 提交节奏统一改动**

```bash
git add lib/widgets/markdown/flutter_markdown_impl.dart lib/widgets/markdown/markdown_widget_impl.dart lib/widgets/markdown/code_widget.dart lib/widgets/tool_renderers/file_change_preview.dart lib/widgets/technical_content_surface.dart test/widgets/chat_blocks/chat_blocks_test.dart test/widgets/chat_timeline/stable_markdown_block_test.dart test/widgets/tool_renderers/write_tool_cards_test.dart test/widgets/tool_renderers/edit_tool_cards_test.dart
git commit -m "feat: refine markdown reading rhythm"
```

## Task 6: 真机验证与截图复核

**Files:**
- Modify: none required
- Verify: Android real device screenshot / current chat screen

- [ ] **Step 1: 安装最新 debug APK 到真机**

Run:

```bash
bash scripts/android_install_debug.sh AUUNW22B08000071
```

Expected:

- `Success`

- [ ] **Step 2: 截图并核对以下视觉目标**

核对点：

- 段落与标题节奏更均匀
- 列表区比当前更舒展
- code block 与 FileChangePreview 属于同一家族
- 含表格回答中的 code block 与普通回答一致

- [ ] **Step 3: 如截图仍不稳定，仅做小幅 token 微调**

限制：

- 只调 spacing / alpha / radius / padding
- 不新增新的视觉分支

- [ ] **Step 4: 最终回归测试**

Run:

```bash
flutter test test/widgets/chat_blocks/chat_blocks_test.dart
flutter test test/widgets/chat_timeline/stable_markdown_block_test.dart
flutter test test/widgets/tool_renderers/write_tool_cards_test.dart
flutter test test/widgets/tool_renderers/edit_tool_cards_test.dart
```

Expected:

- 全绿

- [ ] **Step 5: 最终提交**

```bash
git add lib/widgets/markdown/flutter_markdown_impl.dart lib/widgets/markdown/markdown_widget_impl.dart lib/widgets/markdown/code_widget.dart lib/widgets/tool_renderers/file_change_preview.dart lib/widgets/technical_content_surface.dart test/widgets/chat_blocks/chat_blocks_test.dart test/widgets/chat_timeline/stable_markdown_block_test.dart test/widgets/tool_renderers/write_tool_cards_test.dart test/widgets/tool_renderers/edit_tool_cards_test.dart
git commit -m "feat: unify markdown technical content surfaces"
```

## 备注

- 当前工作区已有未提交的测试草稿，执行前应先确认这些草稿是否与本计划一致。
- `ios/Podfile.lock` 不是本计划目标文件，执行时不要混入提交。
