# Skills 子系统第二阶段完善设计

## 摘要

当前 skills 子系统已经完成第一阶段核心重构：可用 skills 通过 runtime `<system-reminder>` 暴露给 planner，模型通过显式 `skill` tool 加载某个 skill，成功调用后的 skill 正文再通过 invoked skill reminder 进入 planner-visible transcript。

第二阶段不改变这个主模型。完善重点是让这条链路更可靠、更可控、更可观测：

- 提升该调用时调用的可靠性
- 明确 invoked skill 的生命周期与去重规则
- 控制 skill 正文与 catalog 对上下文预算的占用
- 让 Debug 面板能解释 skill 为什么、何时、如何影响模型
- 补齐 simulated integration 回归，验证 skill 调用和投影语义

本阶段不做隐式自动激活、embedding 检索、脚本自动执行、动态工具注入或 marketplace 化能力。

## 当前基线

现有实现已经具备以下基础能力：

1. `SkillRuntimeService` 从本地安装目录扫描、过滤启用状态，并按 id 或 name 读取完整 skill。
2. `RuntimeUserContextService` 生成可用 skills 列表，由 `UserContextMessageBuilder` 作为单独 `<system-reminder>` 注入 planner-visible context。
3. `SkillToolHandler` 作为标准 tool 暴露给 planner，并在执行成功后返回 `InvokedSkillContext` 结构化载荷。
4. `ToolResultContextProjector` 会把 `skill` tool result 投影为包含路径、基目录、正文的 invoked skill reminder。
5. `SessionContextService` 的技能相关测试已经覆盖可用列表注入、invoked reminder 投影以及压缩重建后的基础恢复语义。

这些能力说明第一阶段的架构方向成立。第二阶段应继续沿用“显式工具调用 + transcript 投影”的路径，而不是重新引入自动匹配 prompt 注入。

## 目标

### 产品目标

- 用户启用 skill 后，相关任务更稳定地触发 `skill` tool。
- 当 skill 影响一次回答时，Debug 面板能看出模型看到哪些 skills、调用了哪个 skill、正文是否被裁剪。
- 长 skill 或大量 skills 不会无控制地挤占上下文。
- 重复调用不会制造多份相同 reminder，避免 planner context 变脏。

### 架构目标

- skill 生效仍然必须经过 `skill` tool 和 turn ledger。
- 触发可靠性优先通过测试、verification 和观测改进，不通过硬编码 keyword router。
- skill 正文裁剪、catalog 裁剪、重复调用保护都要结构化、可测试。
- Debug 展示消费 ledger / projection 结果，不扫描 UI timeline 文本反推。

## 非目标

本阶段不包含：

- skill 自动匹配并绕过 `skill` tool 生效
- 基于关键词的大型路由表
- embedding 检索或远端 marketplace 推荐
- skill 脚本自动执行
- skill 动态注册新工具或扩展 tool schema
- 多版本 skill 并存与升级迁移框架

## 完善方向

### 1. 触发可靠性与回归样例

当前触发路径依赖模型根据 skills list reminder 主动调用 `skill` tool。这个方向正确，但需要回归保护。

建议新增一组 simulated integration tests：

- fake planner 第一次决策调用 `skill`
- real `TurnHarness` 执行 `skill` tool
- real `AgentEventProcessor` 写入 tool result / transcript
- real `SessionContextProjector` 投影 invoked reminder
- fake planner 第二次决策能看到 invoked skill reminder 并继续执行

同时保留一个“相关任务应先调用 skill”的 planner regression 样例，例如 Android edge-to-edge 任务对应 `edge-to-edge` skill。该测试不应变成 keyword router 断言，而应验证 planner-visible tool contract 是否足够清晰。

### 2. 重复调用与生命周期

需要补齐明确规则：

- 同一 turn 内同名 skill 已成功调用后，重复调用应返回 no-op 或结构化 failure。
- 跨 turn 允许重新调用同一 skill，避免旧上下文被压缩后无法重新加载。
- 同一 context rebuild 窗口内，相同 skill 的完全相同 invoked reminder 只投影一次。
- 如果 skill 文件内容在两次调用之间发生变化，新的调用应以文件系统最新内容为准。

推荐把“同一 turn 是否已调用”判断放在 tool execution context 可访问的 turn transcript / step ledger 上，而不是在 `SkillRuntimeService` 中维护内存状态。

### 3. 上下文预算与稳定裁剪

skills 会天然消耗上下文，第二阶段需要设置预算护栏：

- catalog reminder 最多展示固定数量的 enabled skills，排序稳定。
- 单个 skill body 设置字符或 token 预算上限。
- 被裁剪的 invoked reminder 必须显式说明裁剪发生，并保留 skill path / base directory。
- 裁剪逻辑应在投影层或 dedicated formatter 中实现，避免修改本地真实 `SKILL.md` 内容。
- 长正文裁剪测试应验证 planner-visible context 不会无限增长。

后续如果 skill 需要更多材料，应通过普通只读文件工具读取 `references/` 中的具体文件，而不是一次性把整个 skill 目录注入上下文。

### 4. Skill 资源读取模型

第一版保留 `references/`、`assets/`、`scripts/` 目录，但不自动执行脚本。第二阶段可以先支持安全的只读资源使用：

- `SKILL.md` 可以描述需要读取的 reference 文件。
- 读取 reference 时仍使用现有 `read` 工具。
- 路径策略必须限制在 skill base directory 或明确允许的只读资源范围内。
- `scripts/` 仍不自动执行；如果未来开放，必须作为单独设计处理权限、确认和沙箱。

这能让复杂 skill 分层加载，同时保持 tool / file policy 边界不被 skill 机制绕开。

### 5. 安装质量与来源可解释性

安装侧可以补齐质量门：

- frontmatter 必须包含有效 `name` 与 `description`。
- skill id 冲突时给出明确处理策略。
- invalid skill 在设置页可见，并展示失败原因。
- `.skill-source.json` 记录来源 URL、ref、安装时间和最近更新时间。
- GitHub 安装应优先支持固定 ref / commit，避免远端默认分支变化导致内容不可复现。

这些能力属于 catalog / settings 层，不应影响 runtime planner contract。

### 6. Debug 可观测性

Debug Turn Inspector 应新增 skills 相关信息：

- 当前 planner context 中的 available skills catalog。
- 本 turn 已调用的 skills。
- 每个 invoked skill reminder 是否进入 projected context。
- skill body 是否裁剪、裁剪前后长度。
- skill tool failure 原因，例如 missing、disabled、duplicate、invalid payload。

Debug 展示应基于 turn ledger、tool result payload 和 context projection，不从 UI message 文本中猜测。

## 建议实施顺序

1. 补同一 turn 重复调用保护和相关单元测试。
2. 补 skill body / catalog 裁剪 formatter 与预算测试。
3. 在 Debug Turn Inspector 增加 skills projection 可见性。
4. 增加 simulated integration test，覆盖 `skill` tool 调用到下一轮 planner 可见的完整链路。
5. 再处理只读 reference 资源和安装质量门。

这个顺序优先稳住已上线语义，再扩展表达能力。

## 验收标准

第二阶段完成时应满足：

1. 同一 turn 重复调用同名 skill 不会产生重复 invoked reminder。
2. 长 skill 正文会被稳定裁剪，裁剪状态对 planner 和 Debug 可解释。
3. 可用 skills 列表过长时会稳定裁剪，不影响其他 runtime user context。
4. Debug Turn Inspector 能展示 available / invoked / projected skills 状态。
5. simulated integration test 覆盖 skill 调用、tool result、transcript projection、后续 planner 可见性。
6. 没有新增绕过 `skill` tool 的隐式 skill 生效路径。

## 风险

### 模型仍可能不调用 skill

缓解方式是持续优化 planner-facing contract 与回归样例，而不是把 skill 选择变成手写路由。

### 裁剪导致 skill 指令缺失

缓解方式是在 `SKILL.md` 写作规范中鼓励把关键规则放在前部，并让裁剪提示保留 reference 读取路径。

### Debug 面板膨胀

缓解方式是默认折叠 skills 详情，只展示状态摘要，展开后再看完整 projection 与裁剪信息。
