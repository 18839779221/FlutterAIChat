# Markdown 公式渲染设计

## 背景

项目内 Markdown 阅读体验已经收敛到 `FlutterMarkdownImpl` 这条 `flutter_markdown` 渲染链路，并通过自定义 block syntax / builder 支持了 Callout。下一步需要补齐 AI 回复中常见的数学公式展示能力，让模型输出的推导、概率、损失函数、复杂度表达式等内容不再以裸文本形式出现。

本设计只关注 `flutter_markdown` 实现，不处理 `markdown_widget` 表格专用路径，也不尝试统一多套 Markdown renderer。

## 目标

1. 支持常见行内公式：`$E = mc^2$` 与 `\( E = mc^2 \)`。
2. 支持常见块级公式：`$$ ... $$` 与 `\[ ... \]`。
3. 使用成熟公式渲染库负责 TeX 排版，项目只负责 Markdown 识别、样式包裹、滚动和失败降级。
4. 保持专业文档级阅读质感：行内公式融入正文，块级公式独占段落并铺满阅读栏。
5. 保守识别 `$...$`，避免把价格、Shell 变量、普通美元符号误判为公式。

## 非目标

1. 不实现自研 TeX/KaTeX 排版引擎。
2. 不在第一版支持所有 LaTeX 环境、编号、引用、宏定义、矩阵对齐编号等高级语法。
3. 不改变表格检测后走 `MarkdownWidgetImpl` 的现有策略。
4. 不让公式语法影响 fenced code、inline code、链接文本等已有 Markdown 语义。

## 技术选择

公式渲染使用 `flutter_math_fork`。它负责 TeX AST 解析和 Flutter Widget 绘制；项目内新增的适配层负责把 Markdown 文本中的公式片段转换为自定义节点，并根据行内 / 块级场景选择合适的展示组件。

不直接采用 `flutter_markdown_latex` 作为第一版集成层，原因是公式展示在本项目里不仅是“能渲染”，还涉及阅读栏宽度、横向滚动、深浅色主题、错误降级、与 Callout / blockquote / code 的节奏一致性。保持薄适配层在项目内，可以让这些行为可测试、可调优。

## Markdown 语法

### 行内公式

支持：

```md
能量公式是 $E = mc^2$。
能量公式是 \( E = mc^2 \)。
```

行内 `$...$` 使用保守规则：

1. 起始 `$` 后不能是空白。
2. 结束 `$` 前不能是空白。
3. 起始 `$` 前不能是数字或字母，降低 `$HOME`、`abc$def$` 等误判。
4. 结束 `$` 后不能紧跟数字或字母，降低价格和变量片段误判。
5. 内容至少包含一个数学特征字符，例如 `\`、`^`、`_`、`=`, `+`, `-`, `*`, `/`, `<`, `>`, `(`, `)`, `[`, `]`, `{`, `}` 或数字与运算符组合。

### 块级公式

支持：

```md
$$
\int_0^1 x^2 dx = \frac{1}{3}
$$
```

以及：

```md
\[
\sum_{i=1}^{n} i = \frac{n(n+1)}{2}
\]
```

块级公式必须独占起止行。起止标记同一行的 `$$ E = mc^2 $$` 可作为第一版可选能力；若实现复杂度升高，第一版只保证多行块级公式。

## 视觉与交互

行内公式：

1. 不使用 chip 背景，不额外制造卡片感。
2. 字号略随正文，颜色使用当前正文主色。
3. 渲染失败时显示原始公式文本，样式接近 inline code 但更轻，避免破坏段落。

块级公式：

1. 铺满当前 Markdown 阅读栏宽度。
2. 公式内容居中展示。
3. 过宽时横向滚动，不压缩到不可读。
4. 表面使用非常轻的技术内容底色或透明背景，避免和代码块混淆。
5. 与上下段落保持 `MarkdownStyleSheet.blockSpacing` 一致的节奏。

## 组件边界

新增文件建议：

1. `lib/widgets/markdown/math_inline_syntax.dart`
   负责识别行内公式并产出 `math-inline` 节点。
2. `lib/widgets/markdown/math_block_syntax.dart`
   负责识别块级公式并产出 `math-block` 节点。
3. `lib/widgets/markdown/markdown_math_builder.dart`
   负责把 Markdown AST 节点转换为行内或块级 Flutter Widget。
4. `lib/widgets/markdown/markdown_math_widgets.dart`
   放置 `MarkdownInlineMath` 与 `MarkdownBlockMath`，封装 `flutter_math_fork`、滚动和失败降级。

`FlutterMarkdownImpl` 只负责注册 syntax 与 builder，不承担公式解析细节。

## 失败降级

当 TeX 解析失败时：

1. 不抛出到页面层，不让消息渲染失败。
2. 显示原始公式文本。
3. 块级公式保留块级容器和滚动能力。
4. 测试中覆盖至少一个非法公式，例如 `\frac{1}`。

## 测试策略

1. 单测行内语法识别：`$E = mc^2$`、`\(...\)` 能生成 `math-inline`；`$12.99`、`$HOME` 不应误判。
2. 单测块级语法识别：`$$...$$`、`\[...\]` 能生成 `math-block`。
3. Widget 测试公式组件：正常公式出现 `Math` 渲染组件；错误公式显示原始文本。
4. 集成测试 `FlutterMarkdownImpl`：普通 Markdown、Callout、blockquote、code block 不受影响。
5. 长块级公式测试：存在横向滚动容器，避免溢出。

## 验收标准

1. AI 回复中的常见行内公式和块级公式能在 `FlutterMarkdownImpl` 中正常渲染。
2. 普通美元金额和 Shell 变量不会被公式语法吞掉。
3. 错误公式不会导致整条消息空白或崩溃。
4. 块级公式在手机宽度下不会横向溢出屏幕。
5. 目标 Markdown 测试和相关聊天块测试通过，目标 analyzer 无问题。
