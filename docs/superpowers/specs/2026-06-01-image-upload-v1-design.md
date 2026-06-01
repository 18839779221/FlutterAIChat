# 图片上传 V1 设计

## 1. 背景与目标

当前 App 已具备：

- 文本对话主链路
- 语音输入能力
- OpenAI Responses / Chat Completions / Anthropic Messages 三套协议接入
- tool / artifact / session context 的基础框架

但“用户图片上传”仍未成为一等能力。现状里：

- 输入区仅支持文本与语音，不支持图片选择
- `ChatMessage` 没有稳定的图片附件结构
- provider capability 仅表达流式与并行 tool call，不表达图片输入能力
- 协议适配层默认按纯文本消息组织输入
- App 当前没有自有后端，直接从客户端对接大模型 provider

本设计目标是为 App 建立一个简单可落地的图片输入 V1：

- 支持用户在发送消息时附带图片
- 支持不同 provider 按各自协议消费图片
- 支持消息级图片的本地持久化、状态展示与失败恢复
- 在无自有后端前提下，由客户端直接完成图片输入链路
- 不把图片输入语义混入 tool 文件系统或 artifact 产物语义

本次不追求一次覆盖所有模态，而是先稳定建立“消息级图片输入”主链路。

## 2. 范围

### 2.1 V1 范围

V1 只支持“当前消息携带图片发送给模型理解”，不支持长期知识库。

支持类型：

- 图片：`jpg` / `jpeg` / `png` / `webp`

V1 用户能力：

- 从移动端选择图片
- 在发送前看到图片列表与基础元信息
- 随消息一起发送
- 在消息气泡中看到图片卡片
- 发送失败后可看到明确失败原因并重试

V1 provider 目标：

- OpenAI Responses
- OpenAI-compatible Chat Completions
- Anthropic Messages

### 2.2 V1 明确不做

- PDF、文本、Office 文档上传
- 视频上传
- 原始音频文件上传给 LLM 进行多模态理解
- 会话级 / Project 级长期文件库
- 文件搜索 / 向量检索 / RAG ingestion
- 用户在历史消息上二次追加图片
- 桌面端拖拽上传的专项优化
- OCR、版面解析、文档结构化抽取增强
- 自有后端文件中转、统一文件云存储、跨设备同步

## 3. 产品语义

附件能力长期看必须拆成两个层次：

- 消息级附件 `message attachments`
  - 某条用户消息随轮次发送给模型
  - 生命周期跟消息发送强绑定
- 会话级文件 `session files`
  - 在整个 session 中长期存在，可多轮复用

V1 只实现第一层中的“消息级图片”。

tool 文件系统能力保持独立：

- `read_file` / `write_file` 等 tool 面向 workspace
- 用户上传图片面向模型输入
- 两者不可混成同一个概念

## 4. 设计原则

- 图片输入是领域对象，不作为松散 JSON 临时拼接
- UI、存储、发送编排、provider 映射都围绕统一图片 attachment 模型展开
- provider 差异停留在 adapter / runtime 边界，不上抬到 `TurnHarness` 或聊天 UI 语义层
- 历史摘要只保留图片事实，不内联图片二进制内容
- 错误必须可见：大小限制、不支持类型、上传失败、provider 不支持都要有明确反馈
- V1 假定没有自有后端，所有图片发送都由客户端直接面向 provider 完成

## 5. 用户流程

### 5.1 正常流程

1. 用户点击输入区图片入口
2. 系统打开图片来源入口
3. 用户选中图片后，输入区展示图片 chip / 卡片
4. 用户输入文本并发送
5. 本地先生成用户消息草稿与图片状态
6. 若 provider 需要预上传，则先上传图片并获得 `provider file id / url`
7. 组装最终多模态请求发送给模型
8. 对话区展示带图片的用户消息
9. 模型开始正常流式响应

### 5.2 失败流程

失败点包括：

- 本地读取失败
- 文件类型不支持
- 文件超限
- provider 预上传失败
- provider 直接拒绝图片输入
- 请求发送失败

失败策略：

- 发送前失败：图片保留在 composer 中，可删除或重试
- 发送中失败：消息进入失败态，保留图片卡片与错误文案
- provider 不支持：发送前就阻止并提示，避免把失败留到上游

## 6. 数据模型

### 6.1 核心实体

建议新增 `ChatAttachment`，作为消息图片的一等实体。

建议字段：

- `id`
- `messageLocalId`
- `kind`
  - `image`
- `source`
  - `localFile`
  - `providerFile`
  - `remoteUrl`
- `fileName`
- `mimeType`
- `byteSize`
- `localPath`
- `thumbnailPath`
- `sha256`
- `status`
  - `selected`
  - `preparing`
  - `uploading`
  - `ready`
  - `failed`
- `errorCode`
- `errorMessage`
- `providerFileRefJson`
  - 存放 provider-specific file id / uri / upload metadata
- `createdAt`
- `updatedAt`

### 6.2 与消息的关系

`ChatMessage` 仍保留为时间线主实体，但不再承担图片附件具体结构。

推荐关系：

- `messages`
  - 保存消息主数据
- `message_attachments`
  - 一对多保存图片附件

这样可以避免：

- 大量图片元数据塞进 `payload_json`
- 单条消息后续无法稳定追加渲染状态
- 不同图片状态更新时必须整条消息覆写

### 6.3 数据库演进

当前 [database_helper.dart](/Users/zyb_wl/flutterSpace/FlutterAIChat/lib/database/database_helper.dart) 已有 `messages` 表与 JSON 辅助字段，但没有附件表。

建议新增表：

- `message_attachments`

建议列：

- `id INTEGER PRIMARY KEY AUTOINCREMENT`
- `message_id INTEGER`
- `local_attachment_id TEXT NOT NULL`
- `kind TEXT NOT NULL`
- `source TEXT NOT NULL`
- `file_name TEXT NOT NULL`
- `mime_type TEXT NOT NULL`
- `byte_size INTEGER`
- `local_path TEXT`
- `thumbnail_path TEXT`
- `sha256 TEXT`
- `status TEXT NOT NULL`
- `error_code TEXT`
- `error_message TEXT`
- `provider_file_ref_json TEXT`
- `created_at INTEGER NOT NULL`
- `updated_at INTEGER NOT NULL`

约束：

- `message_id` 允许在发送前为空，便于 composer 暂存
- 发送成功后再与正式消息 id 绑定

## 7. UI 设计

### 7.1 输入区

改造 [chat_input.dart](/Users/zyb_wl/flutterSpace/FlutterAIChat/lib/widgets/chat_input.dart)：

- 在输入区增加图片入口按钮
- 在文本框上方或下方增加已选图片横向列表
- 每个图片卡片展示：
  - 文件名
  - 缩略图
  - 大小
  - 上传状态
  - 删除按钮

发送中行为：

- 默认锁定 composer，防止发送中继续修改该批图片
- 但失败后允许快速重试

### 7.2 时间线渲染

用户消息卡片要能渲染图片块：

- 小图预览
- 点击查看大图
- 失败时显示图片失败态与错误说明

注意区分三类视觉语义：

- 用户上传的输入图片
- tool 生成的文件结果
- artifact 预览内容

它们不能复用同一种卡片语言，否则用户会混淆“输入给模型的东西”和“模型产出的东西”。

## 8. 发送编排

### 8.1 新的发送输入

当前发送主入口主要是 `sendMessage(String text)`。

建议演进为更明确的输入对象，例如：

- `SendMessageRequest`
  - `text`
  - `attachments`
  - `quotedMessageId`（预留）
  - `source`（手输 / 语音转写，预留）

这样后续不会因为继续叠加参数把 coordinator 接口拉垮。

### 8.2 发送状态机

针对图片消息，发送事务应增加以下阶段：

1. `draftCreated`
2. `attachmentsPreparing`
3. `attachmentsUploading`
4. `plannerRequestSending`
5. `streamingResponse`
6. `completed | failed`

这套状态要进入日志与 UI，便于后续排障。

## 9. Provider 能力矩阵

当前 [provider_capabilities.dart](/Users/zyb_wl/flutterSpace/FlutterAIChat/lib/models/llm/adapters/provider_capabilities.dart) 只表达：

- `supportsPlannerStreaming`
- `supportsParallelToolCalls`

建议扩展为图片输入能力矩阵：

- `supportsImageInput`
- `supportsPreUploadedFiles`
- `supportsInlineBase64Images`
- `supportsRemoteImageUrl`

说明：

- UI 是否允许选择图片，取决于当前锁定模型 / provider style
- 编排层决定该走 inline 还是 pre-upload
- adapter 决定如何映射到具体协议

## 10. 协议映射

### 10.1 OpenAI Responses

目标：

- 支持图片输入

映射原则：

- 图片可映射为 `input_image`
- 优先采用最简单可验证的图片输入方式
- 若某 provider/runtime 需要先上传图片，则允许使用 provider-native file/image upload

### 10.2 Chat Completions

目标：

- 兼容支持多段 `content[]` 的 OpenAI-compatible provider

映射原则：

- 文本仍为 `text` item
- 图片映射为 `image_url` 或 provider 兼容格式
- 如果当前兼容 provider 不支持图片输入，则发送前阻止，不做伪兼容

### 10.3 Anthropic Messages

目标：

- 支持图片 block

映射原则：

- 按 content block 组装多模态输入
- 保持 provider 差异只在 adapter / runtime 内部

## 11. 降级策略

V1 不做文档文本抽取，也不做 OCR。

建议：

- 图片：若当前 provider 支持 image input，则按原生图片输入发送
- 若当前 provider 不支持 image input，则发送前阻止
- 不把图片静默降级成伪文本方案

这样能保持：

- 能力边界清晰
- 用户预期清楚
- 实现复杂度可控

## 12. Session Context 与摘要策略

图片元数据不能直接混进普通消息压缩，否则会有两类问题：

- 图片元数据冗余，压缩收益低
- 历史摘要丢失“用户曾上传过图片”的事实

推荐策略：

- 历史摘要只记录事实
  - 例如“用户上传了一张产品截图，请求分析界面问题”
- 不把图片二进制或 base64 写入 summary
- 当前轮若仍需模型继续引用该图片，应通过 attachment id 或 provider file ref 重放

后续如果引入会话级文件库，再单独处理长期引用语义。

## 13. 本地文件管理

V1 需要一个轻量图片存储服务。

职责：

- 接收 picker 结果
- 将图片复制到 app 可控目录
- 生成缩略图
- 提供清理策略

建议目录语义：

- `attachments/pending/`
- `attachments/persisted/`
- `attachments/thumbs/`

清理原则：

- composer 中被删除的未发送图片可直接清理
- 已发送图片默认保留，跟随消息生命周期
- 删除会话时联动删除关联图片文件

## 14. 错误处理

错误码建议至少区分：

- `unsupportedType`
- `fileTooLarge`
- `fileReadFailed`
- `uploadFailed`
- `providerUnsupported`
- `providerRejected`
- `requestFailed`

展示原则：

- 用户可理解的错误文案
- 保留技术错误码供日志排障
- 失败卡片上提供删除与重试动作

## 15. 日志与观测

考虑到该仓库对排障时序要求较高，图片链路必须补足 file log 字段。

关键事件：

- `attachment.pick.start`
- `attachment.pick.completed`
- `attachment.persist.start`
- `attachment.persist.completed`
- `attachment.upload.start`
- `attachment.upload.completed`
- `attachment.upload.failed`
- `chat.send.with_attachments.start`
- `chat.send.with_attachments.provider_request_ready`
- `llm.first_chunk`

关键维度：

- `attachment_count`
- `attachment_types`
- `provider_style`
- `model_name`
- `total_bytes`
- `fallback_modes`

## 16. 测试策略

### 16.1 单元测试

- attachment model 序列化 / 反序列化
- 数据库 migration
- 文件类型识别
- provider capability gating
- adapter payload 组装

### 16.2 Widget 测试

- 输入区显示已选图片
- 删除图片
- 失败态展示
- 发送中状态
- 时间线图片卡片渲染

### 16.3 集成测试

- 图片消息从选择到发送成功的完整链路
- 不同 provider style 下的 capability 降级
- 上游拒绝时的失败恢复

### 16.4 Live 测试

对触及的 API style，至少验证：

- Responses 一条图片链路
- Anthropic 一条图片链路
- Chat Completions 一条图片链路或显式阻止链路

不要只依赖 mocked test 判定多模态能力可用。

## 17. 分阶段落地建议

### Phase 1

- 建立 attachment domain model
- 建表与 repository
- 输入区支持图片选择与展示
- 时间线支持静态图片渲染

### Phase 2

- 接入发送编排
- 扩展 provider capabilities
- 完成 Responses / Anthropic / Chat Completions 三套映射

### Phase 3

- 增加日志、失败恢复、清理策略
- 补齐 live tests

## 18. 推荐方案

推荐采用：

- 统一附件领域模型
- 消息级图片一等公民存储
- provider-specific 映射停留在 adapter / runtime
- V1 仅覆盖图片
- 纯客户端直连 provider，不依赖自有后端

不推荐：

- 直接把附件信息塞进 `payload_json`
- 仅在 UI 加一个按钮后临时在 `sendMessage` 内拼 payload
- 混用“用户图片输入”和“workspace 文件工具”语义

## 19. 风险与开放点

### 已知风险

- Chat Completions 兼容 provider 对图片输入支持不一致
- 不同 provider 的图片大小限制差异较大
- 移动端本地缓存与缩略图生成可能带来额外 IO 成本

### 开放点

- 图片是否要在 V1 支持拍照直传
- 发送失败后的“重试”是重用既有 provider file id，还是重新上传
- Web 端是否与移动端同时首发，还是先收敛移动端

当前建议：

- V1 文件类型先收敛到 `image`
- 拍照入口可做，但不作为首发阻塞项
- 重试先走“尽量复用已有本地缓存，必要时重新上传”
