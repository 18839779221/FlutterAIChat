# 长期记忆使用层设计

## 摘要

本设计覆盖长期记忆系统的第二阶段：**使用层**。

上一阶段已经把长期记忆存储为 `/memories/MEMORY.md` + topic Markdown files，并通过通用文件工具维护。本阶段让这些文件进入运行时上下文：

- 每轮构建 runtime user context 时自动读取 `/memories/MEMORY.md`。
- 根据当前用户输入和索引内容，选择少量明确相关的 topic file。
- 将索引和选中的记忆正文作为 runtime-only context 注入 planner / final answer。
- 用户明确要求 ignore memory / not use memory 时，本轮按 `MEMORY.md` 为空处理。
- 从记忆中得到的当前代码事实只能作为线索，执行建议前必须验证当前文件、函数或 flag。

本阶段仍不做后台自动抽取。自动抽取属于下一阶段“形成层”。

## 背景

当前长期记忆存储层已经具备：

- `/memories` 是全局长期记忆目录，不属于当前 workspace。
- `Write /memories/...` 不触发 workspace 自动迁移。
- `Delete` 可删除具体 memory topic file，但保护 `/memories` 根和 `/memories/MEMORY.md`。
- system prompt 已保留 memory 存储规则和 `MEMORY.md is always loaded...` 契约。

但如果不接入使用层，用户保存的记忆不会自动影响后续 turn。因此本阶段要补齐“读取索引、选择记忆、注入上下文”的最小闭环。

## 设计目标

### 产品目标

- 用户保存长期记忆后，后续 turn 能自动看到 `MEMORY.md` 索引。
- 当当前输入明显相关时，Agent 能看到少量 topic file 正文。
- 用户明确说不要使用记忆时，本轮完全不应用记忆内容。
- 记忆内容不会被当成当前事实；涉及文件、函数、flag、项目状态的建议必须先验证当前状态。
- 记忆使用对用户不可见，除非用户询问记忆或记忆确实影响回答。

### 架构目标

- 长期记忆使用层属于 runtime user context，不进入 session summary、recent turns 或 persisted timeline。
- 不新增 chat group / workspace / transcript 所有权边界。
- 不把 `/memories` 内容写入 session context snapshot。
- 不引入专用 memory tool；读取仍走内部 file root service，而不是 planner 工具调用。
- 保持 host path 不进入模型上下文。
- 使用层可独立测试，不依赖真实 LLM。

## 非目标

本阶段不包含：

- 后台自动抽取最近对话形成记忆。
- 语义 embedding / vector search。
- UI 记忆管理页。
- 记忆编辑器。
- team memory / private-team scope。
- 自动修复损坏 frontmatter。
- 对所有 topic file 做强 schema migration。

## 核心行为

### 1. MEMORY.md 自动加载

每次 `RuntimeUserContextService.buildSnapshot()` 构建 runtime user context 时，memory provider 尝试读取：

```text
/memories/MEMORY.md
```

如果文件不存在或为空：

- 不注入 memory section。
- 不报错。
- 不影响正常聊天。

如果存在：

- 注入一个 `# memoryIndex` section。
- 保留索引文本，但做行数和字符数裁剪。
- 默认最多保留 200 行，匹配存储 prompt 的约束。

### 2. 选择性 topic recall

本阶段不做 embedding。使用 `side` 辅助选择：

1. 解析 `MEMORY.md` 中的 Markdown link。
2. 读取索引行文本，以及 topic 文件 frontmatter 中可用的 `name / description / type`。
3. 将这些内容整理成一个候选清单，交给 `side` 路径做相关性判断。
4. `side` 返回最多 5 条明确相关的 topic file。
5. 读取这些 topic file，注入 `# recalledMemories` section。

如果 `side` 选择失败、返回空、或不可用：

- 仍然保留 `# memoryIndex`。
- 不退回到脆弱的关键词规则。
- 宁可少召回，也不要错误召回。

如果用户明确要求“回忆 / 查看 / 检查记忆 / 你记得什么”，可以降低相关性门槛：

- 仍不全量灌入全部 topic 正文。
- 可以只注入 `MEMORY.md` 索引，并让 planner 后续通过文件工具读取具体记忆。

### 3. 避免重复和过量注入

本阶段先做单次 build 内去重：

- 同一 path 只读一次。
- 如果 link path 不在 `/memories` 内，跳过。
- 单个 topic file 超过预算时截断。
- 总 recall 正文超过预算时停止追加。

默认建议：

- index 最多 200 行。
- topic file 最多 3000 字符。
- recalled topic 最多 5 条。
- recalled body 总量最多 10000 字符。

后续可在 turn runtime marker 中记录 surfaced memory，避免连续多轮重复注入；本阶段先不引入持久 marker。

### 4. ignore memory

如果当前用户输入明确包含不要使用记忆的语义，例如：

- ignore memory
- do not use memory
- don't use memory
- 不要使用记忆
- 忽略记忆
- 别参考记忆

本轮 memory provider 返回空 snapshot：

- 不注入 `# memoryIndex`。
- 不注入 `# recalledMemories`。
- 不应用 remembered facts。
- 不主动提及 memory content。

这条规则应优先于相关性召回。

### 5. 记忆信任边界

使用层必须注入一段简短使用规则：

```text
Memory records are context clues, not current truth.
If a recalled memory names a file path, function, flag, or current repo state, verify the current state before recommending action based on it.
If memory conflicts with current files or tool results, trust the current observation.
```

中文版结构对齐：

```text
长期记忆是上下文线索，不是当前事实。
如果召回的记忆提到文件路径、函数、flag 或当前仓库状态，在基于它给出行动建议前必须验证当前状态。
如果记忆和当前文件或工具结果冲突，以当前观察为准。
```

这段规则和 recalled memories 一起放入 runtime user context，而不是放进 session summary。

## 架构设计

### 新增 MemoryRuntimeContextService

新增服务建议路径：

```text
lib/services/memory/memory_runtime_context_service.dart
```

职责：

- 从 file sandbox root 读取 `/memories/MEMORY.md`。
- 解析索引中的 Markdown links。
- 根据当前 user input 选择相关 topic file。
- 读取 topic file 正文。
- 输出可注入 runtime user context 的纯文本 section。

服务不负责：

- 写入记忆。
- 删除记忆。
- 自动抽取。
- 修改 session context。
- 调用 LLM。

### 术语说明

为了避免歧义，这里把 memory 索引和 topic 文件里会用到的几个词统一说明一下：

- `title`：`MEMORY.md` 索引行中方括号里的标题，例如 `[Android debug install]` 里的 `Android debug install`。
- `hook`：`MEMORY.md` 索引行中链接后面的那句短提示，例如 `— User prefers debug overwrite install on real Android devices.`。它不是独立字段，只是给索引项补充一行可快速判断相关性的摘要。
- `path`：`MEMORY.md` 索引行中链接目标的路径，例如 `feedback/android-debug-install.md`。
- `frontmatter description`：topic Markdown 文件头部 frontmatter 里的 `description:` 字段，用来描述这条记忆正文的主题。

后续如果文档里再出现 `索引行短句`、`一行提示`、`hook`，都指的是同一个东西。

### RuntimeUserContextService 接入

当前 `RuntimeUserContextService.buildSnapshot({int? groupId})` 没有 current user input 参数。

本阶段需要扩展为：

```dart
Future<RuntimeUserContextSnapshot> buildSnapshot({
  int? groupId,
  String? userInput,
}) async
```

`SessionContextService.buildPlannerContextState()` 已经能拿到 `currentTurn`，因此可传入：

```dart
await _runtimeUserContextService.buildSnapshot(
  groupId: groupId,
  userInput: currentTurn?.userInput,
)
```

保持 `userInput` 可选，避免影响现有调用方和测试。

### File root 依赖

使用层需要读取 app-private agent root。建议以函数注入，避免让 service 直接依赖平台 API：

```dart
typedef MemoryFileReader = Future<String?> Function(String agentPath);
```

或更贴合现有文件工具：

```dart
typedef MemoryRootServiceProvider = Future<FileToolRootService?> Function();
```

推荐第一版使用 `MemoryFileReader`，测试最简单，生产 wiring 可用 `FileToolRootService` 实现：

- 读取 `/memories/MEMORY.md`
- 读取 `/memories/<type>/<topic>.md`

所有输出仍使用 agent path。

### 输出格式

如果只有索引：

```text
# memoryIndex
MEMORY.md is always loaded into your conversation context. Use it as an index, not as complete memory content.

- [Android debug install](feedback/android-debug-install.md) — User prefers debug overwrite install on real Android devices.
```

如果有相关 topic：

```text
# recalledMemories
Memory records are context clues, not current truth. If a recalled memory names a file path, function, flag, or current repo state, verify the current state before recommending action based on it. If memory conflicts with current files or tool results, trust the current observation.

## /memories/feedback/android-debug-install.md
---
name: Android debug install preference
description: User prefers debug overwrite install on Android real devices.
type: feedback
---

Rule/fact: ...
```

## 与 session context 的关系

长期记忆使用层只进入 runtime user context：

- 在 planner message 顺序中位于 snapshot summary、recent turns、current turn transcript 之前。
- 不参与 session summary。
- 不写入 chat messages。
- 不写入 chat events。
- 不改变 current workspace。

这保持现有架构规则：

- runtime user context
- latest snapshot summary
- recent completed turns
- current turn transcript

四者互不混淆。

## 错误处理

### MEMORY.md 不存在

返回空 section，不记录用户可见错误。

### MEMORY.md 损坏

保留原始索引文本中可读部分；无法解析的 link 不进入 topic recall。

### topic file 不存在

跳过该 topic，并可在 section 中不暴露错误。记忆文件缺失属于长期记忆维护问题，不应打断用户请求。

### topic file 过大

按字符预算截断，并标记：

```text
[memory truncated]
```

### reader 异常

吞掉该 memory section 并记录 debug log。不能因为 memory 读取失败阻断 chat send。

## 测试策略

### MemoryRuntimeContextService

覆盖：

- `MEMORY.md` 不存在时返回空。
- 加载 `MEMORY.md` 索引。
- 从索引中解析 Markdown link。
- 根据 user input 选择相关 topic。
- topic path 逃出 `/memories` 时跳过。
- ignore memory 时返回空。
- topic 正文超限时截断。

### RuntimeUserContextService

覆盖：

- `buildSnapshot(userInput: ...)` 注入 memory section。
- 不传 `userInput` 时仍加载 index，但不召回 topic，或只按默认策略返回索引。
- ignore memory 时不注入 memory section。
- workspace / AGENTS / skills sections 不受影响。

### SessionContextService

覆盖：

- `currentTurn.userInput` 会传给 runtime memory context。
- planner messages 中 memory section 出现在 runtime user context 内。
- memory section 不进入 snapshot summary。

### UserContextMessageBuilder

覆盖：

- memory section 作为 `additionalSections` 正常出现在第一条 synthetic user reminder。

## 后续阶段

### 自动形成层

下一阶段单独设计：

- 发送后后台抽取最近消息。
- 用户明确“记住/忘掉”优先。
- 去重、更新、删除过时记忆。
- 抽取器只看最近消息，不扫代码、不查 git。

### 更强召回

后续可考虑：

- LLM-based index selection。
- embedding search。
- surfaced memory marker，避免连续多轮重复注入。
- memory debug inspector。

## 验收标准

- 每轮 planner context 自动包含 `MEMORY.md` 索引，除非用户本轮要求 ignore memory。
- 当前输入与索引相关时，最多 5 条 topic file 被注入 runtime user context。
- topic file 读取失败、缺失或过大不会阻断聊天。
- 记忆使用规则明确提醒“记忆是线索，不是当前事实”。
- memory context 不进入 session summary、chat timeline 或 workspace。
- 所有相关单元测试通过。
