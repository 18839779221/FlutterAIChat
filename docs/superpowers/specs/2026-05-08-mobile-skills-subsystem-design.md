# 手机端 Skills 子系统重构设计

## 摘要

本次设计定义手机端 skills 子系统的新模型，直接对齐现有 agent loop 边界：

- 可用 skills 列表作为 `role=user` 的 `<system-reminder>` 注入 planner-visible context
- skills 的实际使用统一建模为一个专门的 `Skill` tool
- 当 `Skill` tool 被调用后，把被调用 skill 的路径、基目录与正文指令作为新的 `<system-reminder>` 注入当前 turn transcript
- 当会话上下文被压缩或重建时，重新注入可用 skills 列表，并按 transcript 语义保留已调用 skill 的持续影响

本次设计同时要求移除旧路径，不保留 runtimeSections 注入 skills 的兜底、兼容桥接或双写逻辑。

另外，skills 子系统不做数据库存储、持久化索引缓存或额外快照缓存；每次使用时都从文件系统重新读取，并装载到当次运行内存中。

## 背景

当前 skills 子系统需要保留的能力边界很简单：

- 从本地目录加载 `SKILL.md`
- 从 GitHub 下载 skill 到本地目录
- 在设置页启停 skills

需要清理的旧路径包括：

- planner 前的自动匹配逻辑
- 通过 `SkillRuntimeService` 注入 `PromptBuilderService.buildSystemPrompt(runtimeSections: ...)` 的做法

当前实现的核心问题是**建模位置不对**：

1. skill 使用没有进入 tool/ledger/transcript 主链路，难以和 turn 语义对齐
2. skill 生效依赖 planner system prompt 组装，不是 planner-visible transcript 的一部分
3. 上下文压缩后，skills 的可见性与持续影响缺乏统一重建语义
4. 旧实现容易演化成“工具外的隐式 planner 补丁”，违背当前架构对能力边界的要求

因此这版设计采用“可发现 + 可调用 + 可投影”的显式能力。

## 目标

### 产品目标

- App 运行时仍支持本地 skills 安装与远端下载到本地目录
- agent 在每轮规划前都能看到当前可用 skills 列表
- 当某个 task 明显匹配 skill 时，模型通过 `Skill` tool 显式调用 skill
- skill 一旦被调用，其正文指令会进入本轮后续上下文，持续影响当前会话中的后续决策
- 用一个辨识度高、适合手机端场景的 skill 做端到端验证

### 架构目标

- skill 使用必须进入现有 tool use / ledger / transcript 机制
- 可用 skills 列表必须通过 runtime user context reminder 注入，而不是 system prompt runtime sections
- 已调用 skill 指令必须通过 transcript-visible reminder 注入，而不是隐藏在 planner prompt 拼接层
- 上下文压缩与重建后，skills 相关语义可稳定恢复
- 删除旧实现路径，不保留并存语义

## 非目标

第一版重构不包含：

- 独立 marketplace、搜索、评分、推荐
- skill 脚本自动执行
- skill 自带新权限或动态注入任意工具
- 基于 embedding 的 skill 检索
- 多版本并存解析
- 不保留旧版 runtimeSections 技术方案的兼容模式

## 关键原则

### 1. skill 仍是本地文件内容，但使用语义是 tool use

skill 的内容真相源仍然是本地目录中的 `SKILL.md`。  
但“某轮是否使用某个 skill”不再是一个隐式匹配结果，而是一个显式的 `Skill` tool 调用记录。

### 2. 可用列表与已调用内容分层

需要区分两类模型可见信息：

- **可用 skills 列表**：告诉模型“现在有哪些 skill 可以调用”
- **已调用 skill 内容**：告诉模型“这个 skill 已经被调用，请继续遵循这些指令”

前者属于 runtime user context 的能力公告；后者属于当前 session transcript 中已经发生的指导性事件。

### 3. 清理旧路径，不做双轨并存

以下旧行为必须移除，而不是保留为 fallback：

- `AgentPlannerService` 从 `SkillRuntimeService.buildRuntimeSections()` 拉取 active skill sections
- `PromptBuilderService.buildSystemPrompt(runtimeSections: ...)` 承载 skills 生效
- `SkillMatcherService` 直接决定哪些 skill 自动激活并注入 prompt
- 任何“即使不走 Skill tool，skill 仍可自动生效”的旧语义

## 设计总览

重构后的 skills 子系统分成四层：

1. **Skill Catalog**
   - 负责本地目录扫描、解析、下载、安装、启停
   - 每次从文件系统现读现组装“当前可用 skills 列表”

2. **Runtime Reminder Injection**
   - 在构造 runtime user context 时，基于当次文件系统扫描结果把可用 skills 列表注入 `<system-reminder>`
   - 这条提醒在每次 planner context 构建时都可重建

3. **Skill Tool**
   - 作为 planner-visible tool 暴露给模型
   - 模型通过它显式选择某个 skill
   - 调用后返回结构化结果，并向 transcript 追加 skill reminder

4. **Session Context Reconstruction**
   - 上下文压缩或重建时，始终重新注入 skills list reminder
   - 已调用 skill reminder 作为 transcript/projected messages 的一部分继续存在

## 加载策略

### 单一真相源

skills 的唯一真相源是应用本地文件系统中的安装目录。  
系统不为 skills 额外建立数据库表，也不维护持久化索引文件。

### 读取方式

第一版统一采用“按次读取、装载到内存”的策略：

- 构建 skills list reminder 时，从文件系统重新扫描已安装且已启用的 skills
- `Skill` tool 执行时，从文件系统重新读取目标 `SKILL.md`
- 安装完成后，如需刷新 UI 或下一次 planner context，可重新触发一次扫描

### 不做的事

第一版明确不做：

- skill 内容入库
- skill catalog 持久化缓存
- skill 正文 snapshot
- app 重启后复用旧内存态的技能索引

## 本地存储设计

本地目录继续使用应用支持目录下的 skills 根目录：

```text
<appSupportDirectory>/skills/
  installed/
    <skill-id>/
      SKILL.md
      references/
      assets/
      scripts/
      .skill-source.json
```

说明：

- `SKILL.md` 仍是唯一必需文件
- `references/`、`assets/`、`scripts/` 可以下载保存，但第一版不自动执行脚本
- `.skill-source.json` 记录来源 URL、ref、安装时间等元数据

## 数据模型

### `SkillDescriptor`

表示一个可安装并可被调用的 skill 静态描述。

建议保留或扩展的核心字段：

- `id`
- `name`
- `description`
- `entryFilePath`
- `skillRootPath`
- `body`
- `sourceType`
- `sourceUrl`
- `isEnabled`

其中 `body` 指 `SKILL.md` frontmatter 之后的正文，供实际 skill 调用时注入 reminder。

### `SkillCatalogEntry`

表示当前运行时“对模型可见的 skill 列表项”。

建议字段：

- `id`
- `name`
- `description`
- `qualifiedPath`
- `isEnabled`

它不携带完整正文，只服务于“可用技能列表”提醒与 `Skill` tool 参数校验，并由当次文件系统读取结果即时组装。

### `InvokedSkillContext`

表示某个 skill 已经在 session 中被调用后的上下文载荷。

建议字段：

- `skillId`
- `name`
- `qualifiedPath`
- `baseDirectory`
- `instructionBody`

它用于生成 skill invocation reminder，并可作为 `ToolResult.data` 的一部分落到 step ledger。

## Runtime User Context 注入

### 形式

可用 skills 列表应作为 `role=user` 的 `<system-reminder>` 注入，和当前日期提醒使用同一类机制。

建议文本形态：

```text
<system-reminder>
The following skills are available for use with the Skill tool:

- verify: Run project verification after code changes
- commit: Create a commit with project conventions
</system-reminder>
```

### 位置

它应由 `RuntimeUserContextService` 产出数据，由 `UserContextMessageBuilder` 统一包裹为 `<system-reminder>`。

这意味着：

- skills list 不属于 system prompt
- skills list 不持久化到 `messages`
- skills list 每次 build planner context 时都可重新生成
- skills list 每次生成前都应重新读取文件系统，而不是依赖跨次缓存

### 约束

- 只展示已安装且已启用的 skills
- 每项只包含 `name` 与 `description`
- 不在列表中展开全文正文
- 列表过长时允许裁剪，但裁剪规则必须稳定且可测试

## Skill Tool 设计

### 定位

`Skill` 是一个专门的工具，不是普通文件操作工具，也不是 prompt 拼接技巧。  
它的职责是：**在主对话中显式激活一个已可用的 skill，并把该 skill 的正文指令引入当前 session 语义。**

### planner-facing 描述要求

该工具的 `descriptionForModel` 需要清楚表达：

- 当用户请求明显匹配某个 skill 时，必须先调用 `Skill` tool
- 可用 skills 来自 conversation 中的 `<system-reminder>`
- 不要口头提到 skill 却不真正调用工具
- 已在运行中的同一 skill 不应重复调用

### 参数

第一版建议参数：

- `skill`
  - 必填，skill 名称或限定名
- `args`
  - 可选，原样字符串，先保留给 future use

### 执行语义

`Skill` tool handler 负责：

1. 校验 skill 是否在当前 catalog 中存在且已启用
2. 从文件系统读取本地 `SKILL.md`
3. 解析出 skill 的名称、路径、基目录、正文
4. 产出结构化 `ToolResult`
5. 触发向 transcript 追加一条 skill invocation reminder

第一版不要求 `args` 真正驱动 skill 模板参数替换，但接口上先保留。

## 已调用 Skill Reminder 设计

### 注入形态

当 `Skill` tool 被执行成功后，需要生成一条新的 `<system-reminder>`，并进入当前 turn transcript。

建议文本形态：

```text
<system-reminder>
The following skills were invoked in this session. Continue to follow these guidelines:

### Skill: verify
Path: projectSettings:verify

Base directory for this skill: /abs/path/to/verify

After code changes, verify by:
1. Run bun run version
2. Check CLI starts successfully
3. Summarize failures instead of guessing
</system-reminder>
```

### 语义

这条 reminder 不是“工具输出摘要”，而是模型后续必须继续遵循的指导性上下文。

因此它必须满足：

- 对 planner 可见
- 对 transcript/projector 可见
- 在 turn ledger 中有可追踪来源
- 在上下文重建后仍能恢复

### 去重与重复调用

第一版规则建议如下：

- 同一 turn 内如果同名 skill 已成功调用，则后续重复调用应被拒绝
- 跨 turn 是否允许再次调用同一 skill，不做硬禁止
- 但 context projector 应避免在同一重建窗口内重复注入完全相同的 reminder 文本

## 上下文压缩与重建

### 必须保留的语义

当 `SessionContextService` 进行 compression 或重建时：

1. **skills list reminder** 必须重新注入
2. **已调用 skill reminder** 必须作为 transcript 语义的一部分继续投影

### 边界解释

- skills list reminder 属于 runtime-only context，每次 build 时重新生成
- invoked skill reminder 属于“当前 session 中已经发生的显式指导事件”，应通过 transcript 或 turn-step 投影继续存在

### 禁止行为

不要在压缩时把 skill reminder 改写成一段普通 assistant 总结，例如：

- “已加载 verify skill”
- “当前激活了某个 skill”

这种摘要会丢失正文约束，不符合可恢复语义。

## 与现有架构的对接点

### 1. `RuntimeUserContextService`

扩展其 `additionalSections` 来源，使其可加入 skills list block。

### 2. `UserContextMessageBuilder`

继续负责把 runtime sections 包裹成统一 `<system-reminder>` user message，不为 skills 单独发明新包裹格式。

### 3. `ToolRuntimeRegistry`

新增 `SkillToolHandler`，使 planner 可以像其它工具一样看到它。

### 4. tool execution / transcript pipeline

需要为 skill 成功调用后追加 reminder 提供统一入口。  
实现上可以参考已有 tool step -> event projection 机制，但 skill reminder 需要明确作为“模型继续遵循的上下文消息”进入投影结果。

### 5. `AgentPlannerService`

移除对 `SkillRuntimeService.buildRuntimeSections()` 的依赖。  
planner system prompt 不再承担 skills 注入职责。

## 旧实现清理范围

本次重构必须显式处理以下内容：

### 必删语义

- 基于 `turn.userInput` 的隐式匹配并直接生效
- active skills 注入 `runtimeSections`
- planner prompt 内出现 `# Active skill: ...` 之类的段落

### 必改代码

- `lib/services/agent_planner_service.dart`
- `lib/services/skills/skill_runtime_service.dart`
- `lib/services/skills/skill_prompt_section_builder.dart`
- `lib/services/skills/skill_matcher_service.dart`
- 依赖这些旧行为的测试

### 可复用部分

以下能力可保留，但职责需要收缩为 catalog/install 侧：

- `skill_storage_service.dart`
- `skill_index_service.dart`
- `skill_frontmatter_parser.dart`
- `skill_installer_service.dart`
- `github_skill_fetcher.dart`
- `github_skill_source_resolver.dart`

其中 `skill_index_service.dart` 的“index”仅表示一次内存中的扫描结果，不代表持久化索引层。

## 测试样本建议

第一版验证 skill 继续建议使用 Android 官方 skills 仓库里的移动端主题 skill，优先选择：

- `edge-to-edge`

原因：

- 强手机端辨识度
- 指令内容偏 UI/mobile 规范，便于观察 skill 是否真的改变 agent 行为
- skill 指令不是通用“写代码”废话，能较明显区分“加载前后”的回答质量

验证目标不是只看“能下载成功”，而是看：

1. skills list 能否进入 planner-visible context
2. planner 是否会在相关任务下调用 `Skill` tool
3. 调用后 skill reminder 是否进入 transcript
4. 后续规划/回答是否明显遵循该 skill 指令

## 风险与取舍

### 风险 1：模型不调用 Skill tool

缓解：

- 强化 `Skill` tool 的 planner-facing 描述
- 在 skills list reminder 中明确“available for use with the Skill tool”
- 用集成测试覆盖“匹配任务时先发起 Skill tool”

### 风险 2：invoked reminder 导致上下文膨胀

缓解：

- 单个 skill body 设可配置长度上限
- 同一重建窗口去重重复 reminder
- 第一版先控制为单次最多调用少量 skills

### 风险 3：旧路径残留导致双重生效

缓解：

- 在实现计划中把旧路径删除列为单独任务
- 删除旧测试而不是保留双轨断言
- 代码评审时明确检查 `runtimeSections` 中不再出现 skills 注入

## 验收标准

满足以下条件才算第一版完成：

1. 本地已安装且启用的 skills 会出现在 runtime `<system-reminder>` 列表中
2. planner 可见 `Skill` tool，且相关任务会优先调用它
3. `Skill` tool 成功后，会生成包含路径、基目录、正文的 invoked reminder
4. invoked reminder 对后续 planner 可见
5. context compression / rebuild 后，skills list reminder 会重新注入
6. 旧的 runtimeSections 技术路径已删除，相关测试已更新，不保留 fallback
