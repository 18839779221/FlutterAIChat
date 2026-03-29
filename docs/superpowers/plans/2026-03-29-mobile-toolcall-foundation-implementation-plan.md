# 移动端 ToolCall 基础设施实施计划

> **给执行型 agent 的要求：** 必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans` 按任务逐步执行本计划。所有步骤使用复选框（`- [ ]`）语法跟踪。

**目标：** 为 FlutterAIChat 构建第一版可投入使用的移动端 ToolCall 基础设施，包括类型化工具消息、基于策略的确认机制、按工具名白名单、两个自动执行工具、四个默认确认工具，以及设置页中的白名单管理。

**架构：** 在现有类型化消息聊天链路上扩展出一条独立的 ToolCall 流程，而不是把工具执行硬塞进普通文本回复。第一版只做单步工具链路：模型决策、策略判断、必要时确认、执行工具、写回工具结果、可选的最终助手回复。继续复用已有的 `BaseLLM.decideToolCall()` 入口和当前最小工具原型文件，但要将其升级为清晰分层的注册、策略、编排和渲染结构。

**技术栈：** Flutter、Riverpod、SharedPreferences、现有可配置 HTTP LLM、类型化聊天消息、Widget 测试、Service 单元测试

---

## 文件结构

### 需要修改的现有文件

- `lib/models/response/message_content_type.dart`
  作用：扩展 ToolCall 相关消息类型。
- `lib/models/chat_message.dart`
  作用：确保新工具载荷仍能通过现有消息持久化结构安全保存。
- `lib/models/llm/base_llm.dart`
  作用：保留并说明工具决策入口，供新的编排层继续使用。
- `lib/services/chat_service.dart`
  作用：干净地委托工具准备与编排，而不是继续堆叠临时逻辑。
- `lib/providers/chat_providers.dart`
  作用：把工具消息接入聊天主流程，处理确认动作，并保持现有发送行为稳定。
- `lib/widgets/chat_message_list.dart`
  作用：把新增消息类型分发到专用 ToolCall Widget，并暴露确认动作。
- `lib/pages/settings_page.dart`
  作用：新增工具执行模式和白名单管理 UI。
- `lib/repositories/app_settings_repository.dart`
  作用：在现有运行时设置之外，持久化工具模式与按工具名白名单。
- `lib/models/tool/tool_call.dart`
  作用：将现有原始决策模型升级为更严格的调用解析入口。
- `lib/models/tool/tool_definition.dart`
  作用：扩展当前最小工具定义元数据。
- `lib/models/tool/tool_result.dart`
  作用：支持更丰富的执行状态和更适合渲染的结果字段。
- `lib/services/tool_call_service.dart`
  作用：要么重构为兼容层，要么把职责下放到更聚焦的 service 中。
- `lib/services/tool_registry.dart`
  作用：将当前只有一个工具的注册表升级为正式工具目录。
- `lib/services/tool_executor.dart`
  作用：保留现有历史搜索执行逻辑，并扩展为第一批工具的统一执行入口。

### 需要新增的文件

- `lib/models/tool/tool_invocation.dart`
  作用：定义工具调用与确认消息的类型化载荷。
- `lib/models/tool/tool_policy.dart`
  作用：定义工具执行模式、白名单数据和策略判断结果。
- `lib/services/tool_policy_service.dart`
  作用：判断工具是 `auto_run`、`require_confirmation` 还是 `blocked`。
- `lib/services/tool_decision_service.dart`
  作用：调用 LLM，解析严格 JSON，并校验工具名与参数结构。
- `lib/services/tool_orchestrator_service.dart`
  作用：协调决策、策略、执行、结果消息创建以及后续上下文拼装。
- `lib/widgets/tool_call/tool_confirmation_card_widget.dart`
  作用：渲染 `继续` / `取消` / `继续，以后不再确认`。
- `lib/widgets/tool_call/tool_invocation_card_widget.dart`
  作用：渲染计划中 / 执行中的工具状态。
- `lib/widgets/tool_call/tool_result_card_widget.dart`
  作用：渲染工具成功和失败结果。
- `test/models/tool/tool_invocation_test.dart`
  作用：验证调用模型解析与序列化。
- `test/services/tool_policy_service_test.dart`
  作用：验证模式 + 白名单下的策略行为。
- `test/services/tool_decision_service_test.dart`
  作用：验证严格决策解析和非法工具拒绝。
- `test/services/tool_executor_test.dart`
  作用：覆盖搜索和第一批非搜索工具执行逻辑。
- `test/services/tool_orchestrator_service_test.dart`
  作用：验证单步工具编排分支。
- `test/widgets/tool_confirmation_card_widget_test.dart`
  作用：验证三按钮确认交互。
- `test/widgets/tool_result_card_widget_test.dart`
  作用：验证成功/失败结果卡片渲染。

### 拆分原则说明

- 模型解析、策略判断、工具执行、工具编排必须分文件实现，不要让 `tool_call_service.dart` 膨胀成巨石类。
- 工具 UI Widget 要从 `chat_message_list.dart` 中拆开；列表只负责路由，不负责复杂布局。
- 第一版严格限制为单步工具链路，不在本计划中引入多步计划器或工具队列。

## 任务 1：扩展工具消息类型与载荷模型

**文件：**
- 修改：`lib/models/response/message_content_type.dart`
- 修改：`lib/models/chat_message.dart`
- 修改：`lib/models/tool/tool_call.dart`
- 修改：`lib/models/tool/tool_definition.dart`
- 修改：`lib/models/tool/tool_result.dart`
- 新增：`lib/models/tool/tool_invocation.dart`
- 新增：`lib/models/tool/tool_policy.dart`
- 测试：`test/models/tool/tool_invocation_test.dart`

- [ ] **步骤 1：先写失败测试**

补充以下测试：
- 可解析包含 `toolName`、`arguments`、`status`、`summary` 和 `requiresConfirmation` 的合法调用载荷
- 非法 `toolName` 会被拒绝
- 丰富版 `ToolResult` 可以正确序列化/反序列化
- 新增消息类型值能被正确保留和解析

- [ ] **步骤 2：运行测试并确认先失败**

运行：`flutter test test/models/tool/tool_invocation_test.dart`
预期：FAIL，因为新模型和/或枚举值尚不存在。

- [ ] **步骤 3：新增消息内容类型**

更新 `lib/models/response/message_content_type.dart`，新增：
- `toolInvocation`
- `actionConfirmation`

保留已有类型：
- `plainText`
- `structuredCard`
- `toolResult`

- [ ] **步骤 4：实现新的工具载荷模型**

新增 `tool_invocation.dart` 和 `tool_policy.dart`，并升级：
- `ToolCall`：继续作为 LLM 原始决策对象
- `ToolDefinition`：加入标题、schema、是否需确认、支持平台、风险等级
- `ToolResult`：加入更适合 UI 的摘要、状态、错误和载荷字段

- [ ] **步骤 5：确认 `ChatMessage` 仍能承载新的 JSON 载荷**

验证 `payloadJson` 和 `referenceJson` 仍能正确读写 JSON map，不破坏现有消息持久化逻辑。

- [ ] **步骤 6：再次运行测试并确认通过**

运行：`flutter test test/models/tool/tool_invocation_test.dart`
预期：PASS

- [ ] **步骤 7：提交**

```bash
git add lib/models/response/message_content_type.dart lib/models/chat_message.dart lib/models/tool/tool_call.dart lib/models/tool/tool_definition.dart lib/models/tool/tool_result.dart lib/models/tool/tool_invocation.dart lib/models/tool/tool_policy.dart test/models/tool/tool_invocation_test.dart
git commit -m "feat: add typed tool message models"
```

## 任务 2：补齐工具策略存储与决策逻辑

**文件：**
- 修改：`lib/repositories/app_settings_repository.dart`
- 新增：`lib/services/tool_policy_service.dart`
- 测试：`test/services/tool_policy_service_test.dart`

- [ ] **步骤 1：先写失败测试**

覆盖以下场景：
- 平衡模式下 `search_chat_history` 和 `fetch_webpage` 自动执行
- 平衡模式下 `save_note`、`create_reminder`、`create_calendar_event`、`share_result` 需要确认
- 工具加入白名单后变成 `auto_run`
- 工具从白名单移除后恢复确认流程

- [ ] **步骤 2：运行测试并确认先失败**

运行：`flutter test test/services/tool_policy_service_test.dart`
预期：FAIL，因为策略 service 和设置存储键尚不存在。

- [ ] **步骤 3：扩展设置存储，支持工具模式与白名单**

在 repository 中新增方法：
- 读取默认工具执行模式
- 保存默认工具执行模式
- 读取按工具名白名单
- 新增/移除白名单工具名

- [ ] **步骤 4：实现 `ToolPolicyService`**

实现一个聚焦的 service，它需要：
- 读取当前模式和白名单
- 结合工具元数据做判断
- 返回 `auto_run`、`require_confirmation` 或 `blocked`
- 提供“信任该工具”和“取消信任该工具”的辅助方法

- [ ] **步骤 5：再次运行测试并确认通过**

运行：`flutter test test/services/tool_policy_service_test.dart`
预期：PASS

- [ ] **步骤 6：提交**

```bash
git add lib/repositories/app_settings_repository.dart lib/services/tool_policy_service.dart test/services/tool_policy_service_test.dart
git commit -m "feat: add tool policy and whitelist storage"
```

## 任务 3：升级工具注册表与严格工具决策解析

**文件：**
- 修改：`lib/services/tool_registry.dart`
- 新增：`lib/services/tool_decision_service.dart`
- 修改：`lib/models/llm/base_llm.dart`
- 测试：`test/services/tool_decision_service_test.dart`

- [ ] **步骤 1：先写失败测试**

覆盖以下场景：
- 合法决策 JSON 能解析到已注册工具
- `{"toolName":"none"}` 返回无工具
- 未知工具名会被拒绝
- 非法 JSON 会被拒绝
- 缺失必要参数结构时会被拒绝

- [ ] **步骤 2：运行测试并确认先失败**

运行：`flutter test test/services/tool_decision_service_test.dart`
预期：FAIL，因为决策 service 还不存在。

- [ ] **步骤 3：扩展工具注册表，接入第一批 6 个工具**

注册以下工具：
- `search_chat_history`
- `fetch_webpage`
- `save_note`
- `create_reminder`
- `create_calendar_event`
- `share_result`

同时补充是否需确认和基础参数 schema。

- [ ] **步骤 4：实现 `ToolDecisionService`**

职责包括：
- 调用 `BaseLLM.decideToolCall()`
- 使用升级后的 `ToolCall` 解析原始 JSON
- 拒绝未知工具
- 拒绝非法参数结构
- 规范化处理 `none`

- [ ] **步骤 5：保留 `BaseLLM.decideToolCall()`，只更新必要注释/说明**

这一层接口先不要扩宽，保持 LLM 边界简单。

- [ ] **步骤 6：再次运行测试并确认通过**

运行：`flutter test test/services/tool_decision_service_test.dart`
预期：PASS

- [ ] **步骤 7：提交**

```bash
git add lib/services/tool_registry.dart lib/services/tool_decision_service.dart lib/models/llm/base_llm.dart test/services/tool_decision_service_test.dart
git commit -m "feat: add strict tool decision service"
```

## 任务 4：扩展工具执行器，支持第一批工具

**文件：**
- 修改：`lib/services/tool_executor.dart`
- 修改：`lib/storage/chat_storage.dart`（仅当笔记存储需要新增最小接口时）
- 测试：`test/services/tool_executor_test.dart`

- [ ] **步骤 1：先写失败测试**

覆盖以下场景：
- `search_chat_history` 执行成功
- `fetch_webpage` 使用 stub fetcher 执行成功
- `save_note` 在选定的第一版存储策略下执行成功
- 需确认的工具在 stub 平台适配器下返回结构化成功/失败结果

- [ ] **步骤 2：运行测试并确认先失败**

运行：`flutter test test/services/tool_executor_test.dart`
预期：FAIL，因为新的执行入口尚未实现。

- [ ] **步骤 3：先决定第一版最小适配边界**

为尚未存在的外部能力设计小接口，例如：
- 网页获取器
- 提醒适配器
- 日历适配器
- 分享适配器
- 可选的笔记存储适配器

不要让执行器直接依赖 Widget API。

- [ ] **步骤 4：实现执行器入口**

实现以下方法：
- `executeSearchChatHistory`
- `executeFetchWebpage`
- `executeSaveNote`
- `executeCreateReminder`
- `executeCreateCalendarEvent`
- `executeShareResult`

统一返回强类型 `ToolResult`，包含清晰摘要与失败信息。

- [ ] **步骤 5：再次运行测试并确认通过**

运行：`flutter test test/services/tool_executor_test.dart`
预期：PASS

- [ ] **步骤 6：提交**

```bash
git add lib/services/tool_executor.dart lib/storage/chat_storage.dart test/services/tool_executor_test.dart
git commit -m "feat: expand tool executor for first-wave tools"
```

## 任务 5：构建单步工具编排层

**文件：**
- 新增：`lib/services/tool_orchestrator_service.dart`
- 修改：`lib/services/tool_call_service.dart`
- 修改：`lib/services/chat_service.dart`
- 测试：`test/services/tool_orchestrator_service_test.dart`

- [ ] **步骤 1：先写失败测试**

覆盖以下场景：
- 无工具路径会回到普通聊天流程
- 自动执行工具路径会产出调用上下文和工具结果
- 需要确认的路径会返回等待确认状态，而不是直接执行
- 点击信任后，未来同名工具会变成 `auto_run`

- [ ] **步骤 2：运行测试并确认先失败**

运行：`flutter test test/services/tool_orchestrator_service_test.dart`
预期：FAIL，因为 orchestrator service 还不存在。

- [ ] **步骤 3：实现 `ToolOrchestratorService`**

它需要：
- 向 `ToolDecisionService` 请求决策
- 向 `ToolPolicyService` 请求执行策略
- 构建 `ToolInvocation` 载荷
- 根据策略走确认或执行
- 将结果打包给聊天层使用

- [ ] **步骤 4：重构现有 `tool_call_service.dart` 的职责**

二选一，保持结构清晰：
- 把它改造成委托给 orchestrator 的兼容 façade
- 或精简它，把真实编排逻辑全部搬到新 service

不要让两个地方同时保留重复编排逻辑。

- [ ] **步骤 5：更新 `ChatService` 以接入 orchestrator**

保留 `ChatService` 作为聊天业务入口，但停止让它承载临时堆叠的工具逻辑。

- [ ] **步骤 6：再次运行测试并确认通过**

运行：`flutter test test/services/tool_orchestrator_service_test.dart`
预期：PASS

- [ ] **步骤 7：提交**

```bash
git add lib/services/tool_orchestrator_service.dart lib/services/tool_call_service.dart lib/services/chat_service.dart test/services/tool_orchestrator_service_test.dart
git commit -m "feat: add single-step tool orchestration"
```

## 任务 6：补齐工具确认卡片与结果卡片 Widget

**文件：**
- 新增：`lib/widgets/tool_call/tool_confirmation_card_widget.dart`
- 新增：`lib/widgets/tool_call/tool_invocation_card_widget.dart`
- 新增：`lib/widgets/tool_call/tool_result_card_widget.dart`
- 修改：`lib/widgets/chat_message_list.dart`
- 测试：`test/widgets/tool_confirmation_card_widget_test.dart`
- 测试：`test/widgets/tool_result_card_widget_test.dart`

- [ ] **步骤 1：先写失败测试**

覆盖以下场景：
- 确认卡片渲染三个动作按钮
- 点击第三个动作会走信任回调
- 结果卡片能正确渲染成功和失败摘要
- 调用中卡片能稳定展示运行状态

- [ ] **步骤 2：运行测试并确认先失败**

运行：`flutter test test/widgets/tool_confirmation_card_widget_test.dart test/widgets/tool_result_card_widget_test.dart`
预期：FAIL，因为相关 Widget 和渲染路由尚不存在。

- [ ] **步骤 3：实现工具 Widget**

实现以下组件：
- 确认卡片
- 调用/执行中卡片
- 结果卡片

默认不展示原始 JSON，而是展示用户可读摘要，并可选提供简洁详情区。

- [ ] **步骤 4：更新 `chat_message_list.dart` 路由**

让新增 `contentType` 正确分发到新 Widget。

- [ ] **步骤 5：再次运行测试并确认通过**

运行：`flutter test test/widgets/tool_confirmation_card_widget_test.dart test/widgets/tool_result_card_widget_test.dart`
预期：PASS

- [ ] **步骤 6：提交**

```bash
git add lib/widgets/tool_call/tool_confirmation_card_widget.dart lib/widgets/tool_call/tool_invocation_card_widget.dart lib/widgets/tool_call/tool_result_card_widget.dart lib/widgets/chat_message_list.dart test/widgets/tool_confirmation_card_widget_test.dart test/widgets/tool_result_card_widget_test.dart
git commit -m "feat: add tool confirmation and result cards"
```

## 任务 7：把工具流程接入 ChatController

**文件：**
- 修改：`lib/providers/chat_providers.dart`
- 测试：`test/providers/chat_controller_toolcall_test.dart`

- [ ] **步骤 1：先写失败测试**

覆盖以下场景：
- 无工具时发送消息行为与当前保持一致
- 自动执行工具会插入工具调用 / 结果消息
- 需确认工具会插入等待确认消息
- 点击“继续，以后不再确认”会同时执行并更新白名单

- [ ] **步骤 2：运行测试并确认先失败**

运行：`flutter test test/providers/chat_controller_toolcall_test.dart`
预期：FAIL，因为 controller 尚未支持新的工具消息状态。

- [ ] **步骤 3：扩展 controller 的发送流程**

实现以下单步分支：
- 先保存用户消息
- 再调用工具 orchestrator
- 需要确认时插入确认消息
- 自动执行时写回工具结果消息
- 再决定是否进入最终助手回复路径

- [ ] **步骤 4：为确认按钮增加 controller 动作**

实现聚焦的处理方法：
- 继续
- 取消
- 继续并信任工具

这些处理方法需要负责更新消息状态、调用策略 service，并决定执行或终止挂起的工具调用。

- [ ] **步骤 5：再次运行测试并确认通过**

运行：`flutter test test/providers/chat_controller_toolcall_test.dart`
预期：PASS

- [ ] **步骤 6：提交**

```bash
git add lib/providers/chat_providers.dart test/providers/chat_controller_toolcall_test.dart
git commit -m "feat: integrate tool flow into chat controller"
```

## 任务 8：在设置页加入工具模式与白名单管理

**文件：**
- 修改：`lib/pages/settings_page.dart`
- 可选测试：`test/pages/settings_page_tool_settings_test.dart`

- [ ] **步骤 1：先写失败测试**

覆盖以下场景：
- 页面展示当前工具模式
- 页面展示白名单条目
- 移除某条白名单会触发 repository 更新

如果页面测试在第一轮实现中太脆弱，则先把这部分降级为手动验证清单，待 UI 稳定后再补 Widget 测试。

- [ ] **步骤 2：运行测试并确认先失败**

运行：`flutter test test/pages/settings_page_tool_settings_test.dart`
预期：FAIL，因为工具设置 UI 还不存在。

- [ ] **步骤 3：新增工具设置区域**

至少包含：
- 默认工具执行模式选择器
- 白名单列表
- 白名单移除操作

- [ ] **步骤 4：运行测试或执行手动验证**

如果测试文件已存在：
运行：`flutter test test/pages/settings_page_tool_settings_test.dart`
预期：PASS

如果暂不适合写页面测试，则手动验证：
- 模式切换可持久化
- 白名单移除可持久化
- 被移除的工具后续重新恢复确认

- [ ] **步骤 5：提交**

```bash
git add lib/pages/settings_page.dart test/pages/settings_page_tool_settings_test.dart
git commit -m "feat: add tool settings management"
```

## 任务 9：回归验证

**文件：**
- 只验证；除非发现问题，否则不应新增源文件

- [ ] **步骤 1：运行聚焦的 ToolCall 测试**

运行：
```bash
flutter test test/models/tool/tool_invocation_test.dart test/services/tool_policy_service_test.dart test/services/tool_decision_service_test.dart test/services/tool_executor_test.dart test/services/tool_orchestrator_service_test.dart test/widgets/tool_confirmation_card_widget_test.dart test/widgets/tool_result_card_widget_test.dart test/providers/chat_controller_toolcall_test.dart
```

预期：PASS

- [ ] **步骤 2：运行现有相关回归测试**

运行：
```bash
flutter test test/services/chat_service_structured_output_test.dart test/providers/chat_controller_structured_output_test.dart test/widgets/chat_message_list_test.dart test/widgets/structured_summary_card_widget_test.dart test/services/response_parser_service_test.dart
```

预期：PASS

- [ ] **步骤 3：运行 analyze**

运行：`flutter analyze`
预期：不出现新的 ToolCall 相关错误；如果仍有历史 warning，需要明确记录。

- [ ] **步骤 4：手动验证**

在 debug 构建中至少验证：
- `search_chat_history` 自动执行
- `fetch_webpage` 自动执行
- `save_note` 默认确认
- `create_reminder` 默认确认
- 第三个按钮 `继续，以后不再确认`
- 设置页中移除白名单
- 工具执行失败时的回退展示

- [ ] **步骤 5：最终提交**

```bash
git add .
git commit -m "feat: complete mobile toolcall foundation"
```

## 复核说明

- 本计划的意图是升级现有最小工具原型，而不是粗暴推翻重写。
- 第一版必须保持单步工具链路，不引入多工具计划、多轮自动循环执行或自主重试。
- 确认卡片中的第三个动作是硬性需求，不是加分项。
- 如果某些平台工具适配器在第一轮成本过高，应优先保留清晰的注入边界，哪怕先用 stub 接通 UI 和编排链路，也不要把结构做乱。
