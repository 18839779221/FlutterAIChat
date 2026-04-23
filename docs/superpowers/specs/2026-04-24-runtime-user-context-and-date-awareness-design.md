# 运行时 UserContext 与日期感知设计

## 背景

当前项目已经完成了基于 agent loop 的主链路改造，planner 的上下文主要由 [`SessionContextService`](/Users/skka/flutterSpace/FlutterAIChat/lib/services/session_context_service.dart) 构建。但在真实使用中仍存在一个明显问题：

- 模型不知道“今天是哪一天”
- 当用户要求搜索“最新新闻”“最新文档”“最近变化”时，模型可能错误使用去年的年份构造查询
- 长会话跨天后，模型可能继续沿用旧日期理解用户请求

这类问题不是单纯的 session 历史缺失，也不是基础 system prompt 规则缺失，而是“运行时环境上下文”没有被稳定注入模型。

参考 Claude Code 的 prompt 管理方案，适合当前项目的部分不是整套 CLI 缓存与 override 机制，而是其中两条核心思路：

1. 用独立于 system prompt 的 `userContext` synthetic message 向模型提供运行时环境信息
2. 对需要强时间感知的工具，在工具描述中显式注入当前月份和年份，降低查询年份漂移

在此基础上，本项目还需要补充第三层机制：

3. 当会话跨天后，在下一次发送前插入“日期已变化”的运行时提醒，修正长会话中的旧日期残留

## 目标

- 为 planner 和 final answer 两类主模型调用稳定注入 `userContext`
- 让模型在需要处理“最新”“最近”“当前”“今天”这类请求时，具备正确的当前日期感知
- 在会话跨天时自动插入日期变化提醒，而不是依赖模型从旧上下文中自行推断
- 重写 WebSearch 工具描述，使其在“最近信息”场景下强制使用当前年份
- 将运行时环境信息、会话历史信息、系统行为规则三层职责明确分离

## 非目标

- 本轮不设计 `AGENTS.md` 的编辑入口或同步方式
- 本轮不做复杂的 prompt cache boundary 或 section registry 机制
- 本轮不把日期提醒显示为用户可见 timeline 消息
- 本轮不把这些运行时提醒写入 session summary 或压缩快照
- 本轮不扩展为通用长期记忆系统

## 问题拆解

### 1. 当前日期不属于 session 历史事实

`SessionContextService` 当前负责的是：

- 历史摘要
- 最近完成 turn
- 当前 turn transcript

它解决的是“这段会话里发生了什么”，而不是“模型现在所处环境是什么”。今天的日期、运行时项目指令、平台时区等信息不适合被混入 session 历史压缩结果。

### 2. 当前日期也不适合直接写进 system prompt

当前 prompt 管理已经收敛为：

- `base prompt`
- `stage delta`
- `runtime sections`
- `context messages`

日期属于高变化频率的运行时环境值。如果把它直接拼进 system prompt，会带来两个问题：

- 每天都会改变 system prompt 的内容真相
- 把“环境信息”与“行为规则”混在一起，破坏 prompt 分层边界

因此日期更适合进入 `context messages`，而不是进入 `system prompt`。

### 3. 仅在第一轮注入日期仍然不够

即使第一轮通过 `userContext` 告诉模型今天日期，长会话跨天后仍可能出现：

- 模型继续使用昨日日期理解“今天”
- 搜索工具在 query 中继续沿用旧年份

因此除了初始 `userContext` 外，还需要会话级的跨天修正机制。

## 方案总览

本次设计引入三层互补机制：

1. `Runtime UserContext`
2. `Date Change Reminder`
3. `WebSearch Current-Year Prompting`

它们共同构成“运行时时间感知层”。

## 方案 A：Runtime UserContext

### 定义

`userContext` 是一条在真实用户消息之前注入给模型的 synthetic `user` message。

它的职责是向模型提供“可能相关的运行时环境信息”，而不是定义行为规则。

### 初版内容

第一阶段的 `userContext` 包含：

- `currentDate`
- `AGENTS.md` 派生内容占位

其中 `AGENTS.md` 本轮只搭结构，不设计编辑或更新流程。

### 注入范围

`userContext` 只注入到：

- planner
- final answer

不注入到：

- summary

原因如下：

- planner 需要它来做下一步动作判断
- final answer 需要它来理解“今天”“当前”“最新”等面向用户的时间表达
- summary 的职责是压缩历史，不应被当天日期和运行时提醒污染

### 推荐消息格式

建议采用与 Claude Code 近似但命名适配本项目的模板：

```text
<system-reminder>
As you answer the user's questions, you can use the following context:

# agentsMd
...

# currentDate
Today's date is 2026-04-24.

IMPORTANT: this context may or may not be relevant to your task.
Do not mention this context unless it is actually relevant.
</system-reminder>
```

说明：

- 外层仍然是 message，而不是 system prompt section
- 内容中显式提醒“可能相关，也可能无关”
- 避免模型把 `AGENTS.md` 或当前日期主动复述给用户

### 组件划分

建议新增三个窄职责组件。

#### 1. `RuntimeUserContextSnapshot`

用于承载本次运行时要注入的 userContext 数据。

建议字段：

- `currentDateText`
- `agentsMdText`
- `additionalSections`

#### 2. `RuntimeUserContextService`

负责生成 `RuntimeUserContextSnapshot`。

第一版负责：

- 读取当前日期
- 格式化日期文本
- 提供 `AGENTS.md` 派生文本来源占位

#### 3. `UserContextMessageBuilder`

负责将 `RuntimeUserContextSnapshot` 渲染成一条 synthetic `ChatMessage(role: user)`，统一 planner 与 final answer 两个入口的模板。

### 接入点

`userContext` 接到两处：

1. [`SessionContextService.buildPlannerMessages()`](/Users/skka/flutterSpace/FlutterAIChat/lib/services/session_context_service.dart)
2. [`TranscriptBuilderService.buildFinalAnswerMessages()`](/Users/skka/flutterSpace/FlutterAIChat/lib/services/transcript_builder_service.dart)

在两个入口里，`userContext` 都应位于真实用户消息之前。

## 方案 B：Date Change Reminder

### 设计动机

即使第一轮已经通过 `userContext` 注入了 `currentDate`，当 App 保持运行或被杀死重进后重新进入同一会话，仍然需要判断：

- 当前日期是否已经不同于该 session 最近一次注入给模型的日期

如果日期不同，则应在“当前 user message 发给模型之前”插入一条日期变化提醒。

### 提醒格式

固定模板如下：

```text
<system-reminder>
The date has changed. Today's date is now <newDate>.
DO NOT mention this to the user explicitly because they are already aware.
</system-reminder>
```

### 注入时机

日期变化提醒应发生在“准备发送当前 user message 时”，而不是在后台定时写入消息。

具体顺序建议为：

1. 构建 planner / final-answer 输入消息
2. 读取当前 session 最近一次注入日期
3. 若当前日期不同，则先插入 `date changed reminder`
4. 再插入当前真实 user message

### 比较基线

比较基线不是内存中的“上一条日期”，而是当前 session 最近一次已注入给模型的日期。

规则如下：

- 若该 session 尚无注入记录，则第一次以 `userContext.currentDate` 作为初始基线
- 若已存在注入记录，则与最近一次记录的日期比较
- 如果当前日期不同，则插入 reminder，并把新日期更新为最新基线

这样可以正确覆盖：

- App 杀死重进
- 会话挂起后恢复
- 多个 session 各自独立跨天

### 持久化方式

不建议只存在内存中。

推荐新增独立的 session 级 runtime marker 持久化载体，例如：

- `session_runtime_markers`

建议字段：

- `group_id`
- `last_injected_date`
- `updated_at`

职责定义：

- 仅记录当前 session 最近一次注入给模型的日期基线
- 不承担历史压缩职责
- 不承担 UI timeline 展示职责

### 为什么不写入 transcript / timeline

不建议把日期变化提醒做成真实持久化聊天消息或 `chat_event`，原因如下：

- 它不是用户对话事实，而是运行时环境修正
- 写入 transcript 会污染 session summary
- 写入 timeline 会让用户看到内部机制噪音
- 写入 turn ledger 会增加 verifier、event projection、压缩边界的复杂度

因此它更适合作为“发送前运行时注入消息”，而不是持久对话事实。

## 方案 C：WebSearch Current-Year Prompting

### 设计动机

即使模型已经知道今天日期，在发起 WebSearch 时仍可能：

- 搜索“latest Claude news”但实际检索 2024 年结果
- 搜索“latest React docs”但 query 没有体现当前年份

这说明“知道日期”并不等于“会在 search query 中正确使用当前年份”。

因此 WebSearch 工具的 planner-facing / execution-facing 描述需要整体增强。

### 重写原则

尽量复用已验证有效的模板，并适配本项目现有工具契约。

建议保留以下核心语义：

- 允许模型搜索 Web，并用结果辅助回答
- 为当前事件、最近变化、最新数据提供最新信息
- 搜索结果应带标题、摘要与 URL
- 当信息超出模型知识截止时使用该工具
- 回答结尾必须包含 `Sources:`
- `Sources:` 中的链接必须是 markdown hyperlink
- 搜最近信息、新闻、文档、当前事件时，必须使用当前年份

### 动态变量

工具描述中应动态注入：

- `${currentMonthYear}`

例如：

- `The current month is April 2026. You MUST use this year when searching for recent information, documentation, or current events.`

### 推荐描述骨架

以下骨架可作为本项目 WebSearch 工具描述改造的基准：

```text
Allows the model to search the web and use the results to inform responses.
Provides up-to-date information for current events and recent data.
Returns search result information including links as markdown hyperlinks.
Use this tool for accessing information beyond the model's knowledge cutoff.

CRITICAL REQUIREMENT:
- After answering the user's question, you MUST include a "Sources:" section at the end of the response.
- In the Sources section, list all relevant URLs from the search results as markdown hyperlinks: [Title](URL).
- This is mandatory.

IMPORTANT - Use the correct year in search queries:
- The current month is ${currentMonthYear}. You MUST use this year when searching for recent information, documentation, or current events.
- If the user asks for "latest" information, do not default to last year.
```

项目实现时可根据现有 schema 再补充：

- 域名过滤支持
- 可用地区限制
- 结果结构字段说明

## 三层职责边界

### 1. `system prompt`

职责：

- 定义行为规则
- 定义阶段职责
- 定义 runtime sections 约束

不负责：

- 提供当天日期
- 提供跨天修正提醒

### 2. `userContext` / 日期提醒

职责：

- 提供运行时环境信息
- 提供日期变化修正

不负责：

- 取代系统规则
- 成为 session 历史的一部分

### 3. `session context`

职责：

- 提供历史摘要
- 提供最近 turn 工作集
- 提供当前 turn transcript

不负责：

- 提供今天日期
- 承载运行时项目说明

## 数据流

### Planner 链路

planner 调用前的消息组装顺序建议为：

1. `system prompt`
2. `userContext message`
3. 如果跨天则注入 `date changed reminder`
4. `history summary`
5. `recent completed turns`
6. `current turn transcript`

### Final Answer 链路

final answer 调用前的消息组装顺序建议为：

1. `system prompt`
2. `userContext message`
3. 如果跨天则注入 `date changed reminder`
4. 当前 turn 投影消息

### Summary 链路

summary 调用保持不变：

- 不注入 `userContext`
- 不注入日期变化提醒

## 建议改动点

预计涉及以下类型的改动：

- 新增 `RuntimeUserContextSnapshot` model
- 新增 `RuntimeUserContextService`
- 新增 `UserContextMessageBuilder`
- 新增 session runtime marker 持久化 model / repository / storage
- 更新 `SessionContextService`
- 更新 `TranscriptBuilderService`
- 更新 WebSearch tool definition 的描述文本与动态变量注入
- 补充对应测试
- 更新 `README.md` 与 `AGENTS.md`

## 测试重点

### 1. UserContext 注入

- planner 消息中包含 `currentDate`
- final answer 消息中包含 `currentDate`
- summary 消息中不包含 `currentDate`

### 2. 日期变化判断

- 初次发送时建立基线
- 同一天再次发送不插入 reminder
- 跨天发送时插入 reminder
- App 重启后仍能从持久化 marker 恢复正确基线

### 3. WebSearch 描述

- 工具描述包含 `Sources:` 强制要求
- 工具描述包含 `${currentMonthYear}` 动态值
- 最近信息场景说明明确要求使用当前年份

## 风险与取舍

### 1. `AGENTS.md` 来源仍未最终定案

本轮只搭结构，不定义编辑入口，因此初版 `AGENTS.md` 内容来源可能先是：

- 内置默认文本
- 空字符串占位
- 受限配置来源

这不会阻塞整体架构落地，因为 `userContext` 的骨架已经能先承载 `currentDate`。

### 2. 运行时注入与持久化真相分离

日期变化提醒不写入 transcript，意味着调试时不能单靠聊天历史回放完整还原当次 prompt。

这是一个有意取舍。它换来了：

- 更干净的 UI timeline
- 更干净的 session summary
- 更简单的压缩边界

若后续需要调试能力，应通过日志或专门的调试视图暴露，而不是污染对话事实层。

## 结论

本次设计将“今天是哪一天”从一个零散问题，收敛为统一的运行时时间感知层：

- 通过 `userContext` 解决首轮时间感知
- 通过 `date changed reminder` 解决跨天漂移
- 通过 WebSearch 当前年份约束解决查询年份错误

这样可以在不破坏现有 prompt 分层和 session context 架构的前提下，显著降低“最新信息却搜成去年的内容”的问题。
