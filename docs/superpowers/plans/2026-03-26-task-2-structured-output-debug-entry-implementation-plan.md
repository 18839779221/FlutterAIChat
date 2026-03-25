# FlutterAIChat 任务 2：结构化输出调试入口实施计划

> **给执行型 Agent 的说明：** 实施本计划时，必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans` 子技能，并按任务逐项推进。步骤统一使用复选框语法 `- [ ]` 进行跟踪。

**目标：** 增加一个仅限调试环境使用的结构化输出入口，让开发者可以长按一条已完成的助手纯文本消息，对其生成结构化摘要卡片，并在任意失败场景下安全回退为普通文本。

**架构思路：** 保持现有流式聊天主链路不变，新增一条独立的非流式结构化整理链路。`ChatController` 负责编排动作，`ChatService` 负责调用 LLM 并串联解析器，`ResponseParserService` 负责校验原始模型输出，`ChatMessageList` 负责暴露 `kDebugMode` 下的长按调试入口以及 `structuredCard` 的真实渲染。

**技术栈：** Flutter、Dart、flutter_test、Riverpod、任务 1 已完成的类型化消息基础设施、DeepSeek 兼容 LLM 抽象、TDD。

---

## 文件职责映射

### 新建文件

- `lib/models/response/structured_summary_card.dart`
  定义任务 2 唯一使用的结构化摘要卡片 schema，以及对应的 JSON 序列化方法。
- `lib/services/response_parser_service.dart`
  负责把模型原始输出解析成合法的 `StructuredSummaryCard`，或在失败时产出普通文本回退结果。
- `test/services/chat_service_structured_output_test.dart`
  负责覆盖结构化整理服务链路，包括“请求级失败统一回退”的行为。
- `lib/widgets/structured_message/structured_summary_card_widget.dart`
  负责渲染 `StructuredSummaryCard`，不包含任何解析逻辑。
- `test/services/response_parser_service_test.dart`
  负责覆盖解析器的成功和失败路径。
- `test/widgets/structured_summary_card_widget_test.dart`
  负责覆盖结构化卡片组件渲染。
- `test/providers/chat_controller_structured_output_test.dart`
  负责覆盖调试入口动作的至少一条成功路径和一条回退路径。

### 修改文件

- `lib/models/llm/base_llm.dart`
  增加非流式结构化输出契约。
- `lib/models/llm/deepseek_llm.dart`
  实现任务 2 所需的固定 schema 结构化输出请求。
- `lib/database/database_helper.dart`
  增加或扩展消息更新 API，使结构化整理完成后的 `text`、`status`、`contentType`、`payloadJson` 能持久化到 SQLite。
- `lib/services/chat_service.dart`
  增加调试用结构化整理方法，并在内部调用 `ResponseParserService`。
- `lib/providers/chat_providers.dart`
  增加调试整理动作的控制器编排，以及必要的 provider 接线。
- `lib/widgets/chat_message_list.dart`
  增加仅调试模式可见的长按菜单项，并真正渲染 `structuredCard`。
- `test/database/database_helper_test.dart`
  补充结构化消息完成态写回数据库的测试覆盖。

### 直接复用，不新增抽象

- `lib/models/chat_message.dart`
  任务 1 已支持 `contentType` 和 `payloadJson`，本任务不再新建第二套消息信封模型。
- `lib/models/response/message_content_type.dart`
  已定义 `plainText` 和 `structuredCard`，直接复用。

## 验证命令

- 解析器测试：
  `flutter test test/services/response_parser_service_test.dart`
- 服务层测试：
  `flutter test test/services/chat_service_structured_output_test.dart`
- 数据库测试：
  `flutter test test/database/database_helper_test.dart`
- Widget 测试：
  `flutter test test/widgets/structured_summary_card_widget_test.dart`
- 控制器编排测试：
  `flutter test test/providers/chat_controller_structured_output_test.dart`
- 任务 2 聚焦测试集：
  `flutter test test/services/response_parser_service_test.dart test/services/chat_service_structured_output_test.dart test/database/database_helper_test.dart test/widgets/structured_summary_card_widget_test.dart test/providers/chat_controller_structured_output_test.dart`
- 静态检查：
  `flutter analyze`

## 任务 1：定义结构化摘要卡片模型与解析结果契约

**涉及文件：**
- 新建：`lib/models/response/structured_summary_card.dart`
- 新建：`lib/services/response_parser_service.dart`
- 测试：`test/services/response_parser_service_test.dart`

- [x] **步骤 1：先写失败测试**

创建 `test/services/response_parser_service_test.dart`，至少覆盖以下场景：

- 合法 JSON 且字段齐全时，返回结构化卡片成功结果
- 非法 JSON 时，返回普通文本回退结果
- 缺失必填字段时，返回普通文本回退结果
- 字段类型错误时，返回普通文本回退结果

示例测试起点：

```dart
test('合法 json 时返回结构化卡片', () {
  final service = ResponseParserService();

  final result = service.parseStructuredSummaryCard(
    '{"title":"Weekly Summary","summary":"A short summary","keyPoints":["A"],"actionItems":["B"],"risks":["C"]}',
  );

  expect(result.isStructuredCard, isTrue);
  expect(result.card?.title, 'Weekly Summary');
});
```

- [x] **步骤 2：运行测试，确认先失败**

运行：`flutter test test/services/response_parser_service_test.dart`

预期：FAIL，因为此时结构化卡片模型和解析服务都还不存在。

- [x] **步骤 3：实现结构化卡片模型**

创建 `lib/models/response/structured_summary_card.dart`，包含：

- 不可变字段：`title`、`summary`、`keyPoints`、`actionItems`、`risks`
- `fromJson(Map<String, dynamic>)`
- `toJson()`

字段命名必须与 spec 和最终 `payloadJson` 中的 key 一致。

- [x] **步骤 4：实现解析服务与最小结果类型**

创建 `lib/services/response_parser_service.dart`，包含：

- 一个专用于任务 2 的解析方法，例如 `parseStructuredSummaryCard(String rawOutput)`
- 一个最小结果契约，只暴露两种情况：
  - 成功：携带 `StructuredSummaryCard`
  - 失败：携带固定回退文案，例如 `结构化整理失败，请重试。`

失败时不要把原始 JSON 回传给调用方。

- [x] **步骤 5：重新运行解析器测试，确认通过**

运行：`flutter test test/services/response_parser_service_test.dart`

预期：PASS。

- [ ] **步骤 6：提交**

```bash
git add lib/models/response/structured_summary_card.dart lib/services/response_parser_service.dart test/services/response_parser_service_test.dart
git commit -m "feat: add structured summary parser"
```

## 任务 2：增加非流式结构化输出契约与服务层统一回退

**涉及文件：**
- 修改：`lib/models/llm/base_llm.dart`
- 修改：`lib/models/llm/deepseek_llm.dart`
- 修改：`lib/services/chat_service.dart`
- 新建：`test/services/chat_service_structured_output_test.dart`

- [x] **步骤 1：先写服务层失败测试**

创建 `test/services/chat_service_structured_output_test.dart`，覆盖：

- 成功路径：`ChatService` 返回已解析的结构化卡片结果，而不是原始 JSON
- 请求失败路径：当 LLM 抛异常时，`ChatService` 仍返回与解析失败相同的固定普通文本回退结果

这里的关键契约是：对于这个调试功能，`ChatService` 不能泄露原始 JSON，也不能把请求异常继续抛给控制器。

- [x] **步骤 2：运行服务层测试，确认先失败**

运行：`flutter test test/services/chat_service_structured_output_test.dart`

预期：FAIL，因为当前还没有结构化整理服务契约，也没有统一回退逻辑。

- [x] **步骤 3：更新 BaseLLM 契约**

修改 `lib/models/llm/base_llm.dart`，增加一个专用的非流式方法，例如：

```dart
Future<String> structureSummaryCard(String sourceText);
```

不要复用 `chatStream()`。

- [x] **步骤 4：实现 DeepSeek 结构化整理方法**

修改 `lib/models/llm/deepseek_llm.dart`：

- 发送非流式请求
- 使用固定 prompt，请模型只返回任务 2 所需 schema
- 返回原始文本结果给解析器

保持范围尽量小：一个 schema、一个方法、一种响应形态。

- [x] **步骤 5：增加 ChatService 的专用结构化整理方法**

修改 `lib/services/chat_service.dart`，增加一个方法，例如：

```dart
Future<StructuredSummaryParseResult> structureMessageForDebug(String sourceText)
```

这个方法必须：

- 调用新的 LLM 方法
- 将原始输出交给 `ResponseParserService`
- 只返回“结构化成功”或“普通文本回退”两种结果
- 捕获请求级异常，并统一转换成相同的固定回退结果

可以用当前代码风格注入或构造 `ResponseParserService`，但调用归属必须在 `ChatService` 内，不要放到 `ChatController`。

- [x] **步骤 6：重新运行服务层测试，确认通过**

运行：`flutter test test/services/chat_service_structured_output_test.dart`

预期：PASS。

- [ ] **步骤 7：提交**

```bash
git add lib/models/llm/base_llm.dart lib/models/llm/deepseek_llm.dart lib/services/chat_service.dart test/services/chat_service_structured_output_test.dart
git commit -m "feat: add structured output service contract"
```

## 任务 3：补齐结构化整理完成态的数据库持久化

**涉及文件：**
- 修改：`lib/database/database_helper.dart`
- 修改：`test/database/database_helper_test.dart`

- [x] **步骤 1：先写数据库失败测试**

扩展 `test/database/database_helper_test.dart`，验证一条已插入的助手消息后续可以被更新并持久化以下字段：

- 最终 `text`
- 最终 `status`
- 最终 `contentType`
- 最终 `payloadJson`

基于任务 1 已有的 schema 做补充，不要新建第二套存储结构。

- [x] **步骤 2：运行数据库测试，确认先失败**

运行：`flutter test test/database/database_helper_test.dart`

预期：FAIL，因为当前 `DatabaseHelper` 还没有一个专门用于“结构化整理完成态写回”的更新方法。

- [x] **步骤 3：增加数据库更新方法**

修改 `lib/database/database_helper.dart`，增加一个聚焦的更新 API，例如：

```dart
Future<void> updateStructuredMessage(
  int id, {
  required String text,
  required MessageStatus status,
  required MessageContentType contentType,
  String? payloadJson,
});
```

命名可以再优化，但要保证这个方法既能用于结构化成功，也能用于普通文本回退完成态。

- [x] **步骤 4：重新运行数据库测试，确认通过**

运行：`flutter test test/database/database_helper_test.dart`

预期：PASS。

- [ ] **步骤 5：提交**

```bash
git add lib/database/database_helper.dart test/database/database_helper_test.dart
git commit -m "feat: persist structured output message updates"
```

## 任务 4：增加控制器层调试整理编排

**涉及文件：**
- 修改：`lib/providers/chat_providers.dart`
- 测试：`test/providers/chat_controller_structured_output_test.dart`

- [x] **步骤 1：先写控制器编排失败测试**

创建 `test/providers/chat_controller_structured_output_test.dart`，至少覆盖：

- 成功路径：一条已完成的助手纯文本消息会生成一条新的结构化卡片助手消息
- 回退路径：解析失败时会生成一条新的普通文本回退助手消息
- 守卫路径：不支持的消息类型不会触发整理动作

使用 fake 或 stub 服务，不要在测试里访问真实网络。

建议至少包含这样的断言：

```dart
expect(newMessage.contentType, MessageContentType.structuredCard);
expect(newMessage.payloadJson, isNotNull);
```

以及：

```dart
expect(newMessage.contentType, MessageContentType.plainText);
expect(newMessage.status, MessageStatus.completed);
expect(newMessage.text, '结构化整理失败，请重试。');
```

- [x] **步骤 2：运行控制器测试，确认先失败**

运行：`flutter test test/providers/chat_controller_structured_output_test.dart`

预期：FAIL，因为当前还没有控制器动作和相关接线。

- [x] **步骤 3：必要时增加轻量 provider 接线**

如果当前代码结构更适合给 `ResponseParserService` 或结构化整理服务增加 provider，就在 `lib/providers/chat_providers.dart` 中补一个轻量接线，但不要借机做大规模 provider 重构。

- [x] **步骤 4：实现控制器动作**

修改 `lib/providers/chat_providers.dart`，增加一个方法，例如：

```dart
Future<void> structureMessageForDebug(ChatMessage message)
```

这个动作必须：

- 对不支持的消息直接返回
- 创建一条新的助手占位消息
- 调用 `ChatService.structureMessageForDebug(...)`
- 使用新的 `DatabaseHelper` 更新方法把最终结果写回数据库
- 成功时：
  - 设置 `contentType = structuredCard`
  - 将卡片序列化写入 `payloadJson`
  - 设置 `status = completed`
- 回退时：
  - 设置 `contentType = plainText`
  - 写入固定回退文案
  - 设置 `status = completed`

不要修改原始消息。

- [x] **步骤 5：重新运行控制器测试，确认通过**

运行：`flutter test test/providers/chat_controller_structured_output_test.dart`

预期：PASS。

- [ ] **步骤 6：提交**

```bash
git add lib/providers/chat_providers.dart test/providers/chat_controller_structured_output_test.dart
git commit -m "feat: orchestrate debug structured output flow"
```

## 任务 5：增加调试入口 UI 与真实结构化卡片渲染

**涉及文件：**
- 修改：`lib/widgets/chat_message_list.dart`
- 新建：`lib/widgets/structured_message/structured_summary_card_widget.dart`
- 测试：`test/widgets/structured_summary_card_widget_test.dart`
- 修改：`test/widgets/chat_message_list_test.dart`

- [x] **步骤 1：先写卡片组件失败测试**

创建 `test/widgets/structured_summary_card_widget_test.dart`，验证：

- 标题能渲染
- 摘要能渲染
- 列表区块能渲染各自内容
- 空列表字段不会导致组件崩溃

- [x] **步骤 2：先写 ChatMessageList 的任务 2 行为测试**

扩展 `test/widgets/chat_message_list_test.dart`，覆盖：

- `structuredCard` 消息会渲染专用 widget，而不是继续回退为普通文本
- 在 debug 模式下，符合条件的助手消息会暴露 `结构化整理（调试）` 菜单项
- 不支持的消息不会暴露该菜单项

保留任务 1 的现有测试，不要覆盖或删除。

- [x] **步骤 3：运行 Widget 测试，确认先失败**

运行：

- `flutter test test/widgets/structured_summary_card_widget_test.dart`
- `flutter test test/widgets/chat_message_list_test.dart`

预期：FAIL，因为当前既没有结构化卡片组件，也没有调试入口 UI。

- [x] **步骤 4：实现结构化卡片组件**

创建 `lib/widgets/structured_message/structured_summary_card_widget.dart`，提供一个简单但可读的布局，至少包括：

- title
- summary
- key points
- action items
- risks

保持克制，这只是调试验证能力，不是正式产品精修界面。

- [x] **步骤 5：更新 ChatMessageList 的渲染分发**

修改 `lib/widgets/chat_message_list.dart`：

- 对 `contentType = structuredCard` 的助手消息渲染 `StructuredSummaryCardWidget`
- 将 `payloadJson` 反序列化为 `StructuredSummaryCard`
- 如果载荷解析失败，回退到 `Text(message.text)`

- [x] **步骤 6：增加 debug-only 长按入口**

继续修改 `lib/widgets/chat_message_list.dart`：

- 用 `kDebugMode` 包住菜单项
- 只对“已完成的助手 `plainText` 消息”显示 `结构化整理（调试）`
- 菜单项点击后调用 `ChatController.structureMessageForDebug(message)`

不要在 release build 中暴露该入口。

- [x] **步骤 7：重新运行 Widget 测试，确认通过**

运行：

- `flutter test test/widgets/structured_summary_card_widget_test.dart`
- `flutter test test/widgets/chat_message_list_test.dart`

预期：PASS。

- [ ] **步骤 8：提交**

```bash
git add lib/widgets/chat_message_list.dart lib/widgets/structured_message/structured_summary_card_widget.dart test/widgets/chat_message_list_test.dart test/widgets/structured_summary_card_widget_test.dart
git commit -m "feat: add debug structured summary ui"
```

## 任务 6：任务 2 最终验证与手动调试验证

**涉及文件：**
- 修改：`docs/superpowers/plans/2026-03-26-task-2-structured-output-debug-entry-implementation-plan.md`

- [x] **步骤 1：运行任务 2 聚焦自动化测试集**

运行：

```bash
flutter test test/services/response_parser_service_test.dart test/services/chat_service_structured_output_test.dart test/database/database_helper_test.dart test/widgets/structured_summary_card_widget_test.dart test/providers/chat_controller_structured_output_test.dart test/widgets/chat_message_list_test.dart
```

预期：PASS。

- [x] **步骤 2：运行静态检查**

运行：`flutter analyze`

预期：PASS，或者只剩下明确记录过的既有无关 warning。

- [ ] **步骤 3：执行手动调试验证**

当前状态补充：
- 已验证 `flutter run -d macos --debug` 可以成功构建并启动应用，启动日志显示数据库初始化与连接测试通过，未出现任务 2 改动导致的启动时崩溃。
- 已通过直接写入本地 SQLite 的方式构造出一条“已完成的助手纯文本消息”，并确认应用启动后能正常加载该历史消息。
- 已通过桌面自动化触发调试整理动作；数据库中新增了两条新的助手消息，二者均为：
  - `text = 结构化整理失败，请重试。`
  - `status = completed`
  - `content_type = plainText`
  - `payload_json = NULL`
  且原始助手纯文本消息保持未修改，符合失败回退路径要求。
- 当前环境下 DeepSeek 网络请求会被系统拒绝，因此真实模型成功响应仍无法现场验证。
- 为补齐成功路径验证，已新增一个仅限 debug 的本地成功标记 `#debug-structured-success`，并通过自动化测试确认：
  - `ChatService` 命中该标记时会直接返回本地结构化卡片结果，不会访问 LLM。
  - `ChatController -> ChatService -> DatabaseHelper` 真实链路在该标记下会新增 `structuredCard` 消息，并写入 `payloadJson`。

在 debug build 中验证：

- 发送或加载一条已完成的助手纯文本消息
- 长按后能看到 `结构化整理（调试）`
- 触发后会新增一条结构化卡片消息
- 强制制造失败路径（例如 mock 一个非法响应，或临时让解析器返回失败）后，会新增一条普通文本回退消息
- 正常流式聊天主流程仍与改动前一致

- [x] **步骤 4：把本计划中的复选框更新完整**

- [ ] **步骤 5：提交**

```bash
git add docs/superpowers/plans/2026-03-26-task-2-structured-output-debug-entry-implementation-plan.md
git commit -m "docs: mark task 2 implementation plan progress"
```

## 执行注意事项

- 不要把这个功能做成正式产品能力，入口必须保持 debug-only。
- 不要借任务 2 顺手重构整条聊天架构。
- 任意失败路径都不能把原始模型 JSON 泄露到 UI。
- 继续复用任务 1 的类型化消息字段，不要发明第二套消息封装。
- 普通文本回退文案要固定，不要做“半解析半展示”的聪明恢复。
