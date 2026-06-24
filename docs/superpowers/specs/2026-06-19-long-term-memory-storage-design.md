# 长期记忆存储层设计

## 摘要

本设计只覆盖长期记忆系统的第一阶段：**存储层**。

本阶段的实现先交付记忆存储，不先交付记忆召回、planner / final answer 自动注入或后台自动抽取。这里的“先”只是任务分工：这些能力是长期记忆系统的紧邻后续环节，因此本阶段的文件结构、prompt 和测试都必须为自动加载、选择性召回和后台抽取预留稳定契约，避免后续再反向改写 prompt。

长期记忆采用 file-based memory：

- 记忆文件存放在全局 `/memories` 目录。
- `/memories/MEMORY.md` 是索引，不是正文仓库。
- 每条具体记忆是独立 Markdown topic file。
- 记忆由现有 `Read` / `Grep` / `Glob` / `Write` / `Edit` / `Delete` 文件工具维护。
- 本阶段不新增 `memory_save`、`memory_forget` 或专用记忆工具。

这和当前文件沙盒架构一致：Agent 使用 file-native 路径，宿主真实路径保持内部实现细节。

## 背景

参考文档 `/Users/skka/vsSpace/Claude-Code/docs/12-long-term-memory.zh-CN.md` 的核心思路是：

- 长期记忆不是把历史全塞进模型。
- 长期记忆先形成文件，再按需召回和验证。
- 记忆是上下文线索，不是现状真相。
- 记忆只保存未来会再用得上的信息。
- `MEMORY.md` 是索引，topic file 才是正文。

当前 FlutterAIChat 已经有：

- `/memories` 沙盒目录。
- file-native agent path 模型。
- 通用文件工具。
- session context / summary snapshot / runtime user context 分层。
- workspace V1 文件容器。

因此第一阶段应把长期记忆先落在已有文件工具与沙盒模型里，避免新增平行存储系统。

## 设计目标

### 产品目标

- 用户明确要求“记住”长期信息时，Agent 可以用通用文件工具写入 `/memories`。
- 用户明确要求“忘掉”长期信息时，Agent 可以用通用文件工具删除或编辑 `/memories`。
- 记忆文件格式稳定，可被即将实现的召回层读取。
- `MEMORY.md` 始终作为简短索引，并作为后续自动加载 / 选择性召回的第一入口。
- 记忆存储规则尽量保留参考文档中的 prompt 原文，只删除不适配当前 app 的 Claude Code / subagent / team memory 细节。

### 架构目标

- 不新增专用 memory tool。
- 不新增数据库表。
- 不让长期记忆绑定某个 chat group、session context snapshot 或 workspace。
- `/memories` 是全局长期记忆目录，不跟随当前 workspace 自动迁移。
- 保持 host path 不进入 agent-visible context。
- 修改范围集中在 prompt guidance、文件工具边界和文档。

## 本阶段不直接交付

以下能力不在本阶段直接实现，但本阶段必须保留它们依赖的 prompt 与数据契约：

- 自动记忆抽取器。
- 语义检索或相关记忆排序。
- planner / final answer 自动注入记忆内容。
- `MEMORY.md` 自动加载进 runtime user context。
- UI 记忆管理页。
- 团队记忆、private/team scope、`TEAMMEM` 变体。
- 专用 `memory_save` / `memory_forget` tool。
- 对所有记忆 frontmatter 做强 schema 校验。

这些能力会在后续“使用层”和“自动形成层”阶段补上。本阶段不应为了当前代码尚未自动加载而削弱、删除或改写未来使用层需要的 prompt 规则。

## 存储模型

### 目录结构

统一使用 agent-visible 路径：

```text
/memories/
  MEMORY.md
  user/
  feedback/
  project/
  reference/
```

各目录含义：

- `/memories/MEMORY.md`：索引文件，只放简短条目。
- `/memories/user/`：用户角色、偏好、经验、工作方式。
- `/memories/feedback/`：用户明确纠正、偏好、成功或失败反馈。
- `/memories/project/`：当前项目目标、约束、事故、截止日期、协作背景。
- `/memories/reference/`：外部系统入口，例如文档、仪表盘、工单系统等。

本阶段不要求启动时主动创建子目录；Agent 可通过 `Write` 写入对应路径，底层写服务会创建父目录。平台初始化仍至少确保 `/memories` 根目录存在。

### MEMORY.md

`MEMORY.md` 是索引，不是正文仓库。

格式：

```markdown
# Memory Index

- [Title](user/title.md) — one-line hook
```

约束：

- 每条索引应尽量少于 150 字符。
- 索引只写链接和一句话 hook。
- 不把完整记忆正文写入 `MEMORY.md`。
- 新增 topic file 后应同步新增索引。
- 删除 topic file 后应同步删除索引。
- 更新记忆主题或描述后应同步更新索引。

### Topic File

每条记忆使用独立 Markdown 文件，frontmatter 尽量沿用参考文档：

```markdown
---
name: {{memory name}}
description: {{one-line description — used to decide relevance in future conversations, so be specific}}
type: {{user, feedback, project, reference}}
---

{{memory content — for feedback/project types, structure as: rule/fact, then **Why:** and **How to apply:** lines}}
```

类型固定为：

- `user`
- `feedback`
- `project`
- `reference`

文件路径应按类型放入对应目录，例如：

```text
/memories/user/collaboration-style.md
/memories/feedback/android-debug-install.md
/memories/project/flutter-ai-chat-context.md
/memories/reference/provider-dashboard.md
```

文件名应稳定、语义化、使用小写短横线风格。不要用纯时间戳或会话 id 作为主题文件名。

## 通用文件工具边界

### Write

`Write` 继续作为创建新记忆文件或整文件重写的入口。

需要调整的行为：

- 当目标路径位于 `/memories/...` 时，`Write` 必须写入全局 `/memories`。
- `/memories/...` 不应触发 default workspace 的 long-lived output 自动迁移。
- 写入结果应继续返回 agent path，例如 `/memories/user/foo.md`。

原因：

当前 `WriteToolHandler` 对 default workspace 下的新 long-lived output 有自动迁移逻辑。这个逻辑适合 artifact / project output，但不适合长期记忆。长期记忆是全局 agent 资产，不属于当前 chat workspace。

### Edit

`Edit` 可用于更新已有记忆文件或 `MEMORY.md` 索引。

本阶段无需修改 `Edit` 的 workspace 行为，因为它已经按普通沙盒路径和 session guard 工作；但 prompt guidance 必须要求：

- 编辑已有记忆前先 `Read`。
- 更新 topic file 时同步更新 `MEMORY.md`。
- 避免重复记忆，优先更新已有 topic file。

### Delete

`Delete` 当前只允许删除当前 workspace 内内容。本阶段需要把 `/memories` 纳入明确的全局例外。

允许：

- 删除 `/memories/<type>/<topic>.md` 具体记忆文件。
- 删除 `/memories/<type>/...` 下的非根子目录，前提是用户明确要求忘掉对应内容，并且执行前已读取或列出目标。

禁止：

- 删除 `/memories` 根目录。
- 删除 `/memories/MEMORY.md` 整个索引文件。
- 用删除目录的方式粗暴清空全部记忆，除非未来单独设计全量清空流程。

删除记忆时应优先：

1. `Read` / `Glob` / `Grep` 查找相关 topic file 和索引条目。
2. 用 `Delete` 删除具体 topic file。
3. 用 `Edit` 更新 `/memories/MEMORY.md`，移除对应索引。

## Prompt Guidance

### 需要保留的参考 prompt

以下内容应尽量原样放入 app 的 prompt guidance，允许按当前工具名和路径语义做少量适配。即使部分句子依赖后续自动加载 / 召回实现，也应作为近期系统契约预留，避免存储阶段写入的记忆格式和后续使用层脱节。

```text
# auto memory

You have a persistent, file-based memory system at `<memoryDir>`. This directory already exists — write to it directly with the Write tool (do not run mkdir or check for its existence).

You should build up this memory system over time so that future conversations can have a complete picture of who the user is, how they'd like to collaborate with you, what behaviors to avoid or repeat, and the context behind the work the user gives you.

If the user explicitly asks you to remember something, save it immediately as whichever type fits best. If they ask you to forget something, find and remove the relevant entry.

## Types of memory
```

在本项目中 `<memoryDir>` 固定替换为 `/memories`。

```text
## How to save memories

Saving a memory is a two-step process:

**Step 1** — write the memory to its own file using this frontmatter format:

~~~markdown
---
name: {{memory name}}
description: {{one-line description — used to decide relevance in future conversations, so be specific}}
type: {{user, feedback, project, reference}}
---

{{memory content — for feedback/project types, structure as: rule/fact, then **Why:** and **How to apply:** lines}}
~~~

**Step 2** — add a pointer to that file in `MEMORY.md`. `MEMORY.md` is an index, not a memory — each entry should be one line, under ~150 characters: `- [Title](file.md) — one-line hook`. It has no frontmatter. Never write memory content directly into `MEMORY.md`.

- `MEMORY.md` is always loaded into your conversation context — lines after 200 will be truncated, so keep the index concise
- Organize memory semantically by topic, not chronologically
- Update or remove memories that turn out to be wrong or outdated
- Do not write duplicate memories. First check if there is an existing memory you can update before writing a new one.
```

说明：`MEMORY.md is always loaded...` 在当前实现阶段可能先作为 prompt 契约存在，自动加载实现紧随其后补齐。实现顺序不应改变这条规则的目标语义。

```text
## What NOT to save in memory

- Code patterns, conventions, architecture, file paths, or project structure — these can be derived by reading the current project state.
- Git history, recent changes, or who-changed-what — `git log` / `git blame` are authoritative.
- Debugging solutions or fix recipes — the fix is in the code; the commit message has the context.
- Anything already documented in CLAUDE.md files.
- Ephemeral task details: in-progress work, temporary state, current conversation context.

These exclusions apply even when the user explicitly asks you to save. If they ask you to save a PR list or activity summary, ask what was *surprising* or *non-obvious* about it — that is the part worth keeping.
```

在本项目中 `CLAUDE.md` 应适配为 `AGENTS.md` 和项目文档。

```text
## Memory and other forms of persistence

Memory is one of several persistence mechanisms available to you as you assist the user in a given conversation. The distinction is often that memory can be recalled in future conversations and should not be used for persisting information that is only useful within the scope of the current conversation.
- When to use or update a plan instead of memory: If you are about to start a non-trivial implementation task and would like to reach alignment with the user on your approach you should use a Plan rather than saving this information to memory. Similarly, if you already have a plan within the conversation and you have changed your approach persist that change by updating the plan rather than saving a memory.
- When to use or update tasks instead of memory: When you need to break your work in current conversation into discrete steps or keep track of your progress use tasks instead of saving to memory. Tasks are great for persisting information about the work that needs to be done in the current conversation, but memory should be reserved for information that will be useful in future conversations.
```

### 明确不进入存储阶段 prompt 的参考内容

以下参考内容不进入本阶段 app prompt，原因是它们要么是 Claude Code 执行环境细节，要么需要等使用层 / 自动形成层实现时再作为独立 prompt 注入：

- memory extraction subagent 身份说明。
- subagent turn budget。
- Claude Code 专属工具权限列表。
- Bash / MCP / Agent 工具限制。
- `TEAMMEM`、private/team scope 和团队记忆变体。
- “When to access memories” 和 “Before recommending from memory” 使用层规则。

其中“使用层规则”不是要弱化，而是应随自动加载 / 召回实现一起进入对应 runtime context，避免存储阶段先注入无法执行的读取义务。

## Prompt 挂载位置

本阶段建议新增 `PromptCatalog.longTermMemoryStorage()` 或等价 section，由 `PromptBuilderService` 在非 summary stage 加入基础系统 prompt。

挂载范围：

- `PromptStage.planner`
- `PromptStage.chat`
- `PromptStage.finalAnswer`

不挂载：

- `PromptStage.summary`

原因：

- summary stage 负责会话压缩，不应被长期记忆存储规则污染。
- planner 需要知道何时用文件工具保存/删除记忆。
- final answer 需要知道不要把未执行的记忆写入描述成已保存。

## 与现有上下文层的关系

长期记忆存储层不改变当前 session context 架构。

仍保持：

- runtime user context
- latest snapshot summary
- recent completed turns after snapshot boundary
- current turn transcript

互相独立。

本阶段不会把 `/memories` 内容放进：

- session context snapshot
- recent completed turns
- current turn transcript 之外的隐式上下文
- UI timeline message

当 Agent 使用文件工具写入或删除记忆时，这些工具调用本身仍会作为正常 turn transcript 存在。

## 风险与取舍

### 1. 索引一致性依赖模型遵循规则

通用文件工具不会自动保证 topic file 和 `MEMORY.md` 同步。

本阶段接受这个取舍，因为我们明确选择不新增专用 memory tool。缓解方式：

- prompt 明确“两步保存”。
- prompt 明确删除时同步更新索引。
- 测试覆盖文件工具路径行为。
- 后续可增加 lightweight validator 或 debug 检查页。

### 2. Frontmatter 没有强校验

本阶段不做 schema validator。原因：

- 当前入口仍是通用文件工具。
- 强校验需要新增工具或服务入口，和本阶段选择相冲突。

后续如果记忆使用层依赖 frontmatter，可以在召回层读取时做容错解析和质量提示。

### 3. Delete 的 `/memories` 例外会扩大删除作用域

现有 `Delete` 严格限制在当前 workspace。新增 `/memories` 例外需要非常小心。

缓解方式：

- 仍要求 `requiresConfirmation = true`。
- 只允许删除 `/memories` 下具体内容。
- 禁止删除 `/memories` 根。
- 禁止删除 `/memories/MEMORY.md` 整体。
- prompt 要求删除前先读取或列出目标。

### 4. 存储先行会带来短暂能力缺口

如果只完成本阶段实现，用户保存记忆后，后续对话可能还不会自动召回这些记忆。

这是实现顺序带来的短暂缺口，不是最终产品边界。第一阶段先保证存储资产稳定；紧随其后的使用层应补齐：

- 自动加载或读取 `MEMORY.md` 索引。
- 选择相关 topic file。
- 验证记忆中提到的当前代码状态。
- 注入 runtime context。

## 测试策略

### 单元测试

新增或更新：

- `test/tools/handlers/write_tool_handler_test.dart`
  - `/memories/...` 写入不触发 workspace 自动迁移。
  - 写入结果路径保持 `/memories/...`。

- `test/tools/handlers/delete_tool_handler_test.dart`
  - 允许删除 `/memories/user/foo.md`。
  - 拒绝删除 `/memories`。
  - 拒绝删除 `/memories/MEMORY.md`。
  - 当前 workspace 外路径仍拒绝。
  - 当前 workspace 根仍拒绝。

- `test/services/prompt/prompt_builder_service_test.dart` 或现有 prompt 测试文件
  - planner/chat/final answer 包含长期记忆存储规则。
  - summary prompt 不包含长期记忆存储规则，但后续自动抽取器可以拥有独立的 memory extraction prompt。
  - prompt 包含 `/memories/MEMORY.md`、frontmatter、四种 type、不要保存项。

### 文档验证

- 更新 `README.md`，说明 `/memories` 现在承载长期记忆存储层。
- 更新 `docs/architecture/file-sandbox-architecture.md`，说明 `/memories` 是全局长期记忆目录，不属于 workspace。
- 如项目规则需要，更新 `AGENTS.md` 的长期记忆与文件工具边界。

## 后续阶段预留

### 使用层

后续应单独设计：

- 如何自动加载或读取 `MEMORY.md`。
- 如何选择最多 N 条相关记忆。
- 如何避免重复 surfacing。
- 如何处理用户说 ignore memory。
- 如何验证记忆中的文件、函数、flag 是否仍然存在。

### 自动形成层

再后续可设计：

- 发送后后台抽取最近消息。
- 明确“记住/忘掉”优先。
- 去重、更新、删除过时记忆。
- 抽取器只看最近消息，不扫代码、不查 git。

## 验收标准

- Agent 可以通过通用文件工具在 `/memories` 保存长期记忆文件。
- `Write /memories/...` 不会迁移到 `/workspaces/<id>/...`。
- Agent 可以通过通用文件工具删除具体 memory topic file。
- `Delete /memories` 和 `Delete /memories/MEMORY.md` 被拒绝。
- prompt 明确长期记忆的存储格式、保存步骤、类型和不应保存内容。
- prompt 预留 `MEMORY.md` 自动加载、索引简洁性和后续召回层依赖的格式契约。
- summary stage 不包含长期记忆存储规则。
- 文档说明长期记忆存储层是先交付的实现阶段，不是长期记忆系统的完整边界。
