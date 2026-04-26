# Markdown Callout 语义块设计

## 背景

`FlutterMarkdownImpl` 已经完成 Hybrid Reader 阅读底座：正文、标题、列表、引用/旁注和流式态节奏都更接近专业文档阅读面。下一阶段需要在不破坏普通 Markdown 阅读体验的前提下，增加更明确的语义块表达能力。

Callout 的目标不是把回答变成卡片集合，而是让 AI Chat 中高频出现的“补充说明、建议、风险、结论、来源”等内容获得稳定、低噪声、可扫读的文档结构。

## 目标

- 在 `flutter_markdown` 路径支持 Markdown Callout 语义块。
- 保留普通 `>` 引用作为 Hybrid Reader 的轻量旁注。
- 支持少量高频专属语义，同时允许未知语义优雅降级。
- 让 Callout 成为正文内嵌语义块，而不是独立卡片系统。
- 为后续公式、图表、Mermaid 等正文嵌入块延续一致的设计原则。

## 非目标

- 不处理 `markdown_widget` 表格路径。
- 不新增公式、图表、Mermaid 或折叠块能力。
- 不改动消息模型、数据库结构或 tool result 结构化卡片。
- 不通过提示词硬编码大量特殊语义路由。
- 不把普通引用强制升级成 Callout。

## 语法

采用 GitHub / Obsidian 风格的 blockquote callout 语法。

### 标准形式

```md
> [!NOTE]
> 这是补充说明。
```

### 带标题形式

```md
> [!WARNING] 数据限制
> 这个结论只基于当前样本。
```

### 未知类型形式

```md
> [!EXAMPLE] 示例
> 这里展示一个具体用法。
```

未知类型不退回普通引用，而是渲染为通用 Callout，并保留原始类型或自定义标题。

## 语义集合

### 专属类型

#### `NOTE`

用于补充说明、背景、上下文、非阻断性提醒。视觉应接近中性信息块。

#### `TIP`

用于建议、最佳实践、下一步操作、使用技巧。视觉可略有积极倾向，但不能显得活泼或营销化。

#### `WARNING`

用于风险、限制、注意事项、可能失败的条件。视觉需要比其他类型更容易被注意到，但不能做成强红色警报盒。

#### `RESULT`

用于结论、执行结果、最终判断、验证结果。它不是传统 Markdown 标准类型，但非常适合 AI Chat 的回答结构。

#### `SOURCES`

用于来源、引用、参考链接。它应更像文档尾注或来源说明，而不是高强调信息块。

### 通用类型

#### `INFO`

通用信息块。适合无法明确归入专属类型，但仍需要结构化承载的信息。

#### `CALLOUT`

显式通用语义块。适合模型或后续工具已经知道要创建语义块，但不想指定专属类型的场景。

### 未知类型

任意 `[!XXX]` 都应被识别为 Callout，并按通用类型渲染。

降级规则：

- `rawType` 保留原始类型，例如 `EXAMPLE`、`QUESTION`、`IMPORTANT`。
- 如果有自定义标题，优先显示自定义标题。
- 如果没有自定义标题，可以显示 `rawType` 作为 label。
- 未知类型不应显示错误态，也不应回退成普通引用。

这种设计避免“被覆盖语义有漂亮样式，未覆盖语义退回普通文本”的割裂感。

## 普通引用与 Callout 的边界

### 普通引用

普通 `>` 继续表示旁注、引用句、短约束、补充信息。

特点：

- 没有 header。
- 背景轻。
- 只有细竖线作为语义提示。
- 视觉上从属于正文。

### Callout

只有以 `[!TYPE]` 开头的 blockquote 才升级为 Callout。

特点：

- 有轻量 header 或 label。
- 有语义类型。
- 背景强于普通引用，但弱于技术内容块。
- 视觉上仍然是正文嵌入块。

## 视觉方向

Callout 应延续 Hybrid Reader 的“安静、专业、文档优先”方向。

### 结构

建议结构：

- 外层：低噪声语义表面。
- 顶部：小号 label / title 行。
- 内容：正文风格，字号与段落接近。
- 左侧：可选细竖线或轻色带。
- 图标：可选，必须克制，优先使用熟悉的 Material / Lucide 等价符号。

### 色彩

色彩应来自语义 token，而不是散落 hex。

建议语气：

- `NOTE`：中性灰绿 / slate。
- `TIP`：柔和正向绿。
- `WARNING`：低饱和琥珀 / 棕金。
- `RESULT`：稳定成功绿或沉稳蓝绿。
- `SOURCES`：低调中性，接近尾注。
- 未知类型：通用中性信息色。

任何类型都不应使用高饱和警示色、荧光色、大面积纯色背景或强边框。

### 密度

Callout 的垂直节奏应略大于普通引用，但小于代码块或技术内容块。

建议：

- 前后留白略大于段落。
- 内部 padding 不宜过厚。
- 标题与正文之间保持短距离。
- 多个 Callout 连续出现时不应形成卡片堆叠感。

## 实现方向

不推荐覆盖内置 `blockquote` builder。当前 `flutter_markdown 0.6.23` 中，`blockquote` 是内置 block tag，最终外壳由 `MarkdownBuilder` 内部固定处理：

- `blockquote` 会设置 `_isInBlockquote`。
- 完成时被包装为 `DecoratedBox -> Padding -> child`。
- 自定义 `builders['blockquote']` 不能干净替换整个 blockquote 外壳。

推荐新增自定义 block syntax。

### 新增 `CalloutBlockSyntax`

职责：

- 识别 `> [!TYPE] 可选标题`。
- 消费后续同一 blockquote 中的内容行。
- 将内容解析为自定义 AST element：`callout`。
- 在 attributes 中保存：
  - `type`：归一化后的类型。
  - `rawType`：原始类型。
  - `title`：可选标题。

建议识别规则：

```text
^\s*>\s*\[!([A-Za-z][A-Za-z0-9_-]*)\]\s*(.*)?$
```

类型归一化：

- 转大写。
- 去除首尾空白。
- `INFO` / `CALLOUT` 归入通用类型。
- 未知类型保留 `rawType`，`type` 可设为 `CALLOUT`。

### 新增 `MarkdownCalloutBuilder`

职责：

- `isBlockElement() => true`。
- 读取 `callout` element attributes。
- 将 AST 子节点渲染为 `MarkdownCalloutBlock`。
- 不影响普通 `blockquote`。

### 新增 `MarkdownCalloutBlock`

职责：

- 负责视觉呈现。
- 接收 type、rawType、title、content。
- 从 reader/callout tokens 获取字体、颜色、padding、边框。

第一版可以让内容以纯文本或受限 inline 内容展示；如果要完整支持 Callout 内部 Markdown，需要在实现计划里单独验证 `flutter_markdown` 对自定义 block element 的子节点渲染能力。

## MVP 边界

第一版支持：

- 单个标准 Callout 块。
- 带标题 Callout。
- 多行文本内容。
- 未知类型降级。
- 普通引用保持原样。
- 浅色和深色主题基础适配。

第一版不优先支持：

- Callout 内嵌套另一个 Callout。
- Callout 内表格。
- Callout 内复杂多层列表。
- 折叠语法，例如 `[!NOTE]-`。
- 非 blockquote 语法，例如 `:::note`。
- 与 tool workflow 卡片联动。

## 与 Sources 的关系

当前工具描述已经要求联网搜索最终答复包含 `Sources:` 小节。Callout 能力上线后，可以允许模型使用：

```md
> [!SOURCES] Sources
> - [Title](https://example.com)
```

但这不应立即强制替换所有 `Sources:` 文本小节。建议先支持渲染能力，再在后续 prompt 层考虑是否引导模型优先使用 `[!SOURCES]`。

## 测试策略

### Parser / syntax 测试

验证：

- `> [!NOTE]` 被识别为 `callout`。
- `> [!WARNING] 数据限制` 保存标题。
- `> [!EXAMPLE] 示例` 按通用类型降级，并保留 `rawType`。
- 普通 `> 引用` 不被识别为 Callout。

### Widget 测试

验证：

- `FlutterMarkdownImpl` 渲染 NOTE/TIP/WARNING/RESULT/SOURCES。
- 未知类型渲染为通用 Callout。
- 普通 blockquote 仍使用旁注样式。
- Callout 不走 `MarkdownWidgetImpl` 表格路径。

### 回归测试

运行：

- `test/widgets/chat_blocks/chat_blocks_test.dart`
- `test/widgets/chat_timeline/stable_markdown_block_test.dart`
- `test/widgets/chat_message_list_test.dart`

如果实现触碰 parser 或渲染路径较多，再补充 `flutter analyze` 和更广泛 widget 测试。

## 风险与缓解

### 风险 1：BlockSyntax 边界复杂

Markdown blockquote 支持懒续行、嵌套列表、空行等复杂规则。Callout MVP 不应一开始复刻完整 CommonMark blockquote 行为。

缓解：

- 先支持标准 `>` 前缀多行形式。
- 对复杂嵌套明确回退或保持文本。
- 用测试锁住 MVP 行为。

### 风险 2：Callout 变成视觉噪声

如果模型频繁输出 Callout，页面可能变成卡片堆。

缓解：

- 视觉保持低噪声。
- prompt 层后续只建议在确有语义需要时使用。
- 普通补充说明仍可使用正文或普通引用。

### 风险 3：未知类型表现不一致

如果未知类型回退到普通引用，会造成用户感知割裂。

缓解：

- 任何 `[!XXX]` 都渲染为通用 Callout。
- 保留 `rawType` 用于 label。

## 验收标准

- `NOTE`、`TIP`、`WARNING`、`RESULT`、`SOURCES` 能被识别并渲染为语义块。
- `INFO` / `CALLOUT` 能作为通用语义块。
- 未知 `[!XXX]` 不报错、不退回普通引用，按通用 Callout 呈现。
- 普通 `>` 引用仍保持 Hybrid Reader 旁注风格。
- Callout 视觉上强于普通引用、弱于技术内容块。
- 手机宽度下 Callout 内容不拥挤。
- 相关 widget 测试通过。
