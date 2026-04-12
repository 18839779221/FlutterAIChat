# Tool Runtime And Chat Flow Refactor Design

## 背景

当前项目已经形成了相对清晰的分层：

- UI 层：`pages/`、`widgets/`
- 状态与流程层：`lib/providers/chat_providers.dart`
- 服务层：`lib/services/`
- 基础设施层：`storage/`、`repositories/`、`models/llm/`

但随着 tool call、trace、结构化消息、宿主能力接入逐步增加，两个结构性问题已经比较明显：

1. `tool` 相关知识分散在多个模块中，新增或修改一个 tool 需要跨多个 `switch case` 和注册点同步修改。
2. `ChatController` 已经同时承担状态管理、发送事务编排、数据库写入、流式响应处理、工具确认和部分 UI 控制，正在变成过重的流程中心。

本设计目标不是推倒重来，而是在保留现有功能的前提下，逐步重构出更稳定的扩展边界。

## 目标

本次重构分两条主线推进：

### 主线 A：Tool 执行侧组件化

把 tool 从“多个服务共同识别的字符串能力”重构成“可注册、可执行、可自描述的领域组件”。

目标效果：

- 新增一个 tool 时，主要新增一个 handler 并注册，而不是同时修改多个 `switch case`
- tool 的定义、参数归一化、执行逻辑、结果上下文构建尽量收口在 tool 自身
- 外部调度层只处理通用流程，不感知单个 tool 的内部细节

### 主线 B：聊天发送链路解耦

在 tool 边界稳定后，拆分当前过重的发送事务和状态管理逻辑。

目标效果：

- `ChatController` 不再承担完整发送事务编排
- 聊天页状态从大量离散 provider 逐步收拢到更明确的状态域
- 发送主链路更容易测试、追踪和扩展

## 非目标

本轮设计明确不包含以下内容：

- 不引入第三方插件市场或远程动态加载机制
- 不同步重构 UI 展示协议
- 不一次性替换整个 Riverpod 状态管理方案
- 不在本轮中完成所有页面结构整理

## 现状问题分析

### Tool 运行时问题

当前 tool 相关逻辑分散在多个位置：

- `ToolRegistry` 维护 tool definition
- `ToolDecisionService` 维护部分 tool 参数校验和归一化逻辑
- `ToolExecutor` 维护各类 tool 的执行入口
- `ToolOrchestratorService` 维护基于 tool name 的执行分发和上下文构建
- 其他模块还会零散依赖 tool name 做判断

这带来的问题：

- 单个 tool 的领域知识分散
- 迁移和扩展成本高
- 不同 tool 的行为一致性难以保证
- 测试边界不清晰，很多测试变成集成式验证

### 聊天发送链路问题

`lib/providers/chat_providers.dart` 当前体量较大，且 `ChatController` 负责内容过多：

- 分组加载与切换
- 消息加载与分页
- 发送事务
- tool 确认与取消
- 流订阅管理
- 自动摘要
- 输入框 / focus / scroll 的部分 UI 协调

这带来的问题：

- 发送链路变更容易影响无关状态
- 状态来源分散，不易形成单一真相
- 测试只能大量依赖高层集成路径
- 未来继续扩展 tool 或消息类型时，复杂度会继续上升

## 方案总览

建议按以下顺序重构：

1. 先完成 tool 执行侧组件化
2. 再重构聊天发送事务
3. 最后收拢聊天页状态和应用装配

原因：

- tool 边界现在已经是扩展瓶颈
- 发送链路依赖 tool 边界，先稳定 tool 组件边界，再拆发送事务更稳
- UI 不应在这一轮一起卷入，以免重构范围失控

## 方案 A：Tool 执行侧组件化

### 目标边界

每个 tool 应成为一个独立 handler，内部尽量收口以下能力：

- definition
- 参数校验
- 参数归一化
- 执行逻辑
- 结果标准化
- 上下文消息构建

外部只通过注册中心和统一接口访问 handler。

### 目录结构

建议新增目录：

- `lib/tools/core/`
- `lib/tools/handlers/`
- `lib/tools/adapters/`

推荐结构：

```text
lib/tools/core/
  tool_handler.dart
  tool_handler_result.dart
  tool_execution_context.dart
  tool_registry.dart

lib/tools/handlers/
  web_search_tool_handler.dart
  fetch_webpage_tool_handler.dart
  search_chat_history_tool_handler.dart
  create_reminder_tool_handler.dart
  create_calendar_event_tool_handler.dart
  save_note_tool_handler.dart
  share_result_tool_handler.dart

lib/tools/adapters/
  web_searcher.dart
  webpage_fetcher.dart
  reminder_creator.dart
  calendar_event_creator.dart
  note_saver.dart
  result_sharer.dart
```

### 核心接口

推荐引入统一接口：

```dart
abstract class ToolHandler {
  ToolDefinition get definition;

  Future<ToolArgumentResolution> normalizeArguments({
    required Map<String, dynamic> rawArguments,
    required String userMessage,
    required List<ChatMessage> history,
    required DateTime now,
  });

  Future<ToolResult> execute(ToolExecutionContext context);

  List<ChatMessage> buildContextMessages({
    required ToolResult result,
    required ToolExecutionContext context,
  });
}
```

### 配套模型建议

`ToolArgumentResolution`

- `normalizedArguments`
- `isValid`
- `errorCode`
- `errorSummary`

`ToolExecutionContext`

- `groupId`
- `toolName`
- `arguments`
- `history`
- `now`
- 宿主 adapter 引用

### 各模块新职责

#### ToolRegistry

从“definition 注册表”升级为“handler 注册表”：

- 注册 `List<ToolHandler>`
- 按 `toolName` 查找 handler
- 向 `ToolDecisionService` 提供 definition 列表

#### ToolDecisionService

只负责让模型返回：

- `toolName`
- `rawArguments`

不再负责：

- tool 专属参数校验
- tool 专属相对时间归一化
- tool 专属 intent 特判

这些逻辑统一下沉到 handler。

#### ToolOrchestratorService

仅保留通用流程：

1. 请求模型做工具决策
2. 查找 handler
3. 调用 handler 归一化参数
4. 进行策略判断
5. 返回确认态或直接执行
6. 统一记录 trace
7. 组合 `ToolPreparationResult`

`ToolOrchestratorService` 不再持有大面积 `switch case`。

#### ToolExecutor

当前 `ToolExecutor` 的职责偏混合：

- 一部分是 tool 分发
- 一部分是宿主能力适配

重构后建议逐步退化为宿主 adapter 容器，或被分解为注入到各 handler 的具体 adapter。

最终目标不是保留 `ToolExecutor` 作为中心分发器，而是让 tool 直接依赖自己需要的能力接口。

### 为什么参数归一化也要下沉

本项目里的很多 tool 逻辑并不只是“执行一个动作”，还包括：

- reminder / calendar 的时间归一化
- 网页抓取或搜索类参数修正
- tool 特定的参数错误语义

这些都属于 tool 自己的领域知识，不适合继续放在 `ToolDecisionService` 这样的通用决策层。

如果不下沉，表面上是组件化，实际上 tool 逻辑仍然散落在多个服务中。

### 迁移建议

建议按风险从低到高迁移：

1. `web_search`
2. `fetch_webpage`
3. `search_chat_history`
4. `create_reminder`
5. `create_calendar_event`
6. `save_note`
7. `share_result`

优先迁移 `web_search`，因为它最能验证：

- handler 注册
- 参数处理
- 执行
- 上下文构建
- trace 保持不变

优先迁移 reminder / calendar，是因为它们最能验证“参数归一化下沉”这件事是否成立。

## 方案 B：聊天发送链路解耦

这条线不在 tool 组件化之前先落地实现，但应在本轮设计中明确目标。

### 当前问题

当前发送流程横跨多个层级：

- `ChatController.sendMessage()`
- `ChatService.prepareToolAssistance()`
- `ChatService.sendMessageStream()`
- DB 持久化
- Stream listener 回调

流程完整，但缺少独立的“发送事务对象”。

### 建议目标结构

建议把 `ChatController` 拆成三个职责：

#### ChatSessionController

负责：

- group 加载与切换
- message 加载与分页
- 自动摘要

#### ChatSendCoordinator

负责：

- 创建 turnId
- 用户消息入库与上屏
- tool prepare
- tool confirm / cancel
- assistant placeholder
- stream 更新
- 完成 / 失败 / 中断收尾

#### ChatUiController

负责：

- scroll
- focus
- auto scroll
- 输入框交互相关状态

### 状态管理建议

当前状态管理使用 Riverpod 没问题，但“状态粒度组织方式”需要调整。

建议逐步形成三个状态域：

- `ChatSessionState`
- `ChatSendState`
- `ChatUiState`

这样做的目标不是把所有状态硬塞进一个对象，而是让同一条用户心智链路上的状态成组管理，减少离散 `StateProvider` 到处读写。

### ChatMessage 模型问题

`ChatMessage` 目前仍然是可变对象：

- `text`
- `status`
- `id`
- `payloadJson`

这会让状态管理隐式依赖“记得重新赋值 list 触发刷新”。

建议在发送链路稳定后，逐步把运行时核心消息对象转为不可变模型，降低状态同步和 UI 刷新风险。

## 应用装配建议

`main.dart` 当前已经承担了较多依赖装配逻辑。

建议在后续阶段把应用装配进一步收拢为 bootstrap/module：

- `app_bootstrap.dart`
- `chat_module.dart`
- `tool_module.dart`

目标是让：

- `main.dart` 只负责启动
- 依赖装配与环境初始化从入口文件中抽离

## 错误处理与可观测性

这轮重构必须保持现有 trace 体系不退化。

要求：

- `turnId` 继续贯穿发送主链路
- tool handler 内部错误能映射为稳定的 `ToolResult.failure`
- `ToolOrchestratorService` 仍保留统一 trace 记录点
- 不允许把 trace 重新打散回多个自由文本日志

## 测试策略

### Tool 组件化测试

每个 handler 应具备独立测试：

- 参数归一化
- 执行成功
- 执行失败
- context message 构建

保留 orchestrator 级测试：

- 决策命中
- 策略判断
- confirmation / auto-run 分支
- trace 顺序

### 发送链路测试

在发送事务拆分后，应分别覆盖：

- session 层测试
- send coordinator 测试
- UI controller 测试

而不是把所有发送行为都压在一个超大 controller 集成测试里。

## 风险与缓解

### 风险 1：重构范围过大

缓解：

- 先迁移少量代表性 tool
- 新旧接口并行一段时间
- 保留 focused regression tests

### 风险 2：trace 链路退化

缓解：

- 把 trace 顺序断言保留在 orchestrator / chat service 层
- 所有重构步骤都先保证 trace 测试稳定

### 风险 3：发送链路与 tool 迁移互相影响

缓解：

- 明确顺序：先 tool 边界，后 send coordinator
- 不在同一阶段同时重写 UI 和执行层

## 推荐实施顺序

### Phase 1

建立 `ToolHandler` 抽象、注册中心、基础模型，但先不删除旧兼容层。

### Phase 2

迁移：

- `web_search`
- `create_reminder`
- `create_calendar_event`

### Phase 3

清理旧的 tool-specific `switch case`，让 orchestrator 真正只剩通用流程。

### Phase 4

拆分发送事务，引入 `ChatSendCoordinator`。

### Phase 5

收拢聊天页状态域，并逐步推进消息模型不可变。

## 结论

当前项目不需要推倒重来，但确实已经到达需要结构化重构的阶段。

优先级应当是：

1. 先完成 tool 执行侧组件化
2. 再拆发送事务
3. 最后整理状态域和装配层

核心原则：

- 不做大一统重写
- 不把 UI 一起卷入
- 以“降低新增 tool 和维护发送链路的复杂度”为首要目标

