# Task 2: 结构化输出调试入口设计

## 背景

任务 1 已经为消息系统补上了类型化消息基础设施：`ChatMessage` 现在可以承载 `contentType`、`payloadJson` 和 `referenceJson`，数据库与消息列表也已经具备按类型分发渲染的能力，但当前 `structuredCard` 仍然只有回退显示，没有真正的结构化输出闭环。

任务 2 的目标不是把“结构化整理”做成正式产品功能，而是在开发/调试阶段，以最小风险验证下面这条链路是否成立：

1. 对已有助手回复发起结构化整理
2. 调用一个独立的非流式结构化输出接口
3. 解析并校验模型返回内容
4. 将合法结果存为 `structuredCard` 消息
5. 在消息列表中以专用卡片组件渲染
6. 任一步骤失败时安全回退为普通文本消息

## 目标

- 提供一个只在调试环境可见的临时入口，用于对单条助手消息执行“结构化整理”。
- 为当前仓库打通第一种真实可用的 `structuredCard` 渲染场景。
- 保持现有流式聊天链路不变，不把结构化 JSON 混入现有流式协议。
- 失败时保留原始回答，不展示原始 JSON，不破坏现有聊天体验。

## 非目标

- 不将该入口作为正式产品能力暴露给最终用户。
- 不让普通发送消息默认走结构化输出。
- 不支持多种卡片类型；本阶段只支持“结构化摘要卡片”。
- 不实现 Tool Calling、RAG 引用增强、复杂编辑能力或多步骤工作流。
- 不改造现有 `sendMessageStream()` 的流式协议。

## 用户交互

### 调试入口

- 入口只在 `kDebugMode` 下显示。
- 用户长按一条“已完成的助手纯文本消息”时，弹出调试菜单项：`结构化整理（调试）`。
- 该入口不对用户消息开放，也不对 `generating` / `failed` / `interrupted` 消息开放。
- 已经是 `structuredCard` 或 `toolResult` 的消息不提供该入口。

### 结果展示

- 触发后不覆盖原消息，而是新增一条新的助手消息展示整理结果。
- 成功时，新消息为 `contentType = structuredCard`，由结构化卡片组件渲染。
- 失败时，新消息为 `contentType = plainText`，使用普通文本回退展示。
- 原始助手回答始终保留，方便开发时比对整理前后效果。

## 结构化卡片范围

第一版只支持一个固定 schema：`StructuredSummaryCard`。

字段如下：

- `title`: 标题
- `summary`: 摘要
- `keyPoints`: 关键点列表
- `actionItems`: 行动项列表
- `risks`: 风险项列表

这套字段足够覆盖“把一段长回答整理成更清晰摘要卡片”的场景，同时避免第一版在 schema 设计上过度泛化。

## 架构与职责拆分

### 1. UI 层

`ChatMessageList` 负责两件事：

- 对符合条件的消息暴露长按调试菜单入口
- 对 `structuredCard` 类型消息分发到专用 Widget 渲染

消息列表不承担模型请求、JSON 解析或业务编排职责。

### 2. 控制器层

`ChatController` 新增结构化整理动作，例如 `structureMessageForDebug(ChatMessage message)`，负责：

- 校验目标消息是否可整理
- 创建新的占位助手消息
- 调用服务层执行结构化整理
- 根据结果更新消息内容与状态
- 失败时写入回退文本

控制器只编排流程，不直接拼装模型提示词或做 JSON 解析。

### 3. 服务层

`ChatService` 新增一个独立方法，用于执行“将指定文本整理为结构化摘要卡片”。

该方法与 `sendMessageStream()` 分离，原因如下：

- 普通聊天与结构化整理是两条不同的交互链路
- 结构化整理不需要复用现有流式 token 处理协议
- 分离后可以在不影响现有聊天的前提下独立测试和扩展

### 4. LLM 抽象层

`BaseLLM` 增加一个非流式结构化输出方法，由 `DeepSeekLLM` 实现。

该方法：

- 接收待整理的原始文本
- 使用固定的结构化提示词请求模型
- 返回原始模型输出文本

任务 2 不要求 LLM 直接返回强类型对象；强类型化由解析层完成。

### 5. 解析层

新增 `ResponseParserService`，负责：

- 解析模型原始输出
- 校验是否满足 `StructuredSummaryCard` schema
- 成功时返回结构化对象
- 失败时返回回退结果

解析层必须是唯一负责“JSON 是否合法、字段是否完整”的组件，避免控制器和 UI 分散处理容错逻辑。

### 6. 渲染层

新增 `StructuredSummaryCardWidget`，专门渲染 `StructuredSummaryCard`。

Widget 负责布局与展示，不直接接触模型输出原始文本，也不在内部做 JSON 解析。

## 数据流

完整数据流如下：

1. 用户长按某条助手纯文本消息
2. `ChatMessageList` 在调试菜单中触发控制器动作
3. `ChatController` 校验消息类型与状态，创建新的助手占位消息
4. `ChatController` 调用 `ChatService` 的结构化整理方法
5. `ChatService` 调用 `BaseLLM` 的非流式结构化方法
6. `DeepSeekLLM` 返回模型原始输出
7. `ResponseParserService` 解析并校验输出
8. 成功时生成 `StructuredSummaryCard`，写入 `payloadJson`
9. 失败时生成普通文本回退消息
10. `ChatMessageList` 根据 `contentType` 渲染卡片或普通文本

## 失败处理

### 不可触发情况

- 非助手消息
- 非已完成消息
- 非 `plainText` 消息
- 空文本消息

这些情况不应展示调试入口，或在控制器层直接拒绝处理。

### 模型请求失败

- 新增的目标消息标记为失败或回退为普通文本提示
- 不影响原始助手消息
- 不抛出会中断整个聊天页的未处理异常

### 解析失败

- 不展示原始 JSON
- 不把半合法结果拼成卡片
- 回退为普通文本消息

### 渲染失败

- `structuredCard` 渲染路径之外仍保留文本兜底逻辑
- 坏载荷最多影响该条消息的展示，不应导致消息列表整体崩溃

## 测试策略

### 单元测试

`test/services/response_parser_service_test.dart`

- 合法输入可解析为 `StructuredSummaryCard`
- 非法 JSON 可安全失败
- 缺失关键字段可安全失败
- 字段类型错误可安全失败
- 失败时返回普通文本回退结果

### Widget 测试

`test/widgets/structured_summary_card_widget_test.dart`

- 标题、摘要、关键点、行动项、风险项均可正确渲染
- 空列表字段不会导致组件异常

### 集成方向

在本阶段内，允许先不写完整控制器集成测试，但至少需要手动验证：

- 长按助手消息可见调试菜单项
- 成功时新增结构化卡片消息
- 失败时新增普通文本回退消息
- 普通发送消息链路保持不变

## 涉及文件

### 新增

- `lib/models/response/structured_summary_card.dart`
- `lib/services/response_parser_service.dart`
- `lib/widgets/structured_message/structured_summary_card_widget.dart`
- `test/services/response_parser_service_test.dart`
- `test/widgets/structured_summary_card_widget_test.dart`

### 修改

- `lib/models/llm/base_llm.dart`
- `lib/models/llm/deepseek_llm.dart`
- `lib/services/chat_service.dart`
- `lib/providers/chat_providers.dart`
- `lib/widgets/chat_message_list.dart`

## 实现约束

- 入口必须保持调试期属性，不得作为正式产品信息架构的一部分。
- 结构化整理链路必须与普通聊天流式链路解耦。
- 原始消息不可被覆盖。
- 结构化失败必须回退为普通文本，而不是把 JSON 泄露到 UI。
- 任务 2 只做一个固定的结构化卡片类型，避免过度设计。

## 验收标准

- 在调试环境下，用户可以通过长按助手消息触发一次“结构化整理（调试）”。
- 整理成功后，聊天列表中新增一条结构化卡片消息。
- 整理失败时，聊天列表中新增一条普通文本回退消息，且不会显示原始 JSON。
- 现有普通聊天发送、流式展示和 Markdown 渲染行为不受影响。
