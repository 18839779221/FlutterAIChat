# 图片上传 V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为当前无自有后端、客户端直连 provider 的 Flutter AI Chat App 增加消息级图片上传能力，支持图片选择、消息持久化、时间线渲染，以及 OpenAI Responses / Chat Completions / Anthropic Messages 三套协议的图片输入。

**Architecture:** 该功能围绕一个新的消息级 `ChatAttachment` 域模型展开。UI 负责采集与展示图片，发送编排负责在消息发送事务中管理图片状态，LLM adapter 负责把统一 attachment 模型映射为各 provider 的原生图片输入结构；provider 能力差异保持在 adapter / runtime 边界，不回流到 `TurnHarness` 或普通聊天消息语义层。

**Tech Stack:** Flutter, Riverpod, sqflite, path_provider, 图片选择插件（建议 `image_picker`），OpenAI / Anthropic SDK-backed adapters, Flutter widget tests, `fvm flutter` test/analyze

---

## File Structure

### New files

- `lib/models/chat/chat_attachment.dart`
  - 消息级图片附件领域模型、枚举、序列化
- `lib/models/chat/send_message_request.dart`
  - 发送输入对象，承载 `text + attachments`
- `lib/services/attachments/chat_attachment_classifier.dart`
  - 图片类型识别与输入合法性判断
- `lib/services/attachments/chat_attachment_storage_service.dart`
  - 本地图片复制、缩略图路径分配、清理接口
- `lib/services/attachments/chat_attachment_picker_service.dart`
  - 抽象图片选择入口，隔离 `image_picker`
- `lib/services/attachments/chat_attachment_payload_codec.dart`
  - provider adapter 共用的 attachment payload 辅助方法
- `lib/widgets/chat_input_attachment_strip.dart`
  - 输入区图片列表 UI
- `lib/widgets/chat_message_image_attachments.dart`
  - 时间线用户图片卡片 UI
- `test/models/chat/chat_attachment_test.dart`
- `test/services/attachments/chat_attachment_classifier_test.dart`
- `test/services/attachments/chat_attachment_storage_service_test.dart`
- `test/widgets/chat_input_attachment_strip_test.dart`
- `test/widgets/chat_message_image_attachments_test.dart`
- `test/models/llm/adapters/image_input_adapter_contract_test.dart`

### Modified files

- `pubspec.yaml`
  - 新增图片选择依赖
- `lib/models/chat_message.dart`
  - 为消息提供 attachment 引用能力或关联字段
- `lib/models/response/message_content_type.dart`
  - 如有必要，补充图片消息/附件承载语义
- `lib/database/database_helper.dart`
  - 新增 `message_attachments` 表与 migration
- `lib/storage/chat_storage.dart`
  - 增加附件读写接口
- `lib/storage/web_chat_storage.dart`
  - Web 存储实现同步支持 attachment 元数据
- `lib/controllers/chat_controller.dart`
  - 发送入口切换到 `SendMessageRequest`
- `lib/controllers/chat_send_coordinator.dart`
  - 图片消息发送编排、状态机、日志
- `lib/providers/chat_dependency_providers.dart`
  - 注册 attachment picker/storage service provider
- `lib/providers/chat_providers.dart`
  - 暴露发送入口、attachment 相关 provider
- `lib/widgets/chat_input.dart`
  - 集成图片入口与 attachment strip
- `lib/widgets/chat_message_list.dart`
  - 接入图片附件渲染
- `lib/models/llm/adapters/provider_capabilities.dart`
  - 增加图片输入能力矩阵
- `lib/models/llm/adapters/sdk_responses_adapter.dart`
  - 支持 Responses 图片输入 payload
- `lib/models/llm/adapters/sdk_chat_completions_adapter.dart`
  - 支持 Chat Completions 图片输入 payload 或阻止
- `lib/models/llm/adapters/sdk_anthropic_messages_adapter.dart`
  - 支持 Anthropic 图片 block
- `test/controllers/chat_send_coordinator_test.dart`
  - 覆盖图片消息发送状态机
- `test/widgets/chat_input_test.dart`
  - 覆盖图片选择与发送 UI
- `test/models/llm/configurable_http_llm_test.dart`
  - 覆盖新 capability / payload 行为
- `README.md`
  - 更新功能描述
- `AGENTS.md`
  - 如新增图片上传开发约束或验证命令，补充说明
- `docs/feature_todo.md`
  - 将“支持多模态附件”里的图片 V1 状态同步

### Existing files to inspect during implementation

- `lib/controllers/chat_send_coordinator.dart`
- `lib/controllers/chat_controller.dart`
- `lib/widgets/chat_input.dart`
- `lib/models/chat_message.dart`
- `lib/database/database_helper.dart`
- `lib/models/llm/adapters/sdk_responses_adapter.dart`
- `lib/models/llm/adapters/sdk_chat_completions_adapter.dart`
- `lib/models/llm/adapters/sdk_anthropic_messages_adapter.dart`
- `lib/models/llm/configurable_http_llm.dart`
- `test/controllers/chat_send_coordinator_test.dart`
- `test/widgets/chat_input_test.dart`

## Task 1: 定义图片附件领域模型与发送输入对象

**Files:**
- Create: `lib/models/chat/chat_attachment.dart`
- Create: `lib/models/chat/send_message_request.dart`
- Test: `test/models/chat/chat_attachment_test.dart`

- [ ] **Step 1: 写一个失败的 attachment model 测试**

```dart
test('chat attachment serializes image metadata and provider refs', () {
  final attachment = ChatAttachment.image(
    localId: 'att-1',
    fileName: 'demo.png',
    mimeType: 'image/png',
    byteSize: 128,
    localPath: '/tmp/demo.png',
  );

  final encoded = attachment.toJson();
  final decoded = ChatAttachment.fromJson(encoded);

  expect(decoded.kind, ChatAttachmentKind.image);
  expect(decoded.fileName, 'demo.png');
  expect(decoded.mimeType, 'image/png');
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `fvm flutter test test/models/chat/chat_attachment_test.dart`

Expected: FAIL，提示 `ChatAttachment` 未定义。

- [ ] **Step 3: 最小实现 `ChatAttachment` 与 `SendMessageRequest`**

Implementation notes:
- `ChatAttachment` 至少包含 spec 中的图片字段与状态枚举
- `SendMessageRequest` 只先包含 `text` 与 `attachments`
- 注释覆盖公共字段与 wire 语义

- [ ] **Step 4: 再次运行测试确认通过**

Run: `fvm flutter test test/models/chat/chat_attachment_test.dart`

Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add \
  lib/models/chat/chat_attachment.dart \
  lib/models/chat/send_message_request.dart \
  test/models/chat/chat_attachment_test.dart
git commit -m "feat(chat): add image attachment models"
```

## Task 2: 增加附件分类与本地存储服务

**Files:**
- Create: `lib/services/attachments/chat_attachment_classifier.dart`
- Create: `lib/services/attachments/chat_attachment_storage_service.dart`
- Test: `test/services/attachments/chat_attachment_classifier_test.dart`
- Test: `test/services/attachments/chat_attachment_storage_service_test.dart`

- [ ] **Step 1: 写图片类型识别失败测试**

```dart
test('classifier accepts supported image mime types', () {
  expect(
    ChatAttachmentClassifier.isSupportedImageMimeType('image/png'),
    isTrue,
  );
  expect(
    ChatAttachmentClassifier.isSupportedImageMimeType('application/pdf'),
    isFalse,
  );
});
```

- [ ] **Step 2: 写存储服务失败测试**

```dart
test('storage service persists selected image into managed directory', () async {
  final service = ChatAttachmentStorageService(...);
  final stored = await service.persistSelectedImage(...);

  expect(stored.localPath, contains('attachments/persisted'));
});
```

- [ ] **Step 3: 运行测试确认失败**

Run: `fvm flutter test test/services/attachments/chat_attachment_classifier_test.dart test/services/attachments/chat_attachment_storage_service_test.dart`

Expected: FAIL，提示服务类未定义。

- [ ] **Step 4: 最小实现分类器与存储服务**

Implementation notes:
- 只支持 `jpg/jpeg/png/webp`
- 存储服务只做复制、生成缩略图路径占位、删除接口
- 不在本任务引入复杂压缩与 EXIF 处理

- [ ] **Step 5: 再次运行测试确认通过**

Run: `fvm flutter test test/services/attachments/chat_attachment_classifier_test.dart test/services/attachments/chat_attachment_storage_service_test.dart`

Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add \
  lib/services/attachments/chat_attachment_classifier.dart \
  lib/services/attachments/chat_attachment_storage_service.dart \
  test/services/attachments/chat_attachment_classifier_test.dart \
  test/services/attachments/chat_attachment_storage_service_test.dart
git commit -m "feat(chat): add image attachment services"
```

## Task 3: 数据库与存储接口支持 message attachments

**Files:**
- Modify: `lib/database/database_helper.dart`
- Modify: `lib/storage/chat_storage.dart`
- Modify: `lib/storage/web_chat_storage.dart`
- Modify: `lib/models/chat_message.dart`
- Test: `test/controllers/chat_controller_test.dart`

- [ ] **Step 1: 写数据库附件持久化失败测试**

```dart
test('database stores and loads message attachments', () async {
  final messageId = await databaseHelper.insertMessage(message, groupId);
  await databaseHelper.insertMessageAttachments(messageId, [attachment]);

  final loaded = await databaseHelper.getMessagesByGroupId(groupId);
  expect(loaded.single.referenceJson?['attachments'], isNotNull);
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `fvm flutter test test/controllers/chat_controller_test.dart --plain-name "database stores and loads message attachments"`

Expected: FAIL，提示缺少 attachment 存储接口。

- [ ] **Step 3: 最小实现 migration 与读写接口**

Implementation notes:
- `database_helper.dart` 新增 `message_attachments` 表和版本迁移
- `chat_storage.dart` 增加 attachment 读写 API
- `web_chat_storage.dart` 同步 attachment 元数据行为
- `ChatMessage` 可以先通过显式字段或稳定编码方式拿到 attachment 列表，但不要只靠随意 JSON 拼接

- [ ] **Step 4: 再次运行测试确认通过**

Run: `fvm flutter test test/controllers/chat_controller_test.dart --plain-name "database stores and loads message attachments"`

Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add \
  lib/database/database_helper.dart \
  lib/storage/chat_storage.dart \
  lib/storage/web_chat_storage.dart \
  lib/models/chat_message.dart \
  test/controllers/chat_controller_test.dart
git commit -m "feat(storage): persist message image attachments"
```

## Task 4: 输入区图片选择与展示 UI

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/services/attachments/chat_attachment_picker_service.dart`
- Create: `lib/widgets/chat_input_attachment_strip.dart`
- Modify: `lib/widgets/chat_input.dart`
- Modify: `lib/providers/chat_dependency_providers.dart`
- Test: `test/widgets/chat_input_attachment_strip_test.dart`
- Test: `test/widgets/chat_input_test.dart`

- [ ] **Step 1: 写 attachment strip 失败测试**

```dart
testWidgets('attachment strip shows selected image previews', (tester) async {
  await tester.pumpWidget(...);

  expect(find.byKey(const ValueKey('chat-input-attachment-strip')), findsOneWidget);
  expect(find.text('demo.png'), findsOneWidget);
});
```

- [ ] **Step 2: 写 chat input 图片入口失败测试**

```dart
testWidgets('chat input opens picker and renders selected image', (tester) async {
  await tester.tap(find.byKey(const ValueKey('chat-input-add-image')));
  await tester.pump();

  expect(find.text('demo.png'), findsOneWidget);
});
```

- [ ] **Step 3: 运行测试确认失败**

Run: `fvm flutter test test/widgets/chat_input_attachment_strip_test.dart test/widgets/chat_input_test.dart`

Expected: FAIL，提示缺少 strip/picker 入口。

- [ ] **Step 4: 最小实现 picker service、provider 与输入区 UI**

Implementation notes:
- 通过 provider 注入 picker service，避免 widget 直接依赖插件
- 输入区只做“选择、预览、删除”，不在这里写发送编排
- 为测试保留稳定 `ValueKey`

- [ ] **Step 5: 再次运行测试确认通过**

Run: `fvm flutter test test/widgets/chat_input_attachment_strip_test.dart test/widgets/chat_input_test.dart`

Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add \
  pubspec.yaml \
  lib/services/attachments/chat_attachment_picker_service.dart \
  lib/widgets/chat_input_attachment_strip.dart \
  lib/widgets/chat_input.dart \
  lib/providers/chat_dependency_providers.dart \
  test/widgets/chat_input_attachment_strip_test.dart \
  test/widgets/chat_input_test.dart
git commit -m "feat(chat): add image picker entry to composer"
```

## Task 5: 时间线图片卡片渲染

**Files:**
- Create: `lib/widgets/chat_message_image_attachments.dart`
- Modify: `lib/widgets/chat_message_list.dart`
- Test: `test/widgets/chat_message_image_attachments_test.dart`

- [ ] **Step 1: 写图片消息渲染失败测试**

```dart
testWidgets('user message renders image attachments', (tester) async {
  await tester.pumpWidget(...);

  expect(find.byKey(const ValueKey('chat-message-image-attachments')), findsOneWidget);
  expect(find.byType(Image), findsWidgets);
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `fvm flutter test test/widgets/chat_message_image_attachments_test.dart`

Expected: FAIL，提示缺少时间线图片附件组件。

- [ ] **Step 3: 最小实现图片卡片组件与时间线接线**

Implementation notes:
- 只处理用户消息图片，不扩展 tool/artifact 语义
- 失败态展示要可见
- 保持单一纵向滚动 owner，不引入新的纵向嵌套滚动

- [ ] **Step 4: 再次运行测试确认通过**

Run: `fvm flutter test test/widgets/chat_message_image_attachments_test.dart`

Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add \
  lib/widgets/chat_message_image_attachments.dart \
  lib/widgets/chat_message_list.dart \
  test/widgets/chat_message_image_attachments_test.dart
git commit -m "feat(chat): render image attachments in timeline"
```

## Task 6: 发送入口改为 `SendMessageRequest`

**Files:**
- Modify: `lib/controllers/chat_controller.dart`
- Modify: `lib/controllers/chat_send_coordinator.dart`
- Modify: `lib/providers/chat_providers.dart`
- Test: `test/controllers/chat_send_coordinator_test.dart`
- Test: `test/controllers/chat_controller_test.dart`

- [ ] **Step 1: 写发送入口失败测试**

```dart
test('chat controller forwards send request with attachments', () async {
  final request = SendMessageRequest(
    text: '看下这张图',
    attachments: [attachment],
  );

  await controller.sendMessageRequest(request);

  expect(fakeCoordinator.lastRequest.attachments, hasLength(1));
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `fvm flutter test test/controllers/chat_controller_test.dart test/controllers/chat_send_coordinator_test.dart`

Expected: FAIL，提示发送入口仍然只接受字符串。

- [ ] **Step 3: 最小实现发送入口改造**

Implementation notes:
- 保留 `sendMessage(String text)` 作为轻量兼容封装，内部转成 `SendMessageRequest`
- 新逻辑主入口统一走 request object
- 不在这一步接入 provider payload，仅完成 controller/coordinator 契约迁移

- [ ] **Step 4: 再次运行测试确认通过**

Run: `fvm flutter test test/controllers/chat_controller_test.dart test/controllers/chat_send_coordinator_test.dart`

Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add \
  lib/controllers/chat_controller.dart \
  lib/controllers/chat_send_coordinator.dart \
  lib/providers/chat_providers.dart \
  test/controllers/chat_controller_test.dart \
  test/controllers/chat_send_coordinator_test.dart
git commit -m "refactor(chat): route sends through request object"
```

## Task 7: 在发送事务中持久化图片并更新消息状态

**Files:**
- Modify: `lib/controllers/chat_send_coordinator.dart`
- Modify: `lib/providers/chat_dependency_providers.dart`
- Test: `test/controllers/chat_send_coordinator_test.dart`

- [ ] **Step 1: 写图片发送状态机失败测试**

```dart
test('send coordinator persists image attachments before planner request', () async {
  await coordinator.sendMessageRequest(
    SendMessageRequest(text: '分析这张图', attachments: [attachment]),
    ...
  );

  expect(recordedPhases, contains(ChatSendPhase.preparing));
  expect(fakeStorage.persistCalls, 1);
  expect(insertedUserMessageAttachments, hasLength(1));
});
```

- [ ] **Step 2: 写 provider 不支持时阻止发送的失败测试**

```dart
test('send coordinator blocks image send when provider lacks image support', () async {
  await coordinator.sendMessageRequest(
    SendMessageRequest(text: '分析', attachments: [attachment]),
    ...
  );

  expect(fakeLlm.invoked, isFalse);
  expect(messages.last.status, MessageStatus.failed);
});
```

- [ ] **Step 3: 运行测试确认失败**

Run: `fvm flutter test test/controllers/chat_send_coordinator_test.dart`

Expected: FAIL，提示图片持久化和 capability gating 未实现。

- [ ] **Step 4: 最小实现发送编排**

Implementation notes:
- 发送前先 persist attachment，再写 message + attachment 记录
- 若 provider 不支持图片输入，前置失败并给可见错误
- 先复用现有 `ChatSendPhase`，必要时仅增加最小扩展
- 日志写入 attachment 数量与类型

- [ ] **Step 5: 再次运行测试确认通过**

Run: `fvm flutter test test/controllers/chat_send_coordinator_test.dart`

Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add \
  lib/controllers/chat_send_coordinator.dart \
  lib/providers/chat_dependency_providers.dart \
  test/controllers/chat_send_coordinator_test.dart
git commit -m "feat(chat): send image attachments with user messages"
```

## Task 8: 扩展 provider capabilities 并覆盖 adapter 合同

**Files:**
- Modify: `lib/models/llm/adapters/provider_capabilities.dart`
- Test: `test/models/llm/adapters/image_input_adapter_contract_test.dart`
- Modify: `test/models/llm/configurable_http_llm_test.dart`

- [ ] **Step 1: 写 capability 合同失败测试**

```dart
test('responses and anthropic adapters advertise image input support', () {
  expect(const SdkResponsesAdapter().capabilities.supportsImageInput, isTrue);
  expect(const SdkAnthropicMessagesAdapter().capabilities.supportsImageInput, isTrue);
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `fvm flutter test test/models/llm/adapters/image_input_adapter_contract_test.dart`

Expected: FAIL，提示 capability 字段不存在。

- [ ] **Step 3: 最小实现 capability 扩展**

Implementation notes:
- `ProviderCapabilities` 新增图片输入相关字段
- 三套 SDK adapter 都要显式声明
- 默认值不能靠隐式 null

- [ ] **Step 4: 再次运行测试确认通过**

Run: `fvm flutter test test/models/llm/adapters/image_input_adapter_contract_test.dart`

Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add \
  lib/models/llm/adapters/provider_capabilities.dart \
  test/models/llm/adapters/image_input_adapter_contract_test.dart \
  test/models/llm/configurable_http_llm_test.dart
git commit -m "feat(llm): add image input provider capabilities"
```

## Task 9: OpenAI Responses adapter 支持图片输入

**Files:**
- Modify: `lib/models/llm/adapters/sdk_responses_adapter.dart`
- Modify: `test/models/llm/configurable_http_llm_test.dart`

- [ ] **Step 1: 写 Responses 图片 payload 失败测试**

```dart
test('responses adapter serializes image attachments as input_image items', () {
  final payload = const SdkResponsesAdapter().buildChatPayload(
    messages: [messageWithImage],
    config: chatConfig,
    modelName: 'gpt-4.1',
    stream: false,
  );

  expect(jsonEncode(payload), contains('input_image'));
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `fvm flutter test test/models/llm/configurable_http_llm_test.dart --plain-name "responses adapter serializes image attachments as input_image items"`

Expected: FAIL，payload 里只有 `input_text`。

- [ ] **Step 3: 最小实现 Responses 图片映射**

Implementation notes:
- 普通文本仍保留 `input_text`
- 图片 attachment 追加为 `input_image`
- 只处理本地图片 / provider ref，不扩展其他文件类型

- [ ] **Step 4: 再次运行测试确认通过**

Run: `fvm flutter test test/models/llm/configurable_http_llm_test.dart --plain-name "responses adapter serializes image attachments as input_image items"`

Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add \
  lib/models/llm/adapters/sdk_responses_adapter.dart \
  test/models/llm/configurable_http_llm_test.dart
git commit -m "feat(responses): support image attachments"
```

## Task 10: Chat Completions adapter 支持图片输入或显式阻止

**Files:**
- Modify: `lib/models/llm/adapters/sdk_chat_completions_adapter.dart`
- Modify: `test/models/llm/configurable_http_llm_test.dart`

- [ ] **Step 1: 写 Chat Completions 图片 payload 失败测试**

```dart
test('chat completions adapter serializes image attachments for multimodal messages', () {
  final payload = const SdkChatCompletionsAdapter().buildChatPayload(
    messages: [messageWithImage],
    config: chatConfig,
    modelName: 'gpt-4.1-mini',
    stream: false,
  );

  expect(jsonEncode(payload), contains('image_url'));
});
```

- [ ] **Step 2: 写 capability 不支持时的显式阻止测试**

```dart
test('chat completions adapter can be marked unsupported for image input', () {
  expect(const SdkChatCompletionsAdapter().capabilities.supportsImageInput, isA<bool>());
});
```

- [ ] **Step 3: 运行测试确认失败**

Run: `fvm flutter test test/models/llm/configurable_http_llm_test.dart --plain-name "chat completions adapter serializes image attachments for multimodal messages"`

Expected: FAIL

- [ ] **Step 4: 最小实现 Chat Completions 图片映射**

Implementation notes:
- 构建 `content[]` 的 text + image 结构
- 如果当前实现无法稳定表达某 provider 兼容格式，至少要让 capability gating 可以在发送前阻止

- [ ] **Step 5: 再次运行测试确认通过**

Run: `fvm flutter test test/models/llm/configurable_http_llm_test.dart --plain-name "chat completions adapter serializes image attachments for multimodal messages"`

Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add \
  lib/models/llm/adapters/sdk_chat_completions_adapter.dart \
  test/models/llm/configurable_http_llm_test.dart
git commit -m "feat(chat-completions): support image attachments"
```

## Task 11: Anthropic Messages adapter 支持图片 block

**Files:**
- Modify: `lib/models/llm/adapters/sdk_anthropic_messages_adapter.dart`
- Modify: `test/models/llm/configurable_http_llm_test.dart`

- [ ] **Step 1: 写 Anthropic 图片 block 失败测试**

```dart
test('anthropic adapter serializes image attachments as content blocks', () {
  final payload = const SdkAnthropicMessagesAdapter().buildChatPayload(
    messages: [messageWithImage],
    config: chatConfig,
    modelName: 'claude-sonnet',
    stream: false,
  );

  expect(jsonEncode(payload), contains('"type":"image"'));
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `fvm flutter test test/models/llm/configurable_http_llm_test.dart --plain-name "anthropic adapter serializes image attachments as content blocks"`

Expected: FAIL

- [ ] **Step 3: 最小实现 Anthropic 图片 block 映射**

Implementation notes:
- 文本 block 与图片 block 同列进 `content`
- 保持 tool/result 语义不回归

- [ ] **Step 4: 再次运行测试确认通过**

Run: `fvm flutter test test/models/llm/configurable_http_llm_test.dart --plain-name "anthropic adapter serializes image attachments as content blocks"`

Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add \
  lib/models/llm/adapters/sdk_anthropic_messages_adapter.dart \
  test/models/llm/configurable_http_llm_test.dart
git commit -m "feat(anthropic): support image attachments"
```

## Task 12: 文档与 backlog 同步

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `docs/feature_todo.md`

- [ ] **Step 1: 更新 README**

Add:
- 图片上传 V1 能力说明
- 当前只支持图片，不支持通用附件

- [ ] **Step 2: 更新 AGENTS**

Add if needed:
- 图片上传相关验证命令
- 纯客户端直连 provider 的实现约束

- [ ] **Step 3: 更新 feature todo**

Add:
- “多模态附件”拆分为图片 V1 已完成 / 其他模态待续

- [ ] **Step 4: 运行文档相关检查**

Run: `rg -n "图片上传|多模态附件|image upload" README.md AGENTS.md docs/feature_todo.md`

Expected: 显示新增条目

- [ ] **Step 5: 提交**

```bash
git add README.md AGENTS.md docs/feature_todo.md
git commit -m "docs: document image upload v1 scope"
```

## Task 13: 最终验证

**Files:**
- Inspect: modified source and test files from Tasks 1-12

- [ ] **Step 1: 跑核心单元/组件测试**

Run:

```bash
fvm flutter test \
  test/models/chat/chat_attachment_test.dart \
  test/services/attachments/chat_attachment_classifier_test.dart \
  test/services/attachments/chat_attachment_storage_service_test.dart \
  test/widgets/chat_input_attachment_strip_test.dart \
  test/widgets/chat_message_image_attachments_test.dart \
  test/controllers/chat_send_coordinator_test.dart \
  test/models/llm/adapters/image_input_adapter_contract_test.dart
```

Expected: PASS

- [ ] **Step 2: 跑受影响既有测试**

Run:

```bash
fvm flutter test \
  test/widgets/chat_input_test.dart \
  test/controllers/chat_controller_test.dart \
  test/models/llm/configurable_http_llm_test.dart
```

Expected: PASS

- [ ] **Step 3: 跑 analyze**

Run:

```bash
fvm flutter analyze \
  lib/controllers \
  lib/models/chat \
  lib/models/llm/adapters \
  lib/services/attachments \
  lib/widgets \
  test
```

Expected: PASS

- [ ] **Step 4: 若有 provider 凭据，执行至少一条 live 图片链路**

Run examples:

```bash
HEADLESS_LIVE_PROVIDER_RESPONSES=<provider-id> \
fvm flutter test --tags live-headless-agent \
test/integration/chat_send_live/chat_send_live_responses_test.dart
```

```bash
HEADLESS_LIVE_PROVIDER_ANTHROPIC=<provider-id> \
fvm flutter test --tags live-headless-agent \
test/integration/chat_send_live/chat_send_live_anthropic_test.dart
```

Expected: 至少一条真实图片输入链路通过；若环境不具备凭据，明确记录未执行。

- [ ] **Step 5: 汇总风险并准备执行**

Record:
- 哪些 provider 已真实验证
- Chat Completions 是否走了真实图片输入
- 是否仍有 Web 端或拍照入口未覆盖

## Notes

- 该计划基于已确认的 spec：
  - [2026-06-01-image-upload-v1-design.md](/Users/zyb_wl/flutterSpace/FlutterAIChat/docs/superpowers/specs/2026-06-01-image-upload-v1-design.md)
- 按 developer instruction，本次没有使用 subagent 做计划文档审阅，因为当前会话未获得显式 delegation 授权；执行前可由人工或后续单独会话补做计划审阅。
