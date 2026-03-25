# FlutterAIChat AI 演进路线图实施计划

> **给执行型 Agent 的说明：** 实施本计划时，必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans` 子技能，并按任务逐项推进。步骤统一使用复选框语法 `- [ ]` 进行跟踪。

**目标：** 将 FlutterAIChat 从一个以聊天为主的客户端，逐步升级为一个具备类型化响应、工具执行、可观测性、最小可用 RAG 能力，以及至少一项差异化多模态能力的移动端 AI 助手。

**架构思路：** 保留当前 `Riverpod -> ChatController -> ChatService -> BaseLLM -> SQLite/UI` 的主干结构，但不再把所有助手输出都当作纯 Markdown 文本处理。第一步先引入“类型化消息载荷”层，再把结构化输出、工具结果、遥测信息、知识引用等能力挂接到这层上。RAG 第一版优先采用更适合客户端落地的方案，例如本地文档解析 + SQLite FTS，或一个轻量后端，而不是一开始就在 Flutter 内部硬上复杂向量检索。

**技术栈：** Flutter、Riverpod、sqflite、http、flutter_markdown、现有 DeepSeek 兼容 LLM 抽象，以及在第 4 阶段可选接入的轻量检索/Embedding 后端。

---

## 当前基线

- `lib/providers/chat_providers.dart` 当前职责过重，同时承担了持久化、流式处理、UI 状态管理、自动摘要调度和响应解析。
- `lib/services/chat_service.dart` 当前只负责上下文组装和转发文本流，尚不具备类型化响应处理、重试策略或指标埋点能力。
- `lib/models/chat_message.dart` 目前只存储了 `text`、`status` 和 `reasoningContent`，无法承载结构化卡片、工具元数据、引用信息或原始载荷。
- `lib/database/database_helper.dart` 中 `messages` 表当前仍以纯文本消息为主，数据库版本为 `5`。
- `lib/widgets/chat_message_list.dart` 当前默认助手消息就是 Markdown，用户消息就是纯文本。
- `lib/models/llm/base_llm.dart` 当前仅暴露了 `chatStream`、`validateApiKey` 和 `summarizeConversation`。
- `test/` 目录目前几乎为空，只有 `test/widget_test.dart`，因此下面每个阶段都需要同步补测试。

## 范围拆分

这份路线图涵盖了多个相对独立的子系统，建议按下面的阶段分别实施：

1. 类型化消息基础设施
2. 结构化输出最小闭环
3. Tool Calling 最小闭环
4. 可观测性与稳定性增强
5. 最小可用 RAG
6. 多模态与 Android 差异化能力

不要试图在一个分支里一次性做完全部六个部分。每完成一个阶段，都先验证稳定，再进入下一个阶段。

## 推荐的 90 天推进顺序

- 第 1-2 周：类型化消息 + 结构化输出
- 第 3-4 周：Tool Calling + 遥测/错误处理
- 第 5-8 周：最小 RAG + 知识库管理
- 第 9-12 周：语音/OCR + 一项 Android 原生差异化能力 + 项目包装

## 必须优先处理的跨阶段事项

- [ ] 在任何公开演示或分享前，先把 [deepseek_llm.dart](/C:/DiskD/AndroidSpace/FlutterAIChat/lib/models/llm/deepseek_llm.dart) 中硬编码的 API Key 移除。
- [ ] 每完成一个阶段后，都执行 `flutter analyze` 和有针对性的 `flutter test`。
- [ ] 数据库迁移必须保持前向兼容，不能破坏现有本地聊天历史。
- [ ] 所有 schema 和 UI 改动优先采用“增量字段 + 回退渲染”方案，确保旧消息仍能正常显示。

### 任务 1：类型化消息基础设施

**涉及文件：**
- 新建：`lib/models/response/message_content_type.dart`
- 新建：`lib/models/response/structured_card.dart`
- 新建：`lib/models/response/message_payload.dart`
- 修改：`lib/models/chat_message.dart`
- 修改：`lib/database/database_helper.dart`
- 修改：`lib/widgets/chat_message_list.dart`
- 测试：`test/models/chat_message_test.dart`
- 测试：`test/database/database_helper_test.dart`
- 测试：`test/widgets/chat_message_list_test.dart`

- [ ] 新增 `MessageContentType` 枚举，至少包含 `plainText`、`structuredCard`、`toolResult`。
- [ ] 扩展 `ChatMessage`，让它能承载类型化消息元数据，例如 `contentType`、`payloadJson`、可选的 `referenceJson`。
- [ ] 补齐序列化/反序列化逻辑，保证老数据在没有新字段时默认仍按 `plainText` 处理。
- [ ] 将 SQLite schema 从版本 `5` 升级到 `6`，只增加字段，不替换现有 `text` 字段。
- [ ] 更新 [chat_message_list.dart](/C:/DiskD/AndroidSpace/FlutterAIChat/lib/widgets/chat_message_list.dart)，按 `contentType` 分发渲染，同时保留 Markdown 作为默认回退路径。
- [ ] 补测试，验证旧版纯文本消息、新版结构化消息和失败消息都能安全渲染。
- [ ] 使用 `flutter test test/models/chat_message_test.dart test/database/database_helper_test.dart test/widgets/chat_message_list_test.dart` 验证。
- [ ] 运行 `flutter analyze`。

**验收标准：**
- 数据库迁移后，现有聊天记录仍可正常打开。
- 助手消息可以承载非 Markdown 的结构化内容，且不会破坏 UI。
- 无法识别的消息载荷会自动回退为普通文本显示。

### 任务 2：结构化输出最小闭环

**涉及文件：**
- 新建：`lib/models/response/structured_summary_card.dart`
- 新建：`lib/services/response_parser_service.dart`
- 新建：`lib/widgets/structured_message/structured_summary_card_widget.dart`
- 修改：`lib/models/llm/base_llm.dart`
- 修改：`lib/models/llm/deepseek_llm.dart`
- 修改：`lib/services/chat_service.dart`
- 修改：`lib/providers/chat_providers.dart`
- 修改：`lib/widgets/chat_message_list.dart`
- 测试：`test/services/response_parser_service_test.dart`
- 测试：`test/widgets/structured_summary_card_widget_test.dart`

- [ ] 第一阶段只选一个范围足够小的结构化输出场景，例如“把一段长回答整理成结构化卡片：标题、摘要、关键点、行动项、风险项”。
- [ ] 在 `BaseLLM` 中增加一个非流式结构化响应方法，不要继续把结构化 JSON 硬塞进现有文本流里解析。
- [ ] 实现一个解析/校验服务，输入模型原始输出，输出要么是合法的 `structuredCard` 载荷，要么回退成普通文本。
- [ ] 在 `lib/widgets/structured_message/` 下实现专用结构化卡片组件。
- [ ] 这个能力先通过一个显式入口暴露，例如消息长按菜单中的“结构化整理”，或页面操作菜单中的一个入口。
- [ ] 结构化解析失败时必须保留原始文本回答，绝不把原始 JSON 直接展示给用户。
- [ ] 使用 `flutter test test/services/response_parser_service_test.dart test/widgets/structured_summary_card_widget_test.dart` 验证。
- [ ] 在 [chat_page.dart](/C:/DiskD/AndroidSpace/FlutterAIChat/lib/pages/chat_page.dart) 上手动验证：解析失败时，仍能按普通 Markdown 正常显示。

**验收标准：**
- 用户可以完整走通一个结构化输出场景。
- 结构化结果以卡片形式呈现，而不是 JSON 文本。
- 结构化失败时会自动回退为普通文本，不影响现有对话流程。

### 任务 3：Tool Calling 最小闭环

**涉及文件：**
- 新建：`lib/models/tool/tool_definition.dart`
- 新建：`lib/models/tool/tool_call.dart`
- 新建：`lib/models/tool/tool_result.dart`
- 新建：`lib/services/tool_registry.dart`
- 新建：`lib/services/tool_executor.dart`
- 新建：`lib/services/tool_call_service.dart`
- 修改：`lib/models/llm/base_llm.dart`
- 修改：`lib/models/llm/deepseek_llm.dart`
- 修改：`lib/providers/chat_providers.dart`
- 修改：`lib/database/database_helper.dart`
- 修改：`lib/widgets/chat_message_list.dart`
- 测试：`test/services/tool_registry_test.dart`
- 测试：`test/services/tool_executor_test.dart`
- 测试：`test/providers/chat_controller_tool_flow_test.dart`

- [ ] 第一版只实现一个内部工具：`search_chat_history`。
- [ ] 工具定义与 UI 解耦，工具注册层不能依赖具体 Widget。
- [ ] 通过 `ToolCallService` 实现模型决策是否调用工具的编排逻辑。
- [ ] 工具执行通过 `ToolExecutor` 完成，输出稳定的结果对象，并回注到最终回答流程。
- [ ] 在聊天 UI 中展示最小执行状态，例如“已执行：搜索历史记录”。
- [ ] 工具执行元数据存入消息载荷，而不是写死到 Markdown 文本里。
- [ ] 等 `search_chat_history` 稳定后，再追加第二个工具 `extract_todos`。
- [ ] 使用 `flutter test test/services/tool_registry_test.dart test/services/tool_executor_test.dart test/providers/chat_controller_tool_flow_test.dart` 验证。
- [ ] 运行 `flutter analyze`。

**验收标准：**
- 应用能够跑通完整链路：“模型决策 -> 工具执行 -> 结果回注 -> 最终回答”。
- 工具失败时界面有友好反馈，不是静默失败。
- 工具执行层与 UI 层保持解耦。

### 任务 4：可观测性、错误处理与稳定性

**涉及文件：**
- 新建：`lib/models/telemetry/chat_request_metrics.dart`
- 新建：`lib/models/telemetry/chat_error_type.dart`
- 新建：`lib/services/chat_metrics_service.dart`
- 新建：`lib/utils/error_mapper.dart`
- 修改：`lib/services/chat_service.dart`
- 修改：`lib/models/llm/deepseek_llm.dart`
- 修改：`lib/providers/chat_providers.dart`
- 修改：`lib/utils/logger.dart`
- 测试：`test/utils/error_mapper_test.dart`
- 测试：`test/services/chat_metrics_service_test.dart`

- [ ] 为每次请求引入 `requestId`，并贯穿整个发送消息链路进行日志追踪。
- [ ] 记录请求耗时、解析失败、传输失败、用户手动中断等关键状态。
- [ ] 增加统一错误映射层，把原始异常归类为 `network`、`auth`、`timeout`、`parse`、`model` 等错误类型。
- [ ] 仅针对可安全重试的错误类型加入超时与最小重试策略。
- [ ] 流式中断和自动重试逻辑必须分离，避免用户手动取消后仍被误重试。
- [ ] 第一版只需要轻量指标接收层，先存日志或内存统计即可，不急着做分析页面。
- [ ] 使用 `flutter test test/utils/error_mapper_test.dart test/services/chat_metrics_service_test.dart` 验证。
- [ ] 手动做一次失败演练：无效 Key、离线网络、畸形 JSON、用户取消。

**验收标准：**
- 你能明确知道错误发生在网络、鉴权、模型还是解析阶段。
- 每个请求都有可衡量的耗时和终态。
- 重试逻辑不会重复生成已经完成的回答内容。

### 任务 5：面向开发文档的最小可用 RAG

**涉及文件：**
- 新建：`lib/models/knowledge/knowledge_document.dart`
- 新建：`lib/models/knowledge/knowledge_chunk.dart`
- 新建：`lib/models/knowledge/knowledge_reference.dart`
- 新建：`lib/services/knowledge_base_service.dart`
- 新建：`lib/pages/knowledge_base_page.dart`
- 新建：`lib/widgets/reference_chip.dart`
- 修改：`lib/database/database_helper.dart`
- 修改：`lib/services/chat_service.dart`
- 修改：`lib/providers/chat_providers.dart`
- 修改：`lib/main.dart`
- 测试：`test/services/knowledge_base_service_test.dart`
- 测试：`test/providers/chat_controller_rag_flow_test.dart`

- [ ] 第一版只支持一种文档来源：导入 Markdown 或纯文本开发笔记。
- [ ] 首个可交付版本优先选择 SQLite FTS 或其他简单本地检索方案。
- [ ] 如果检索质量不够，再把向量/Embedding 部分拆到轻量后端，不要一开始就强行塞进 Flutter。
- [ ] 建立文档生命周期模型：已导入、已解析、已切片、已索引、失败。
- [ ] 回答结果中增加引用，并通过引用 Chip 进行展示。
- [ ] 低置信度检索时要保守降级，明确告诉用户“没有找到相关资料”，不要胡编引用。
- [ ] 在 `eval/` 下建立一个 20-30 题的小型评测集，题目来源可以是仓库内容或 Android 文档。
- [ ] 使用 `flutter test test/services/knowledge_base_service_test.dart test/providers/chat_controller_rag_flow_test.dart` 验证。
- [ ] 手动验证：询问导入资料之外的问题时，不会生成看似很自信的假引用。

**验收标准：**
- 应用可以基于导入文档回答问题，并展示至少一个引用来源。
- 没有检索命中时，会明确给出兜底提示。
- 你拥有一套可重复执行的小型评测集，而不是只靠主观感觉判断效果。

### 任务 6：多模态与 Android 差异化能力

**涉及文件：**
- 新建：`lib/services/speech_service.dart`
- 新建：`lib/services/ocr_service.dart`
- 新建：`lib/pages/multimodal_page.dart`
- 修改：`lib/main.dart`
- 修改：`lib/pages/chat_page.dart`
- 修改：`android/app/src/main/`
- 测试：`test/services/speech_service_test.dart`
- 测试：`test/services/ocr_service_test.dart`

- [ ] 第一优先的多模态路径建议选择 `OCR + 结构化总结`，它和当前仓库最契合。
- [ ] 语音输入作为后续能力推进，除非 OCR 提前顺利落地。
- [ ] OCR 的输出结果回接到任务 2 中的结构化输出链路，避免为新能力再单独造一套渲染体系。
- [ ] 至少加入一项 Android 原生能力，通过 Platform Channel 或插件边界接入，例如原生文件选择、原生 OCR 预处理、原生性能采样等。
- [ ] 在动 UI 前先定义清楚权限处理和失败状态。
- [ ] 尽量补充聚焦测试，并在 Android 真机上做一次端到端验证。

**验收标准：**
- 应用展示出一项真正有移动端辨识度的能力，而不只是“聊天页多了个按钮”。
- 多模态结果复用类型化消息管线，不另起一套平行逻辑。
- 至少有一部分实现能体现你的 Android 原生工程能力。

## 每周执行节奏

- [ ] 工作日建议节奏：30 分钟学理论，60-90 分钟做功能，15 分钟记录问题与结论。
- [ ] 周末建议节奏：半天做功能，半天做文档、录屏、README 和复盘。
- [ ] 每周至少产出三样东西：一个新认知、一个可运行功能增量、一份文字化沉淀。

## 建议持续保留的产出物

- [ ] 每个大阶段完成后更新 README
- [ ] 一张请求/响应链路架构图
- [ ] 结构化输出、工具调用、RAG 引用能力的截图或录屏
- [ ] `eval/` 评测样例集
- [ ] 一份放在 `docs/` 下的简短周报或构建记录

## 建议立刻进入的下一份实施计划

下一份真正要开始执行的实现计划，建议只覆盖 **任务 1 + 任务 2**。这是当前仓库最小但最有价值的一段升级闭环，不会一下子把系统复杂度拉得过高。

推荐顺序：

1. 类型化消息 schema
2. 结构化卡片渲染
3. 一个显式的结构化输出入口
4. 回退兜底逻辑
5. 测试与数据库迁移验证

在这段链路稳定之前，不建议立刻开始 Tool Calling 或 RAG。
