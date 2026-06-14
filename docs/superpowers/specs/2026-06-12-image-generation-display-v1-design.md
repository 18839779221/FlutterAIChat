# 生图功能与结果展示设计

## 背景

目标是支持生图能力，但第一步只解决“模型生成出来的图片能在聊天时间线里展示”。完整生图链路会涉及 provider API、工具定义、运行时调用、结果持久化、UI 投影和错误处理；直接一次性接入会扩大改动面。

当前仓库已经具备用户图片上传的基础能力：

- `ChatAttachment` 可以表达图片附件，并能保存 `providerFileRefJson`。
- `ChatMessageImageAttachments` 已经能从 `providerFileRefJson.data_url` 解码 `data:image/...;base64,...`。
- 聊天时间线只在用户消息侧渲染图片附件，助手消息还没有同等入口。

因此功能拆成两段：

- V1：让助手消息也能携带图片附件，并在时间线里显示生成图。
- V2：新增真实生图工具，以 `gpt-image-2` / OpenAI-compatible Images API 为首个实现样例。

## 范围

V1 包含：

- 为 `ChatAttachment` 增加生成图片构造入口，明确来源是 provider 结果。
- 复用现有 data URL 解码路径展示 base64 图片。
- 让助手最终回答块可以在正文下方展示自己的图片附件。
- 保持用户图片附件仍然右侧对齐，助手生成图左侧对齐。
- 补充聚焦 widget/model 测试。

V2 包含：

- 新增 `generate_image` 工具，让 planner 在用户明确要求生图时可调用。
- 新增注入式 `ImageGenerator` adapter，并通过独立的生图配置解析器选择可用 provider。
- 首个 adapter 走 OpenAI-compatible Images API：`POST /images/generations`。
- 默认模型来自生图配置；未配置时才回退到 `gpt-image-2`。工具参数仍允许显式覆盖模型。
- 把 API 返回的 base64 图片归一化为 `ChatAttachment.generatedImage`。
- 在工具结果落到时间线时，把生成图片附件写入对应助手消息并持久化到 `message_attachments`。
- 工具结果给 planner 的上下文只描述图片已生成和附件元数据，不把 base64 原文暴露给 planner。

暂不包含：

- 不实现图片编辑、局部重绘或多图参考输入。
- 不处理图片编辑、变体、上传到远端文件服务或跨设备同步。
- 不改变用户上传图片输入能力。
- 不把生图能力塞进 `ConfigurableHttpLLM` 的聊天 adapter/runtime。
- 不新增单独的图片资源库或图库页面。
- 不把生图 provider 绑定到当前聊天 provider；聊天模型选择和生图运行配置必须解耦。
- 不复用 `supportsImageInput` 表达生图能力；`supportsImageInput` 只表示图片输入/图片理解。

## 数据模型

继续使用 `ChatAttachment` 作为聊天消息上的图片载体，不新增平行的 `GeneratedImage` 消息类型。

新增 `ChatAttachment.generatedImage(...)` 工厂方法：

- `kind = ChatAttachmentKind.image`
- `source = ChatAttachmentSource.providerFile`
- `status = ChatAttachmentStatus.ready`
- `providerFileRefJson.data_url = data:image/...;base64,...`
- 可附带 `model`、`provider`、`revised_prompt` 等后续 API 元数据

这样后续真实 gpt-image-2 接入时，只需要把 API 返回的 base64 图片转换成这个附件模型，UI 不需要理解具体 provider。

## UI 行为

用户图片附件保持原行为：

- 跟随用户气泡。
- 右侧对齐。
- 点击打开现有大图预览。

助手生成图附件新增行为：

- 跟随对应助手最终回答。
- 在文本正文下方显示。
- 左侧对齐。
- 使用同一套缩略图和预览逻辑。

如果 data URL 无效或图片无法解码，继续使用现有图片占位符，不把它升级为聊天错误。

## 后续 gpt-image-2 接入边界

真实生图能力作为 V2：

- `generate_image` 是工具，不是聊天模型协议分支。
- 工具 handler 只做参数校验、工具定义和执行入口。
- `ImageGenerator` adapter 负责 HTTP 请求、响应解析和错误归一化。
- `ImageGenerationConfigResolver` 负责从 provider 列表和附加配置里解析生图运行配置。
- `ToolResult.data.generatedImages` 是工具结果中的结构化事实源。
- `AgentEventProcessor` 或等价事件消费层负责把 `generatedImages` 投影为助手消息附件。
- UI 只消费 `ChatMessage.attachments`，不解析 provider 原始响应。

## 生图 provider 配置解析

生图配置是工具运行配置，不是当前聊天模型配置。默认工具 registry 不应调用 `getLlmConfig()` 来取得当前聊天 provider 的 `apiKey`、`baseUrl` 或 `model`，否则用户切换聊天模型会意外改变生图 provider。

V2 初始版本使用独立解析器。该版本证明了生图配置不能绑定当前聊天 provider，但 provider 级 `provider_id/model` 配置会在后续修正中被模型级 `supportsImageGeneration` 与默认生图模型选择替代：

- 读取所有 `LlmProviderConfig`。
- 读取 local defaults / `LLMConfig.additionalConfig` 中的 `image_generation.*` 配置。
- 优先使用 `image_generation.provider_id` 指向的 provider。
- 若没有显式配置 `provider_id`，则视为未配置生图能力，不自动拿当前聊天 provider 冒充生图 provider。
- `image_generation.base_url` 可选；未设置时使用 provider 自身 `baseUrl`。
- `image_generation.model` 可选；未设置时使用 `gpt-image-2`。
- `image_generation.quality_default` 可选；未设置时使用 `low`。

历史最小配置形态如下，后续不再作为最终推荐形态：

```json
{
  "image_generation": {
    "provider_id": "beehears",
    "model": "gpt-image-2",
    "quality_default": "low"
  }
}
```

这个配置可以让聊天 provider 继续使用 OpenAI、MiniMax 或任意其他 provider，同时生图固定走 Beehears 或另一个专门的 OpenAI-compatible Images provider。

## 生图模型配置与工具可见性

后续修正把生图能力从 provider 级临时配置收敛到模型级配置：

- `LlmProviderModel.supportsImageGeneration` 表示这个模型可以执行图片生成。
- `supportsImageInput` 继续只表示图片输入/图片理解，不能复用为生图能力。
- Provider 表单的模型列表中，每个模型行增加“支持生图”勾选项。
- 模型列表中提供“测试生图”能力，直接调用 OpenAI-compatible `POST /images/generations`，使用低质量测试请求，并以可解码 `data[0].b64_json` 作为成功标准。
- 测试成功后可以自动勾选该模型的 `supportsImageGeneration`；如果当前没有默认生图模型，可把该模型设为默认生图模型。
- 生图测试按钮必须有费用/耗时提示：点击后先提示“会调用真实生图接口，可能较慢且产生费用”，用户确认后才发起请求。
- 生图测试必须防抖：同一模型测试进行中禁用测试按钮，并且页面内已有生图测试运行时不允许重复发起新的生图测试。

默认生图模型选择规则：

- 没有任何 `supportsImageGeneration=true` 的模型时，`generate_image` 对 planner 不可见，执行层也稳定返回未配置失败。
- 只有一个支持生图的模型时，自动选择这个模型。
- 多个模型支持生图时，优先使用 `image_generation.default_provider_id` + `image_generation.default_model_id`。
- 默认配置指向不存在的模型，或指向未勾选 `supportsImageGeneration` 的模型时，视为未配置生图能力。

推荐配置形态：

```json
{
  "providers": [
    {
      "id": "beehears",
      "base_url": "https://ai.beehears.com/v1",
      "models": [
        {
          "id": "gpt-image-2",
          "name": "GPT Image 2",
          "supports_image_generation": true
        }
      ]
    }
  ],
  "image_generation": {
    "default_provider_id": "beehears",
    "default_model_id": "gpt-image-2",
    "quality_default": "low"
  }
}
```

实现上不要求物理移除 runtime handler。`GenerateImageToolHandler` 可以常驻 registry，便于旧调用和执行层防御；真正的“注册给模型”发生在 planner 可见工具列表中：只有 resolver 能解析到可用生图模型时，`generate_image` 才能通过 tool policy 暴露给 planner。

## `generate_image` 工具契约

工具名：`generate_image`

参数：

- `prompt`：必填，描述要生成的图片。
- `size`：可选，默认 `1024x1024`。
- `quality`：可选，默认 `low`。只有用户明确要求高质量、高清、高分辨率、印刷质量或类似需求时才使用 `high`。
- `model`：可选，默认使用生图配置中的模型；未配置时回退到 `gpt-image-2`。

行为：

- 当用户明确要求生成图片、插图、封面、素材、视觉稿等输出时调用。
- 不用于图片理解；图片理解继续走已有用户附件输入能力。
- 不在用户只是询问“怎么生成图”时自动调用。

成功结果：

```json
{
  "toolName": "generate_image",
  "status": "success",
  "summary": "已生成图片",
  "data": {
    "prompt": "...",
    "model": "gpt-image-2",
    "size": "1024x1024",
    "generatedImages": [
      {
        "localId": "generated-image-...",
        "fileName": "generated-image-1.png",
        "mimeType": "image/png",
        "dataUrl": "data:image/png;base64,..."
      }
    ]
  }
}
```

失败结果：

- 缺 API Key：`missing_api_key`
- 非 2xx：`http_<statusCode>`
- 响应无可用 base64：`missing_image_data`
- 网络或 JSON 解析异常：`network_error` / `invalid_response`

## API 适配

V2 先使用 Images API，而不是 Responses API image generation tool，原因是本阶段只需要一次性文本生图，不需要多轮编辑和模型上下文续接。

请求：

- Endpoint 从生图 provider base URL 派生：如果 base URL 是 `/v1/chat/completions`、`/v1/responses` 或 `/v1`，统一解析到同 host 下的 `/v1/images/generations`。
- Header 使用 `Authorization: Bearer <apiKey>` 和 `Content-Type: application/json`。
- Body 至少包含 `model`、`prompt`、`size`、`quality`。

响应解析：

- 优先读取 `data[*].b64_json`。
- 兼容读取 `data[*].url`，但 V2 只把可内联展示的 base64 作为成功主路径；只有 URL 时先返回结构化失败，避免 UI 持久化远端临时链接。
- 每张图片转换为一个 `ChatAttachment.generatedImage`。

## 时间线与持久化

工具结果事件仍保留为 `MessageContentType.toolResult`，用于表达工具执行事实。

当 `toolName == generate_image` 且 `ToolResult.data.generatedImages` 非空时：

- 事件处理层从 payload 中恢复 `ChatAttachment.generatedImage` 列表。
- 插入 tool result 助手消息后，调用 `insertMessageAttachments(messageId, attachments)`。
- 内存时间线中的同一条消息也带上 `attachments`。
- 现有助手附件展示逻辑会自动渲染生成图。

这保持了单一 UI 展示入口：生成图不是一套新卡片，而是助手消息的附件。

## 测试策略

V1 已覆盖：

- `ChatAttachment.generatedImage` 正确设置 source/status/data URL。
- 图片附件组件能显示 data URL 图片，并支持左/右对齐。
- 助手最终回答行能渲染生成图片附件，并保持在助手侧。

V2 新增覆盖：

- `GenerateImageToolHandler` 参数校验和工具定义。
- `buildOpenAIImageGenerator` 发送正确 endpoint/body，并把 `b64_json` 转换为 `generatedImages`。
- 生图工具注册到默认工具 registry，并通过独立 resolver 注入生图 provider 配置。
- 当前聊天 provider 与配置的生图 provider 不同时，`generate_image` 必须使用生图 provider。
- `supportsImageInput=true` 不能让一个 provider 自动获得生图能力。
- `AgentEventProcessor` 能把 `generate_image` tool result 中的 `generatedImages` 持久化为助手消息附件。
- `ToolResultContextProjector` 对 `generate_image` 返回不含 base64 的 planner-visible 文本。

验证命令：

```bash
flutter test test/models/chat/chat_attachment_test.dart test/widgets/chat_message_image_attachments_test.dart test/widgets/chat_timeline_row_test.dart
flutter test test/tools/handlers/generate_image_tool_handler_test.dart test/services/default_tool_adapters_test.dart test/controllers/agent_event_processor_test.dart test/services/tool_result_context_projector_test.dart
flutter analyze
```
