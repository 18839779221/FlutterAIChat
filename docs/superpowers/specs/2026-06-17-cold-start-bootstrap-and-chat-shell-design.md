# 冷启动分层引导与聊天页首帧骨架设计

## 摘要

当前应用冷启动时，`lib/main.dart` 在 `runApp()` 前串行完成了大量初始化工作，导致用户进入应用后先经历一段白屏，再真正看到聊天页。

本设计的目标不是单纯用视觉包装掩盖白屏，而是同时优化两件事：

- 真实缩短 Flutter 首帧前的阻塞时间
- 让用户更早进入同一套真实聊天页 UI 的可感知状态

本次方案采用分层引导：

- 首帧前只保留最小入口初始化
- 首帧直接进入聊天页启动状态
- 聊天页消息区先显示骨架
- 输入框立即可编辑
- 发送能力在核心 runtime 完成后再开放
- 其余重初始化在首帧后异步完成

## 背景

当前 `lib/main.dart` 的启动路径，在 `runApp()` 前完成了以下一类重初始化：

- `Logger.initialize()`
- `SharedPreferences.getInstance()`
- `ChatStorage` 创建与 `testDatabaseConnection()`
- `getApplicationSupportDirectory()`
- `ArtifactFileStorageService.ensureReady()`
- `SkillStorageService` / `SkillRuntimeService` / `SkillInstallerService`
- `LLMFactory.createLLM(...)`
- `ToolExecutor` / `ToolCallService` / `TurnHarness`
- 基于这些对象创建 `ProviderContainer(overrides: [...])`

这些步骤多数都包含磁盘 IO、数据库初始化、目录解析或较重的运行时装配。由于它们被放在 `runApp()` 之前串行执行，Flutter 首帧被整体推迟，用户只能先看到原生启动层或白屏。

## 问题

### 1. 首帧前阻塞过重

当前冷启动的核心问题不是聊天页 build 本身慢，而是应用在进入 Flutter 首屏前先完成了整套运行时组装。

### 2. 启动链路没有分层

当前设计默认“只有完整 runtime 就绪后才能显示 UI”。这让本可延后的初始化也占用了首帧路径。

### 3. 用户最高频的首个动作没有被优先保证

根据已确认的使用模式，用户进入应用后的最常见第一操作是提问，因此首屏最应该优先保障的是：

- 尽快看到聊天界面
- 尽快进入可编辑输入状态

而不是优先加载完整历史消息或所有附加能力。

## 目标

1. 将首帧前启动链路压缩为最小可运行集合。
2. 冷启动时直接进入同一套真实聊天页 UI，而不是单独做一张假的启动页。
3. 消息区在 bootstrap 未完成前显示骨架，而不是空白等待。
4. 输入框在 bootstrap 阶段即可编辑。
5. 发送按钮在核心初始化完成前保持不可用，完成后原地恢复。
6. 把原本位于 `runApp()` 前的大部分重初始化迁移到首帧后异步完成。
7. Android 与 iOS 统一采用同一套 Flutter 启动状态方案，Android 为主要验证优先级。

## 非目标

本次不做以下事情：

- 不新增独立的假启动页或品牌过场页
- 不优先做“先展示旧消息缓存”的策略
- 不要求 bootstrap 阶段即可发送消息
- 不引入复杂的启动失败降级体系
- 不新增“重试初始化”入口
- 不借此重构聊天控制器、TurnHarness 或 LLM 架构边界
- 不在这一轮处理所有启动性能问题的终极优化，例如 isolate 化大规模拆分

## 已确认的体验约束

### 1. 启动首屏必须是真实聊天页 UI

不做独立的伪首页，不做页面级跳转切换。冷启动进入后看到的就是聊天页，只是处于启动状态。

### 2. 数据不是首要优先项

用户不需要在最短时间内看到历史消息或最近会话数据。消息内容可以延后，首屏主要保证聊天结构与输入区到位。

### 3. 输入框优先于发送能力

用户进入应用后，输入框应当可以立即编辑；但真正发送消息可以等到核心初始化完成后再开放。

### 4. 启动异常只做最小处理

不设计专门的恢复流。如果延迟初始化阶段出现异常，仅保留日志和轻量提示，不扩展复杂兜底逻辑。

## 核心设计

### 1. 启动链路拆成三段

#### Phase A：首帧前最小入口

这一阶段只保留绝对必要的启动步骤：

- `WidgetsFlutterBinding.ensureInitialized()`
- `SystemChrome` 沉浸式与系统栏样式设置
- 创建轻量 bootstrap 状态控制器
- 尽快 `runApp()`

这一阶段不得再等待数据库、偏好设置、目录、技能、artifact、LLM runtime 等重初始化。

#### Phase B：聊天页启动状态首帧

Flutter 首帧直接渲染聊天页，但页面处于 bootstrap 状态：

- 真实聊天页布局已经可见
- 消息区显示骨架占位
- 输入框可聚焦、可输入、可编辑草稿
- 发送按钮不可用
- 依赖 runtime 的附加能力默认禁用或弱化

#### Phase C：首帧后异步 runtime 装配

首帧渲染完成后，再异步启动当前 `main.dart` 中的大部分运行时初始化，包括：

- 日志
- 偏好设置
- 数据库
- 应用支持目录
- artifact / skill 子系统
- LLM 与 tool runtime
- 最终 provider overrides 所依赖的运行时对象

当核心运行时准备完成后，聊天页在原位从启动状态切换为正常状态。

### 2. 聊天页维持同一套真实 UI，只切换状态

本设计不引入单独的假聊天页。冷启动首屏与正常使用页共享同一套页面骨架：

- 顶部区域仍是聊天页顶部结构
- 中间区域仍是消息区
- 底部仍是现有输入区与相关停靠层

差异只来自当前 bootstrap 状态：

- 消息区内容不同
- 输入区发送能力不同
- 部分依赖 runtime 的控件可用性不同

这样可以避免冷启动后再从“假页面”切到“真页面”的视觉跳变。

### 3. 消息区采用骨架态，不阻塞首帧

在 bootstrap 未完成前，消息区不加载真实消息列表，而显示专门的聊天骨架占位。

骨架原则：

- 保持与现有聊天页一致的空间节奏
- 体现消息轨道与底部输入结构
- 不伪造旧消息数据
- 不显示误导性的历史内容

bootstrap 完成后，消息区原地切换到真实 `ChatMessageList`，并开始正常加载群组和消息数据。

### 4. 输入框立即可编辑，但发送保持禁用

输入区是本次体验优化的重点。

在 bootstrap 未完成前：

- `TextField` 保持可用
- 用户可以输入、删除、修改草稿
- 键盘与焦点行为正常
- 发送按钮 disabled
- 页内可以显示一条轻量准备态文案，例如“正在准备，稍后可发送”

这里要明确区分两种状态：

- `composer editable`
- `sending enabled`

它们不应继续被混在当前 `sendPhase` 语义里，而应由独立的 bootstrap 状态参与 gating。

### 5. 首次数据加载改为 ready 后触发

当前 `ChatPage.initState()` 中通过 `Future.microtask(() => ref.read(chatControllerProvider).loadGroups())` 触发会话加载。

这一行为应调整为：

- bootstrap ready 前不触发真实群组加载
- bootstrap ready 后再统一调度 `loadGroups()`
- 避免在 runtime 尚未准备好时提前拉起真实数据库链路

### 6. 运行时装配从 `main.dart` 抽离

当前 `main.dart` 同时承担了入口、初始化、装配、错误渲染多重职责。

本次建议引入独立 bootstrap 边界，建议至少拆出以下对象：

- `app_bootstrap_controller.dart`
  - 管理 `booting / ready / failed`
- `app_runtime.dart`
  - 聚合 bootstrap 完成后的关键依赖对象
- `app_bootstrap_scope.dart`
  - 根据 bootstrap 状态向应用树提供启动态或真实 runtime

`main.dart` 收缩为最小入口，只负责：

- 最小首帧前准备
- 启动 bootstrap
- 渲染应用根组件

## 初始化拆分边界

### 保留在首帧前

- `WidgetsFlutterBinding.ensureInitialized()`
- `SystemChrome.setEnabledSystemUIMode(...)`
- `SystemChrome.setSystemUIOverlayStyle(...)`
- bootstrap 状态容器本身
- `runApp()`

### 延后到首帧后

- `Logger.initialize()`
- `SharedPreferences.getInstance()`
- `AppSettingsRepository` 依赖装配
- `ChatStorage` 创建
- `storage.testDatabaseConnection()`
- `getApplicationSupportDirectory()`
- `buildDefaultFileToolHostAdapters()`
- `ArtifactFileStorageService.ensureReady()`
- `SkillStorageService`
- `SkillIndexService`
- `SkillRuntimeService`
- `SkillInstallerService`
- `ModelBudgetRegistry`
- `ModelCapabilityResolver`
- `LLMFactory.createLLM(...)`
- `ToolExecutor`
- `ToolCallService`
- `ChatService`
- `SessionContextService`
- `TurnHarness`
- 真实 `ProviderContainer` 的 runtime 依赖覆盖

## 页面行为设计

### 启动态聊天页

聊天页在 bootstrap 阶段需要具备以下行为：

- 顶部区域正常显示
- 抽屉入口保留现有外观，但其内部数据可暂不加载
- 消息区显示骨架
- 输入区立即可编辑
- 发送按钮禁用
- 模型信息、上下文统计、依赖 session runtime 的交互可以延后刷新

### ready 切换

当 bootstrap 完成后：

- 骨架消息区切换为真实消息区
- 触发群组与消息加载
- 发送按钮恢复可用
- runtime 相关 UI 恢复正常交互

整个过程不跳页、不闪屏、不更换页面骨架。

### 异常处理

如果延迟初始化阶段出现异常：

- 记录日志
- 显示轻量异常提示

本次不增加：

- 初始化重试入口
- 多层降级状态页
- 独立错误流

## 状态模型建议

建议引入独立 bootstrap 状态，而不是继续挤进现有发送状态机：

- `booting`
- `ready`
- `failed`

建议由独立 provider 暴露最少两类只读语义：

- `isBootstrapReady`
- `isComposerEditable`
- `isSendAvailable`

其中：

- `isComposerEditable` 在 `booting` 与 `ready` 都为 `true`
- `isSendAvailable` 仅在 `ready` 为 `true`

这样可以让 `ChatInput` 的可编辑性和可发送性分离，避免复用 `sendPhase` 导致语义污染。

## 对现有结构的影响

### `lib/main.dart`

- 从“大量 await + 构建 ProviderContainer + runApp”收缩为最小入口
- 重运行时装配迁移到 bootstrap 控制层

### `lib/pages/chat_page.dart`

- 增加 bootstrap 状态感知
- `loadGroups()` 改为在 ready 后调度
- 消息区支持 skeleton 与真实列表切换

### `lib/widgets/chat_input.dart`

- 发送按钮 gating 增加 bootstrap 维度
- 保持文本编辑能力独立于 runtime ready

### Provider 装配边界

需要重新梳理哪些 provider 可以在 bootstrap 前就存在，哪些 provider 必须依赖 ready 后的 runtime。

本次不要求重做整个 provider 体系，但要避免“页面已经首帧可见，底层 provider 仍在 build 阶段抛未注入异常”的情况。

## 测试与验证

### 1. 启动状态单测

至少验证：

- `booting -> ready`
- bootstrap 状态变化时发送可用性 gating 正确

### 2. Widget 测试

至少验证：

- 冷启动首帧能渲染聊天页结构
- 消息区在 booting 时显示骨架
- 输入框在 booting 时可编辑
- 发送按钮在 booting 时不可用
- ready 后切换为真实消息区并恢复发送能力

### 3. Android / iOS 实机验证

重点观察：

- 冷启动进入聊天页的可见时间是否明显提前
- 白屏时长是否缩短
- 输入框是否能更早进入可编辑状态
- 发送按钮是否只在 runtime 完成后开放

建议记录至少三类时点：

- `runApp()` 到首帧时间
- bootstrap 完成时间
- 发送按钮可用时间

这样可以区分：

- 只是体感更快
- 还是真实首帧也更快

## 实施原则

1. 先把首帧前阻塞迁移出去，再做局部视觉收尾。
2. 不为了低概率失败路径扩展复杂恢复体系。
3. 不把这次启动优化升级成全局架构重写。
4. 优先保证“同一套聊天页 UI 更早可见”和“输入框更早可编辑”。
5. 发送能力仍以核心 runtime 完成为前提，不提前承诺可用性。

