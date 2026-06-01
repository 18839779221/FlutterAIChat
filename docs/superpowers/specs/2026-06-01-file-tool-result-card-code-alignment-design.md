# 文件工具结果卡片与 Markdown 代码块视觉收敛设计

## 背景

当前仓库中的 Markdown 围栏代码块已经形成稳定的技术内容阅读表面：

- [FlutterMarkdownImpl](/Users/zyb_wl/flutterSpace/FlutterAIChat/.worktrees/file-tool-result-code-align/lib/widgets/markdown/flutter_markdown_impl.dart) 负责 Markdown 主渲染链。
- [CodeBlockWidget](/Users/zyb_wl/flutterSpace/FlutterAIChat/.worktrees/file-tool-result-code-align/lib/widgets/markdown/code_widget.dart) 已接入 `flutter_highlight`，并通过 [TechnicalContentSurface](/Users/zyb_wl/flutterSpace/FlutterAIChat/.worktrees/file-tool-result-code-align/lib/widgets/technical_content_surface.dart) 提供统一 header、背景和代码阅读氛围。

但 `Write/Edit` 结果卡片仍是另一套视觉结构：

- [WriteToolResultCard](/Users/zyb_wl/flutterSpace/FlutterAIChat/.worktrees/file-tool-result-code-align/lib/widgets/tool_renderers/write_tool_result_card.dart) 与 [EditToolResultCard](/Users/zyb_wl/flutterSpace/FlutterAIChat/.worktrees/file-tool-result-code-align/lib/widgets/tool_renderers/edit_tool_result_card.dart) 使用普通信息卡片样式。
- [FileChangePreview](/Users/zyb_wl/flutterSpace/FlutterAIChat/.worktrees/file-tool-result-code-align/lib/widgets/tool_renderers/file_change_preview.dart) 只保留行级 diff 背景和纯文本代码行，没有语法高亮。

这带来两个问题：

- 文件工具结果卡片和 Markdown 代码块的阅读体验割裂，整体风格不统一。
- `Edit` 结果卡虽然保留了 diff 语义，但代码本身缺乏语言高亮，阅读成本偏高。

## 目标

本次改造目标是让 `Write/Edit result card` 与现有 Markdown 代码块在阅读表面上收敛，同时保留文件工具结果的独立语义。

具体目标：

- `Write/Edit result card` 复用与 Markdown 代码块同一家族的技术内容表面。
- `Write` 结果中的代码预览支持基于文件路径推断语言的 `flutter_highlight` 高亮。
- `Edit` 结果中的 diff 预览保留 `added/removed/context` 行级背景语义，同时代码文本本身支持语言高亮。
- 工具结果卡仍然明确展示 `WRITE/EDIT` 身份、文件路径和操作摘要，不伪装成普通 assistant Markdown。

## 非目标

- 本次不改 `workflow/proposed` 阶段卡片。
- 本次不改 `FlutterMarkdownImpl` 的 Markdown 主渲染链。
- 本次不修改 tool result payload contract，不新增后端字段。
- 本次不做词级 diff 高亮，只做行级 diff 背景和代码语法高亮。
- 本次不重做 `postWriteData`、`oldString/newString` 等详情区的语义结构，仅调整结果卡主体阅读面。

## 方案对比

### 方案 A：仅替换预览区

做法：

- 保留现有 `Write/Edit result card` 外层结构。
- 仅把 `FileChangePreview` 和 `Write` 的内容预览改成更像代码块的样式。

优点：

- 改动面小。

缺点：

- 外层卡片和内层代码面仍然像两套系统拼接。
- 很难真正实现“整体风格对齐”。

### 方案 B：结果卡整体收敛到技术内容表面

做法：

- 为 `Write/Edit result card` 新建共享结果卡 surface。
- header 明确展示工具身份和路径。
- 主体内容全面收敛到代码阅读表面。
- `Write` 走普通代码高亮。
- `Edit` 走“diff 背景 + 代码高亮”。

优点：

- 风格统一度高。
- 不会丢失工具执行语义。
- 可复用的高亮和视觉底座边界清晰。

缺点：

- 改动比局部替换更大。

### 方案 C：直接伪装成普通 fenced code block

做法：

- 最大程度弱化 `Write/Edit` 工具身份。
- 结果卡视觉上几乎等同普通 Markdown 代码块。

优点：

- 视觉最统一。

缺点：

- 会模糊工具结果和普通 assistant 文档块的语义边界。
- 在时间线中不利于用户区分“内容正文”和“工具执行结果”。

### 推荐

推荐方案 B。

原因：

- 用户要求的是“整体风格对齐”，而不是语义消失。
- `Write/Edit` 是工具执行结果，必须保留身份和状态信息。
- 共享 surface + 共享高亮能力更利于后续其它技术类卡片复用。

## 目标架构

### 一、保留 Markdown 与文件工具的展示边界

`FlutterMarkdownImpl` 继续只负责 Markdown 文档渲染。

文件工具结果卡单独处于 `tool_renderers` 体系内，但视觉上与 `CodeBlockWidget` 收敛。这样既不破坏 Markdown 主链，也不把工具结果误并入 assistant 正文。

### 二、抽出共享高亮基础设施

新增一个轻量共享高亮层，职责分为两部分：

- 文件路径到 highlight language 的推断 helper。
- 统一的高亮内容渲染组件，封装 `HighlightView`、明暗主题切换、代码字体、自动换行与横向滚动策略。

这层能力应同时可被 Markdown code block 和文件工具结果卡消费，避免未来出现两套 `flutter_highlight` 配置。

### 三、为文件工具结果卡定义独立 surface

新增一个文件工具结果卡专用 surface，承担以下职责：

- 渲染 `WRITE/EDIT` header 标签。
- 渲染主标题文件路径。
- 渲染副信息，如 `新建文件`、`覆盖文件`、`替换 N 处`、长度变化。
- 渲染摘要文本。
- 预留一个主体内容槽位，承载高亮代码预览或 diff 预览。

这个 surface 在设计上应该与 `TechnicalContentSurface` 同家族，但不强求和 Markdown code block 完全共用同一个 widget。前者偏“技术内容块”，后者偏“工具结果容器”。

## 结果卡行为设计

### `Write result card`

顶部：

- `WRITE` 标签
- 文件路径主标题
- 副信息：`新建文件` 或 `覆盖文件`
- 如果有长度变化，显示 `oldLength -> newLength`

主体：

- 若 `newContentPreview` 非空，则展示一块完整代码预览
- 代码预览按 `filePath` 推断语言并用 `flutter_highlight` 高亮
- 若预览被截断，保留“预览已截断，仅展示前部内容”

说明：

- `Write` 主体不保留 diff 前缀，因为它更接近一个完整快照，不是增删对比阅读模式

### `Edit result card`

顶部：

- `EDIT` 标签
- 文件路径主标题
- 副信息：`替换 N 处`
- 如果有长度变化，显示 `oldLength -> newLength`

主体：

- 保留现有 `added/removed/context` 行模型
- 每行保留：
  - 行号列
  - `+/-/空白` 前缀列
  - 代码文本列
- 行背景继续表达 diff 语义：
  - added: success 低透明度
  - removed: warning 低透明度
  - context: 弱代码背景
- 代码文本列按 `filePath` 推断语言后做 `flutter_highlight`

说明：

- diff 语义由“行容器背景 + 前缀列”承担
- 代码语义由“文本列高亮”承担
- 第一版不做词级 diff 标注，避免复杂度失控

## 语言推断策略

仓库当前没有现成的 `filePath -> language` 推断 helper，因此本次需要新增一个轻量映射层。

首版策略：

- `*.dart -> dart`
- `*.md -> markdown`
- `*.json -> json`
- `*.yaml` / `*.yml -> yaml`
- `*.js -> javascript`
- `*.ts -> typescript`
- `*.css -> css`
- `*.html -> xml` 或 highlight 支持的 HTML 对应 id
- `*.sh -> bash`
- 未命中时回退 `plaintext`

原则：

- 只覆盖仓库当前最常见文件类型
- 不做内容猜测
- 不做复杂 shebang 或混合语言识别

## 需要修改的模块边界

### 1. Markdown 高亮共享层

- 修改 [code_widget.dart](/Users/zyb_wl/flutterSpace/FlutterAIChat/.worktrees/file-tool-result-code-align/lib/widgets/markdown/code_widget.dart)
- 新增共享高亮 helper / widget

需要完成：

- 收拢 `HighlightView` 配置，避免 Markdown 代码块和文件工具结果卡重复维护

### 2. 文件工具结果卡 surface

- 新增文件工具结果卡专用 surface

需要完成：

- 把 `WRITE/EDIT` 身份、路径和副信息组织成统一壳层

### 3. `WriteToolResultCard`

- 修改 [write_tool_result_card.dart](/Users/zyb_wl/flutterSpace/FlutterAIChat/.worktrees/file-tool-result-code-align/lib/widgets/tool_renderers/write_tool_result_card.dart)

需要完成：

- 从普通信息卡切到文件工具结果卡 surface
- 让 `newContentPreview` 走高亮代码阅读面

### 4. `FileChangePreview` 与 `EditToolResultCard`

- 修改 [file_change_preview.dart](/Users/zyb_wl/flutterSpace/FlutterAIChat/.worktrees/file-tool-result-code-align/lib/widgets/tool_renderers/file_change_preview.dart)
- 修改 [edit_tool_result_card.dart](/Users/zyb_wl/flutterSpace/FlutterAIChat/.worktrees/file-tool-result-code-align/lib/widgets/tool_renderers/edit_tool_result_card.dart)

需要完成：

- 让 diff 预览升级为“diff 背景 + 高亮文本列”
- 保持现有行模型和截断提示语义

### 5. 测试层

- 修改 `Write/Edit` 结果卡相关 widget tests
- 视情况补充共享 helper 的单测

需要完成：

- 验证 header、路径、副信息、预览模式
- 验证 `Edit` 结果卡仍保留 diff 行语义
- 验证高亮组件已接入

## 风险与控制

### 风险 1：逐行高亮的性能和排版复杂度

`Edit` 结果卡如果为每一行都单独创建 `HighlightView`，可能带来额外开销。

控制策略：

- 第一版严格依赖现有 preview 截断机制
- 不扩大 preview 长度
- 只在结果卡层面使用，不向长列表全文 diff 扩散

### 风险 2：语言 id 与文件扩展名不完全匹配

不同 highlight 包支持的语言 id 不完全一致。

控制策略：

- 用受控映射表而不是直接取扩展名
- 对未知扩展名统一回退 `plaintext`

### 风险 3：结果卡与 Markdown 代码块过于相像

如果 header 语义太弱，用户可能误以为这是 assistant 正文代码块。

控制策略：

- 明确保留 `WRITE/EDIT` header
- 保留路径与操作摘要
- 不把工具结果 header 完全降成语言标签样式

## 实施策略

### 阶段 1：共享高亮能力与 `Write` 收敛

目标：

- 建立语言推断和共享高亮底座
- 先让 `Write result card` 完整切到代码阅读表面

原因：

- `Write` 没有 diff 混合问题，适合作为共享底座的首个消费者

### 阶段 2：`Edit` diff 预览升级

目标：

- 在保留现有 diff 行语义的前提下，引入代码文本高亮

原因：

- `Edit` 的关键复杂度在于 diff 语义和代码语义并存，应该在共享底座稳定后单独处理

### 阶段 3：评估 Markdown 代码块是否反向复用共享高亮组件

目标：

- 如果抽取后的共享高亮层足够清晰，考虑让 `CodeBlockWidget` 也切过去，减少重复逻辑

本次不强求：

- 只要行为一致、测试覆盖清晰，本次可以先接受 `CodeBlockWidget` 仍保留少量外层封装
