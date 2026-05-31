# flutter_markdown 表格自渲染 + 边缘渐隐外壳设计

## 背景

主路径 Markdown 渲染在 2026-05-26 的 [单引擎收敛 spec](2026-05-26-single-markdown-engine-convergence-design.md) 之后已统一走 `flutter_markdown`（commit `beb3662 refactor: converge markdown rendering to flutter_markdown`）。该 spec 接受了「表格视觉先降级」，并明确将「在同一条 `flutter_markdown` 链中增强表格体验」作为后续迭代项。

本设计为该后续迭代的落地方案：把已下线的 `MarkdownWidgetImpl` 路径里那套表格视觉（圆角面板外壳 + 行底色分层 + `TableEdgeFadeScrollShell` 边缘渐隐）迁回主路径 `FlutterMarkdownImpl`，让所有 Markdown 表格在单引擎上获得一致观感。

参考代码块路径的实现经验：`CodeBlockBuilder` / `CodeElementBuilder` 通过 `MarkdownElementBuilder` 接管 `<pre>`/`<code>` 渲染，套上共享的 `TechnicalContentSurface`。表格希望借鉴「`MarkdownElementBuilder` 接管 + 共享外壳组件」的模式。

## 目标

- 主路径 `FlutterMarkdownImpl` 的表格获得「横向滚动 + 边缘渐隐」体验
- 视觉与已下线的 `MarkdownWidgetImpl` 表格保持一致（圆角面板 + 行底色 + 分隔线 + fade）
- **列宽按内容自适应**，而不是 `flutter_markdown` 默认的等分行为：短列保持紧凑、长列撑开后由外层横滚承接
- 单元格内联 Markdown（粗体 / 斜体 / 行内代码 / 链接 / 行内数学）继续工作
- 用户的 Markdown 源码无需任何改动，AI 模型输出的标准 GFM table 照常被识别
- 在同一次 PR 中顺手把 `flutter_markdown ^0.6.18` 升级到 `flutter_markdown_plus ^1.0.6`（社区接管 fork）

## 非目标

- 不为表格加 header 操作区（标签 / 复制按钮 / 列数信息）—— 后续可再加，但本次不做
- 不实现表头粘性 / 列宽手动调整 / 排序 / CSV 导出
- 不移除遗留的 `MarkdownWidgetImpl`（其唯一引用在两条 regression 测试中，与本次范围无关）
- 不改 Markdown 输入文本本身，不引入任何非标准 GFM 语法

## 现状梳理

- `lib/widgets/markdown/flutter_markdown_impl.dart`：主路径，`MarkdownBody` + `builders: {code, pre, math-inline, math-block, callout}`，**表格没有任何自定义，靠 `flutter_markdown 0.6.x` 默认渲染**（无横滚、无圆角面板、无 fade）
- `lib/widgets/markdown/markdown_widget_impl.dart`：已下线主路径，但保留实现。`TableConfig` 内有完整的表格视觉规范，包括 `TableEdgeFadeScrollShell` 外壳，可作为视觉基线
- `lib/widgets/markdown/table_edge_fade_scroll_shell.dart`：可复用的横向滚动 + 边缘渐隐组件，已存在，本次设计直接复用
- `flutter_markdown 0.6.23`：`<table>` 渲染在 `builder.dart:440-446` 硬编码为 `Table` widget，**不允许 `builders['table']` 接管，也无 wrapper 钩子**
- `flutter_markdown_plus 1.0.6`：提供 `tableColumnWidth: IntrinsicColumnWidth()` 时内置 `Scrollbar + SingleChildScrollView(Axis.horizontal)`，但**仍不暴露 `ScrollController`**，无法实现监听位置的边缘渐隐效果

## 方案对比

### 方案 A：自定义 BlockSyntax + 自渲染（采纳）

- 关闭 `flutter_markdown_plus` 默认的 GFM table 解析
- 注入子类化 `RichTableBlockSyntax`，复用父类全部 GFM table 解析能力，仅将产出的 AST 元素重命名为 `<rich-table>` / `<rich-thead>` / `<rich-tbody>` / `<rich-tr>` / `<rich-th>` / `<rich-td>`
- 通过 `builders['rich-table']` 完全接管渲染，绕过库对 `<table>` 标签的硬编码路径
- 单元格内联 Markdown 通过嵌套 `MarkdownBody` 渲染：复用顶层 `styleSheet`，但通过 `copyWith` 把 `blockSpacing` 置 0、`p` 文本样式调整为单元格期望字号；单元格 widget 自身不再额外加 Padding，仅依赖 `Table` 的 `tableCellsPadding`

优点：

- 同时满足横滚 + 边缘渐隐
- 对 markdown 源码零耦合（AST 层重命名）
- 视觉、外壳、配色完全复用 `MarkdownWidgetImpl` 已经成熟的方案
- 与 `flutter_markdown` 主路径其它自定义（callout / math / code）解耦

缺点：

- 单元格嵌套 `MarkdownBody` 有少量构造开销（每个单元格一次），可接受

### 方案 B：仅升级 flutter_markdown_plus

- 只升级，依赖库内置的横滚

优点：零自定义代码

缺点：做不到边缘渐隐；视觉与 `MarkdownWidgetImpl` 老路径有差距

### 方案 C：恢复 MarkdownWidgetImpl 分流

- 把 `assistant_doc_block` / `final_response_block` / `fetch_webpage_tool_result_card` 切回 `MarkdownWidgetImpl`

优点：直接复用现成实现

缺点：与单引擎收敛方向冲突，破坏 5/26 spec 的成果

**结论：采用方案 A。**

## 实施计划

整合在一个 PR 内，按两阶段提交保持回滚粒度清晰。

### 阶段 1：依赖升级（独立 commit）

- `pubspec.yaml`：`flutter_markdown: ^0.6.18` → `flutter_markdown_plus: ^1.0.6`
- 全局替换 `import 'package:flutter_markdown/flutter_markdown.dart'` → `'package:flutter_markdown_plus/flutter_markdown_plus.dart'`
- 适配 0.6 → 1.0 的 breaking changes：
  - 检查 `MarkdownBody` 的 `selectable`、`fitContent`、`onTapLink` 等参数签名
  - 检查 `MarkdownElementBuilder` 的 `visitElementAfterWithContext` 是否仍是当前实现
  - 检查 `MarkdownStyleSheet` 字段名（新增的 `tableHeadCellsPadding` / `tableHeadCellsDecoration` 等无需主动设置，保持默认即可）
- 验证：跑全套 widget 测试 + `flutter analyze` 干净 + 真机看 `final_response_block` / `assistant_doc_block` 视觉无回归
- 此阶段表格视觉因 plus 内置横滚已有改善，但还没有边缘渐隐

### 阶段 2：自渲染表格（独立 commit）

新增文件：

- `lib/widgets/markdown/rich_table_block_syntax.dart`
  - `class RichTableBlockSyntax extends md.TableSyntax`
  - 覆写 `parse(parser)`：调用 `super.parse(parser)`，对返回的 `Element` 子树**深度遍历**，把所有 `'table' / 'thead' / 'tbody' / 'tr' / 'th' / 'td'` 标签替换为 `'rich-' + 原 tag`。所有 `attributes`（特别是单元格的 `align` 属性，值为 `'left' / 'center' / 'right'`）原样保留
- `lib/widgets/markdown/rich_table_element_builder.dart`
  - `class RichTableElementBuilder extends MarkdownElementBuilder`
  - `isBlockElement() => true`
  - `visitElementAfter(element, preferredStyle)`：
    - 遍历 `<rich-thead>` / `<rich-tbody>` 下的 `<rich-tr>`，每个 tr 转换为 `TableRow`
    - 每个 `<rich-th>` / `<rich-td>` 转换为 `TableCell`：
      - 单元格文本通过 `_serializeCellMarkdown(element)` 反序列化为 markdown 字符串
      - 单元格 widget 用嵌套 `MarkdownBody(data: cellMarkdown, styleSheet: cellStyleSheet, extensionSet: 同顶层, blockSyntaxes: 同顶层, inlineSyntaxes: 同顶层, builders: {math-inline, math-block, callout, code, pre})`
      - 列对齐属性透传到 `TableCell` 的 `TextAlign`
    - 外层用 Flutter `Table` widget 装配 rows，显式设置 `defaultColumnWidth: const IntrinsicColumnWidth()`，让每列宽度由列内最宽单元格的 intrinsic 宽度决定
    - 套 `TableEdgeFadeScrollShell` 实现横滚 + fade（`IntrinsicColumnWidth` 让窄列保持紧凑、宽列撑开，再由横滚承接整体溢出宽度）
    - 最外层用 `Container` + `BoxDecoration` 套圆角面板（背景色 `tableShellFill`、`BorderRadius.circular(12)`、`clipBehavior: Clip.antiAlias`），完整复刻 `MarkdownWidgetImpl` 的 `TableConfig.wrapper`
  - 私有方法 `_serializeCellMarkdown(md.Element cellElement) -> String`：
    - 将单元格子树（`md.Text` / `md.Element` 节点）反序列化为对应的 markdown 文本片段（`<em>x</em>` → `*x*`、`<code>x</code>` → `` `x` `` 等）
    - 该序列化只需覆盖 GFM table 单元格里允许出现的 inline 元素：em / strong / code / a / del / br 以及自定义 inline math 标签 `<math-inline>`

修改文件：

- `lib/widgets/markdown/flutter_markdown_impl.dart`
  - `MarkdownBody.extensionSet`：构造一个新 `ExtensionSet`，沿用 GFM 全部 inline & block syntaxes，但把 `md.TableSyntax` 替换为 `RichTableBlockSyntax`
  - `builders` 增加 `'rich-table': RichTableElementBuilder()`
  - 注意：`<rich-thead>` / `<rich-tbody>` / `<rich-tr>` / `<rich-th>` / `<rich-td>` 这些子节点**不需要**单独的 builder——它们都被 `RichTableElementBuilder.visitElementAfter` 拿到 `<rich-table>` 时通过 `element.children` 直接遍历访问，库不会再为它们派发 builder
  - 通过 `MarkdownElementBuilder.isBlockElement()` 返回 `true`，让 `<rich-table>` 自动加入 `_kBlockTags`（参考 `flutter_markdown` 0.6.23 `builder.dart:193-197`，plus 同等位置）

复用文件（不修改）：

- `lib/widgets/markdown/table_edge_fade_scroll_shell.dart`
- `lib/widgets/markdown/flutter_markdown_reader_tokens.dart`（颜色 / 字号 token）

## 关键设计点

### 私有 AST 标签与 markdown 源码的关系

用户写的 Markdown 始终是标准 GFM table：

```
| a | b |
|---|---|
| 1 | 2 |
```

`RichTableBlockSyntax` 复用父类的 GFM 解析逻辑（管道符切分、对齐分隔行、单元格 inline 解析），仅修改输出 AST 节点的 tag 名。AST 是 markdown 包内部表示，对输入文本完全透明。

### 单元格内联 markdown 的渲染策略

不重新实现 inline 渲染器，而是让单元格内的 inline 子树**反序列化回 markdown 文本片段**，再用嵌套 `MarkdownBody` 渲染。这样：

- 自动继承所有 inline syntax 与 styleSheet
- 行内数学（自定义 `MathInlineSyntax`）也自然继续工作
- 单元格嵌套 `MarkdownBody` 的实例化成本可接受（每个单元格只构造一次 widget tree）

反序列化只需覆盖 GFM table 单元格允许出现的 inline 元素清单，不是通用 markdown 序列化器。

### 块级 tag 注册

`flutter_markdown_plus` 沿袭 `flutter_markdown` 的逻辑，在 `MarkdownBuilder.build()` 入口处把每个 `builder` 注册的 tag 加入 `_kBlockTags`（前提是 `builder.isBlockElement() == true`）。我们的 `RichTableElementBuilder.isBlockElement() => true`，因此 `<rich-table>` 自动作为 block 进入正确的 dispatch 路径。

### 列宽策略

`flutter_markdown` 默认对表格使用 `FlexColumnWidth()`（0.6.x）或 `FixedColumnWidth(48.0)`（0.7.x / plus），这两种策略要么按可用宽度等分、要么强制定宽，都不符合"内容定宽"的预期。

本设计在 `Table` widget 上显式设置：

```dart
Table(
  defaultColumnWidth: const IntrinsicColumnWidth(),
  ...
)
```

`IntrinsicColumnWidth` 让每列宽度等于"该列所有单元格中最宽内容的 intrinsic 宽度"，效果：

- 短文本列（如 `1` / `2`）保持紧凑
- 长文本列（如 `这是一段较长说明`）按内容自然撑开
- 整体表格宽度可能超出父容器 → 由外层 `TableEdgeFadeScrollShell` 的 `SingleChildScrollView(Axis.horizontal)` 承接横滚

这点与 `MarkdownWidgetImpl` 路径 `TableConfig.defaultColumnWidth: const IntrinsicColumnWidth()` 的设置保持一致，复用其已被验证过的列宽行为。

## 边界与降级

| 场景 | 处理 |
|---|---|
| 表头/分隔行不合法 | `canParse` 返回 false（父类逻辑），fallback 为段落 |
| 空表（仅表头） | 渲染只有 `<rich-thead>` 的 Table，空 `<rich-tbody>` 跳过 |
| 单元格数量不一致 | 父类 `TableSyntax.parse` 已处理：少了塞空 `<td>`，多了截断 |
| 单元格内含 block 元素 | GFM 解析阶段已限制为 inline；万一出现，嵌套 `MarkdownBody` 也能处理，不崩 |
| 流式渲染中的不完整表格 | 与现状一致：未到分隔行前 `canParse` 失败，按段落渲染；分隔行到位后开始按表格渲染 |
| 超宽表格父容器约束 | `TableEdgeFadeScrollShell` 用 `SingleChildScrollView(Axis.horizontal)`，Flutter `Table` widget 配合 `IntrinsicColumnWidth` 正确报告 intrinsic 宽度 |
| 列对齐 | `TableSyntax` 在分隔行上识别对齐属性，写入每个单元格的 `attributes['align']`（`'left' / 'center' / 'right'`）；builder 解析此属性透传为 `TextAlign`；未设置时表头默认居中、表体默认左对齐（与 `flutter_markdown` 行为一致） |

## 测试策略

新增：

- `test/widgets/markdown/rich_table_block_syntax_test.dart`
  - 标准 GFM table 被解析为 `<rich-table>` 根，整棵子树都是 `rich-*` 前缀
  - 三种对齐分隔行（左 `:---` / 中 `:---:` / 右 `---:`）正确写入单元格 `attributes['align']`
  - 表头列数 ≠ 分隔行列数时 `canParse` 返回 false
  - 单元格数量超过/不足列数时与父类行为一致

- `test/widgets/markdown/rich_table_rendering_test.dart`
  - 含表格的 markdown 渲染产物中存在 `Table` widget 与 `TableEdgeFadeScrollShell`
  - 单元格 `**bold**` / `` `code` `` / `[link](url)` / `*em*` 渲染为对应 widget（非字面量）
  - 单元格 `$x^2$` 行内数学正确渲染（与 `MathInlineSyntax` 协同）
  - 列对齐属性透传到 `TableCell.textAlign`
  - **列宽自适应**：构造含「短文本列 + 长文本列」的样本，断言 `Table.defaultColumnWidth is IntrinsicColumnWidth`，并通过 widget 测量断言两列的渲染宽度差异符合预期（短列窄、长列宽）

扩展：

- `test/widgets/markdown/markdown_rendering_regression_test.dart`
  - 添加包含表格的 markdown 样本，断言渲染产物结构稳定（不再走 `MarkdownWidgetImpl` 路径）

回归：

- `fvm flutter test test/widgets/markdown/`
- `fvm flutter test test/widgets/chat_blocks/`
- `fvm flutter analyze`
- 阶段 1 commit 完成后专门跑一次：含 math / callout / code / list / 普通表格的样本，Android 真机查看 `assistant_doc_block` / `final_response_block` 视觉无回归

## 风险与已知限制

- `flutter_markdown_plus` 1.0.6 与项目当前 0.6.x 的 API 差异未在本设计中完全枚举，阶段 1 commit 中按编译错误逐项处理
- 单元格反序列化器对未来新增的 inline syntax 需要同步维护（例如未来若加 `<u>` 下划线，需要在序列化映射里补一条）。可在序列化器入口加一个未知 tag 的 fallback：未识别的 inline element 直接输出其 `textContent`，保证不丢字面量
- 流式片段进入时表格的"是否构成有效表格"判定与现状完全一致，本设计不改变流式渲染策略
