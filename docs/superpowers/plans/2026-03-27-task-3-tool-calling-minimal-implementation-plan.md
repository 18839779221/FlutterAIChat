# FlutterAIChat 任务 3：Tool Calling 最小闭环实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 FlutterAIChat 增加第一条真正可用的 Tool Calling 链路，让模型能够在必要时调用本地 `search_chat_history` 工具，再基于工具结果生成最终回答。

**Architecture:** 延续当前 `Riverpod -> ChatController -> ChatService -> BaseLLM -> ChatStorage/UI` 主干，不引入第二套并行消息系统。工具决策与执行由 `ToolCallService`、`ToolRegistry`、`ToolExecutor` 负责，工具执行结果继续复用任务 1 的类型化消息能力，以 `contentType = toolResult` 的消息持久化和渲染。

**Tech Stack:** Flutter、Dart、Riverpod、现有 `ConfigurableHttpLLM`、`ChatStorage`、flutter_test、TDD

---

## 文件职责映射

### 新建文件

- `lib/models/tool/tool_definition.dart`
  定义工具名称、描述、参数 schema 等静态元数据。
- `lib/models/tool/tool_call.dart`
  定义模型产出的工具调用请求，以及最小 JSON 解析/校验逻辑。
- `lib/models/tool/tool_result.dart`
  定义工具执行结果、展示文案和消息载荷序列化格式。
- `lib/services/tool_registry.dart`
  维护当前允许模型调用的工具定义集合，第一版只注册 `search_chat_history`。
- `lib/services/tool_executor.dart`
  负责执行本地工具。第一版只实现基于 `ChatStorage.getMessagesByGroup()` 的会话内历史搜索。
- `lib/services/tool_call_service.dart`
  负责“是否调用工具”的模型决策、决策结果解析、工具执行，以及给最终回答准备工具上下文。
- `test/services/tool_registry_test.dart`
  验证工具注册表只暴露允许的工具，并提供稳定元数据。
- `test/services/tool_executor_test.dart`
  验证 `search_chat_history` 的搜索结果、空结果和失败路径。
- `test/services/tool_call_service_test.dart`
  验证模型决策 JSON 的解析、未知工具兜底、以及执行结果到上下文的整理行为。
- `test/providers/chat_controller_tool_flow_test.dart`
  验证控制器层能把工具结果消息和最终回答消息正确写入 UI 与存储。

### 修改文件

- `lib/models/llm/base_llm.dart`
  增加工具决策所需的非流式 LLM 契约。
- `lib/models/llm/configurable_http_llm.dart`
  实现工具决策请求，并复用已有的非流式文本请求能力。
- `lib/services/chat_service.dart`
  增加“工具预处理 + 最终回答”的服务接口，并把工具上下文注入最终模型请求。
- `lib/providers/chat_providers.dart`
  在现有 `sendMessage()` 流程中接入工具调用最小闭环，并持久化 `toolResult` 消息。
- `lib/widgets/chat_message_list.dart`
  让 `toolResult` 消息显示最小执行状态，而不是仅靠纯文本回退。
- `test/widgets/chat_message_list_test.dart`
  补齐 `toolResult` 消息渲染测试。

### 直接复用，不新增抽象

- `lib/models/chat_message.dart`
  继续使用现有 `contentType`、`payloadJson`、`referenceJson` 作为消息信封。
- `lib/storage/chat_storage.dart`
  第一版直接复用 `getMessagesByGroup()` 获取当前分组消息，不为最小闭环额外扩展存储接口。
- `lib/database/database_helper.dart`
  第一版不改 schema，直接复用任务 1/2 已支持的类型化消息持久化能力。

## 验证命令

- 注册表测试：
  `flutter test test/services/tool_registry_test.dart`
- 执行器测试：
  `flutter test test/services/tool_executor_test.dart`
- 工具决策服务测试：
  `flutter test test/services/tool_call_service_test.dart`
- 控制器测试：
  `flutter test test/providers/chat_controller_tool_flow_test.dart`
- Widget 测试：
  `flutter test test/widgets/chat_message_list_test.dart`
- 任务 3 聚焦测试集：
  `flutter test test/services/tool_registry_test.dart test/services/tool_executor_test.dart test/services/tool_call_service_test.dart test/providers/chat_controller_tool_flow_test.dart test/widgets/chat_message_list_test.dart`
- 静态检查：
  `flutter analyze`

## 任务 1：定义工具模型与注册表

**涉及文件：**
- 新建：`lib/models/tool/tool_definition.dart`
- 新建：`lib/models/tool/tool_call.dart`
- 新建：`lib/models/tool/tool_result.dart`
- 新建：`lib/services/tool_registry.dart`
- 新建：`test/services/tool_registry_test.dart`

- [x] **步骤 1：先写注册表失败测试**

创建 `test/services/tool_registry_test.dart`，至少覆盖：

- 注册表默认只暴露一个工具 `search_chat_history`
- 该工具的 `name`、`description`、参数字段稳定
- 未注册工具无法通过名称查到定义

建议断言起点：

```dart
expect(registry.getAllTools(), hasLength(1));
expect(registry.getAllTools().single.name, 'search_chat_history');
expect(registry.findByName('missing_tool'), isNull);
```

- [x] **步骤 2：运行测试，确认先失败**

运行：`flutter test test/services/tool_registry_test.dart`

预期：FAIL，因为此时工具模型和注册表都还不存在。

- [x] **步骤 3：实现最小工具模型**

创建：

- `lib/models/tool/tool_definition.dart`
- `lib/models/tool/tool_call.dart`
- `lib/models/tool/tool_result.dart`

这一轮只实现任务 3 需要的最小字段：

- `ToolDefinition`: `name`、`description`、`parameters`
- `ToolCall`: `toolName`、`arguments`，以及最小 JSON 解析方法
- `ToolResult`: `toolName`、`status`、`displayText`、`payload`，以及 `toJson()/fromJson()`

不要在第一轮就做多工具继承体系或复杂泛型。

- [x] **步骤 4：实现注册表**

创建 `lib/services/tool_registry.dart`，只注册一个工具：

- `search_chat_history`

参数约束保持最小：

- `query`: 必填字符串
- `maxResults`: 可选整数，默认值在执行器里兜底

- [x] **步骤 5：重新运行注册表测试，确认通过**

运行：`flutter test test/services/tool_registry_test.dart`

预期：PASS。

- [x] **步骤 6：提交**

```bash
git add lib/models/tool/tool_definition.dart lib/models/tool/tool_call.dart lib/models/tool/tool_result.dart lib/services/tool_registry.dart test/services/tool_registry_test.dart
git commit -m "feat: add tool registry primitives"
```

## 任务 2：实现 `search_chat_history` 工具执行器

**涉及文件：**
- 新建：`lib/services/tool_executor.dart`
- 新建：`test/services/tool_executor_test.dart`

- [x] **步骤 1：先写执行器失败测试**

创建 `test/services/tool_executor_test.dart`，覆盖：

- 当前分组里存在匹配消息时，返回稳定结果对象
- 查询为空时，返回失败结果而不是抛出未处理异常
- 无匹配结果时，返回成功但结果列表为空
- 结果按“越新的消息越靠前”排序

建议至少断言：

```dart
expect(result.status, ToolExecutionStatus.success);
expect(result.payload['matches'], hasLength(2));
expect(result.displayText, '已执行：搜索历史记录');
```

以及：

```dart
expect(result.status, ToolExecutionStatus.failure);
expect(result.displayText, contains('搜索失败'));
```

- [x] **步骤 2：运行测试，确认先失败**

运行：`flutter test test/services/tool_executor_test.dart`

预期：FAIL，因为执行器还不存在。

- [x] **步骤 3：实现最小执行器**

创建 `lib/services/tool_executor.dart`：

- 通过构造函数接收 `ChatStorage`
- 提供一个聚焦方法，例如：

```dart
Future<ToolResult> executeSearchChatHistory({
  required int groupId,
  required String query,
  int maxResults = 3,
})
```

- 内部复用 `chatStorage.getMessagesByGroup(groupId)`
- 仅搜索当前分组、仅匹配 `text` 非空消息
- 返回结果时做预览截断，避免把整段长消息全部塞进 payload

第一版不要引入全文索引、跨分组搜索或复杂打分算法。

- [x] **步骤 4：重新运行执行器测试，确认通过**

运行：`flutter test test/services/tool_executor_test.dart`

预期：PASS。

- [x] **步骤 5：必要时补一个轻量重构**

只有在测试全绿之后才允许：

- 提取结果裁剪辅助方法
- 提取查询归一化逻辑

- [x] **步骤 6：提交**

```bash
git add lib/services/tool_executor.dart test/services/tool_executor_test.dart
git commit -m "feat: add search chat history tool executor"
```

## 任务 3：增加工具决策 LLM 契约与 ToolCallService

**涉及文件：**
- 修改：`lib/models/llm/base_llm.dart`
- 修改：`lib/models/llm/configurable_http_llm.dart`
- 新建：`lib/services/tool_call_service.dart`
- 新建：`test/services/tool_call_service_test.dart`

- [x] **步骤 1：先写 ToolCallService 失败测试**

创建 `test/services/tool_call_service_test.dart`，至少覆盖：

- 模型返回合法工具调用 JSON 时，得到有效 `ToolCall`
- 模型返回 `none` 或未知工具名时，不触发工具执行
- 模型返回非法 JSON 时，安全回退为“不调用工具”
- 成功执行后会产出可注入最终回答的工具上下文文本

示例断言起点：

```dart
expect(result.toolResult?.toolName, 'search_chat_history');
expect(result.additionalContextMessages, isNotEmpty);
```

以及：

```dart
expect(result.toolResult, isNull);
expect(result.additionalContextMessages, isEmpty);
```

- [x] **步骤 2：运行测试，确认先失败**

运行：`flutter test test/services/tool_call_service_test.dart`

预期：FAIL，因为当前没有工具决策契约或服务。

- [x] **步骤 3：更新 BaseLLM 契约**

修改 `lib/models/llm/base_llm.dart`，增加一个专用的非流式工具决策方法，例如：

```dart
Future<String> decideToolCall({
  required String userMessage,
  required List<ChatMessage> history,
  required List<ToolDefinition> tools,
});
```

不要复用 `chatStream()`。

- [x] **步骤 4：在 ConfigurableHttpLLM 中实现工具决策请求**

修改 `lib/models/llm/configurable_http_llm.dart`：

- 复用已有 `_sendTextRequest(...)`
- 使用固定 prompt，要求模型只返回：
  - `{"toolName":"search_chat_history","arguments":{"query":"...","maxResults":3}}`
  - 或 `{"toolName":"none"}`
- 不要在第一版尝试接通开放式函数调用协议

- [x] **步骤 5：实现 ToolCallService**

创建 `lib/services/tool_call_service.dart`，提供一个聚焦入口，例如：

```dart
Future<ToolPreparationResult> prepareToolContext({
  required int groupId,
  required String userMessage,
  required List<ChatMessage> history,
})
```

这个服务必须：

- 从 `ToolRegistry` 读取允许工具列表
- 调用 LLM 决策是否需要工具
- 解析并校验工具调用 JSON
- 只允许执行注册过的工具
- 调用 `ToolExecutor`
- 将工具执行结果整理成：
  - 可持久化的 `ToolResult`
  - 一到两条可注入最终回答的附加上下文消息

解析失败、未知工具、空参数时统一降级为“不调用工具”，不要抛异常打断主聊天流程。

- [x] **步骤 6：重新运行 ToolCallService 测试，确认通过**

运行：`flutter test test/services/tool_call_service_test.dart`

预期：PASS。

- [x] **步骤 7：提交**

```bash
git add lib/models/llm/base_llm.dart lib/models/llm/configurable_http_llm.dart lib/services/tool_call_service.dart test/services/tool_call_service_test.dart
git commit -m "feat: add tool decision service contract"
```

## 任务 4：把工具结果接入聊天主流程与 UI

**涉及文件：**
- 修改：`lib/services/chat_service.dart`
- 修改：`lib/providers/chat_providers.dart`
- 修改：`lib/widgets/chat_message_list.dart`
- 修改：`test/providers/chat_controller_tool_flow_test.dart`
- 修改：`test/widgets/chat_message_list_test.dart`

- [x] **步骤 1：先写控制器失败测试**

创建 `test/providers/chat_controller_tool_flow_test.dart`，至少覆盖：

- 成功路径：当工具被调用时，会新增一条 `toolResult` 助手消息，再生成最终回答消息
- 无工具路径：正常消息发送时不会新增 `toolResult` 消息
- 工具失败路径：仍有一条 `toolResult` 消息展示失败状态，但最终回答链路不崩溃

建议至少断言：

```dart
expect(toolMessage.contentType, MessageContentType.toolResult);
expect(toolMessage.payloadJson?['toolName'], 'search_chat_history');
```

以及：

```dart
expect(finalAssistantMessage.contentType, MessageContentType.plainText);
expect(finalAssistantMessage.status, MessageStatus.completed);
```

- [x] **步骤 2：先写 Widget 行为测试**

扩展 `test/widgets/chat_message_list_test.dart`，覆盖：

- `toolResult` 消息会显示最小执行状态
- `payloadJson` 为空或非法时，会安全回退到 `message.text`

不要删除任务 1/2 已有测试。

- [x] **步骤 3：运行测试，确认先失败**

运行：

- `flutter test test/providers/chat_controller_tool_flow_test.dart`
- `flutter test test/widgets/chat_message_list_test.dart`

预期：FAIL，因为当前主链路还没有 Tool Calling 集成。

- [x] **步骤 4：在 ChatService 中接入工具预处理**

修改 `lib/services/chat_service.dart`：

- 通过构造函数注入 `ToolCallService`
- 增加一个工具预处理入口，例如：

```dart
Future<ToolPreparationResult> prepareToolAssistance({
  required int groupId,
  required String userMessage,
  required List<ChatMessage> history,
})
```

- 在最终回答阶段，把 `ToolPreparationResult.additionalContextMessages` 追加到历史消息，再调用现有 `_llm.chatStream(...)`

任务 3 不要把工具调用和最终回答重新包装成新的大而全状态机。

- [x] **步骤 5：在 ChatController.sendMessage() 中接线**

修改 `lib/providers/chat_providers.dart`：

- 在创建最终 AI 占位消息前，先调用 `ChatService.prepareToolAssistance(...)`
- 若返回 `toolResult`，则：
  - 新建一条助手消息
  - `contentType = MessageContentType.toolResult`
  - `status = MessageStatus.completed`
  - `payloadJson = toolResult.toJson()`
  - `text = toolResult.displayText`
- 将该消息插入 UI 和存储
- 然后再继续现有 AI 最终回答占位与流式更新逻辑

重点保持：

- 原有纯聊天路径改动尽量小
- 工具结果消息与最终回答消息分开
- 工具元数据写入 `payloadJson`，不是拼进 Markdown 正文

- [x] **步骤 6：更新 ChatMessageList 的 `toolResult` 渲染**

修改 `lib/widgets/chat_message_list.dart`：

- 优先从 `payloadJson` 解析 `ToolResult`
- 第一版只展示最小状态，例如：
  - `已执行：搜索历史记录`
  - `找到 2 条历史消息`
  - 或 `搜索历史记录失败`
- 若解析失败，则回退为 `Text(message.text)`

保持 UI 克制，不在第一版做复杂卡片。

- [x] **步骤 7：重新运行聚焦测试，确认通过**

运行：

- `flutter test test/providers/chat_controller_tool_flow_test.dart`
- `flutter test test/widgets/chat_message_list_test.dart`

预期：PASS。

- [x] **步骤 8：提交**

```bash
git add lib/services/chat_service.dart lib/providers/chat_providers.dart lib/widgets/chat_message_list.dart test/providers/chat_controller_tool_flow_test.dart test/widgets/chat_message_list_test.dart
git commit -m "feat: wire tool calling into chat flow"
```

## 任务 5：任务 3 最终验证与收尾

**涉及文件：**
- 修改：`docs/superpowers/plans/2026-03-27-task-3-tool-calling-minimal-implementation-plan.md`

- [x] **步骤 1：运行任务 3 聚焦自动化测试集**

运行：

```bash
flutter test test/services/tool_registry_test.dart test/services/tool_executor_test.dart test/services/tool_call_service_test.dart test/providers/chat_controller_tool_flow_test.dart test/widgets/chat_message_list_test.dart
```

预期：PASS。

- [x] **步骤 2：运行静态检查**

运行：`flutter analyze`

预期：PASS，或只剩下明确记录过的既有无关 warning。

当前状态补充：
- 已使用 `fvm flutter analyze` 执行静态检查。
- 当前仍有 72 条既有 warning/info，主要集中在 `DatabaseHelper` 缺少 `@override`、若干 `withOpacity` 弃用提示、以及仓库历史测试/Markdown 组件 lint；本轮 Task 3 新增的明显 lint 已清理。

- [ ] **步骤 3：执行手动功能验证**

在 debug build 中验证：

- 普通聊天请求仍能正常发送
- 发送一个明显依赖历史上下文的问题，例如“我刚才提过的数据库版本是多少？”
- 工具触发时，聊天列表里会新增一条 `toolResult` 助手消息
- 最终回答能引用工具搜到的历史信息，而不是完全忽略它
- 工具未触发时，不会平白出现执行状态消息
- 工具失败或无结果时，界面仍有明确状态，最终回答流程不崩溃

- [x] **步骤 4：把本计划中的复选框更新完整**

- [ ] **步骤 5：提交**

```bash
git add docs/superpowers/plans/2026-03-27-task-3-tool-calling-minimal-implementation-plan.md
git commit -m "docs: add task 3 tool calling implementation plan"
```

## 执行注意事项

- 第一版只做一个工具：`search_chat_history`，不要顺手把 `extract_todos` 一起做掉。
- 第一版只搜当前分组消息，不扩大到所有分组或外部知识库。
- 不要引入开放式的多轮工具循环；本任务只允许“一次决策 -> 最多一次工具执行 -> 最终回答”。
- 不要把工具执行原始结果直接拼进用户可见 Markdown 正文；用户看到的是简化状态，结构化元数据继续放在 `payloadJson`。
- 如果模型返回非法工具调用 JSON，直接按“不调用工具”降级，不要让主对话失败。
