# 统一 Bottom Sheet 外层交互设计

## 摘要

当前项目里的 `showModalBottomSheet` 已经分散到多个业务场景：

- 工作区切换
- Skill 安装
- Provider API Style 选择
- Debug Test Cases
- Context Window 占用明细
- Debug Turn Inspector
- `web_search` 结果详情
- `fetch_webpage` 详情

这些场景都在使用同一种“底部弹出”交互，但外层行为并不统一：

- 顶部 drag bar 在不同组件里各自手写
- 有的 sheet 高度靠 `FractionallySizedBox`，有的靠内容撑开
- 有的 sheet 把 header 和滚动内容写在同一个滚动容器里，导致顶部视觉锚点会一起滑走
- 键盘抬升、顶部圆角、背景色、内边距也在重复实现

本设计不重做现有业务内容，而是把 Bottom Sheet 的“基础交互和基础布局”收敛到公共外层：

- 点击外部可关闭
- 向下拖拽可关闭
- 顶部 drag bar 固定可见
- 内容区独立滚动，不把顶部 bar 一起划走
- 支持两类高度策略：
  - `adaptive`：自适应内容，高度上限 80%
  - `fixed80`：固定 80% 高

目标是让所有 `showModalBottomSheet` 场景共享同一套底层交互和结构约束，同时保持业务内容样式各自独立。

## 目标

### 体验目标

- 所有 Bottom Sheet 都具备一致的关闭手势和顶部 drag bar
- 长内容场景滚动时，顶部 bar 和 header 始终固定在顶部
- 短内容场景不会被无意义地拉到大高度
- 表单场景的键盘抬升行为统一，不再各自补 `viewInsets`

### 工程目标

- 新增一个统一调用入口，避免后续继续直接散落 `showModalBottomSheet`
- 新增一个统一外层壳组件，收敛 drag bar、圆角、背景、SafeArea、滚动容器分层
- 业务侧只负责自己的正文内容，不再自己画 sheet 外层
- 保持底层仍是 Flutter `showModalBottomSheet`，不引入新的弹层路由体系

## 非目标

- 不把 `showCupertinoModalPopup` 和 `showGeneralDialog` 一起并入本轮
- 不引入第三种“可展开高度”的通用模式
- 不重做各业务内容卡片、文案、tab、列表项视觉
- 不改动聊天页里的其他 overlay / drawer / dialog 体系

## 场景归类

### 一、自适应矮 Sheet（最大 80% 高）

适用规则：

- 主要是选择器或短表单
- 主要任务是“快速选一下 / 填一下”
- 默认不需要稳定浏览超长内容

本轮归类：

- 工作区切换
  - `lib/widgets/chat_drawer.dart`
- Skill 安装
  - `lib/pages/settings_page.dart`
- Provider API Style 选择
  - `lib/pages/provider_form_page.dart`

### 二、固定 80% 高 Sheet

适用规则：

- 主要是详情浏览、长列表或多段信息
- 需要更稳定的可视浏览区
- 内容区应独立滚动

本轮归类：

- Debug Test Cases
  - `lib/pages/chat_page.dart`
- Context Window 占用明细
  - `lib/pages/chat_page.dart`
- Debug Turn Inspector
  - `lib/pages/chat_page.dart`
- `web_search` 结果详情
  - `lib/widgets/tool_renderers/web_search_tool_result_card.dart`
- `fetch_webpage` 详情
  - `lib/widgets/tool_renderers/fetch_webpage_tool_result_card.dart`

## 现状问题

### 1. 外层交互重复实现且容易分叉

`ContextWindowBottomSheet`、`DebugTurnInspectorSheet`、`web_search` 详情、`fetch_webpage` 详情都在各自渲染顶部 drag bar。后续只要改一次视觉或交互，就需要多处同步。

### 2. 顶部锚点和滚动区边界不统一

有的 sheet 把整个内容都塞进 `ListView` 或 `SingleChildScrollView`，导致顶部 bar 和标题天然属于滚动内容；有的 sheet 又单独做了 `Column + Expanded(ListView)`。这种不一致会直接影响“顶部始终可见”的交互目标。

### 3. 高度策略散落在业务组件里

有的场景直接 `FractionallySizedBox(heightFactor: 0.78/0.82/0.92)`，有的场景用 `ConstrainedBox(maxHeight: ...)`，没有统一的语义层。

### 4. 键盘抬升和 SafeArea 逻辑重复

例如 `SkillInstallSheet` 自己处理了 `viewInsets.bottom`。如果未来更多表单类 sheet 出现，这部分重复会继续扩大。

## 设计原则

### 1. 统一外层，不统一业务内容

公共层只负责：

- modal 调用参数
- 顶部 drag bar
- 高度模式
- 内容区滚动边界
- SafeArea / 键盘 inset / 外层装饰

业务组件仍负责：

- 标题文案
- 列表项样式
- 按钮排布
- tab、markdown、信息卡片等正文结构

### 2. 顶部永远是固定结构，不属于内容滚动区

不管是 `adaptive` 还是 `fixed80`，公共壳都使用：

- 固定顶部 drag bar
- 可选固定标题区
- 独立内容区

这样才能保证拖动提示和顶部锚点在长内容滚动时不消失。

### 3. 用最少模式覆盖全部场景

本轮只保留两种模式：

- `adaptive`
- `fixed80`

不预设更多配置枚举，避免过早抽象。

### 4. 保持与现有主题系统一致

公共壳继续复用：

- `AppThemeSpec`
- `AppSpacing`
- `AppRadius`

不引入新的颜色体系或底部 sheet 专属主题层。

## 方案比较

### 方案 A：只抽一个 `show...BottomSheet` 帮助方法

优点：

- 改动最小

缺点：

- 各业务组件仍然自己实现 drag bar、滚动区、标题区
- 后续行为和样式还是会继续分叉

不采用。

### 方案 B：抽“统一调用入口 + 统一外层壳组件”

优点：

- 一次性收敛外部点击关闭、下拉关闭、顶部固定、两档高度、键盘 inset
- 业务组件只需要输出正文内容
- 后续新增 sheet 也有明确接入点

缺点：

- 需要迁移现有 8 个场景的外层结构

采用本方案。

### 方案 C：全面改成 `DraggableScrollableSheet`

优点：

- 高度控制能力最强

缺点：

- 对短选择器和短表单过重
- 需要更多场景显式配合 scroll controller
- 不符合本轮最小统一目标

不采用。

## 公共 API 设计

### 一、统一高度模式

新增一个高度模式枚举，例如：

- `AppBottomSheetMode.adaptive`
- `AppBottomSheetMode.fixed80`

语义：

- `adaptive`：按内容自然撑开，但最终高度不超过屏幕的 80%
- `fixed80`：整体固定为屏幕 80% 高，内容区自行滚动

### 二、统一调用入口

新增统一入口，例如：

`showAppBottomSheet<T>(...)`

职责：

- 封装 `showModalBottomSheet`
- 统一 `isScrollControlled`
- 统一背景与外层基础参数
- 构建统一外层壳

参数保持最小：

- `context`
- `mode`
- `title`
- `subtitle`
- `body`
- `bodyPadding`
- `useSafeArea`
- `useRootNavigator`

不暴露大量低层细节，避免重新长成“showModalBottomSheet 参数透传器”。

### 三、统一外层壳

新增统一外层组件，例如：

`AppBottomSheetScaffold`

职责：

- 绘制顶部 drag bar
- 提供可选标题区
- 管理 `adaptive` / `fixed80` 布局
- 管理键盘 inset 和 SafeArea
- 管理内容区滚动边界

建议结构：

1. 外层 `SafeArea(top: false)`
2. 带顶部圆角和背景的主容器
3. 固定顶部 drag bar
4. 可选固定标题区
5. 内容承载区

## 布局与交互细节

### 1. 点击外部关闭

继续依赖 `showModalBottomSheet` 默认 barrier dismiss 行为，统一所有场景。

### 2. 向下拖拽关闭

继续使用 `showModalBottomSheet` 的 drag dismiss 行为，不额外自建手势识别器。公共壳只负责让 drag bar 始终可见，不重写底层拖拽实现。

### 3. 顶部 drag bar 固定

drag bar 由公共壳统一绘制，位于固定头部最上方，不进入业务内容滚动容器。

### 4. 标题区可固定

如果业务侧传了 `title` / `subtitle`，它们与 drag bar 一起属于顶部固定区；若未传，则只渲染 drag bar。

### 5. 内容区独立滚动

`fixed80` 模式：

- 外层整体固定高度
- 正文区用 `Expanded` 承载
- 业务正文在需要时自行使用 `ListView` / `SingleChildScrollView`

`adaptive` 模式：

- 允许内容自然高度
- 通过 `ConstrainedBox(maxHeight: screen * 0.8)` 限制上限
- 当内容本身可滚动时，由业务内容滚动；当正文不滚动时，高度保持自然

### 6. 键盘抬升

公共壳统一把 `MediaQuery.viewInsets.bottom` 纳入底部 padding，这样表单型 sheet 不再自己处理输入法抬升。

## 业务迁移规则

### 一、自适应矮 Sheet

#### 工作区切换

- 去掉业务组件自己的外层 `SafeArea + Padding` 顶层职责
- 通过公共壳传入 `title`
- 业务侧只保留选项列表

#### Skill 安装

- 去掉业务组件自己的 `viewInsets.bottom` 处理
- 通过公共壳统一键盘抬升
- 业务侧保留说明、输入框、按钮

#### Provider API Style 选择

- 去掉业务组件自己的外层高度策略
- 通过公共壳传入 `title` / `subtitle`
- 业务侧保留 3 项选择列表

### 二、固定 80% 高 Sheet

#### Debug Test Cases

- 顶部交给公共壳
- 业务组件保留 grouped list 和操作按钮

#### Context Window 占用明细

- 删除组件内部自己绘制的 drag bar
- 保留卡片区和长列表内容
- 继续维持详情页语义

#### Debug Turn Inspector

- 删除组件内部 drag bar 和顶部空隙
- 保留刷新、turn 选择、TabBar、TabBarView

#### `web_search` 结果详情

- 把当前内联 `Column` 顶部结构迁到公共壳
- 业务层只保留结果列表 body

#### `fetch_webpage` 详情

- 把当前内联 drag bar、标题和固定高度迁到公共壳
- 业务层只保留 markdown 详情内容

## 测试设计

### 1. 公共壳 Widget Test

新增测试覆盖：

- `adaptive` 短内容时高度不会被强撑到 80%
- `adaptive` 超长内容时被限制在 80%
- `fixed80` 时高度稳定为 80%
- drag bar 始终位于固定顶部

### 2. 交互级 Bottom Sheet Test

覆盖：

- 点击 barrier 可以关闭
- 向下拖拽可以关闭

### 3. 业务回归测试

优先补或更新：

- `ContextWindowBottomSheet`
- `DebugTurnInspectorSheet`
- `fetch_webpage` tool card 打开详情
- `web_search` tool card 打开详情

### 4. 手动回归建议

实现后至少手动看 3 类代表场景：

- 短选择器：工作区切换或 API Style 选择
- 表单：Skill 安装
- 长详情：Context Window 或 `fetch_webpage`

## 风险与对策

### 1. 业务正文本身已带滚动容器，迁移后可能出现双重滚动

对策：

- 公共壳不强行把所有正文再包一层滚动
- `fixed80` 只提供受限高度容器，正文继续自行决定滚动方式

### 2. `adaptive` 模式下超长内容的滚动边界不清晰

对策：

- 对短场景只接入已有可滚动列表或短表单
- 若后续出现正文不自带滚动但又可能超长的场景，再单独补一个 `scrollableBody` 变体，不预先设计

### 3. 现有测试依赖具体内部结构，迁移后会脆弱

对策：

- 优先断言稳定语义元素和关键 key
- 减少对过深 widget 结构的耦合

## 实施顺序

1. 先写公共壳失败测试，锁定两档高度和固定头部行为
2. 实现 `AppBottomSheetMode`、`showAppBottomSheet`、`AppBottomSheetScaffold`
3. 先迁移一个 `adaptive` 场景和一个 `fixed80` 场景验证模式
4. 再批量迁移剩余 6 个场景
5. 更新现有测试并补交互回归

## 最终方案

采用“统一调用入口 + 统一外层壳组件”的方案：

- 底层继续使用 Flutter `showModalBottomSheet`
- 上层新增 `showAppBottomSheet` 和 `AppBottomSheetScaffold`
- 收敛两档高度模式：`adaptive` / `fixed80`
- 统一所有当前 8 个 `showModalBottomSheet` 场景
- 只统一基础交互和基础布局，不重写业务内容表现
