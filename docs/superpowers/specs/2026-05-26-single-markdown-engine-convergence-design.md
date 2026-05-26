# 单引擎 Markdown 渲染收敛设计

## 背景

当前项目中的 Markdown 渲染已经不是两套独立、清晰可替换的实现，而是一个“统一入口 + 内容分流 + 局部共享部件 + 分支内定制 patch”的混合系统：

- [FlutterMarkdownImpl](/Users/zyb_wl/flutterSpace/FlutterAIChat/lib/widgets/markdown/flutter_markdown_impl.dart) 作为统一入口，根据内容是否包含表格、是否包含数学公式来决定走哪条底层渲染链。
- 普通 Markdown 走 `flutter_markdown`。
- 含表格且不含数学公式的 Markdown 走 [MarkdownWidgetImpl](/Users/zyb_wl/flutterSpace/FlutterAIChat/lib/widgets/markdown/markdown_widget_impl.dart)，底层依赖 `markdown_widget`。
- 两条路径共享 `AppTypography`、`AppThemeSpec`、`CodeBlockWidget` 等上层视觉资产，但基础段落、列表、强调、表格等 block 的实现语义并不统一。

这导致了一个结构性问题：

- “消息里是否有表格”会决定整条消息的段落、列表、加粗、引用等基础排版落到不同引擎。
- 基础阅读问题会被误判成表格问题。
- 新增 Markdown 能力时，主路径和表格路径会持续漂移。

本次 Android 真机定位中，列表字号异常正是因为消息中包含表格后整条消息切入了 `markdown_widget` 路径，而不是单纯的列表样式问题。

## 目标

本次改造目标是将 Markdown 渲染收敛为**单引擎架构**：

- 移除 `FlutterMarkdownImpl -> MarkdownWidgetImpl` 的内容分流。
- 让所有 Markdown 消息统一走 `flutter_markdown` 路径。
- 删除 `MarkdownWidgetImpl` 及其专属行为 patch。
- 接受表格视觉会先回落到 `flutter_markdown` 默认能力上限，但保证基础排版语义统一。
- 在后续迭代中，于同一条 `flutter_markdown` 渲染链中增强表格体验，而不再引入第二套 Markdown 引擎。

## 非目标

- 本次不要求一步到位恢复当前 `markdown_widget` 路径下的全部表格观感。
- 本次不处理 artifact、HTML 预览、inline artifact、WebView 等非 Markdown 渲染链。
- 本次不重做 code block、math、callout 的功能语义；仅保证它们继续在单引擎路径下工作。
- 本次不改消息模型、持久化结构、聊天页布局、controller/provider 架构。

## 方案对比

### 方案 A：保留双引擎，只修列表/正文漂移

做法：

- 保留 `FlutterMarkdownImpl` 分流。
- 继续修 `MarkdownWidgetImpl` 中的列表、段落、强调、表格细节。

优点：

- 表格当前观感保持最稳定。

缺点：

- 长期继续维护两套 Markdown 语义。
- “有表格就换整套 renderer”的结构问题不解决。
- 后续 math、callout、code、list 等问题还会反复出现。

### 方案 B：单引擎收敛，表格先降级后增强

做法：

- 删除 `MarkdownWidgetImpl` 分流。
- 所有 Markdown 一律走 `flutter_markdown`。
- 先保证基础排版一致性与可维护性。
- 后续在 `flutter_markdown` 路径内单独增强表格。

优点：

- 彻底消除“表格决定整条消息换引擎”的问题。
- 基础排版只保留一条真相来源。
- 后续功能扩展与测试结构都更简单。

缺点：

- 短期内表格视觉可能比当前特化分支更朴素。

### 方案 C：单引擎收敛，同时补一套新的 `flutter_markdown` 表格增强层

做法：

- 与方案 B 一样去掉 `MarkdownWidgetImpl`。
- 在同一次改造中同步补齐自定义表格增强组件或表格 wrapper。

优点：

- 最终形态更理想。

缺点：

- 一次性交付面更大。
- 排查问题时难区分是“收敛问题”还是“新表格增强问题”。

### 推荐

推荐方案 B。

原因：

- 当前最主要的问题不是表格本身，而是双引擎导致的基础排版不一致。
- 先做“单引擎收敛”，可以最快恢复 Markdown 系统的结构清晰度。
- 表格增强是局部能力，后续在单引擎内补足更稳妥。

## 目标架构

### 一、统一入口保留

[FlutterMarkdownImpl](/Users/zyb_wl/flutterSpace/FlutterAIChat/lib/widgets/markdown/flutter_markdown_impl.dart) 继续作为唯一 Markdown 渲染入口。

但其职责收敛为：

- 负责 `flutter_markdown` 的 AST 扩展配置。
- 负责 `MarkdownStyleSheet` 的文档阅读样式。
- 负责 code block、math、callout 等局部 block builder 的挂载。

它不再承担“根据内容决定切换底层引擎”的职责。

### 二、移除表格专用第二引擎

[MarkdownWidgetImpl](/Users/zyb_wl/flutterSpace/FlutterAIChat/lib/widgets/markdown/markdown_widget_impl.dart) 以及其专用列表 patch 不再保留在主渲染链中。

这意味着：

- `markdown_widget` 不再是 Markdown 时间线渲染的运行时依赖入口。
- “表格消息”和“非表格消息”回到同一套段落、列表、强调、引用语义。

### 三、表格恢复为单引擎内的局部 block

表格在架构上应被视为：

- 同一 Markdown 引擎中的一个 block 类型
- 而不是触发整条消息切换 renderer 的内容特征

本次先接受 `flutter_markdown` 原生 table 能力与现有样式配置带来的观感。
后续若需要继续优化，应在 `FlutterMarkdownImpl` 这条路径里做：

- 样式增强
- cell padding 调整
- 横向滚动包装
- 边缘渐隐
- 自定义 table builder / wrapper

而不是重新引入第二套完整 Markdown 渲染器。

## 需要修改的模块边界

### 1. 渲染入口

- 修改 [flutter_markdown_impl.dart](/Users/zyb_wl/flutterSpace/FlutterAIChat/lib/widgets/markdown/flutter_markdown_impl.dart)

需要完成：

- 删除 `_containsMarkdownTable` 分流逻辑
- 删除 `MarkdownWidgetImpl` 依赖
- 所有 Markdown 内容统一走 `MarkdownBody`

### 2. 表格特化实现

- 删除或废弃 [markdown_widget_impl.dart](/Users/zyb_wl/flutterSpace/FlutterAIChat/lib/widgets/markdown/markdown_widget_impl.dart)

需要完成：

- 停止被运行时引用
- 清理其专属列表 patch / TableConfig / MarkdownGenerator 覆写

### 3. 表格附属视觉部件

- 评估 [table_edge_fade_scroll_shell.dart](/Users/zyb_wl/flutterSpace/FlutterAIChat/lib/widgets/markdown/table_edge_fade_scroll_shell.dart) 是否仍被其他地方使用

本次策略：

- 如果仅服务 `MarkdownWidgetImpl`，可先移除或暂时保留但不再运行时引用
- 后续若在 `flutter_markdown` 路径里重建表格增强，再决定是否复用

### 4. 测试层

- 修改 [test/widgets/chat_blocks/chat_blocks_test.dart](/Users/zyb_wl/flutterSpace/FlutterAIChat/test/widgets/chat_blocks/chat_blocks_test.dart)

需要完成：

- 删除“表格应该走 `MarkdownWidgetImpl`”的断言
- 改为断言“表格仍走 `MarkdownBody`，并能渲染 `Table`”
- 统一围绕单引擎结果做验证

### 5. 文档层

- 更新旧的 Hybrid Reader / Markdown 设计与计划中涉及双路径定位的描述
- 至少在新的 spec / implementation plan 中明确：
  - `flutter_markdown` 是唯一 Markdown 主实现
  - 表格增强以后作为局部能力处理

## 主要影响分析

### 影响较小的部分

以下能力本来就主要在 `FlutterMarkdownImpl` 主链上：

- 段落
- 标题
- 引用
- `strong` / `em`
- code block
- callout
- math

因此单引擎收敛后，它们整体会更稳定，而不是风险更大。

### 影响最大的部分

风险主要集中在表格：

- 表格视觉可能回退为更朴素的 `flutter_markdown` 样式
- 表格横向体验不如当前 `markdown_widget` 特化方案
- 表格 cell padding、外壳背景、边缘渐隐会暂时丢失或减弱

但这是可控风险，因为它被局限在**表格 block 本身**，不会再外溢到整条消息的列表/段落/强调语义。

## 实施策略

### 阶段 1：完成单引擎收敛

目标：

- 不再让表格决定整条消息切换引擎
- 删除 `MarkdownWidgetImpl` 运行时路径
- 保证所有现有非表格增强功能继续工作

验收标准：

- 所有 Markdown 消息统一走 `MarkdownBody`
- 表格消息中的列表、标题、引用、强调与普通消息完全同源
- 原有 math、callout、code block 相关测试继续通过

### 阶段 2：评估表格视觉回退

目标：

- 在真实页面、真机截图中确认表格回退后的实际问题清单

输出：

- 是否需要继续做表格增强
- 如果要做，明确是简单样式微调，还是引入自定义 table wrapper

### 阶段 3：在单引擎内增强表格

后续可能方向：

- 利用 `MarkdownStyleSheet.table*` 配置先提升基础观感
- 若不够，再做单独表格包装能力
- 仍然保持在 `flutter_markdown` 主链内，不恢复第二引擎

## 风险与缓解

### 风险 1：表格观感短期回退明显

缓解：

- 在 spec 中明确这是可接受的阶段性代价
- 真机验证后再决定是否立即补表格增强

### 风险 2：删除分流后旧测试大面积失效

缓解：

- 先重写测试目标，从“走哪条分支”改为“最终渲染结果正确”
- 只删除与 `MarkdownWidgetImpl` 强绑定的断言，不削弱表格渲染验证

### 风险 3：运行时还有其他隐式引用 `MarkdownWidgetImpl`

缓解：

- 在实施前用全文搜索确认引用点
- 实施中先删除入口引用，再清理残留测试和未使用文件

## 验收标准

- `FlutterMarkdownImpl` 不再根据是否含表格切换到底层第二引擎
- `MarkdownWidgetImpl` 不再参与聊天 Markdown 运行时渲染
- 表格消息仍能渲染为 `Table`
- 表格消息中的列表、正文、强调与普通 Markdown 消息保持同一渲染语义
- 现有 Markdown 相关 widget tests、theme tests、chat block tests 通过
- Android 真机上“有表格消息中的列表排版漂移”问题不再由双引擎切换造成

