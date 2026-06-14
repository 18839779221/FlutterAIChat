# 生图功能与结果展示 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让助手消息能够携带并展示由 provider 返回的生成图片附件，并新增首个 `generate_image` 生图工具。

**Architecture:** 复用现有 `ChatAttachment` 和 `ChatMessageImageAttachments`，不新增单独的图片消息类型。V1 已完成展示层；V2 新增 `generate_image` 工具和 OpenAI-compatible Images API adapter，工具结果通过 `generatedImages` 结构化字段投影为助手消息附件。生图运行配置由独立 resolver 从 provider 列表和 `image_generation.*` 配置解析，不能绑定到当前聊天 provider。

**Tech Stack:** Flutter 3.35.7, Riverpod, existing chat timeline widgets, Flutter widget tests.

---

## 文件结构

- Modify: `lib/models/chat/chat_attachment.dart`
  - 新增 `ChatAttachment.generatedImage(...)` 工厂方法。
- Modify: `lib/widgets/chat_message_image_attachments.dart`
  - 新增 `alignment` 参数，默认保持 `Alignment.centerRight`。
- Modify: `lib/widgets/chat_timeline/chat_timeline_row.dart`
  - 对助手 block 的 `sourceMessage.attachments` 做统一渲染，使用左对齐。
- Test: `test/models/chat/chat_attachment_test.dart`
  - 覆盖生成图附件元数据。
- Test: `test/widgets/chat_message_image_attachments_test.dart`
  - 覆盖 data URL 图片和左对齐。
- Test: `test/widgets/chat_timeline_row_test.dart`
  - 覆盖助手最终回答携带生成图附件。
- Create: `lib/tools/handlers/generate_image_tool_handler.dart`
  - 定义 `generate_image` 工具、参数校验和执行入口。
- Modify: `lib/services/tool_executor.dart`
  - 新增 `ImageGenerator` typedef 与 `executeGenerateImage`。
- Modify: `lib/services/default_tool_adapters.dart`
  - 新增 OpenAI-compatible image generator adapter。
- Create: `lib/services/image_generation_config_resolver.dart`
  - 从 provider 列表和附加配置解析生图 provider、base URL、API key、默认模型和默认质量。
- Modify: `lib/models/llm/llm_provider_model.dart`
  - 新增 `supportsImageGeneration`，与 `supportsImageInput` 分离。
- Modify: `lib/pages/provider_form_page.dart`
  - 模型行增加“支持生图”勾选、“测试生图”按钮、费用/耗时确认和测试中防抖。
- Modify: `lib/services/llm_model_test_service.dart`
  - 新增 OpenAI-compatible Images API 生图能力测试。
- Modify: `lib/services/tool_policy_service.dart`
  - 仅当 resolver 能解析出可用生图模型时，允许 `generate_image` 对 planner 可见。
- Modify: `lib/tools/default_tool_runtime_registry.dart`
  - 注册 `GenerateImageToolHandler`，并使用生图配置 resolver 注入运行配置。
- Modify: `lib/repositories/app_settings_repository.dart`
  - 暴露 provider 列表和 local defaults 中的附加配置给生图 resolver 使用。
- Modify: `lib/controllers/agent_event_processor.dart`
  - 将 `generate_image` tool result 的 `generatedImages` 写为助手消息附件。
- Modify: `lib/services/tool_result_context_projector.dart`
  - 为 `generate_image` 生成不含 base64 的 planner-visible 结果文本。
- Test: `test/tools/handlers/generate_image_tool_handler_test.dart`
  - 覆盖参数校验和执行。
- Test: `test/services/default_tool_adapters_test.dart`
  - 覆盖请求 endpoint/body 与 base64 响应解析。
- Test: `test/services/image_generation_config_resolver_test.dart`
  - 覆盖模型级生图能力、默认生图模型选择和不复用当前聊天 provider。
- Test: `test/models/llm/llm_provider_model_test.dart`
  - 覆盖 `supportsImageGeneration` 序列化。
- Test: `test/pages/provider_form_page_test.dart`
  - 覆盖模型行勾选、测试前确认、测试中防抖和测试成功后自动勾选。
- Test: `test/services/llm_model_test_service_test.dart`
  - 覆盖生图能力测试请求和响应判定。
- Test: `test/services/tool_policy_service_test.dart`
  - 覆盖未配置生图模型时 `generate_image` 对 planner 不可见。
- Test: `test/controllers/agent_event_processor_test.dart`
  - 覆盖工具结果附件落库和内存时间线。
- Test: `test/services/tool_result_context_projector_test.dart`
  - 覆盖生图结果上下文不泄露 base64。

## Task 1: 生成图片附件模型

**Files:**
- Modify: `lib/models/chat/chat_attachment.dart`
- Test: `test/models/chat/chat_attachment_test.dart`

- [ ] **Step 1: 确认红灯测试**

Run:

```bash
flutter test test/models/chat/chat_attachment_test.dart
```

Expected: FAIL，报错 `Member not found: 'ChatAttachment.generatedImage'`。

- [ ] **Step 2: 实现最小工厂方法**

在 `ChatAttachment` 中加入：

```dart
factory ChatAttachment.generatedImage({
  required String localId,
  required String fileName,
  required String mimeType,
  required String dataUrl,
  int? byteSize,
  String? sha256,
  String? errorCode,
  String? errorMessage,
  Map<String, dynamic>? providerFileRefJson,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  return ChatAttachment(
    localId: localId,
    kind: ChatAttachmentKind.image,
    source: ChatAttachmentSource.providerFile,
    fileName: fileName,
    mimeType: mimeType,
    byteSize: byteSize,
    sha256: sha256,
    status: ChatAttachmentStatus.ready,
    errorCode: errorCode,
    errorMessage: errorMessage,
    providerFileRefJson: {
      if (providerFileRefJson != null) ...providerFileRefJson,
      'data_url': dataUrl,
    },
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
```

- [ ] **Step 3: 验证模型测试通过**

Run:

```bash
flutter test test/models/chat/chat_attachment_test.dart
```

Expected: PASS。

## Task 2: 图片附件组件支持助手侧对齐

**Files:**
- Modify: `lib/widgets/chat_message_image_attachments.dart`
- Test: `test/widgets/chat_message_image_attachments_test.dart`

- [ ] **Step 1: 确认红灯测试**

Run:

```bash
flutter test test/widgets/chat_message_image_attachments_test.dart
```

Expected: FAIL，报错 `No named parameter with the name 'alignment'`。

- [ ] **Step 2: 添加 alignment 参数**

把组件构造函数扩展为：

```dart
const ChatMessageImageAttachments({
  super.key,
  required this.attachments,
  this.alignment = Alignment.centerRight,
});

final Alignment alignment;
```

并把 `Align(alignment: Alignment.centerRight)` 改为 `Align(alignment: alignment)`。

- [ ] **Step 3: 验证组件测试通过**

Run:

```bash
flutter test test/widgets/chat_message_image_attachments_test.dart
```

Expected: PASS。

## Task 3: 助手最终回答展示生成图

**Files:**
- Modify: `lib/widgets/chat_timeline/chat_timeline_row.dart`
- Test: `test/widgets/chat_timeline_row_test.dart`

- [ ] **Step 1: 确认红灯测试**

Run:

```bash
flutter test test/widgets/chat_timeline_row_test.dart --plain-name "assistant final response row renders generated image attachments on assistant side"
```

Expected: FAIL，找不到 `chat-message-image-attachments-align`。

- [ ] **Step 2: 在助手 block 下方渲染附件**

在 `_buildAssistantBlock` 得到 `blockWidget` 后，追加一个小包装：

```dart
final assistantAttachments = sourceMessage?.attachments ?? const <ChatAttachment>[];
final blockWithAttachments = assistantAttachments.isEmpty
    ? blockWidget
    : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          blockWidget,
          ChatMessageImageAttachments(
            alignment: Alignment.centerLeft,
            attachments: assistantAttachments,
          ),
        ],
      );
```

后续返回和 `AnimatedSwitcher` 包装都使用 `blockWithAttachments`。

- [ ] **Step 3: 验证时间线测试通过**

Run:

```bash
flutter test test/widgets/chat_timeline_row_test.dart
```

Expected: PASS。

## Task 4: 聚焦回归与静态检查

**Files:**
- Modify: no new files unless formatter changes.

- [ ] **Step 1: 跑聚焦测试**

Run:

```bash
flutter test test/models/chat/chat_attachment_test.dart test/widgets/chat_message_image_attachments_test.dart test/widgets/chat_timeline_row_test.dart
```

Expected: PASS。

- [ ] **Step 2: 跑 analyze**

Run:

```bash
flutter analyze
```

Expected: PASS or only unrelated pre-existing issues. If there are issues in touched files, fix them before continuing。

## Task 5: 后续 API 接入准备

**Files:**
- Modify: `docs/superpowers/specs/2026-06-12-image-generation-display-v1-design.md`
- Modify: `docs/superpowers/plans/2026-06-12-image-generation-display-v1-implementation-plan.md`

- [x] **Step 1: 记录下一阶段边界**

真实 gpt-image-2 接入作为 V2：先查 OpenAI 官方文档确认当前图片 API 返回结构，再把 provider 返回的 base64 归一化为 `ChatAttachment.generatedImage`。

## Task 6: 生图工具 handler

**Files:**
- Create: `lib/tools/handlers/generate_image_tool_handler.dart`
- Modify: `lib/services/tool_executor.dart`
- Test: `test/tools/handlers/generate_image_tool_handler_test.dart`

- [ ] **Step 1: 写红灯测试**

测试内容：

- 空 prompt 返回 invalid。
- 默认参数为 `model=gpt-image-2`、`size=1024x1024`、`quality=low`；只有用户明确要求高质量、高清、高分辨率、印刷质量或类似需求时才使用 `high`。
- execute 调用注入的 `ImageGenerator`。

Run:

```bash
flutter test test/tools/handlers/generate_image_tool_handler_test.dart
```

Expected: FAIL，缺少 handler 文件或类型。

- [ ] **Step 2: 实现 typedef 与 executor**

在 `ToolExecutor` 增加：

```dart
typedef ImageGenerator = Future<ToolResult> Function({
  required String prompt,
  required String model,
  required String size,
  required String quality,
  String? apiKey,
  String? baseUrl,
});
```

构造函数接受 `ImageGenerator? imageGenerator`，并新增 `executeGenerateImage(...)`。

- [ ] **Step 3: 实现 handler**

`GenerateImageToolHandler` 注入 `ImageGenerator`，定义 `prompt`、`model`、`size`、`quality` 参数，`requiresConfirmation=false`，`isConcurrencySafe=false`。

- [ ] **Step 4: 验证 handler 测试通过**

Run:

```bash
flutter test test/tools/handlers/generate_image_tool_handler_test.dart
```

Expected: PASS。

## Task 7: OpenAI-compatible Images API adapter

**Files:**
- Modify: `lib/services/default_tool_adapters.dart`
- Test: `test/services/default_tool_adapters_test.dart`

- [ ] **Step 1: 写红灯测试**

测试内容：

- base URL 为 `/v1/chat/completions` 时，请求发到 `/v1/images/generations`。
- body 包含 `model`、`prompt`、`size`、`quality`。
- 响应 `data[0].b64_json` 被转换为 `generatedImages[0].dataUrl`。
- 缺 API Key 返回 `missing_api_key`。

Run:

```bash
flutter test test/services/default_tool_adapters_test.dart --plain-name "image generator"
```

Expected: FAIL，缺少 `buildOpenAIImageGenerator`。

- [ ] **Step 2: 实现 adapter**

新增 `buildOpenAIImageGenerator({http.Client? client})`。成功结果使用：

```dart
ToolResult(
  toolName: 'generate_image',
  status: ToolExecutionStatus.success,
  summary: '已生成图片',
  data: {
    'prompt': prompt,
    'model': model,
    'size': size,
    'quality': quality,
    'generatedImages': images,
  },
)
```

- [ ] **Step 3: 验证 adapter 测试通过**

Run:

```bash
flutter test test/services/default_tool_adapters_test.dart --plain-name "image generator"
```

Expected: PASS。

## Task 8: 生图配置 resolver

**Files:**
- Create: `lib/services/image_generation_config_resolver.dart`
- Modify: `lib/repositories/app_settings_repository.dart`
- Test: `test/services/image_generation_config_resolver_test.dart`

- [ ] **Step 1: 写红灯测试**

测试内容：

- 只有 `supportsImageGeneration=true` 的模型能被 resolver 选为生图模型。
- 只有一个支持生图的模型时自动选择。
- 多个支持生图模型时，使用 `image_generation.default_provider_id/default_model_id`。
- 默认配置指向未勾选或不存在的模型时返回 `null`。
- `supportsImageInput=true` 不代表支持生图。
- `qualityDefault` 默认 `low`。

Run:

```bash
flutter test test/services/image_generation_config_resolver_test.dart
```

Expected: FAIL，缺少 resolver 文件或 API。

- [ ] **Step 2: 实现 resolver**

新增：

```dart
class ImageGenerationRuntimeConfig {
  final String providerId;
  final String apiKey;
  final String baseUrl;
  final String model;
  final String qualityDefault;
}
```

`ImageGenerationConfigResolver.resolve(...)` 接收 provider 列表和 additional config，读取模型级 `supportsImageGeneration` 和 `image_generation.default_provider_id/default_model_id/quality_default`。

- [ ] **Step 3: 暴露 repository 查询入口**

在 `AppSettingsRepository` 增加窄方法，例如：

```dart
Future<Map<String, dynamic>> getAdditionalConfig()
Future<ImageGenerationRuntimeConfig?> getImageGenerationConfig()
```

实现中复用 local defaults 的 `additionalConfig` 和 `getProviders()`，不要调用 `getLlmConfig()` 取得当前聊天 provider。

## Task 8A: 模型级生图能力配置 UI 与测试

**Files:**
- Modify: `lib/models/llm/llm_provider_model.dart`
- Modify: `lib/pages/provider_form_page.dart`
- Modify: `lib/services/llm_model_test_service.dart`
- Test: `test/models/llm/llm_provider_model_test.dart`
- Test: `test/pages/provider_form_page_test.dart`
- Test: `test/services/llm_model_test_service_test.dart`

- [ ] **Step 1: 写红灯测试**

覆盖：

- `supportsImageGeneration` 支持 camelCase/snake_case JSON 读写。
- 模型编辑卡显示“支持生图”勾选，保存后进入 `LlmProviderModel.supportsImageGeneration`。
- 点击“测试生图”先显示费用/耗时确认，取消不请求。
- 确认后发起一次真实生图探测，测试中按钮禁用，重复点击不会重复请求。
- 测试成功后自动勾选“支持生图”。

- [ ] **Step 2: 实现模型字段**

在 `LlmProviderModel` 增加 `supportsImageGeneration`，JSON 支持 `supportsImageGeneration` 与 `supports_image_generation`。

- [ ] **Step 3: 实现测试服务**

在 `LlmModelTestService` 增加 `testImageGenerationModel(...)`，请求 `/images/generations`，body 使用 `quality=low`、小测试 prompt，成功标准为 `data[0].b64_json` 非空且可 base64 解码。

- [ ] **Step 4: 实现 UI**

模型卡增加“支持生图”勾选和“测试生图”按钮。按钮点击先弹确认提示；确认后设置页面级 `_imageGenerationTestingIndex`，测试期间禁用所有生图测试按钮。成功后自动勾选当前行。

- [ ] **Step 5: 验证测试通过**

Run:

```bash
flutter test test/models/llm/llm_provider_model_test.dart test/pages/provider_form_page_test.dart test/services/llm_model_test_service_test.dart
```

Expected: PASS。

- [ ] **Step 4: 验证 resolver 测试通过**

Run:

```bash
flutter test test/services/image_generation_config_resolver_test.dart
```

Expected: PASS。

## Task 9: 注册生图工具

**Files:**
- Modify: `lib/tools/default_tool_runtime_registry.dart`
- Test: `test/tools/default_tool_runtime_registry_test.dart`

- [ ] **Step 1: 写红灯测试**

断言：

- 默认 registry 包含 `generate_image`。
- 当前聊天 provider 和 `image_generation.provider_id` 不同时，执行 `generate_image` 使用生图 provider 的 `apiKey/baseUrl/model/qualityDefault`。
- 未配置生图 provider 时，执行结果是稳定失败，不读取当前聊天 provider。

Run:

```bash
flutter test test/tools/default_tool_runtime_registry_test.dart --plain-name "generate_image"
```

Expected: FAIL。

- [ ] **Step 2: 注册 handler**

`buildDefaultToolRuntimeRegistry` 创建 `GenerateImageToolHandler`，执行时调用 `appSettingsRepository.getImageGenerationConfig()` 解析生图配置，再调用 `toolExecutor.executeGenerateImage(...)`。不要调用 `getLlmConfig()`，不要使用当前聊天 provider 的 `apiKey/baseUrl` 作为隐式 fallback。

- [ ] **Step 3: 验证 registry 测试通过**

Run:

```bash
flutter test test/tools/default_tool_runtime_registry_test.dart --plain-name "generate_image"
```

Expected: PASS。

## Task 10: 工具结果附件落库

**Files:**
- Modify: `lib/controllers/agent_event_processor.dart`
- Test: `test/controllers/agent_event_processor_test.dart`

- [ ] **Step 1: 写红灯测试**

构造 `generate_image` tool result event，payload 中包含 `data.generatedImages`；处理后应插入助手消息并写入 `message_attachments`。

Run:

```bash
flutter test test/controllers/agent_event_processor_test.dart --plain-name "generate_image"
```

Expected: FAIL，助手消息没有附件。

- [ ] **Step 2: 实现附件恢复**

在 `_appendToolResultMessage` 中，如果 payload 是 `generate_image` 且 `generatedImages` 非空，则恢复 `ChatAttachment.generatedImage` 列表，插入消息后调用 `insertMessageAttachments`，并把附件带入内存消息。

- [ ] **Step 3: 验证 processor 测试通过**

Run:

```bash
flutter test test/controllers/agent_event_processor_test.dart --plain-name "generate_image"
```

Expected: PASS。

## Task 11: planner-visible 生图结果投影

**Files:**
- Modify: `lib/services/tool_result_context_projector.dart`
- Test: `test/services/tool_result_context_projector_test.dart`

- [ ] **Step 1: 写红灯测试**

断言 `generate_image` 结果上下文包含 prompt/model/image count，不包含 `base64` 或 `data:image`。

Run:

```bash
flutter test test/services/tool_result_context_projector_test.dart --plain-name "generate_image"
```

Expected: FAIL。

- [ ] **Step 2: 实现投影**

新增 `_projectGenerateImage`，返回简洁事实文本，例如：

```text
Generated 1 image with generate_image. Model: gpt-image-2. Prompt: ...
```

- [ ] **Step 3: 验证 projector 测试通过**

Run:

```bash
flutter test test/services/tool_result_context_projector_test.dart --plain-name "generate_image"
```

Expected: PASS。

## Task 12: V2 聚焦回归

**Files:**
- Modify: touched files only if verification requires fixes.

- [ ] **Step 1: 跑 V1+V2 聚焦测试**

Run:

```bash
flutter test test/models/chat/chat_attachment_test.dart test/widgets/chat_message_image_attachments_test.dart test/widgets/chat_timeline_row_test.dart test/tools/handlers/generate_image_tool_handler_test.dart test/services/default_tool_adapters_test.dart test/services/image_generation_config_resolver_test.dart test/tools/default_tool_runtime_registry_test.dart test/controllers/agent_event_processor_test.dart test/services/tool_result_context_projector_test.dart
```

Expected: PASS。

- [ ] **Step 2: 跑 touched files analyze**

Run:

```bash
flutter analyze lib/models/chat/chat_attachment.dart lib/widgets/chat_message_image_attachments.dart lib/widgets/chat_timeline/chat_timeline_row.dart lib/tools/handlers/generate_image_tool_handler.dart lib/services/tool_executor.dart lib/services/default_tool_adapters.dart lib/services/image_generation_config_resolver.dart lib/tools/default_tool_runtime_registry.dart lib/controllers/agent_event_processor.dart lib/services/tool_result_context_projector.dart lib/repositories/app_settings_repository.dart test/models/chat/chat_attachment_test.dart test/widgets/chat_message_image_attachments_test.dart test/widgets/chat_timeline_row_test.dart test/tools/handlers/generate_image_tool_handler_test.dart test/services/default_tool_adapters_test.dart test/services/image_generation_config_resolver_test.dart test/tools/default_tool_runtime_registry_test.dart test/controllers/agent_event_processor_test.dart test/services/tool_result_context_projector_test.dart
```

Expected: PASS。
