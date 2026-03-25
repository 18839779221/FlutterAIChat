# FlutterAIChat 任务 1：类型化消息基础设施实施计划

> **给执行型 Agent 的说明：** 实施本计划时，必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans` 子技能，并按任务逐项推进。步骤统一使用复选框语法 `- [ ]` 进行跟踪。

**目标：** 为 FlutterAIChat 增加类型化消息元数据与 JSON 载荷存储能力，让后续结构化输出、工具结果等功能都能建立在稳定的消息模型、数据库字段和渲染分发层之上。

**架构思路：** 保持 `ChatMessage` 作为中心消息模型，但扩展出 `contentType`、`payloadJson`、`referenceJson` 三个字段。数据库直接持久化这些字段，UI 层在 `ChatMessageList` 中增加轻量的按类型分发渲染逻辑，并在新类型尚未实现时统一回退到 `text` 文本展示。这样任务 1 改动范围可控，同时能为任务 2 留出稳定接口。

**技术栈：** Flutter、Dart、flutter_test、sqflite、现有 Riverpod/UI 结构、TDD。

---

## 文件职责映射

### 新建文件

- `lib/models/response/message_content_type.dart`
  负责定义第一版消息内容类型枚举及字符串解析辅助方法。
- `lib/models/response/structured_card.dart`
  负责预留一个最小结构化卡片模型，为后续任务做准备。
- `lib/models/response/message_payload.dart`
  负责提供一个轻量 payload 包装/辅助模型，给后续类型化消息解析预留接口。
- `test/models/chat_message_test.dart`
  负责验证 `ChatMessage` 的序列化和类型化字段行为。
- `test/widgets/chat_message_list_test.dart`
  负责验证按类型分发渲染和安全回退行为。

### 修改文件

- `lib/models/chat_message.dart`
  负责承载 `contentType`、`payloadJson`、`referenceJson` 并安全序列化。
- `lib/database/database_helper.dart`
  负责把数据库 schema 升到版本 `6`，并持久化新的消息列。
- `lib/widgets/chat_message_list.dart`
  负责按 `contentType` 分发助手消息渲染，并在无法处理时安全回退到 `text`。

### 本计划暂缓的部分

- `test/database/database_helper_test.dart`
  原因：如果当前仓库的 sqflite 集成测试环境搭建成本较高，可以先用模型测试 + Widget 测试 + 手动数据库验证完成任务 1。若接入成本不高，则在执行时追加该测试文件。

## 验证命令

- 模型测试：
  `flutter test test/models/chat_message_test.dart`
- Widget 测试：
  `flutter test test/widgets/chat_message_list_test.dart`
- 聚焦验证：
  `flutter test test/models/chat_message_test.dart test/widgets/chat_message_list_test.dart`
- 静态检查：
  `flutter analyze`

## 任务 1：定义消息类型与载荷骨架

**涉及文件：**
- 新建：`lib/models/response/message_content_type.dart`
- 新建：`lib/models/response/structured_card.dart`
- 新建：`lib/models/response/message_payload.dart`
- 测试：`test/models/chat_message_test.dart`

- [ ] **步骤 1：先写失败测试**

在 `test/models/chat_message_test.dart` 中先写测试，验证：

- 新建 `ChatMessage` 时默认 `contentType` 为 `MessageContentType.plainText`
- 可以显式设置 `contentType`

示例：

```dart
test('chat message defaults to plainText content type', () {
  final message = ChatMessage(
    text: 'hello',
    role: MessageRole.user,
  );

  expect(message.contentType, MessageContentType.plainText);
});
```

- [ ] **步骤 2：运行测试，确认它先失败**

运行：`flutter test test/models/chat_message_test.dart`

预期：FAIL，因为此时 `MessageContentType` 和 `contentType` 还不存在。

- [ ] **步骤 3：写最小实现**

新建：

- `lib/models/response/message_content_type.dart`
- `lib/models/response/structured_card.dart`
- `lib/models/response/message_payload.dart`

这一轮只实现：

- `MessageContentType` 枚举：`plainText`、`structuredCard`、`toolResult`
- 从字符串解析并在未知值时回退到 `plainText`
- 最小占位模型，只保留基础字段与最简单的序列化辅助

- [ ] **步骤 4：重新运行测试，确认通过**

运行：`flutter test test/models/chat_message_test.dart`

预期：PASS。

- [ ] **步骤 5：提交**

```bash
git add lib/models/response/message_content_type.dart lib/models/response/structured_card.dart lib/models/response/message_payload.dart test/models/chat_message_test.dart
git commit -m "feat: add typed message content enums"
```

## 任务 2：扩展 ChatMessage 的序列化能力

**涉及文件：**
- 修改：`lib/models/chat_message.dart`
- 测试：`test/models/chat_message_test.dart`

- [ ] **步骤 1：先写失败测试**

补充测试，验证：

- `toMap()` 会输出 `content_type`、`payload_json`、`reference_json`
- `fromMap()` 能正确恢复这些字段
- 未知 `content_type` 会回退到 `plainText`
- `payload_json` 和 `reference_json` 为空时不会崩溃

示例：

```dart
test('chat message serializes typed payload fields', () {
  final message = ChatMessage(
    text: 'fallback text',
    role: MessageRole.assistant,
    contentType: MessageContentType.structuredCard,
    payloadJson: '{"title":"Weekly Summary"}',
    referenceJson: '[{"id":"doc-1"}]',
  );

  final map = message.toMap();

  expect(map['content_type'], 'structuredCard');
  expect(map['payload_json'], '{"title":"Weekly Summary"}');
  expect(map['reference_json'], '[{"id":"doc-1"}]');
});
```

- [ ] **步骤 2：运行测试，确认它先失败**

运行：`flutter test test/models/chat_message_test.dart`

预期：FAIL，因为 `ChatMessage` 还没有这些字段。

- [ ] **步骤 3：写最小实现**

修改 `lib/models/chat_message.dart`：

- 引入 `MessageContentType`
- 新增 `contentType`、`payloadJson`、`referenceJson`
- 更新构造函数默认值
- 更新 `toMap()`
- 更新 `fromMap()`
- 更新 `copyWith()`

除测试要求外，不做额外抽象。

- [ ] **步骤 4：重新运行测试，确认通过**

运行：`flutter test test/models/chat_message_test.dart`

预期：PASS。

- [ ] **步骤 5：必要时做轻量重构**

只有在测试全绿之后才允许：

- 提取很小的字符串转枚举辅助逻辑
- 做最小的可读性优化

- [ ] **步骤 6：提交**

```bash
git add lib/models/chat_message.dart test/models/chat_message_test.dart
git commit -m "feat: add typed payload fields to chat message"
```

## 任务 3：为类型化消息增加 SQLite 字段

**涉及文件：**
- 修改：`lib/database/database_helper.dart`
- 测试：`test/models/chat_message_test.dart`

- [ ] **步骤 1：先写失败测试**

先在 `test/models/chat_message_test.dart` 中补一个“面向数据库字段”的测试，验证 `ChatMessage.toMap()` 已经具备新 schema 需要的 key。

如果当前仓库接入 sqflite 集成测试很顺手，再额外新建：

- `test/database/database_helper_test.dart`

并补一条插入后再读取的集成测试。

- [ ] **步骤 2：运行测试，确认红灯**

运行：`flutter test test/models/chat_message_test.dart`

预期：如果 map 结构还没对齐，则 FAIL；如果任务 2 已经对齐，那就补数据库集成测试作为这一轮的 RED。

- [ ] **步骤 3：写最小实现**

修改 `lib/database/database_helper.dart`：

- 数据库版本从 `5` 升到 `6`
- 建表 SQL 中新增 `content_type`、`payload_json`、`reference_json`
- 增加版本 `6` 的升级逻辑，给 `messages` 表补这 3 列

因为你已经允许清空开发数据库，所以迁移逻辑保持简单即可。

- [ ] **步骤 4：运行验证**

运行：

- `flutter test test/models/chat_message_test.dart`
- 如果补了数据库测试，再运行 `flutter test test/database/database_helper_test.dart`

预期：PASS。

- [ ] **步骤 5：做一次手动冒烟验证**

必要时先删除本机开发数据库，然后启动 App，发一条消息，确认：

- 应用能正常启动
- 插入消息不会报 SQL 错误

- [ ] **步骤 6：提交**

```bash
git add lib/database/database_helper.dart test/models/chat_message_test.dart test/database/database_helper_test.dart
git commit -m "feat: persist typed message fields in database"
```

## 任务 4：在 ChatMessageList 中增加类型分发与安全回退

**涉及文件：**
- 修改：`lib/widgets/chat_message_list.dart`
- 测试：`test/widgets/chat_message_list_test.dart`

- [ ] **步骤 1：先写失败测试**

在 `test/widgets/chat_message_list_test.dart` 中补测试，覆盖：

- `plainText` 助手消息仍走当前渲染路径
- `structuredCard` 在尚未实现专用渲染器时会回退到 `text`
- `toolResult` 在尚未实现专用渲染器时会回退到 `text`
- `payloadJson` 为空、非法、未知类型时不会导致渲染崩溃

测试尽量使用真实 `ChatMessage`，不要 mock 渲染分支行为。

- [ ] **步骤 2：运行测试，确认它先失败**

运行：`flutter test test/widgets/chat_message_list_test.dart`

预期：FAIL，因为现在还没有类型分发逻辑。

- [ ] **步骤 3：写最小实现**

修改 `lib/widgets/chat_message_list.dart`：

- 按 `contentType` 分发助手消息渲染
- 用户消息保持原样
- `plainText` 继续走原有 Markdown / Text 路径
- `structuredCard`、`toolResult` 先统一回退为 `message.text`

任务 1 不引入真正的结构化卡片组件。

- [ ] **步骤 4：重新运行 Widget 测试，确认通过**

运行：`flutter test test/widgets/chat_message_list_test.dart`

预期：PASS。

- [ ] **步骤 5：跑完整聚焦验证**

运行：

- `flutter test test/models/chat_message_test.dart test/widgets/chat_message_list_test.dart`
- `flutter analyze`

预期：PASS，且不引入新的 analyzer 错误。

- [ ] **步骤 6：提交**

```bash
git add lib/widgets/chat_message_list.dart test/widgets/chat_message_list_test.dart
git commit -m "feat: add typed message render dispatch"
```

## 任务 5：任务 1 最终验证与收尾

**涉及文件：**
- 修改：`docs/superpowers/plans/2026-03-25-task-1-typed-message-foundation-implementation-plan.md`

- [ ] **步骤 1：如有 schema 漂移问题，删除本机开发数据库**

只有在启动或迁移失败时才执行。你已经明确允许清空开发数据库。

- [ ] **步骤 2：运行最终验证**

运行：

- `flutter test test/models/chat_message_test.dart test/widgets/chat_message_list_test.dart`
- `flutter analyze`
- 可选：`flutter test test/database/database_helper_test.dart`

预期：PASS。

- [ ] **步骤 3：手动验证应用主流程**

检查：

- App 能正常启动
- 能创建并发送消息
- 聊天列表仍能正常显示用户/助手消息
- 启动和发消息过程中没有 SQL 报错

- [ ] **步骤 4：把本计划中的复选框勾完**

- [ ] **步骤 5：提交**

```bash
git add .
git commit -m "feat: complete typed message foundation"
```

## 执行注意事项

- 在整个任务 1 中，`text` 仍然是最终兜底展示字段。
- 任务 1 不实现真实结构化卡片渲染。
- 任务 1 不提前实现 Tool Calling 或知识引用业务。
- 如果数据库集成测试明显拖慢进度，就优先保证模型测试 + Widget 测试 + 手动数据库验证先落地，数据库自动化测试可以在后续补齐。
