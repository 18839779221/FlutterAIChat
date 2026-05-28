# 文档排版调试页设计

## 背景

当前文档排版问题主要出现在“大模型回复中的 Markdown 文档块”这一类内容上，但现有调试方式依赖真实对话、真实模型输出和运行时上下文，存在几个明显问题：

- 同一问题难以稳定复现，因为模型回复内容、长度、结构都会漂移。
- UI 调整后缺少固定回归样例，容易出现“修好一个样式，打坏另一个样式”的情况。
- 现有 debug case 更偏发送链路、agent loop 和交互流程，不适合做纯渲染层排版回归。

仓库中已经有成熟的真实渲染组件，例如 [AssistantDocBlock](/Users/zyb_wl/flutterSpace/FlutterAIChat/lib/widgets/chat_blocks/assistant_doc_block.dart) 与 [FlutterMarkdownImpl](/Users/zyb_wl/flutterSpace/FlutterAIChat/lib/widgets/markdown/flutter_markdown_impl.dart)。因此本次不应该再造一套“近似 UI”，而应该提供一个稳定的、脱离 LLM 的真实渲染调试页。

## 目标

- 提供一个独立路由页面，用于稳定调试文档排版效果。
- 页面不依赖真实 LLM 回复、数据库消息或发送链路。
- 首版直接复用真实助手回复渲染组件，保证调试结果与聊天时间线中的真实效果一致。
- 内容由仓库内固定构造案例提供，确保每次打开都能稳定复现。
- 数据结构为后续接入 tool card、artifact block 或混合时间线保留扩展空间。

## 非目标

- 本次不构建完整对话模拟器，不回放多轮 transcript。
- 本次不加入运行时 Markdown 编辑器、JSON 编辑器或持久化草稿功能。
- 本次不接入真实消息表、chat_turns、chat_events 或任何会话上下文服务。
- 本次不处理 LLM 请求、模型设置、发送按钮或任何“从输入到回复”的链路。
- 本次不把调试入口混入正式聊天流程，只作为开发期显式路由存在。

## 方案对比

### 方案 A：独立页面，直接硬编码几个示例 widget

做法：

- 新增一个独立 page。
- 页面里手写几个 `AssistantDocBlock(...)` 示例。

优点：

- 起步最快。

缺点：

- 样例会散落在页面实现里，后续很难维护。
- 新增 tool card 或混合场景时容易失控。
- 不利于复用到测试或未来的其他调试入口。

### 方案 B：独立页面，固定案例库驱动真实 block 渲染

做法：

- 新增独立 page 和一组固定 debug cases。
- 页面通过 case 切换，渲染真实 block 组件。
- block 数据结构首版只支持 `assistantDoc`，但保留 `type` 扩展位。

优点：

- 稳定、可回归、边界清晰。
- 结构上足以平滑扩展到 tool card。
- 页面、测试、案例数据都能共用同一批构造样例。

缺点：

- 需要先补一层轻量数据模型与 block 分发。

### 方案 C：独立页面，完整时间线 JSON 驱动

做法：

- 从一开始就建模整段 assistant timeline。
- 调试页通过 JSON/asset 回放完整消息列表和工具卡片混排。

优点：

- 最终扩展性最强。

缺点：

- 首版成本明显偏高。
- 当前目标是文档排版回归，不值得提前实现时间线模拟器。

### 推荐

推荐方案 B。

原因：

- 它已经满足“稳定调试文档排版”的核心目标。
- 它能直接复用真实组件，避免 mock UI 与生产 UI 漂移。
- 它保留了向 tool card 混排演进的结构，不会把首版做成死路。

## 页面职责与入口

### 一、独立路由页面

新增独立页面，例如：

- [layout_debug_page.dart](/Users/zyb_wl/flutterSpace/FlutterAIChat/lib/pages/layout_debug_page.dart)

并在现有路由中注册固定入口。当前仓库已有 [RouteConstant](/Users/zyb_wl/flutterSpace/FlutterAIChat/lib/constants/route_constant.dart) 与 `MaterialApp.routes` 注册方式，因此本次延续相同模式，不额外引入新的导航框架。

### 二、与现有 `testPage` 的关系

当前 [test_page.dart](/Users/zyb_wl/flutterSpace/FlutterAIChat/lib/pages/test_page.dart) 只是零散实验页，不承载真实回复排版调试职责。

本次不建议在旧 `testPage` 上继续堆功能，而是：

- 新增明确语义的文档排版调试页路由。
- 保持 `testPage` 不作为该能力的正式入口。

原因是“代码高亮试验页”和“真实助手回复排版回归页”属于不同职责，混在一起会继续放大历史实验代码。

### 三、页面职责边界

页面只负责三件事：

- 展示内置案例列表。
- 根据当前选择渲染真实回复块。
- 为视觉排查提供极少量辅助信息，例如 case 名称、说明、block 数量。

页面不负责：

- 生成内容。
- 编辑内容。
- 保存调试状态到数据库。
- 参与聊天发送与 agent loop。

## 数据模型设计

### 一、案例模型

新增轻量 debug model，例如：

- `LayoutDebugCase`

建议字段：

- `id`：稳定 case 标识，用于切换和测试定位。
- `title`：案例标题，用于列表和页面头部展示。
- `description`：案例说明，描述当前案例覆盖的排版风险点。
- `blocks`：该案例要渲染的一组 block。

首版不需要加筛选标签、优先级、编辑时间等额外元数据，避免过度设计。

### 二、Block 模型

新增统一 block 模型，例如：

- `LayoutDebugBlock`

关键要求：

- block 必须显式带 `type`，而不是依赖字段推断。
- 首版仅实现 `assistantDoc` 分支。
- 结构上预留后续新增 `toolWorkflow`、`toolResult`、`artifact`、`reasoningOnly` 等类型。

首版 `assistantDoc` block 建议字段：

- `label`：映射真实 `AssistantDocBlock.label`。
- `reasoningText`：映射真实 `AssistantDocBlock.reasoningText`。
- `markdownText`：映射真实 `AssistantDocBlock.text`。
- `markdownCacheKey`：可选。默认可由调试页按 case/block 派生，便于复用稳定 markdown cache 行为。

### 三、数据源位置

首版案例数据建议放在 Dart 常量文件中，而不是 asset JSON。

推荐原因：

- 首版改动更小，避免引入额外 loader 和 asset 声明。
- 多行 Markdown 在 Dart 原始字符串中更易维护。
- 类型安全更好，页面和测试都能直接 import 使用。

可以新增例如：

- `lib/debug/layout_debug_cases.dart`

当未来案例数量明显增长，或需要让非开发同学维护时，再评估迁移到 asset JSON。

## 渲染架构

### 一、复用真实渲染组件

调试页必须直接复用真实 UI 组件，不创建平行 mock 实现。

首版核心复用链路：

- [AssistantDocBlock](/Users/zyb_wl/flutterSpace/FlutterAIChat/lib/widgets/chat_blocks/assistant_doc_block.dart)
- [StableMarkdownBlock](/Users/zyb_wl/flutterSpace/FlutterAIChat/lib/widgets/chat_timeline/stable_markdown_block.dart)
- [FlutterMarkdownImpl](/Users/zyb_wl/flutterSpace/FlutterAIChat/lib/widgets/markdown/flutter_markdown_impl.dart)

这样可以确保调试页中看到的：

- 文档容器内边距
- label 区块
- reasoning 区块
- Markdown 主体排版

与真实聊天时间线保持一致。

### 二、Block 分发器

页面内部需要一个轻量 block renderer，例如：

- `_buildBlock(LayoutDebugBlock block)`

它的职责只是按 `type` 分发到对应真实组件，不承载业务逻辑。

首版只需一条分支：

- `assistantDoc -> AssistantDocBlock`

后续如果要支持 tool card，只是在同一分发器中新增分支，不需要推翻页面结构。

### 三、页面布局

页面布局建议保持朴素、强调可读性：

- 桌面/宽屏：左侧案例列表，右侧预览区域。
- 窄屏：顶部 case picker，下方预览区域。

重点不是设计一个新花样 UI，而是提供稳定的对比和切换体验。预览区域应让 block 在接近真实聊天阅读宽度的容器内渲染，避免“全屏无限宽”导致的假象。

## 首批案例建议

首版至少准备以下固定案例：

### 1. 基础长文案例

覆盖：

- 一级到三级标题
- 普通段落
- 粗体、斜体、删除线
- 有序列表、无序列表
- 引用块

目的：

- 验证基础阅读节奏、段落间距与标题层级。

### 2. 复杂结构案例

覆盖：

- 表格
- 代码块
- 行内代码
- 分割线
- 普通链接

目的：

- 验证技术文档类回复中的主要复杂 block。

### 3. 边界压力案例

覆盖：

- 超长表格列名或超长单元格内容
- 超长代码行
- 超长单词或 URL
- 连续多级标题与密集段落

目的：

- 暴露换行、横向溢出、边距挤压和滚动壳问题。

### 4. 完整助手回复案例

覆盖：

- `label + reasoning + markdown` 同时出现

目的：

- 以最接近真实 assistant 文档回复的形式验证整体节奏，而不只是 Markdown 主体。

### 5. 预留扩展案例名

可以预留一个 `mixed-future` 之类的案例占位，但首版不实际渲染 tool card。其存在只是提醒后续扩展方向，不要求现在交付混排能力。

## 测试策略

### 一、Widget Test

首版优先补 widget test，验证：

- 页面可以正常打开。
- 默认案例能渲染。
- 切换案例后内容会更新。
- 页面复用了真实 `AssistantDocBlock`，而不是替身 widget。

可新增例如：

- `test/pages/layout_debug_page_test.dart`

### 二、测试关注点

测试重点应放在结构和可达性，而不是像素级视觉快照：

- case 标题是否出现
- case 切换是否生效
- 指定 markdown 片段是否可见
- 指定 reasoning 文案是否可见
- 指定 block 数量是否与案例一致

### 三、暂不引入截图回归

本次不默认引入 golden/screenshot 测试。

原因：

- 当前目标是先建立稳定的人肉调试入口。
- Flutter 文本和排版的像素快照维护成本较高。
- 在没有沉淀出明确视觉基线之前，先用 widget 结构测试更稳妥。

后续如果这个页面成为长期排版回归基线，再单独评估是否补充 golden。

## 对现有文档与入口的影响

### 一、README

如果该页面成为团队常用调试入口，应在 `README.md` 中补一小段开发调试说明，说明：

- 路由入口
- 页面用途
- 固定案例库位置

### 二、AGENTS

当前约束已经强调“调试用例”“真实组件复用”“不要引入第二套真相来源”。本次不一定需要立即改 `AGENTS.md`，除非实现后团队决定把该页面上升为通用调试规范的一部分。

## 风险与控制

### 风险 1：调试页逐渐演变成第二套聊天页

控制方式：

- 坚持页面只渲染固定构造 block，不接入发送链路和数据库。
- 不把时间线模拟、输入框和模型配置一起塞进首版。

### 风险 2：案例散落，失去统一维护点

控制方式：

- 所有案例集中放在单一数据文件。
- 页面和测试共同引用这份数据。

### 风险 3：后续加入 tool card 时推翻首版模型

控制方式：

- 从首版开始保留 block `type`。
- 页面通过统一分发器渲染 block，而不是在页面里写死 `AssistantDocBlock` 列表。

## 实施顺序

### 阶段 1：建立页面骨架

- 新增路由常量与路由注册。
- 新增文档排版调试页基础布局。

### 阶段 2：建立案例模型与固定案例库

- 新增 `LayoutDebugCase` 与 `LayoutDebugBlock`。
- 准备首批固定 Markdown 案例。

### 阶段 3：接入真实 block 渲染

- 页面按 block 类型分发到真实组件。
- 首版打通 `assistantDoc`。

### 阶段 4：补 widget test

- 覆盖默认渲染与案例切换。

## 验收标准

- 可以通过独立路由打开文档排版调试页。
- 页面不依赖真实 LLM 或聊天发送链路。
- 页面能稳定切换并渲染至少 4 个固定文档案例。
- 渲染使用真实 `AssistantDocBlock` 与真实 Markdown 渲染链。
- 存在基础 widget test 覆盖页面打开与案例切换。

