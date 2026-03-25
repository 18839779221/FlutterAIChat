# FlutterAIChat 任务 1：类型化消息基础设施设计

**日期：** 2026-03-25

**目标：** 为现有聊天系统增加“消息类型 + 原始载荷”基础能力，让后续结构化输出、工具结果、引用信息都能基于同一套消息模型和存储方式演进。

---

## 1. 背景

当前 FlutterAIChat 的消息模型只适合承载纯文本聊天：

- `ChatMessage` 只有 `text`、`status`、`reasoningContent`
- `messages` 表主要围绕文本字段设计
- `ChatMessageList` 默认把助手消息按 Markdown 渲染

这套结构足以支持当前聊天能力，但无法自然承载后续要加入的：

- 结构化卡片
- Tool Calling 执行结果
- 引用来源
- 其他非纯文本消息体

因此任务 1 的目标不是直接做结构化输出功能，而是先把“消息本身可以有类型和载荷”这件事接入现有链路。

## 2. 范围

### 本任务要做的事

- 扩展 `ChatMessage`，支持消息类型与 JSON 载荷
- 扩展数据库 schema，支持消息类型字段和原始载荷字段
- 在聊天列表里增加按消息类型分发渲染的能力
- 为未知类型、空载荷、解析失败提供安全回退
- 补充模型、数据库、Widget 三层测试

### 本任务不做的事

- 不实现真正的结构化卡片业务能力
- 不引入 Tool Calling
- 不处理知识库或引用渲染
- 不重构整个消息系统为复杂的多态继承体系

## 3. 约束与前提

- 当前没有真实用户在使用，因此**不以旧数据兼容为目标**
- 允许清空本机开发数据库，优先选择结构清晰、后续演进顺畅的实现
- 但代码层仍保留基础默认值兜底，避免空字段导致运行时崩溃
- 本任务优先做“最小但正确”的地基，不提前做任务 2 的完整能力

## 4. 方案选择

讨论过的三个方向如下：

### 方案 A：最小增量方案

- 在 `ChatMessage` 中增加 `contentType`、`payloadJson`、`referenceJson`
- 数据库新增对应字段
- UI 只做按类型分发和回退

优点：

- 改动最小
- 对现有业务链路侵入低
- 最适合快速打地基

缺点：

- 载荷仍是字符串，类型安全较弱

### 方案 B：半强类型方案

- 在保留原始 JSON 字段的同时，引入 `MessagePayload` 等中间对象
- 内存里逐步往强类型对象靠拢

优点：

- 有利于后续结构化输出继续演进

缺点：

- 任务 1 的改动面更大

### 方案 C：全面重构方案

- 把消息模型彻底拆成多种子类型
- 数据库与渲染层一并重构

优点：

- 长期最干净

缺点：

- 当前阶段风险过高
- 不符合“先打地基”的目标

### 最终采用方案

本任务采用：**方案 A 为主，少量为方案 B 铺路**

具体原则：

- 落库采用 `payloadJson/referenceJson` 字符串字段
- 代码结构上预留 `lib/models/response/` 目录，为后续强类型消息体铺路
- 本任务不引入复杂多态和完整对象树

## 5. 数据模型设计

### 5.1 ChatMessage 新增字段

`ChatMessage` 保留现有字段，并新增：

- `contentType`
- `payloadJson`
- `referenceJson`

其中：

- `text` 继续保留，作为当前主展示文本与回退文本
- `payloadJson` 用于承载结构化消息主体
- `referenceJson` 用于承载引用、工具附加信息等扩展数据

### 5.2 内容类型枚举

第一版 `MessageContentType` 仅包含：

- `plainText`
- `structuredCard`
- `toolResult`

这样已经足够覆盖任务 1 的地基需求，也能给任务 2 和任务 3 留出扩展入口。

### 5.3 序列化原则

- `toMap()` 输出所有字段
- `fromMap()` 对空值提供安全默认值
- 如果 `contentType` 缺失或无法识别，则回退为 `plainText`
- `payloadJson` 和 `referenceJson` 允许为空

## 6. 数据库存储设计

### 6.1 schema 变更

数据库版本从 `5` 升到 `6`。

`messages` 表新增字段：

- `content_type TEXT NOT NULL DEFAULT 'plainText'`
- `payload_json TEXT`
- `reference_json TEXT`

### 6.2 迁移策略

由于当前不存在真实用户数据，本任务不为旧开发数据编写复杂迁移逻辑。

实现目标是：

- schema 能正确升级或重建
- 新字段能正确写入与读取
- 本地开发数据库如需清空重建，可接受

### 6.3 DatabaseHelper 边界

`DatabaseHelper` 只负责：

- schema 定义
- 字段读写
- 将数据库记录映射为 `ChatMessage`

它**不负责**解析结构化业务对象。

## 7. UI 渲染设计

### 7.1 渲染原则

`ChatMessageList` 新增按 `contentType` 分发渲染的能力：

- `plainText`：继续沿用当前纯文本/Markdown 渲染逻辑
- `structuredCard`：任务 1 只做接口预留和安全回退
- `toolResult`：任务 1 只做接口预留和安全回退

### 7.2 回退策略

如果出现以下任意情况：

- `contentType` 未知
- `payloadJson` 为空
- `payloadJson` 格式非法
- 对应渲染器尚未实现

统一回退为展示 `text`。

### 7.3 本阶段 UI 目标

任务 1 的 UI 目标不是“渲染新样式”，而是“具备渲染分发入口，并且绝不因为新类型崩溃”。

## 8. 测试策略

### 8.1 模型测试

文件：

- `test/models/chat_message_test.dart`

覆盖点：

- `toMap()/fromMap()` 正常工作
- `contentType` 默认值正确
- `payloadJson/referenceJson` 能正确序列化
- 空值时不会崩溃

### 8.2 数据库测试

文件：

- `test/database/database_helper_test.dart`

覆盖点：

- 新 schema 下消息可写入
- `content_type/payload_json/reference_json` 可正确读取
- 新增字段不会影响现有消息写入流程

### 8.3 Widget 测试

文件：

- `test/widgets/chat_message_list_test.dart`

覆盖点：

- `plainText` 正常渲染
- 未知类型安全回退
- 空 payload 安全回退
- 失败消息状态仍能正常显示

## 9. 文件调整建议

### 新建文件

- `lib/models/response/message_content_type.dart`
- `lib/models/response/structured_card.dart`
- `lib/models/response/message_payload.dart`
- `test/models/chat_message_test.dart`
- `test/database/database_helper_test.dart`
- `test/widgets/chat_message_list_test.dart`

### 修改文件

- `lib/models/chat_message.dart`
- `lib/database/database_helper.dart`
- `lib/widgets/chat_message_list.dart`

## 10. 验收标准

任务 1 完成时，应满足以下条件：

- `ChatMessage` 已支持消息类型与 JSON 载荷
- 数据库存储链路已支持新字段
- 聊天列表已具备按类型分发和安全回退能力
- 模型、数据库、Widget 三层测试已补齐
- 尚未实现结构化卡片业务，但已经为任务 2 打好了稳定地基

## 11. 下一步

任务 1 完成后，任务 2 将在此基础上接入：

- 非流式结构化输出请求
- 结构化响应解析与校验
- 结构化卡片渲染组件
- 一个显式的“结构化整理”入口

也就是说，任务 1 的核心价值不是功能可见性，而是后续所有 AI 系统能力都不需要再回头重做消息模型和存储层。
