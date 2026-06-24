# 设置域沉浸式顶部壳层设计

## 1. 背景与问题

当前设置域页面的顶部结构仍是传统 `Scaffold.appBar` 思路：

- 一级设置页 `lib/pages/settings_page.dart`
- 二级设置页 `lib/pages/model_management_page.dart`
- 三级设置页 `lib/pages/provider_form_page.dart`

这些页面分别维护自己的 `_buildTintedHeader(...)`，导致几个问题：

- 顶部视觉与首页已建立的沉浸式 header 语言脱节。
- 标题区是“导航栏”而不是“悬浮 chrome”，空间感更割裂。
- 一级、二级、三级页没有共享同一套 header 结构，后续继续演化时容易再次分叉。

用户期望是：设置页 title 区域像首页一样固定悬浮在顶部，内容从其下方滚动经过；这套效果需要在一级、二级、三级设置页统一复用。

## 2. 目标

本次只解决设置域页面顶部壳层问题，不顺手重做正文内容结构。

目标如下：

1. 为设置域提供一套可复用的沉浸式顶部壳层。
2. 让一级、二级、三级设置页的顶部空间语言与首页保持一致。
3. 保持标题固定悬浮，页面内容从其下方开始并滚动经过。
4. 消除页面内重复维护的 `_buildTintedHeader(...)`。
5. 为后续继续改造二级、三级正文内容保留稳定骨架。

非目标如下：

- 不在本次统一所有非设置域页面的顶部壳层。
- 不在本次重做二级、三级页的正文布局和交互。
- 不将首页 `chat_page` 的 header 实现直接整段复制到设置页。

## 3. 设计原则

### 3.1 顶部不是导航栏，而是 chrome

设置域页面顶部不再使用传统 `AppBar` 作为主视觉结构。顶部应被视为悬浮 chrome：

- 标题浮在页面背景之上。
- 返回按钮是独立悬浮控件，而不是贴在导航栏边界里。
- 顶部区域通过 veil 保证状态栏与标题可读性，而不是通过实体 bar 分割内容。

### 3.2 结构统一，细节可分级

一级、二级、三级页共享同一个 scaffold 结构，但允许 header 细节按层级收敛：

- 一级页：标题更稳、更中性，强调总览入口。
- 二级页：返回语义更明确，标题略收紧。
- 三级页：保留右上角操作位，适配“编辑类”页面。

### 3.3 共享空间结构，避免共享错层实现

共享的是“顶部 veil + floating header + body top inset + 内容下穿”的结构，不是把某一页的 widget 树原样拷贝给所有页面。设置域需要一套专用 scaffold，而不是每页继续手写 header。

### 3.4 先做设置域专用，不提前过度泛化

本轮先抽设置域专用 `ImmersiveSettingsScaffold`，而不是直接做全局 `AppTopChromeScaffold`。原因：

- 设置域当前已存在明确替换目标。
- 首页 header 行为更复杂，包含 workspace、调试按钮等特有逻辑。
- 现在就做全局统一会扩大范围并提高回归风险。

## 4. 方案对比

### 方案 A：保留 `AppBar`，只做透明化

做法：

- 保留现有 `Scaffold.appBar`
- 调整背景透明度、去边线、弱化实体感

优点：

- 改动小
- 风险低

问题：

- 本质仍是传统导航栏
- 无法形成“固定悬浮 + 内容从下方经过”的首页式空间体验
- 仍然不是设置域可复用的骨架

结论：

不采用。

### 方案 B：设置域专用 `ImmersiveSettingsScaffold`

做法：

- 设置域页面不再使用 `appBar`
- 统一用 `Scaffold + Stack`
- 底层是页面 body
- 顶层是固定 veil 和 floating header
- body 自动获得与 header 高度匹配的 top inset

优点：

- 最符合用户目标
- 与首页 header 空间语言一致
- 结构边界清楚，复用成本低
- 可逐步替换一级、二级、三级页

问题：

- 需要改动页面骨架
- 需要补齐 header 高度、safe area、内容 inset 的统一规则

结论：

采用本方案。

### 方案 C：直接做全局 `AppTopChromeScaffold`

做法：

- 把首页与设置页都纳入同一全局顶层 chrome scaffold

优点：

- 长期统一性最强

问题：

- 当前范围过大
- 容易把首页稳定结构也卷入回归
- 不符合本轮“只先处理设置域”的节奏

结论：

本轮不采用。

## 5. 目标结构

## 5.1 新增共享壳层

新增一个设置域专用 widget，例如：

- `lib/widgets/settings/immersive_settings_scaffold.dart`

职责：

- 提供设置域页面的统一顶层布局。
- 管理顶部 safe area、veil、floating header、body top inset。
- 允许一级、二级、三级页通过参数配置 title、leading、trailing、content width 等差异。

建议接口：

```dart
ImmersiveSettingsScaffold(
  title: '设置',
  body: ...,
  leading: ...,
  trailing: ...,
  maxContentWidth: 760,
  bodyPadding: ...,
  scrollController: ...,
  headerStyle: SettingsHeaderStyle.root,
)
```

其中 `headerStyle` 只决定细节 token，不改变整体布局结构。

## 5.2 内部层级

内部结构建议如下：

```text
Scaffold
  body: Stack
    1. 页面内容层
    2. 顶部 veil
    3. 顶部 floating header
```

### 内容层

- 由页面自身提供 `ListView` 或 `CustomScrollView`
- scaffold 自动为内容注入顶部占位
- 页面本身不再重复手写“给 AppBar 留空间”的逻辑

### 顶部 veil

职责：

- 覆盖状态栏与顶部标题区域
- 把顶部 chrome 压回页面背景，形成沉浸感
- 向下渐隐，避免正文第一屏被硬切开

要求：

- 视觉方向与首页一致
- 只承担可读性和空间过渡，不做重玻璃卡片感
- 不额外画实体 bottom border

### floating header

职责：

- 固定在顶部，不随列表滚动
- 提供返回按钮、居中标题、可选右侧操作
- 在视觉上是悬浮 chrome，而不是实体导航栏

要求：

- 标题始终居中
- 左右控件存在时不影响标题中心
- 返回按钮作为独立交互表面存在

## 6. 分级规则

### 6.1 一级页

适用：

- `settings_page.dart`

规则：

- 标题为 `设置`
- 返回按钮为默认导航返回
- 不默认显示右侧操作
- header 与第一页内容之间保留更充足呼吸区

### 6.2 二级页

适用：

- `model_management_page.dart`

规则：

- 标题如 `模型配置`
- 使用同样的悬浮返回按钮
- 标题尺寸与权重可略微收紧，但不改变总体布局

### 6.3 三级页

适用：

- `provider_form_page.dart`

规则：

- 标题如 `新增 Provider` / `编辑 Provider`
- 允许右上角出现页面级操作位，但仍必须服从同一 chrome 结构
- 正文可更密，但顶部空间结构不能退回传统 `AppBar`

## 7. 页面替换范围

本轮第一批替换以下页面：

1. `lib/pages/settings_page.dart`
2. `lib/pages/model_management_page.dart`
3. `lib/pages/provider_form_page.dart`

替换目标：

- 删除各页面局部 `_buildTintedHeader(...)`
- 改用共享 `ImmersiveSettingsScaffold`
- 保持各页现有正文内容与交互逻辑尽量不动

## 8. 与首页的关系

首页已经存在成熟的顶部沉浸式语言，例如：

- 顶部 veil
- 固定 ghost header
- 内容从 header 下方滚动经过

设置域应向这套语言靠齐，但不直接复制首页实现。原因：

- 首页 header 绑定了 workspace、新建会话、调试按钮等业务逻辑
- 设置域只需要借用空间结构与视觉语言
- 设置域应抽出更小、更纯的设置专用壳层

因此本次是“语义对齐、实现解耦”。

## 9. 验证要求

### 9.1 视觉验证

至少验证以下内容：

1. 标题固定悬浮，不随内容滚动。
2. 页面内容从标题下方开始，并在滚动时从其下方经过。
3. 一级、二级、三级页顶部结构一致，没有再次退回传统 `AppBar`。
4. 返回按钮、标题、可选右上角操作在 claude / olive-paper 两个主题下都成立。

### 9.2 代码验证

至少补充或更新：

- 设置页相关 widget/page tests
- 新 scaffold 自身的结构测试
- 定向 `fvm flutter analyze`

## 10. 风险与约束

### 10.1 顶部占位与实际 header 高度不同步

如果内容层 top inset 与真实 floating header 高度不一致，第一页内容会贴住 header 或留下异常大空洞。

要求：

- inset 逻辑由共享 scaffold 统一管理
- 不允许各页面写各自 magic number

### 10.2 标题居中被左右控件拖偏

如果直接使用普通 `Row` 结构，左侧返回与右侧操作数量变化时，标题很容易视觉漂移。

要求：

- 标题中心对齐必须独立保证
- 不能依赖“左右正好一样宽”这种脆弱结构

### 10.3 再次散落局部 header 实现

如果只是“先给三个页面分别改一下”，后续仍会继续分叉。

要求：

- 必须先落共享 scaffold，再替换页面
- 不接受继续新增 `_buildTintedHeader(...)`

## 11. 实施顺序

建议实施顺序：

1. 新增设置域共享 `ImmersiveSettingsScaffold`
2. 先替换一级设置页并验证
3. 替换 `model_management_page.dart`
4. 替换 `provider_form_page.dart`
5. 补齐针对新 scaffold 的测试与定向分析

这样可以先在一级页确认 header 语言正确，再把相同骨架推广到二级、三级页。

## 12. 结论

本次设置域顶部改造采用“设置域专用沉浸式共享壳层”方案。

核心结论：

- 不再延续传统 `AppBar` 方案
- 不直接复制首页实现
- 先抽设置域专用 `ImmersiveSettingsScaffold`
- 一级、二级、三级页共用同一套顶部空间结构
- 本轮只统一顶部壳层，不扩散到正文重构
