# Markdown 节奏与技术内容块统一设计

## 背景

当前聊天时间线中的 Markdown 渲染方向已经基本成立，尤其表格已经从“线框表格”调整为更接近文档阅读面的结构化数据块。但从真实设备截图与现有实现看，整体仍存在以下问题：

- 同一段 Markdown 内部的垂直节奏不稳定，部分段落、标题、列表、引用、分割线之间偏紧，部分区域又偏松。
- 普通 Markdown 与“含表格 Markdown”走两套渲染路径，段落、引用、代码块、列表等细节容易持续漂移。
- fenced code、CLI/命令块、Edit/Write tool 的文件预览、diff 预览不属于同一视觉家族，造成同类技术内容呈现割裂。
- 当前深色代码块与浅色 tool preview 并存，会削弱“文档阅读面”这一核心产品气质。

## 目标

本轮改造目标是把 Markdown 区域收敛成一个更稳定的“文档阅读系统”，并把代码/文件预览等技术内容统一为同一视觉语法。

需要达成的结果：

- Markdown 的段落、标题、列表、引用、分割线、表格在纵向节奏上更统一，偏向“稍松、稳定、可连续阅读”。
- 代码块、命令块、Edit/Write tool 内部预览、diff 预览收敛为同一类“技术内容块”。
- 继续保持表格当前的文档化方向，不回退到线框风。
- 普通 Markdown 与含表格 Markdown 的共享 token 增加，减少长期视觉漂移。

## 非目标

- 不重做聊天页整体布局，不修改顶部栏、输入栏、消息宽度策略。
- 不重设计 tool workflow 外层卡片结构，只统一其中的技术内容预览家族。
- 不引入新的 Markdown 渲染库，也不移除现有 `flutter_markdown` / `markdown_widget` 双路径结构。

## 设计原则

### 1. 阅读优先，块感克制

Markdown 区域首先是一个文档阅读面，而不是一组展示组件。视觉层级应更多依赖留白、轻微表面差、文本节奏，而不是厚边框、深色大卡片或强对比条带。

### 2. 特殊内容是正文嵌入块，不是独立模块

引用、代码、表格、文件预览都应被理解为正文中的嵌入内容。它们可以更突出，但不应像完全独立的卡片系统那样与正文割裂。

### 3. 技术内容块必须同一家族

以下内容在用户感知中都属于同类信息，应共享视觉语言：

- fenced code
- CLI/命令输出
- Edit/Write tool 内部文件内容预览
- diff/file preview
- 未来其他预格式化技术内容块

它们不必完全相同，但必须共用：

- 同一套圆角等级
- 同一套表面明度逻辑
- 同一套内容 padding
- 同一套滚动提示逻辑
- 同一套标题栏/标签栏语气
- 同一套代码字体、字号、行高基准

## 方案对比

### 方案 A：继续局部修补现有每个组件

做法：

- 单独调 `FlutterMarkdownImpl` 的 spacing
- 单独把 `CodeBlockWidget` 改浅色
- 单独把 `FileChangePreview` 改浅色

优点：

- 改动快
- 风险低

缺点：

- 仍然没有共享“技术内容块”基础层
- 后续新增 preview / code surface 时还会重复漂移

### 方案 B：抽一层共享技术内容块样式并统一节奏

做法：

- 新增共享技术内容块 surface/widget/style helper
- `CodeBlockWidget`、`markdown_widget` 的 `PreConfig`、`FileChangePreview` 共用该层
- 同时把 Markdown 主节奏 token 整体放松并拉齐

优点：

- 能同时解决“家族感”和“节奏感”
- 后续新增技术块时可继续复用

缺点：

- 改动面比 A 稍大

### 方案 C：统一回单一 Markdown 渲染器

做法：

- 尝试让所有 Markdown 都回到一条 renderer 链路

优点：

- 理论上一致性最高

缺点：

- 当前不必要
- 对现有表格和代码块能力风险更大

### 推荐

推荐方案 B。

原因是本次问题的核心不是某一个组件不好看，而是“阅读节奏”和“技术内容块家族”两个横向问题。只有抽共享层，才能让 code block、tool preview 和未来其他技术内容真正收敛。

## 目标结构

### 一、Markdown 主节奏

#### 段落

- 正文段落保持 `13px` 左右字号不变。
- 通过增加 block 间距，而不是单纯增大字高，来获得更轻松的阅读感。
- 段落之间的间距比当前略增。

#### 标题

- 保持现有标题字号体系，不再明显放大。
- 通过增加标题前后 padding 建立章节感。
- 标题字重比当前略轻，避免“粗标签感”。

#### 列表

- 列表项内部行高保持舒适。
- 列表整体上下留白增加，让其成为“更容易扫读的区域”。

#### 引用

- 引用块弱化提示框感，保留左侧竖条但更轻。
- 背景色进一步淡化。
- 引用前后节奏略大于段落，但小于代码块。

#### 分割线

- 分割线自身继续保留，但视觉存在感下降。
- 分割线前后留白比当前略收，避免内容被切得太碎。

### 二、技术内容块

#### 统一定义

技术内容块是一种共享表面类型，用于承载需要等宽字体、可能横向滚动、通常带轻量操作或标签的内容。

统一表现：

- 浅色文档嵌入表面为默认方向
- 柔和圆角
- 轻量 header/label 区
- 轻边界或无边界，避免深色强框
- 当发生横向溢出时，用与表格一致的边缘提示语法

#### fenced code

- 由当前深色终端感改为浅色文档嵌入感
- 保留语言标记、复制、自动换行操作
- 顶栏高度与 tool preview 的标题带语言一致

#### FileChangePreview / diff preview

- 外壳与 fenced code 共用同一技术内容表面
- 增删行仍保留语义色，但整体表面不再像另一套组件
- 行号、行高、代码字体与 fenced code 对齐

#### markdown_widget 路径中的 pre

- 不再走与 `CodeBlockWidget` 明显不同的另一套样式
- 应直接复用统一 code block 组件，避免“含表格回答”与“普通回答”代码块气质不同

### 三、普通 Markdown 与表格 Markdown 的共享层

保留双渲染路径，但统一以下 token：

- body 字体与字号
- 标题字重与字号
- 列表缩进与行高
- 引用 padding / margin / tone
- 代码块统一组件
- 表格外壳与技术内容块在表面语气上保持相邻但不完全相同

## 文件边界建议

### 需要新增

- `lib/widgets/technical_content_surface.dart`
  - 共享技术内容块表面与色彩/圆角/内边距语法

### 需要修改

- `lib/widgets/markdown/flutter_markdown_impl.dart`
  - 调整 Markdown 主节奏 token
- `lib/widgets/markdown/markdown_widget_impl.dart`
  - 与普通 Markdown 路径对齐节奏，并复用统一 code block
- `lib/widgets/markdown/code_widget.dart`
  - 将 fenced code 收敛为共享技术内容块
- `lib/widgets/tool_renderers/file_change_preview.dart`
  - 复用共享技术内容块
- `test/widgets/chat_blocks/chat_blocks_test.dart`
  - 更新 Markdown 节奏与 code surface 相关测试
- `test/widgets/tool_renderers/write_tool_cards_test.dart`
  - 补技术内容块统一测试
- 视实现需要补充 `edit_tool_cards_test.dart`

## 验收标准

- 真机截图中，Markdown 的标题、列表、引用、段落节奏明显比当前更统一。
- 普通 fenced code 与含表格回答中的 code block 样式一致。
- `Edit/Write` tool 中的文件预览与 code block 属于同一家族。
- 表格继续保持当前文档化方向，不回退到线框风。
- 所有相关 widget 测试通过，且 `flutter analyze` 无问题。

## 风险与缓解

### 风险 1：节奏放松过头，导致消息变得过长

缓解：

- 只放松 block 间距，不显著增大正文行高
- 通过截图与真机验证控制密度

### 风险 2：统一技术内容块后，tool preview 信息识别度下降

缓解：

- 外层 workflow/result card 仍保留 tool 语义
- 仅统一内部技术内容承载层

### 风险 3：双渲染路径继续漂移

缓解：

- 本轮至少把共享 token 抽出来
- 让 code block 直接复用同一组件

## 测试策略

- Widget test 验证 Markdown 主节奏 token 更新
- Widget test 验证 code block 使用共享技术内容块
- Widget test 验证 Write/Edit preview 使用共享技术内容块
- 相关 Markdown/time line/tool renderer 测试回归
- `flutter analyze` 检查新增共享层无 lint 问题
