# AskUserQuestion Message Card Design

## 背景

当前项目已经具备一套可工作的 agent turn loop、tool runtime registry、tool confirmation workflow 和消息流投影机制：

- `TurnHarness` 负责 turn 生命周期与 loop 恢复
- `AgentPlannerService` 负责让模型做下一步决策
- `ToolCallService` / `ToolOrchestratorService` 负责工具执行
- `ChatSendCoordinator` 负责把 turn event 投影为聊天消息
- UI 侧已经支持 confirmation card、tool workflow card、tool result card

现状里唯一缺少的是一类新的交互能力：

- 当模型需要用户补充信息时，不是直接终止并要求用户重发消息
- 而是由模型显式发出 `AskUserQuestion` tool call
- 客户端把该请求渲染成 assistant 消息卡片
- 用户完成回答后恢复当前 turn，让模型继续当前推理链路

这类能力和现有 `tool confirmation` 在“运行时控制流”上相似，都需要暂停当前 turn 并等待用户操作；但在业务语义上并不是一回事：

- tool confirmation 是执行前授权
- AskUserQuestion 是执行中的信息采集

因此本设计目标不是“把 AskUserQuestion 塞进 tool confirmation”，而是在不破坏现有架构方向的前提下，扩展出一条独立但可复用挂起/恢复基础设施的交互通道。

## 目标

本次设计目标如下：

1. 支持模型通过 `AskUserQuestion` tool call 发起单题或多题提问
2. UI 以特殊 assistant 消息卡片形式承载交互，而不是浮层或输入框重发
3. 支持单选、多选、自动追加 `Other`
4. 支持多题 wizard：单卡片内逐题切换，统一提交
5. 用户提交答案后恢复同一个 turn，而不是开启新 turn
6. 在架构上保持现有 controller / service / tool runtime 边界稳定
7. 明确区分普通工具执行与交互型工具，不让 `ToolOrchestratorService` 吞并 UI 语义

## 非目标

本轮设计明确不包含：

- 不支持由应用层主动发起同样的问答卡片
- 不支持 planner 不经 tool call 直接触发问答卡片
- 不实现 VS Code / web headless defer 兼容链路
- 不实现 preview 富内容渲染
- 不把所有 interactive flow 统一抽象成通用表单框架
- 不在本轮重构整个聊天消息协议

## 设计原则

### 1. AskUserQuestion 仍然是模型侧 tool

模型是否需要用户补充信息，应由模型自己通过 `AskUserQuestion` tool call 判断并触发。客户端不引入第二条平行的“澄清问题机制”。

### 2. 共享挂起能力，不共享领域模型

`tool confirmation` 与 `AskUserQuestion` 共享的是：

- turn 暂停
- event 投影
- 用户输入后恢复 loop

但它们不应共享同一业务模型：

- `ToolInvocation` 代表的是“将要执行的工具”
- `AskUserQuestionRequest` 代表的是“等待用户回答的问题集合”

### 3. 消息卡片优先

问题交互落在聊天流里，而不是用临时弹窗。这样可以获得：

- 更稳定的恢复与重建行为
- 更自然的上下文呈现
- 更容易落库与回放
- 与当前项目的 tool workflow UI 一致

### 4. 尽量不改现有主干架构

本次是架构扩展，不是架构改向：

- `ChatController` 仍然保持 facade 角色
- `TurnHarness` 仍是唯一 loop 执行入口
- `ToolOrchestratorService` 仍只处理“可立即执行的工具”
- UI 仍通过消息内容类型投影结构化事件

## 现状分析

### 已具备的能力

当前仓库已经有足够的基础设施承载 AskUserQuestion：

1. `TurnHarness.runTurn()` 与 `resumeAfterConfirmation()` 已经证明 turn 可中断后恢复
2. `ChatSendCoordinator` 已经支持把等待态事件投影为 `actionConfirmation` 消息
3. `ChatEventType` / `ChatMessage.contentType` / payloadJson 已经形成结构化消息渲染路径
4. tool runtime 已经通过 `ToolDefinition`、`ToolRuntimeRegistry`、`ToolHandler` 组织

### 当前不足

当前系统仍有几个缺口：

1. `awaitingToolConfirmation` 是唯一等待态，语义过窄
2. `ToolInvocation` 只能表达“待执行工具”，不能表达“待回答问题”
3. `ToolOrchestratorService` 的 contract 假定 handler 会立即返回 `ToolResult`
4. 消息类型里没有专门承载交互式问题卡片的内容类型
5. 现有 coordinator 只有 `confirmToolInvocation()`，没有“提交结构化回答”的恢复入口

## 方案总览

推荐新增一条独立的 interaction 通道，但复用现有 turn suspension/resume 骨架。

```text
Model AskUserQuestion tool call
    ↓
AgentPlannerService / tool loop adapter 解析为 ModelToolCall
    ↓
TurnHarness 识别该 tool 为 interaction tool
    ↓
创建 pending question step + 写入 assistantQuestionPrompt event
    ↓
ChatSendCoordinator 投影为 ask-user-question assistant message card
    ↓
用户在卡片中逐题回答并统一提交
    ↓
ChatInteractionCoordinator.submitQuestionAnswers(...)
    ↓
TurnHarness.resumeAfterQuestionAnswered(...)
    ↓
写入 interaction result / step completion
    ↓
继续当前 turn loop
```

这个方案的关键点是：

- AskUserQuestion 保留 tool 入口，方便模型调用
- 运行时不进入普通 `ToolHandler.execute()` 语义
- 恢复链路与 confirmation 并列，而不是嵌套在 confirmation 里

## 架构影响评估

### 是否改变整体架构

不会改变项目主架构方向，但会新增一个清晰的交互子能力边界。

当前架构文档的核心边界仍然成立：

- UI 层负责渲染消息与收集用户输入
- controller 层负责页面流程与交互回调
- service 层负责 turn orchestration、planner、tool runtime
- data/model 层负责结构化状态与持久化

本次变化更准确地说是：

- 从“tool confirmation 单一等待态”
- 扩展为“interactive checkpoints：tool confirmation + ask-user-question”

### 需要补充到架构文档的内容

建议后续同步更新 `AGENTS.md` / `README.md` / `docs/architecture` 中和 agent loop 相关的描述，补充：

1. `TurnHarness` 除了 tool execution loop，还负责 interactive checkpoint 恢复
2. `ToolOrchestratorService` 只负责立即执行型工具，不负责 question-style user interaction
3. `ChatInteractionCoordinator` 负责 question answer submit / cancel 等用户交互恢复动作
4. AskUserQuestion 属于“interaction tool”，不是普通 side-effect tool

## 新增模型设计

### AskUserQuestionRequest

建议新增：

- `lib/models/interaction/ask_user_question_request.dart`

字段建议：

- `questions: List<AskUserQuestionItem>`
- `stepId: int?`
- `providerCallId: String?`
- `agentTurnId: int`
- `traceTurnId: String?`

### AskUserQuestionItem

建议新增：

- `lib/models/interaction/ask_user_question_item.dart`

字段建议：

- `id: String`
- `question: String`
- `header: String`
- `multiSelect: bool`
- `options: List<AskUserQuestionOption>`

说明：

- `id` 应为稳定 question id，不建议用 question 文本本身作为 response key
- transcript、step result、provider continuation 都应基于 question id 恢复结构化答案

### AskUserQuestionOption

建议新增：

- `lib/models/interaction/ask_user_question_option.dart`

字段建议：

- `label: String`
- `description: String`
- `isRecommended: bool`

说明：

- `isRecommended` 不要求模型单独传字段，第一版可由客户端在解析时根据 label 是否以 `(Recommended)` 结尾推导
- 进入 UI 展示时可以去掉后缀再单独高亮

### AskUserQuestionResponse

建议新增：

- `lib/models/interaction/ask_user_question_response.dart`

字段建议：

- `answersByQuestionId: Map<String, String>`
- `selectedOptionLabelsByQuestionId: Map<String, List<String>>`
- `freeTextAnswersByQuestionId: Map<String, String>`

说明：

- 对 transcript 恢复链路可以简化成 `Map<String, String>` 输出
- 对 UI 卡片内部状态可保留更细粒度的结构

### QuestionCardPayload

建议新增：

- `lib/models/interaction/question_card_payload.dart`

职责：

- 作为 `ChatMessage.payloadJson` 的稳定消息协议
- 供 UI 与恢复入口读取

字段建议：

- `type`
- `agentTurnId`
- `stepId`
- `traceTurnId`
- `status`
- `questions`
- `submittedAnswers`
- `currentQuestionIndex`

## 现有模型改动建议

### ChatTurnStatus

建议新增 `awaitingUserInteraction`，不要复用现有 `awaitingToolConfirmation`。

原因：

- 两者语义不同
- 恢复动作不同
- UI 提示文本不同
- 未来统计 / trace / debug 时需要区分

### ChatEventType

建议新增：

- `assistantQuestionPrompt`
- `userInteractionResult`

也可以只新增 `assistantQuestionPrompt`，并继续用现有 `toolResult` 风格承载恢复结果；但从长期清晰度看，显式新增结果事件更稳。

### MessageContentType

建议新增：

- `askUserQuestionPrompt`
- 可选：`askUserQuestionResult`

不建议继续复用 `actionConfirmation`，否则 UI 和领域语义会持续纠缠。

### ToolDefinition

建议给 `ToolDefinition` 增加执行模式字段，例如：

- `runtimeKind: immediate | requiresConfirmation | userInteraction`

或：

- `interactionKind: none | confirmation | askUserQuestion`

原因：

- 避免在 `TurnHarness` 里硬编码工具名分支
- 让 planner/runtime 元数据更完整
- 后续如果再加其他 interaction-style tool，扩展点更自然
- 不要与现有用户策略层 `ToolExecutionMode(conservative|balanced|aggressive)` 重名

## 服务层设计

### TurnHarness

`TurnHarness` 是本次改造的核心。

#### 新职责

- 在 planned tool call 执行前，识别 AskUserQuestion 是否属于 `userInteraction` 模式
- 创建 interaction step
- 追加 `assistantQuestionPrompt` event
- 把 turn 状态切换为 `awaitingUserInteraction`
- 提供 `resumeAfterQuestionAnswered(...)`

#### 不应新增的职责

- 不在这里管理 UI 草稿状态
- 不直接拼装 widget 结构
- 不直接执行普通 tool handler 之外的界面交互

#### 推荐新增方法

```dart
Stream<ChatEvent> resumeAfterQuestionAnswered({
  required int turnId,
  required AskUserQuestionRequest request,
  required AskUserQuestionResponse response,
  required ChatConfig config,
})
```

恢复链路约束：

- `resumeAfterQuestionAnswered(...)` 不应再经过 `ToolOrchestratorService.executeToolInvocation()`
- 用户提交的结构化答案本身就是 AskUserQuestion 这次 tool call 的 result
- 恢复时应直接写入 interaction result event、完成对应 step，然后回到 `_continueTurnLoop()`

### ToolOrchestratorService

保持职责不变：

- 只执行真正会立即返回 `ToolResult` 的工具

不建议让它承担：

- 问答卡片生成
- turn suspension
- interaction payload formatting

如果让 `ToolOrchestratorService` 处理 AskUserQuestion，会把“工具执行”和“等待用户输入”这两种语义混在一起，后续维护成本会越来越高。

额外约束：

- AskUserQuestion 不应进入 `ToolHandler.execute()` 普通执行路径
- 如果 runtime 侧需要 blocked / policy guard，应在 `TurnHarness` 识别 interaction tool 时显式处理，而不是伪装成一次普通工具执行

### ChatSendCoordinator

继续承担：

- 发起 `runTurn()`
- 把 event 投影为消息
- 处理 tool call / tool confirmation / final answer / tool result

新增：

- 接收 `assistantQuestionPrompt` 事件
- 将其投影为 `askUserQuestionPrompt` 消息

建议不要继续把“用户回答问题后的恢复逻辑”全部塞进它，而是引入独立协调器。

### ChatInteractionCoordinator

建议新增：

- `lib/controllers/chat_interaction_coordinator.dart`

职责：

- `submitQuestionAnswers(...)`
- `cancelQuestionPrompt(...)`
- `confirmToolInvocation(...)` 可后续迁移到这里统一管理

如果第一版改动范围需要更小，可以先保留 `confirmToolInvocation()` 在 `ChatSendCoordinator`，但 `AskUserQuestion` 的提交建议从一开始就走独立 coordinator，避免再次扩张发送协调器。

## UI 设计

### 为什么选消息卡片

相比浮层，消息卡片更适合当前项目：

- 与 tool workflow / result card 一致
- app rebuild 后恢复更自然
- 用户能在聊天记录中回看提问与答案
- 不需要维护额外 modal 生命周期

### 单题卡片

显示内容：

- header
- 完整问题文本
- 选项列表
- 自动追加 `Other`
- 提交按钮

单选：

- 点击一个选项后即记录当前选择

多选：

- 支持勾选多个选项

### 多题 card wizard

你已经确认采用“单卡片内逐题切换，最后统一提交”。

建议结构：

- 顶部：header chips / segmented control 显示当前进度
- 中部：当前题的 question + options
- 底部：`上一步` / `下一步` / `提交`

关键规则：

- 每题必须完成最低有效输入后才能进入下一题
- 最后一题统一提交，不在中途写回 turn
- 用户可返回上一题修改

### Other

由客户端自动追加：

- 单选题：`Other`
- 多选题：`Other`

选中后显示文本输入框。

第一版建议：

- `Other` 作为 UI 层虚拟选项，不写进模型原始 request
- 提交时把其文本映射成对应 question 的 answer 值

## Transcript 与恢复策略

### 推荐做法

用户提交答案后，不创建新的普通 user message 作为新 turn 开始，而是在当前 turn 内生成一条 interaction result。

建议 transcript 注入的文本形式保持清晰、稳定、低噪音，例如：

```text
User answered AskUserQuestion:
- Framework: Flutter
- Data storage: SQLite
- Features: Search, Reminders
```

同时保留结构化 payload，供后续 planner/ledger 使用。

这里建议明确双轨保存：

- `ChatEvent.content` 保存稳定、低噪音的人类可读 transcript 文本
- `ChatEvent.payloadJson` 保存结构化 answer payload，供 UI / trace / debug / replay 使用
- `ChatTurnStep.resultJson` 同步保存结构化结果，供 provider continuation item 生成使用

### 为什么不走普通 user message

因为那会导致：

- 当前 turn 被人为切断
- planner 需要跨 turn 理解“上一轮其实还没结束”
- trace 和 step ledger 更难追

保持在同一 turn 内恢复更符合你要模拟的 Claude Code 语义。

## 持久化策略

### 需要持久化的内容

- prompt 消息 payload
- 当前 pending interaction 对应的 turn / step 状态
- 用户最终提交的答案结果
- interaction step 的 `providerResponseId` / `providerCallId` / `resultJson`

补充说明：

- 当前 native tool-calling provider continuation 由 step ledger 构建，而不是直接从 message 或 event 反推
- 因此 AskUserQuestion 对应 step 在用户提交后必须写成 completed/failed，并带上稳定的结构化 `resultJson`

### 不建议立即持久化的内容

- 卡片作答中的临时草稿
- 当前正在编辑的 `Other` 输入内容
- 多题切换中的中间索引

这些第一版建议放在 provider 中按 `messageId` 或 `turnId` 保存；只有点击提交时再持久化最终结果。

原因：

- 减少 DB 噪音
- 避免一边输入一边刷消息 payload
- 第一版实现简单且稳定

## 分阶段实现任务

### Task 1：运行时骨架

目标：

- 新增 AskUserQuestion interaction models
- 给 `ToolDefinition` 增加 execution mode
- `TurnHarness` 能识别 AskUserQuestion 并进入 `awaitingUserInteraction`
- `ChatEventType` / `MessageContentType` 新增 question prompt 类型
- 能把 prompt 投影成一条占位消息

验收：

- 模型发出 AskUserQuestion tool call 后，turn 不再继续执行
- 聊天列表出现一条可识别的 question prompt 卡片消息

### Task 2：单题卡片提交闭环

目标：

- 完成单题单选 / 多选交互
- 支持 `Other`
- 新增 `submitQuestionAnswers(...)`
- `resumeAfterQuestionAnswered(...)` 恢复当前 turn
- 恢复后 provider continuation 仍能生成对应的 `function_call_output`

验收：

- 单题问答后模型能继续当前 turn 并输出 final answer
- OpenAI Responses 风格 continuation 不会丢失 AskUserQuestion 的 call output

### Task 3：多题 wizard

目标：

- 一个卡片承载 1-4 题
- header 作为 wizard 顶部步骤标签
- 支持逐题切换与统一提交

验收：

- 多题场景可完整填写并一次提交
- 最终恢复只发生一次

### Task 4：结果投影、trace 与测试

目标：

- 为 interaction result 增加清晰消息摘要
- 补 trace 事件
- 补 widget/service/controller tests

验收：

- 用户能在消息流中回看问答结果
- trace 能区分 confirmation 与 ask-user-question

## 测试策略

### 单元测试

建议新增：

- AskUserQuestion request / response / payload 编解码测试
- `TurnHarness` interaction suspension/resume 测试
- `ChatInteractionCoordinator` 提交与取消测试

### Widget 测试

建议新增：

- 单题单选卡片
- 单题多选卡片
- `Other` 输入
- 多题 wizard 的下一步 / 上一步 / 提交

### 集成测试

建议覆盖：

- planner 产生 AskUserQuestion tool call
- UI 渲染卡片
- 用户回答
- 当前 turn 恢复并结束

## 风险与注意事项

### 1. provider continuation 恢复格式

如果当前 provider adapter 对 tool result continuation 有严格要求，需要确认 AskUserQuestion 恢复是否也要构造成与普通 tool result 相同的 provider continuation item。

### 2. step ledger 分类

如果当前 step summary 默认认为所有 step 都是“工具执行”，后续需要在 ledger builder 中补充 interaction step 的展示文本，否则 debug 信息会失真。

### 3. UI 草稿状态恢复

第一版不持久化草稿更简单，但如果 app 在用户填写中被杀死，卡片会回到未提交状态。这个 trade-off 可以接受，但需要在实现时明确。

### 4. recommendation 解析

第一版用 label 后缀 `(Recommended)` 解析足够，但应把这个规则集中在一个小 helper 里，不要分散在 widget 中重复判断。

## 结论

在当前项目中实现 Claude Code 风格的 `AskUserQuestion` 是可行的，且不需要推翻现有 agent/tool 架构。

最佳落地方式是：

- 保持 AskUserQuestion 为模型侧 tool
- 在运行时把它视为 interaction tool，而不是普通立即执行 tool
- 复用现有 turn suspension/resume 骨架
- 使用独立交互模型与 assistant 消息卡片
- 通过新增 `ChatInteractionCoordinator` 和 `awaitingUserInteraction` 等窄边界完成扩展

这条方案既能支持完整的单题/多题卡片，又能保持当前架构文档所描述的 controller/provider/service/tool 边界基本稳定。
