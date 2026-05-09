# 手机端 Skills 子系统重构 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将手机端 skills 子系统实现为“skills list reminder + Skill tool + invoked skill reminder”的新模型，并删除旧的 runtimeSections 自动激活路径。

**Architecture:** 保留本地 skills 安装与下载能力，但把“skill 如何生效”迁移到显式 tool use。skills 不做数据库或持久化缓存；运行时每次从文件系统重新读取并装载到内存。系统通过 runtime user context 注入可用 skills 列表，通过 `Skill` tool 成功调用后向 transcript 追加 skill reminder，并让 session context 重建逻辑稳定恢复这些语义。

**Tech Stack:** Flutter, Riverpod, existing agent loop / turn ledger / transcript pipeline, `path_provider`, current skills local storage services, tool registry/handler infrastructure, session context services

---

## 涉及文件与职责

### 需要新增

- `lib/models/skill/skill_catalog_entry.dart`
  - 面向 runtime reminder / tool 参数校验的轻量 skill 列表项

- `lib/models/skill/invoked_skill_context.dart`
  - skill 成功调用后写入 tool result 与 reminder 投影的结构化载荷

- `lib/tools/handlers/skill_tool_handler.dart`
  - `Skill` tool 定义、参数校验与执行

- `test/tools/handlers/skill_tool_handler_test.dart`
  - skill tool 参数校验、成功调用、重复调用保护测试

- `test/services/prompt/runtime_user_context_service_skills_test.dart`
  - runtime user context 中 skills list 注入测试

- `test/services/session_context_service_skills_test.dart`
  - compression / rebuild 后 skills reminder 语义测试

### 需要修改

- `lib/services/prompt/runtime_user_context_service.dart`
  - 注入可用 skills 列表 sections

- `lib/models/prompt/runtime_user_context_snapshot.dart`
  - 如有必要，补充 skills list section 的承载字段或保持用 `additionalSections`

- `lib/services/prompt/user_context_message_builder.dart`
  - 保持统一 `<system-reminder>` 包裹，必要时补充可测试格式细节

- `lib/services/skills/skill_index_service.dart`
  - 提供“单次文件系统扫描后的当前已启用 skill catalog”能力

- `lib/services/skills/skill_runtime_service.dart`
  - 提供按次文件读取的 catalog 查询与 skill 内容加载

- `lib/services/skills/skill_matcher_service.dart`
  - 删除旧自动激活职责；如无保留价值则删除文件及引用

- `lib/services/skills/skill_prompt_section_builder.dart`
  - 删除文件及引用，不保留旧 prompt section 生成逻辑

- `lib/services/agent_planner_service.dart`
  - 删除 skills runtimeSections 注入

- `lib/tools/core/tool_runtime_registry.dart`
  - 注册 `SkillToolHandler`

- `lib/main.dart`
  - 注入新 skill tool 依赖与 skills catalog 依赖；移除旧 runtimeSections 依赖 wiring

- `lib/providers/chat_dependency_providers.dart`
  - 调整 provider：保留 catalog/install 所需，去除旧 runtime section 组装职责

- `lib/pages/settings_page.dart`
  - 继续保留 skills 管理 UI，但文案与行为改为“管理可用 skills”，不再暗示自动匹配立即生效

- `test/services/agent_planner_service_test.dart`
  - 删除旧“注入 active skill runtime sections”断言，改为验证 planner 只依赖普通 prompt + tool exposure

- `test/pages/settings_page_tool_settings_test.dart`
  - 更新与 skills 文案/依赖相关的测试

- `docs/superpowers/specs/2026-05-08-mobile-skills-subsystem-design.md`
  - 如计划落地中发现边界需微调，同步更新 spec

### 可能需要新增或修改的 turn/transcript 相关文件

- `lib/services/session_context_projector.dart`
- `lib/services/tool_result_context_projector.dart`
- `lib/models/chat_event.dart`
- `lib/models/agent/chat_turn_step.dart`
- 以及对应测试

说明：

- 是否需要新增专门 event 类型，取决于现有 tool result 投影能否无损承载 invoked skill reminder
- 但无论实现落点在哪，最终都必须让 invoked skill reminder 进入 planner-visible transcript

## 任务 1：删除旧设计文档假设并建立新测试基线

**Files:**
- Modify: `docs/superpowers/specs/2026-05-08-mobile-skills-subsystem-design.md`
- Modify: `docs/superpowers/plans/2026-05-08-mobile-skills-subsystem-implementation-plan.md`
- Modify: `test/services/agent_planner_service_test.dart`

- [ ] **Step 1: 写失败测试，明确 planner 不再注入 skills runtimeSections**

新增或改写测试，断言：

- `AgentPlannerService` 不再调用旧 skills runtime section builder
- prompt 中不再出现 `# Active skill:` 之类段落

- [ ] **Step 2: 运行相关测试并确认失败**

Run:

```bash
fvm flutter test test/services/agent_planner_service_test.dart
```

Expected:

- FAIL，仍保留旧注入路径或旧断言

- [ ] **Step 3: 删除旧文档中的 runtimeSections 生效表述**

要求：

- 设计文档与计划文档都只描述新模型
- 不保留“未来也许兼容旧方案”的表述

- [ ] **Step 4: 重新运行测试，确认测试仍指向待实现的新目标**

Run:

```bash
fvm flutter test test/services/agent_planner_service_test.dart
```

Expected:

- FAIL，但失败原因已经对准新架构缺口，而不是旧文档/旧断言

## 任务 2：把 skills catalog 从“自动激活器”收缩为“可用技能目录”

**Files:**
- Modify: `lib/models/skill/skill_descriptor.dart`
- Create: `lib/models/skill/skill_catalog_entry.dart`
- Modify: `lib/services/skills/skill_index_service.dart`
- Modify: `lib/services/skills/skill_runtime_service.dart`
- Test: `test/services/skills/skill_index_service_test.dart`

- [ ] **Step 5: 写 catalog 失败测试**

覆盖场景：

- 只返回已安装且启用的 skills list
- list 项只包含 name / description / id / path 等轻量字段
- 不再返回“当前 turn 自动匹配出的 active skill”
- 每次调用都会重新扫描文件系统，不依赖持久化缓存

- [ ] **Step 6: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/services/skills/skill_index_service_test.dart
```

- [ ] **Step 7: 调整 `SkillDescriptor` 与新增 `SkillCatalogEntry`**

要求：

- 明确区分“完整 skill 内容”和“catalog 列表项”
- 为外部消费字段补充简洁注释

- [ ] **Step 8: 改造 `skill_index_service.dart`**

要求：

- 提供列出 enabled catalog entries 的接口
- 保留本地目录扫描与 frontmatter 解析
- 不承担 turn 级匹配或 prompt 注入职责
- 不写数据库，不维护持久化索引文件；“index”只表示当次内存扫描结果

- [ ] **Step 9: 改造 `skill_runtime_service.dart`**

要求：

- 删除 `buildRuntimeSections(userInput)` 之类接口
- 改为提供：
  - 列出可用 skills
  - 按 skill 名称/限定名读取完整 skill 内容
  - 校验 skill 是否已启用
- 每次查询或读取均从文件系统现读现用，只保留当次调用需要的内存对象

- [ ] **Step 10: 重新运行测试并确认通过**

Run:

```bash
fvm flutter test test/services/skills/skill_index_service_test.dart
```

Expected:

- PASS

## 任务 3：把可用 skills 列表接入 runtime user context

**Files:**
- Modify: `lib/services/prompt/runtime_user_context_service.dart`
- Modify: `lib/models/prompt/runtime_user_context_snapshot.dart`
- Modify: `lib/services/prompt/user_context_message_builder.dart`
- Test: `test/services/prompt/runtime_user_context_service_skills_test.dart`
- Modify: `test/services/prompt/user_context_message_builder_test.dart`

- [ ] **Step 11: 写 skills list reminder 失败测试**

覆盖场景：

- 有 enabled skills 时，会生成：

```text
The following skills are available for use with the Skill tool:
```

- 后续每项以 `- name: description` 形式出现
- 无 enabled skills 时，不注入 skills list block
- 重复构建时会重新读取文件系统最新状态

- [ ] **Step 12: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/services/prompt/runtime_user_context_service_skills_test.dart
```

- [ ] **Step 13: 在 `RuntimeUserContextService` 中接入 skills catalog**

要求：

- 通过依赖注入获得 skills catalog provider/service
- 把 skills list block 追加到 `additionalSections`
- 不把完整 skill 正文塞进 runtime user context
- 每次 buildSnapshot 都重新触发 skills 文件系统读取，不复用持久化缓存

- [ ] **Step 14: 调整 `UserContextMessageBuilder` 对 reminder 结构的测试**

要求：

- 保持统一 `<system-reminder>` 包裹
- skills list block 与 currentDate / agentsMd 并存时顺序稳定、格式稳定

- [ ] **Step 15: 重新运行测试并确认通过**

Run:

```bash
fvm flutter test test/services/prompt/runtime_user_context_service_skills_test.dart
fvm flutter test test/services/prompt/user_context_message_builder_test.dart
```

Expected:

- PASS

## 任务 4：新增 Skill tool，并通过 tool 语义显式激活 skill

**Files:**
- Create: `lib/models/skill/invoked_skill_context.dart`
- Create: `lib/tools/handlers/skill_tool_handler.dart`
- Modify: `lib/tools/core/tool_runtime_registry.dart`
- Modify: `lib/main.dart`
- Test: `test/tools/handlers/skill_tool_handler_test.dart`

- [ ] **Step 16: 写 Skill tool 失败测试**

覆盖场景：

- skill 参数缺失时报参数错误
- 指向未安装或未启用 skill 时失败
- 指向已启用 skill 时返回成功 `ToolResult`
- 返回结果中包含 `skillId`、`name`、`qualifiedPath`、`baseDirectory`、`instructionBody`

- [ ] **Step 17: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/tools/handlers/skill_tool_handler_test.dart
```

- [ ] **Step 18: 实现 `InvokedSkillContext`**

要求：

- 字段完整表达 reminder 所需信息
- 为 planner/tool/transcript 共用字段补充注释

- [ ] **Step 19: 实现 `SkillToolHandler`**

要求：

- tool name 使用稳定值，例如 `skill`
- `descriptionForModel` 明确要求：匹配任务时先调用 Skill tool
- 参数至少支持 `skill` 和可选 `args`
- 执行时读取本地 `SKILL.md` 并构造 `InvokedSkillContext`
- 不从数据库或持久化缓存读取 skill 正文

- [ ] **Step 20: 注册 `SkillToolHandler`**

要求：

- 在 registry 中可见
- 在 planner tool exposure 中可被正常暴露
- 不通过 keyword router 做硬编码选择

- [ ] **Step 21: 重新运行测试并确认通过**

Run:

```bash
fvm flutter test test/tools/handlers/skill_tool_handler_test.dart
```

Expected:

- PASS

## 任务 5：把 invoked skill reminder 接入 transcript / planner-visible context

**Files:**
- Modify: `lib/services/tool_result_context_projector.dart`
- Modify: `lib/services/session_context_projector.dart`
- Modify: `lib/models/chat_event.dart`
- Modify: `lib/models/agent/chat_turn_step.dart`
- Test: `test/services/session_context_service_skills_test.dart`
- Test: `test/services/agent_planner_service_test.dart`

- [ ] **Step 22: 写 invoked reminder 投影失败测试**

覆盖场景：

- `Skill` tool 成功后，planner-visible messages 中出现新的 `<system-reminder>`
- reminder 文本包含：
  - `### Skill: <name>`
  - `Path: ...`
  - `Base directory for this skill: ...`
  - skill 正文

- [ ] **Step 23: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/services/session_context_service_skills_test.dart
```

- [ ] **Step 24: 选择并实现 reminder 注入落点**

实现要求：

- 可以通过 tool result context projector，把成功的 `skill` tool 结果投影为一条系统提醒消息
- 或通过 chat event / turn step 的专门语义投影实现
- 但最终 planner-visible transcript 中必须出现完整 reminder，而不是 assistant 摘要

- [ ] **Step 25: 增加重复调用保护**

要求：

- 同一 turn 内如果某个 skill 已成功调用，再次调用同一 skill 应失败
- 失败结果需结构化可见，避免 silent ignore

- [ ] **Step 26: 重新运行测试并确认通过**

Run:

```bash
fvm flutter test test/services/session_context_service_skills_test.dart
fvm flutter test test/services/agent_planner_service_test.dart
```

Expected:

- PASS

## 任务 6：删除旧的自动匹配与 runtimeSections 注入路径

**Files:**
- Modify or Delete: `lib/services/skills/skill_matcher_service.dart`
- Delete: `lib/services/skills/skill_prompt_section_builder.dart`
- Modify: `lib/services/agent_planner_service.dart`
- Modify: `lib/providers/chat_dependency_providers.dart`
- Modify: `lib/main.dart`
- Test: `test/services/agent_planner_service_test.dart`

- [ ] **Step 27: 写旧路径删除后的失败测试**

断言：

- `AgentPlannerService` 不再依赖 `SkillRuntimeService.buildRuntimeSections`
- planner prompt 中不再出现 active skill sections
- 相关 provider 不再暴露旧路径对象给 planner

- [ ] **Step 28: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/services/agent_planner_service_test.dart
```

- [ ] **Step 29: 删除 `skill_prompt_section_builder.dart`**

要求：

- 删除文件
- 清理所有 import / provider / tests

- [ ] **Step 30: 处理 `skill_matcher_service.dart`**

要求：

- 若仅服务旧自动激活模型，直接删除
- 若其中少量解析逻辑对 skill 名称匹配有复用价值，可收缩为 tool 参数解析辅助，但不得保留“自动生效”语义

- [ ] **Step 31: 修改 `AgentPlannerService`**

要求：

- 去掉 `_skillRuntimeService.buildRuntimeSections(turn.userInput)`
- planner system prompt 恢复为只接收正常 runtimeSections（非 skills）
- 保持 tool exposure 与 transcript 输入链路清晰

- [ ] **Step 32: 清理 wiring 与 provider**

要求：

- `main.dart` 与 `chat_dependency_providers.dart` 不再为 planner 注入旧 skills runtime path
- 仅保留 catalog/install/tool handler 所需依赖

- [ ] **Step 33: 重新运行测试并确认通过**

Run:

```bash
fvm flutter test test/services/agent_planner_service_test.dart
```

Expected:

- PASS

## 任务 7：更新设置页与安装管理文案，避免暗示旧语义

**Files:**
- Modify: `lib/pages/settings_page.dart`
- Modify: `lib/widgets/settings/skill_install_sheet.dart`
- Modify: `test/pages/settings_page_tool_settings_test.dart`

- [ ] **Step 34: 写设置页失败测试**

覆盖场景：

- 文案描述为“可用 skills / 安装到本地 / 供 Skill tool 使用”
- 不再描述“自动影响 planner 的工作流判断”这类旧语义

- [ ] **Step 35: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/pages/settings_page_tool_settings_test.dart
```

- [ ] **Step 36: 调整设置页文案与行为**

要求：

- 技能列表仍可启停、刷新、安装
- 文案改为说明“这些 skills 会出现在运行时上下文中，并可由 Skill tool 调用”
- 不新增与本期无关的 UI 复杂度

- [ ] **Step 37: 重新运行测试并确认通过**

Run:

```bash
fvm flutter test test/pages/settings_page_tool_settings_test.dart
```

Expected:

- PASS

## 任务 8：验证上下文压缩 / 重建语义

**Files:**
- Modify: `lib/services/session_context_service.dart`
- Modify: `lib/services/session_context_projector.dart`
- Test: `test/services/session_context_service_skills_test.dart`

- [ ] **Step 38: 写 compression / rebuild 失败测试**

覆盖场景：

- build planner context 时总能重新生成 skills list reminder
- 已调用 skill reminder 在 snapshot + recent turns + current turn 重建后仍可见
- 不会被改写成普通 assistant 总结
- 即使 app 内存态失效，重新构建时也能仅依赖文件系统恢复 skills list

- [ ] **Step 39: 运行测试并确认失败**

Run:

```bash
fvm flutter test test/services/session_context_service_skills_test.dart
```

- [ ] **Step 40: 调整 session context 重建实现**

要求：

- runtime user context 每次都重新产出 skills list block
- transcript 投影保留 invoked skill reminder 文本
- 压缩时不丢失 skill 正文约束
- 不为 skills 额外引入数据库缓存恢复路径

- [ ] **Step 41: 重新运行测试并确认通过**

Run:

```bash
fvm flutter test test/services/session_context_service_skills_test.dart
```

Expected:

- PASS

## 任务 9：回归安装能力并选定验证样本

**Files:**
- Modify: `lib/services/skills/skill_installer_service.dart`
- Modify: `lib/services/skills/github_skill_fetcher.dart`
- Modify: `lib/services/skills/github_skill_source_resolver.dart`
- Test: `test/services/skills/skill_installer_service_test.dart`

- [ ] **Step 42: 写安装链路回归测试**

覆盖场景：

- 远端 GitHub skill 仍能下载到本地目录
- `edge-to-edge` 能成功安装并进入 enabled catalog
- 安装后会出现在 skills list reminder 数据源中

- [ ] **Step 43: 运行测试并确认失败或部分失败**

Run:

```bash
fvm flutter test test/services/skills/skill_installer_service_test.dart
```

- [ ] **Step 44: 修整安装链路以适配新 catalog 模型**

要求：

- 安装后索引与 enabled 状态正常衔接
- 不依赖旧 runtimeSections 生效链路
- 安装完成后的可见性来自后续文件系统重扫，而不是写入额外缓存层

- [ ] **Step 45: 重新运行测试并确认通过**

Run:

```bash
fvm flutter test test/services/skills/skill_installer_service_test.dart
```

Expected:

- PASS

## 任务 10：跑完整验证并清理残留

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: 与 skills 旧路径相关的残留测试或文档

- [ ] **Step 46: 全局搜索旧语义残留**

Run:

```bash
rg -n "Active skill|buildRuntimeSections\\(|skill_prompt_section_builder|自动匹配 skill|runtimeSections.*skill|skills 会影响 planner" lib test docs
```

Expected:

- 只剩新设计允许的提及，旧语义无残留

- [ ] **Step 47: 更新 README / AGENTS / 架构文档**

要求：

- README 描述 skills 新模型
- AGENTS 如有必要补充“skills 使用通过 Skill tool 完成”
- 若相关架构文档提到旧 prompt 注入路径，同步修正

- [ ] **Step 48: 运行有代表性的测试集合**

Run:

```bash
fvm flutter test test/services/agent_planner_service_test.dart
fvm flutter test test/tools/handlers/skill_tool_handler_test.dart
fvm flutter test test/services/session_context_service_skills_test.dart
fvm flutter test test/services/prompt/runtime_user_context_service_skills_test.dart
fvm flutter test test/services/skills/skill_installer_service_test.dart
fvm flutter test test/pages/settings_page_tool_settings_test.dart
```

Expected:

- PASS

- [ ] **Step 49: 运行静态检查**

Run:

```bash
fvm flutter analyze
```

Expected:

- 无新增 analyzer 错误

- [ ] **Step 50: 做一次端到端人工验证记录**

建议流程：

1. 安装 `android/skills` 仓库中的 `edge-to-edge`
2. 确认设置页显示已安装且启用
3. 发起一个明显匹配移动端沉浸式 UI 的请求
4. 确认 planner 先走 `Skill` tool
5. 确认 transcript 中出现 invoked skill reminder
6. 确认后续回答/规划遵循该 skill

- [ ] **Step 51: 提交变更**

```bash
git add docs/superpowers/specs/2026-05-08-mobile-skills-subsystem-design.md \
  docs/superpowers/plans/2026-05-08-mobile-skills-subsystem-implementation-plan.md \
  lib test README.md AGENTS.md
git commit -m "refactor: redesign mobile skills runtime around skill tool"
```
