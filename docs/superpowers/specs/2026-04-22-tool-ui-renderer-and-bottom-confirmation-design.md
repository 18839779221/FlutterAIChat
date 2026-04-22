# Tool UI Renderer And Bottom Confirmation Design

## 背景

当前仓库的 tool use UI 已经具备一条完整的基础链路：

- `ChatSendCoordinator` 将 agent loop 事件投影为 `ChatMessage`
- `ChatBlockBuilder` 将 message 重组为 `AssistantTurnBlock`
- `ChatMessageList` 根据 block 类型渲染 `ToolWorkflowCard`、`ToolOutcomeCard`、`ToolExceptionCard`、`ToolInlineStepRow`

这条链路已经能稳定工作，但在“可解释性”和“可定制性”上存在三个核心问题：

1. 文件修改类与联网检索类卡片无法充分解释“到底发生了什么”
2. `requiresConfirmation` 当前耦合在 `ToolWorkflowCard` 内部，限制了专属工具 UI 的设计空间
3. 现有渲染入口偏向少数通用卡片，缺少“某个工具可以接管自己的 UI”的稳定扩展点

本设计的目标不是再发明一层强约束的展示 schema，而是在保持现有状态枚举和主数据结构稳定的前提下，让：

- 每个工具可以拥有自己的专属 UI
- 默认通用卡片继续存在并作为兜底
- 权限确认交互从 tool 卡片本身解耦，收敛为统一底部交互

## 目标

1. 继续复用现有 `ToolInvocationStatus`、`ToolWorkflowStepStatus`、`ToolExecutionStatus`
2. 不新增一层预先定义所有展示槽位的“展示描述层”
3. 允许工具专属 UI 直接消费原始 `details` / `data`
4. 保留现有通用卡片体系作为兜底渲染
5. 将 `requiresConfirmation` 相关按钮从 tool 卡片内移除，改为统一底部确认交互
6. 第一批重点支持 `Write`、`Edit`、`web_search`、`fetch_webpage`
7. 为遗留 `widgets/tool_call/*` 组件退场提供明确路径

## 非目标

1. 本轮不修改 planner、tool runtime、turn loop 的底层决策协议
2. 本轮不重写 `ToolWorkflowStep`、`ToolResult` 的核心语义
3. 本轮不要求所有工具都立即接入专属 UI
4. 本轮不实现并行多确认队列的复杂桌面工作台式交互
5. 本轮不把所有 tool payload 统一重构成新 schema

## 现状梳理

### 当前通用 workflow 卡片依赖的数据结构

当前 `toolInvocation` / `actionConfirmation` 不会直接渲染成 widget，而是先被 `ChatBlockBuilder` 转换为：

- `AssistantTurnBlock(type: toolWorkflow)`

其 `payload.steps` 中保存的是 `ToolWorkflowStep` 的 json 形式。当前通用 workflow UI 实际依赖的字段为：

- `stepId`
- `turnId`
- `toolName`
- `title`
- `summary`
- `status`
- `requiresConfirmation`
- `executionPolicy`
- `toolAccess`
- `details`

其中：

- `status` 负责通用状态展示
- `details` 本质上是当前工具调用参数
- `requiresConfirmation` / `executionPolicy` / `toolAccess` 负责确认与访问策略

### 当前通用 result 卡片依赖的数据结构

`toolResult` / `toolError` 会先被转换为：

- `AssistantTurnBlock(type: toolResultSummary)`

其 `payload` 直接承载 `ToolResult.toJson()` 的内容。当前通用 result UI 实际依赖的字段为：

- `toolName`
- `status`
- `summary`
- `toolResultText`
- `data`
- `executionPolicy`
- `toolAccess`
- `errorMessage`

其中：

- `summary` 是默认时间线摘要
- `data` 是工具专属的原始结果数据
- `errorMessage` 参与失败卡片分型

### 当前问题的本质

现有系统其实已经存在一套“通用稳定字段 + 工具原始 data”的隐式协议，但它还没有被正式定义成 UI 扩展边界。

因此出现了两个后果：

1. 默认卡片只吃到很少的信息，导致 `Write` / `Edit` / `web_search` 等卡片解释力不足
2. 没有正式的工具专属 renderer 入口，导致专属 UI 只能靠继续堆叠通用分型逻辑

## 设计原则

### 1. 状态统一，展示可插拔

状态语义继续由现有枚举承载：

- `ToolInvocationStatus`
- `ToolWorkflowStepStatus`
- `ToolExecutionStatus`

这些状态只表达“现在处于什么阶段”，不再绑定“必须显示成什么卡片”。

### 2. 不新增强约束展示模型

不引入一层类似 `summary/evidence/nextStep/...` 的统一展示 schema。

原因是：

- 各工具的内容差异过大
- 强行统一会形成新的约束源
- 后续新工具很容易落入“不适配就丢信息 / 适配就膨胀 schema”的两难

本轮推荐的做法是：

- 通用卡片继续消费少量稳定字段
- 专属工具 UI 直接消费 `details` / `data`

### 3. 默认卡片永远是兜底，不再是唯一主路径

未接入专属 renderer 的工具仍可依赖现有：

- `ToolWorkflowCard`
- `ToolOutcomeCard`
- `ToolExceptionCard`
- `ToolInlineStepRow`

这保证系统可以渐进迁移，而不是一次性重写全部工具 UI。

### 4. 确认是系统级交互，不是工具内容展示

`requiresConfirmation` 的本质是 turn control flow 中的授权节点，而不是工具结果本身的一部分。

因此：

- tool 卡片负责展示“准备做什么 / 做了什么”
- 底部统一确认区负责处理“是否允许继续”

这样可以把确认交互与工具专属 UI 解耦。

## 方案总览

推荐采用三层结构：

1. 状态与数据层
2. renderer 注册层
3. UI 渲染层

其中只新增 renderer 注册能力，不新增强约束展示描述层。

```text
ChatMessage / ToolResult / ToolWorkflowStep
    ↓
AssistantTurnBlock
    ↓
ToolUiRendererRegistry
    ↓
专属 renderer 或默认 renderer
    ↓
时间线卡片展示

独立并行：
messagesProvider
    ↓
activePendingToolConfirmationProvider
    ↓
底部统一确认区
```

## 详细设计

### 一、状态与数据层保持现状，增加“原始数据可直达 UI”约定

本轮不改动以下模型的主语义：

- `ToolWorkflowStep`
- `ToolResult`
- `AssistantTurnBlock`

但要明确新的 UI 约定：

#### 1. workflow 阶段

专属 workflow renderer 直接消费：

- `ToolWorkflowStep.status`
- `ToolWorkflowStep.toolName`
- `ToolWorkflowStep.summary`
- `ToolWorkflowStep.details`
- `ToolWorkflowStep.toolAccess`
- `ToolWorkflowStep.executionPolicy`

其中 `details` 视为该工具调用的主要原始参数来源。

#### 2. result 阶段

专属 result renderer 直接消费：

- `ToolResult.status`
- `ToolResult.toolName`
- `ToolResult.summary`
- `ToolResult.data`
- `ToolResult.toolAccess`
- `ToolResult.executionPolicy`
- `ToolResult.errorMessage`

其中 `data` 视为该工具执行结果的主要原始数据来源。

#### 3. 默认兜底卡片

默认卡片只依赖少量稳定字段：

- tool 名称
- 状态
- 摘要
- 通用失败码
- 少量通用键值信息

默认卡片不再承担“把每种工具都解释到位”的职责。

### 二、引入 renderer 注册机制

建议新增一组轻量接口，负责“某个工具是否有专属 UI，以及如何渲染”。

推荐文件：

- `lib/models/chat/tool_ui_render_mode.dart`
- `lib/services/tool_ui_renderer_registry.dart`
- `lib/widgets/tool_renderers/`

推荐接口形态：

```dart
abstract class ToolUiRenderer {
  bool supportsWorkflowStep(String toolName);
  bool supportsResult(String toolName);

  Widget? buildWorkflowStep(
    BuildContext context, {
    required ToolWorkflowStep step,
    required ChatMessage? sourceMessage,
    required bool isExpanded,
    required VoidCallback? onTap,
  });

  Widget? buildResult(
    BuildContext context, {
    required ToolResult result,
    required ChatMessage? sourceMessage,
  });
}
```

说明：

- renderer 可以只接管 workflow 或只接管 result
- 返回 `null` 时由默认卡片继续兜底
- renderer 直接拿 `ToolWorkflowStep` / `ToolResult`，不经过新的展示 schema

推荐 registry 形态：

```dart
class ToolUiRendererRegistry {
  final List<ToolUiRenderer> renderers;

  ToolUiRenderer? findWorkflowRenderer(String toolName);
  ToolUiRenderer? findResultRenderer(String toolName);
}
```

### 三、默认 renderer 的职责收敛

当前 `ChatMessageList` 内部直接分发到：

- `ToolWorkflowCard`
- `ToolOutcomeCard`
- `ToolExceptionCard`
- `ToolInlineStepRow`

本轮后建议改成：

1. 先查 registry
2. 命中专属 renderer 则直接渲染
3. 未命中则走默认 renderer

默认 renderer 的职责：

- 保留现有通用视觉语言
- 处理未定制工具
- 作为迁移过程中的稳定 fallback

默认 renderer 不再负责权限确认按钮。

### 四、底部统一确认交互

#### 目标

把当前嵌入在 `ToolWorkflowCard` 内的确认按钮移除，改成页面底部统一确认条，交互形态接近 Claude Code：

- 当前待确认工具信息固定出现在底部
- 操作始终一致
- 工具卡片本身只展示“待确认”状态和关键上下文

#### 新 provider

建议新增：

- `activePendingToolConfirmationProvider`

职责：

- 从 `messagesProvider` 中找出最新仍处于待确认状态的 tool message
- 返回当前待确认的 `ChatMessage` 与解析后的 `ToolInvocation`

选择规则应与现有 `activeAskUserQuestionMessageProvider` 一致，优先最新、未决、仍可恢复的确认节点。

#### 新底部组件

建议新增：

- `lib/widgets/tool_confirmation/tool_confirmation_bottom_bar.dart`

展示内容建议：

- 工具显示名
- 一句简短摘要
- 可选的风险提示
- `继续`
- `取消`
- `继续，以后不再确认`

该组件不负责解释工具细节；工具细节仍在时间线卡片中查看。

#### 页面接入

建议在 [chat_page.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/pages/chat_page.dart) 中，将底部确认区放在：

- `ChatMessageList` 与 `ChatInput` 之间

布局顺序建议：

1. 时间线
2. 底部确认区（条件显示）
3. 输入框

这样可以保持和 `AskUserQuestion` 类似的“当前回合挂起信息在下方集中处理”的体验。

#### 现有 workflow 卡片变化

从 `ToolWorkflowCard` 中移除：

- `onContinue`
- `onCancel`
- `onContinueAndTrust`
- 内部确认按钮区域

保留：

- 步骤状态展示
- 展开/折叠
- 当前步骤高亮
- 对“待确认”的状态标签表达

### 五、第一批专属工具 UI

#### 1. Write

目标：

- 默认先回答“写了哪个文件、是新建还是覆盖、改动量多大”
- 展开后再回答“具体写了哪些内容证据”

workflow 阶段可展示：

- 目标文件路径
- 写入类型：新建 / 覆盖
- 内容长度摘要

result 阶段默认摘要展示：

- 文件路径
- 新建还是覆盖
- 写入前后长度变化
- 状态

result 展开区展示：

- `filePreviouslyExisted`
- `oldLength`
- `newLength`
- `fileVersion`
- `postWriteData`
- 文件内容预览或摘要

#### 2. Edit

目标：

- 默认先回答“改了哪个文件、替换了几处、改动量多大”
- 展开后展示关键 diff 证据

workflow 阶段可展示：

- 文件路径
- 是否 `replace_all`
- `old_string` / `new_string` 的摘要预览

result 阶段默认摘要展示：

- 文件路径
- 替换次数
- 文件长度变化
- 状态

result 展开区展示：

- `replacementCount`
- `oldLength`
- `newLength`
- `fileVersion`
- 关键替换前后片段
- `replace_all`

注意：

- 当前 `FileToolWriteOutcome` 没有直接提供 diff hunk，本轮可以先做字符串摘要预览
- 若后续需要更强 diff，可在文件写入服务里补充更细粒度 diff 数据

#### 3. web_search

目标：

- 默认先回答“搜了什么、为什么这样搜、找到了多少结果”
- 展开后展示“具体来源与 snippet”

workflow 阶段可展示：

- 查询词
- 最大结果数
- 搜索意图短句

result 阶段默认摘要展示：

- 查询词
- 返回结果数量
- 主要来源域名概览
- 状态

result 展开区展示：

- 每条结果的标题
- 来源域名
- snippet
- URL

本轮不要求模型额外产出“搜索原因”字段，可由 UI 基于 query 和 tool 类型生成稳定文案。

#### 4. fetch_webpage

目标：

- 默认先回答“读了哪个网页、拿到了什么”
- 展开后展示网页标题、链接和正文摘要

workflow 阶段可展示：

- URL
- `extractMode`

result 阶段默认摘要展示：

- 网页标题
- URL host
- 是否成功提取正文

result 展开区展示：

- 完整 URL
- 标题
- 正文预览
- 正文长度
- `extractMode`

### 六、ChatMessageList 的分发改造

当前 `ChatMessageList` 的 block 分发逻辑集中在一个 widget 文件里，且直接绑定具体卡片组件。

建议改造为：

1. `ChatMessageList` 继续负责时间线分段与 block 遍历
2. 新增 `ToolBlockRenderer` 或同等 helper，负责：
   - workflow/result 的 renderer 查找
   - 专属 renderer 与默认 renderer 的回退
3. `ChatMessageList` 不再直接掌握某个工具是否需要专属 UI

这样可以避免后续每增加一个工具都去膨胀 `ChatMessageList` 的 switch 分支。

### 七、遗留组件清理

当前仓库存在未被主链路使用的：

- `lib/widgets/tool_call/tool_invocation_card_widget.dart`
- `lib/widgets/tool_call/tool_result_card_widget.dart`
- `lib/widgets/tool_call/tool_confirmation_card_widget.dart`

这些组件代表旧的 card 路径，不应继续与新 renderer 体系并存。

推荐处理顺序：

1. 确认无运行时引用
2. 完成新 renderer 注册与底部确认区迁移
3. 删除 `widgets/tool_call/*`

## 兼容性与迁移策略

### 渐进迁移

本设计应支持分阶段落地：

1. 先引入 registry，但先不挂专属 renderer
2. 再迁移底部统一确认区
3. 再逐个接入 `Write`、`Edit`、`web_search`、`fetch_webpage`
4. 最后删除遗留组件

这样每一步都能保持工具展示链路可用。

### 对已有状态流的影响

本轮不改变：

- `confirmToolInvocation()`
- `cancelToolInvocation()`
- `resumeAfterConfirmation()`

变化只在于：

- 确认操作不再由 `ToolWorkflowCard` 内部按钮触发
- 而由底部统一确认条触发同一套 controller 方法

因此业务状态流保持稳定。

## 风险与应对

### 风险 1：renderer 注册后，分发入口进一步分散

应对：

- renderer 只负责工具专属内容
- 分发入口集中在 registry 和单一 block renderer helper

### 风险 2：专属 renderer 直接解析 `details/data`，可能导致字段依赖变散

应对：

- 明确每个工具专属 renderer 的字段契约写在对应实现文件注释里
- 把“哪些字段是该工具 UI 的稳定输入”记录到测试中

### 风险 3：底部确认条与输入框交互冲突

应对：

- 确认条固定出现在输入框上方
- 仅在存在活动确认节点时显示
- 不遮挡 message list 的滚动锚点

### 风险 4：默认卡片和专属卡片并存时视觉语言割裂

应对：

- 共用主题 token、圆角、间距、状态色
- 专属卡片只定制信息结构，不推翻整体视觉基底

## 测试与验证建议

### 单元测试

建议新增覆盖：

- registry 能正确为工具选择 workflow/result renderer
- 未注册工具时会回退到默认 renderer
- `activePendingToolConfirmationProvider` 能正确选中当前待确认工具

### Widget 测试

建议新增：

- `Write` result card 默认摘要与展开区展示
- `Edit` result card 替换次数与片段展示
- `web_search` result card 来源列表展示
- `fetch_webpage` result card 标题与正文预览展示
- 底部确认条在待确认态出现，并能触发继续/取消/信任

### 手动验证

重点验证：

1. `Write`：新建文件与覆盖文件都能看懂发生了什么
2. `Edit`：知道改了哪个文件、改了几处、主要改动内容
3. `web_search`：知道搜了什么、搜到了哪些来源
4. `fetch_webpage`：知道打开了哪个网页、提取到了什么
5. 待确认工具：卡片中不再出现按钮，底部统一确认区工作正常

## 需要同步更新的文档

实现完成后，建议同步更新：

- `README.md`
- `AGENTS.md`
- 相关 tool use / interaction 设计文档引用关系

如果后续为 trace/log 添加新字段，详细规则应仅写入 [docs/architecture/logging.md](/Users/skka/flutterSpace/FlutterAIChat/docs/architecture/logging.md)。

## 决策总结

本轮最终设计决策如下：

1. 沿用现有状态枚举，不新增状态专用 UI 枚举
2. 不引入强约束的“展示描述层”
3. 工具专属 UI 直接解析 `ToolWorkflowStep.details` 与 `ToolResult.data`
4. 通过 renderer 注册机制让工具接管自己的 UI
5. 保留现有通用卡片作为兜底展示
6. 将 `requiresConfirmation` 从 tool 卡片中解耦，迁移为底部统一确认交互
7. 第一批重点接入 `Write`、`Edit`、`web_search`、`fetch_webpage`
