# Agent Tool Recognition Redesign Design

## 背景

当前项目已经具备一套可工作的 agent turn loop、tool runtime registry 和 tool handler 体系，但“模型是否能正确识别该不该用工具、该用哪个工具、参数该怎么填”这件事，仍然主要依赖弱约束文本提示。

现状里最关键的问题有三类：

1. planner 只看到工具名白名单，几乎看不到完整工具语义。
2. tool definition 只包含极简字段，无法作为强约束 schema 暴露给模型。
3. tool 执行结果虽然已结构化落库，但下一轮 planner 没有充分消费这些结构化反馈。

这会直接导致：

- 该调工具时不调
- 选错工具
- 参数名漂移或字段不完整
- 调用失败后下一轮仍然不知道如何纠偏

## 目标

本次设计的目标不是单纯“改 prompt”，而是把 tool recognition 从脆弱的自由文本匹配，升级为更接近 Claude Code / Anthropic 官方推荐模式的结构化决策链路。

目标效果：

- planner 决策时能看到完整、准确、可执行的工具定义
- 模型输出尽量受 schema 约束，而不是自由生成 JSON
- 不同类型工具按能力域裁剪暴露，减少误选
- tool result / tool error 能作为下一轮决策输入，形成闭环
- 保留现有 Flutter 端 runtime/handler 架构，避免推倒重来

## 非目标

本轮设计明确不包含：

- 不引入远程 MCP server
- 不引入插件市场或动态下载工具
- 不一次性改造所有消息渲染 UI
- 不同步重构整个 ChatController 架构
- 不把所有 agent 能力都改成 subagent 模式

## 现状问题

### 1. Planner 暴露给模型的信息过弱

`AgentPlannerService` 当前只把工具名白名单塞进 system prompt：

- `search_chat_history`
- `web_search`
- `fetch_webpage`
- `save_note`
- `create_reminder`
- `create_calendar_event`
- `share_result`

问题在于，模型并不知道：

- 每个工具“什么时候该用”
- “什么时候不要用”
- 每个参数的真实语义
- 参数是否必填
- 参数格式要求
- 调用失败后应该如何重试或换工具

这类设计在工具数稍多时准确率会迅速下降。

### 2. ToolDefinition 无法支撑强 schema

当前 `ToolDefinition` 只有这些字段：

- `name`
- `title`
- `description`
- `parameters`
- `requiresConfirmation`
- `riskLevel`
- `supportedPlatforms`

这不足以表达：

- required 字段集合
- 每个字段的详细说明
- enum 值
- 示例输入
- 字段别名
- 何时拒绝调用
- 工具分类与使用边界

也就是说，runtime 可以执行 tool，但 decision layer 还拿不到真正适合给模型看的 schema。

### 3. 结构化反馈没有闭环回 planner

当前 event repository 已经能保存：

- tool call
- tool confirmation
- tool result
- tool error

而且 `toolResult.payloadJson` 里已经有结构化内容。但 planner 上下文构造仍然偏弱，更多是在传递摘要文本，而不是把“上轮工具做了什么、拿到了什么、失败原因是什么、还缺什么参数”结构化回灌给下一轮决策。

这导致 agent loop 容易出现以下问题：

- 重复调用同一工具
- 对失败原因无感知
- 明明已经拿到链接却仍继续搜索
- 应该进入 final answer 时继续盲目试工具

## 对外部实现的借鉴

### Anthropic / Claude 系路线索

从 Anthropic 官方 tool use 文档、Claude Code 文档和工程文章里，最值得借鉴的不是某个隐藏 prompt，而是以下原则：

1. 优先使用原生 tool calling，而不是让模型手写 JSON。
2. tool description 要非常具体，明确边界、前置条件、失败场景和参数含义。
3. 工具越多，越要做工具裁剪、延迟暴露或 tool search。
4. 把重复工作流迁移到 skills / commands / hooks，不要把所有动作都交给一个大 planner 去猜。
5. 安全和高风险动作要单独建模，不要和纯查询能力混在同一决策面板。

### OpenAI 路线索

OpenAI 在 function calling / Structured Outputs 里的核心借鉴点是：

1. 直接给模型 JSON Schema，而不是仅给字段名。
2. 对参数结构用 strict schema 做硬约束。
3. 让工具参数生成成为受控输出，而不是 prompt 猜测结果。

### MCP 路线索

MCP 的价值不在于“必须上协议”，而在于它把工具、资源、prompt 分成了不同概念：

- tools：执行动作
- resources：提供上下文
- prompts：提供复用工作流

这个拆分对当前项目有启发：

- `search_chat_history` / `fetch_webpage` 这类读能力更接近“上下文资源获取”
- `save_note` / `create_reminder` / `share_result` 这类写能力才是典型 action tools

这意味着后续可以避免把所有能力都放在同一层 planner 里裸选。

## 设计总览

本次改造分四层推进：

1. 定义层：把 `ToolDefinition` 升级为可导出给模型的强 schema
2. 决策层：让 planner 使用结构化工具定义，而不是只看工具名
3. 暴露层：按能力域裁剪本轮可见工具集合
4. 反馈层：把 tool result / error 结构化回灌到下一轮 planner

## 方案 A：升级 ToolDefinition

### 新目标

`ToolDefinition` 不再只是 runtime 元数据，而是同时承担“模型侧声明”的职责。

建议新增字段：

- `category`
- `descriptionForModel`
- `whenToUse`
- `whenNotToUse`
- `argumentSchema`
- `requiredArguments`
- `argumentDescriptions`
- `argumentExamples`
- `outputSummaryStyle`
- `requiresConfirmation`
- `riskLevel`
- `supportedPlatforms`

其中最关键的是：

### `descriptionForModel`

用于给模型看的长描述，必须明确：

- 工具的核心用途
- 适用意图
- 不适用意图
- 参数补全规则
- 输出预期

例如 `web_search` 的模型侧描述不应只是“搜索外部网页并返回结构化结果列表”，而应说明：

- 当用户询问实时信息、网页资料、外部来源时使用
- 如果用户已经提供 URL，应优先用 `fetch_webpage` 而不是再次搜索
- 如果问题只依赖当前聊天上下文，应优先用 `search_chat_history`
- `query` 应是短而具体的检索词，不要直接复制整段用户消息

### `argumentSchema`

从 `Map<String, String>` 升级为可导出 JSON Schema 的结构，至少需要表达：

- `type`
- `properties`
- `required`
- `enum`
- `description`
- `format`

这样未来无论底层接 Anthropic、OpenAI 还是你自己的 planner prompt，都能统一从一份 schema 导出。

## 方案 B：决策层从“文本 JSON”升级为“结构化工具规划”

### 现状

当前 planner 的主要约束方式是：

- system prompt 里告诉模型只能输出两种 JSON
- 其中一种是 `call_tool`
- 工具名必须在白名单中

这是一个脆弱的文本协议。

### 建议方向

优先级从高到低分两档：

#### 档位 1：先在现有接口上强化 planner prompt

短期内不改底层 LLM API 时，可先把 planner prompt 改为结构化清单形式，至少包含：

- 当前可用工具列表
- 每个工具的长描述
- 每个工具的参数表
- 每个工具的典型触发场景
- 工具选择规则
- final answer 退出条件

这样即使仍然输出 JSON 文本，也比现在只有工具名强很多。

#### 档位 2：切换到原生 tool calling

中期建议让 `BaseLLM.planNextAction()` 支持原生 tool definition 输入和 tool call 输出，而不是返回一段字符串。

目标接口应接近：

- 输入：messages + tool schemas + tool choice policy
- 输出：respond 或 tool call 结构体

这样可以减少：

- 解析失败
- JSON 漂移
- 参数键名不一致
- toolName 拼写错误

## 方案 C：按能力域裁剪工具暴露

### 现状问题

当前 planner 默认看到全部工具。

虽然工具数量不算多，但它们混合了：

- 查询
- 读取
- 写入
- 分享
- 系统侧动作

这会让模型在“只是查资料”时也能看到高风险写工具。

### 建议分组

先按意图分三组：

#### 1. Context Retrieval

- `search_chat_history`
- `web_search`
- `fetch_webpage`

适用于：

- 回忆历史上下文
- 查询联网资料
- 读取给定 URL

#### 2. Personal Productivity

- `save_note`
- `create_reminder`
- `create_calendar_event`

适用于：

- 用户明确要求落库、提醒、安排时间

#### 3. Output Action

- `share_result`

适用于：

- 用户明确要求分享、导出、发送

### 暴露策略

第一阶段不做复杂 classifier，只做规则化裁剪：

- 用户消息包含 URL 时，优先暴露 `fetch_webpage`
- 用户消息是明显实时/外部信息查询时，暴露 `web_search`
- 用户消息涉及“提醒/日程/笔记/分享”时，再暴露对应写工具
- 默认情况下，写工具不参与纯问答检索轮次

这样能立刻降低误触发率。

## 方案 D：把 tool 结果作为结构化 planner state

### 新目标

每一轮 planner 都应该看到足够明确的状态摘要，例如：

- 已尝试工具列表
- 最近一次工具调用
- 最近一次工具是否成功
- 最近一次失败原因
- 最近一次 tool result 是否已足够回答用户
- 当前仍缺失的关键信息

### 建议新增 planner state 摘要

可由 `TranscriptBuilderService` 负责生成单独的 planner context，内容类似：

- `user_goal`
- `attempted_tools`
- `latest_tool_call`
- `latest_tool_result_summary`
- `latest_tool_error`
- `known_urls`
- `known_entities`
- `missing_slots`
- `should_answer_now`

这里的关键不是做很复杂的知识图谱，而是把 event log 转成 planner 真正能消费的结构。

### 行为收益

这样改完后，planner 更容易做出正确判断：

- 已经拿到网页正文后，转 final answer
- 搜索无结果后，改写 query 或换工具
- 参数缺时间时，不贸然创建 reminder
- 已经调用过 `fetch_webpage` 且失败时，不无脑重复调同链接

## 方案 E：明确“工具”与“工作流”的边界

Claude Code 一个很重要的借鉴点是：不是所有能力都做成自动工具选择。

对于当前项目，建议逐步形成以下边界：

- tools：单步能力，输入输出清晰，可程序化执行
- prompts / reusable workflows：多步文本策略，例如“先搜索再总结”
- UI actions：必须由用户明确触发的高风险动作

对当前仓库的启发是：

- `search + open + summarize` 不一定要变成一个新工具
- 但可以在 planner prompt 里明确为推荐工作流
- 高风险写动作继续保留 confirmation gate

## 落地顺序

建议分三期实施。

### Phase 1：低风险增益

- 扩展 `ToolDefinition` 数据模型
- 为每个现有工具补长描述和参数描述
- planner prompt 动态注入完整工具定义
- planner 增加“何时直接回答”的退出规则
- transcript builder 增加结构化 planner summary

这一期不动底层 LLM 接口，主要提升识别率。

### Phase 2：中风险结构升级

- `BaseLLM.planNextAction()` 增加原生 tool schema 支持
- planner 输出改为结构化 tool call 响应
- 增加工具分组暴露策略
- 让 tool error 进入下一轮决策

这一期会触到接口和测试，但收益很高。

### Phase 3：进一步演进

- 引入 tool search / deferred loading 思路
- 把查询类能力进一步和 action tool 解耦
- 视模型能力决定是否引入更细粒度 planner/router

这期不是当前必须项。

## 测试策略

这类改造的关键不是“单元测试有没有”，而是要有能衡量识别质量的测试样本。

建议补三层测试：

### 1. Tool definition 导出测试

验证：

- 每个工具导出的 schema 完整
- required 字段正确
- 风险等级与确认策略一致
- 平台过滤正确

### 2. Planner prompt / planner state 测试

验证：

- planner 能看到动态工具定义而不是固定白名单
- planner context 包含最近一次 tool result/error 摘要
- URL 场景下能优先看到 `fetch_webpage`

### 3. Decision regression fixtures

新增一批真实意图样本，覆盖：

- 应调用 `search_chat_history`
- 应调用 `web_search`
- 应调用 `fetch_webpage`
- 应直接回答
- 应进入 confirmation flow
- 应拒绝写动作

这些 fixture 将成为之后每次调 prompt/schema 的回归依据。

## 风险与权衡

### 风险 1：描述太长导致 token 增长

解决思路：

- 只暴露本轮候选工具
- 读写分组裁剪
- descriptionForModel 控制在高信息密度而非长篇废话

### 风险 2：过早切原生 tool calling 会增加接入复杂度

解决思路：

- 先做 Phase 1
- 用可导出 schema 的设计为 Phase 2 铺路

### 风险 3：规则化裁剪过强会漏掉合法工具

解决思路：

- 初期裁剪策略只做“默认隐藏高风险写工具”
- 对 retrieval 工具保留较宽松暴露
- 通过 regression fixtures 校验误伤率

## 需要修改的核心文件

第一阶段预计主要涉及：

- `lib/models/tool/tool_definition.dart`
- `lib/tools/core/tool_runtime_registry.dart`
- `lib/tools/default_tool_runtime_registry.dart`
- `lib/services/agent_planner_service.dart`
- `lib/services/transcript_builder_service.dart`
- `lib/models/llm/base_llm.dart`
- `lib/models/llm/configurable_http_llm.dart`
- `lib/tools/handlers/*.dart`
- `test/services/agent_planner_service_test.dart`
- `test/services/transcript_builder_service_test.dart`
- 新增 planner/tool schema 相关测试

## 结论

当前项目的主要问题不是“tool runtime 不存在”，而是“decision layer 没有真正消费 tool 语义”。因此最有价值的方向不是继续堆 prompt 小技巧，而是：

1. 让工具定义变强
2. 让 planner 能看到这些定义
3. 让工具集合按场景裁剪
4. 让工具结果回灌下一轮决策

如果这四步做对，tool recognition 的可见提升会远大于单纯微调一句 prompt。
