# Workspace V1 文件容器设计

## 摘要

当前项目的稳定主轴已经明确收敛到：

- `chat group / session`
- `turn / transcript / ledger`
- `session context`

这些层已经承担了对话、agent loop、上下文压缩与恢复执行的主语义职责。

但当任务开始产生文件型产物时，当前项目仍缺少一个更高层、跨会话可复用的“文件容器”概念，结果是：

- 文件归属容易散在全局目录里
- 不同 chat 难以共享同一批 artifact / attachment
- 模型虽然能使用文件工具，但不知道“当前正在使用哪个工作区”
- 用户也缺少一个轻量方式，把多个会话绑定到同一份工作资料

本设计引入 `workspace`，但明确将其约束为：

> `workspace` 是文件容器，不是新的对话容器，也不是新的 planner 语义真相源。

第一版目标非常克制：

- 让文件有稳定归属
- 允许多个 chat 复用同一 workspace
- 让模型知道当前 workspace
- 不改写现有 session / transcript / summary 架构

## 设计目标

### 产品目标

- 用户可以从普通 chat 开始，不必先理解 workspace。
- 当任务首次产生长期文件时，系统可自动创建 workspace。
- 用户也可以手动创建 workspace，并在不同 chat 间复用。
- 同一 workspace 下的文件可以跨 chat 共享。
- 默认情况下文件不会散落到无归属目录。

### 架构目标

- `workspace` 不替代 `chat group`。
- `workspace` 不成为新的 session context 真相源。
- 文件归属直接由目录结构表达，而不是额外维护一张 workspace 文件索引表。
- workspace 注入复用现有 runtime user context / runtime reminder 机制。

## 非目标

第一版不包含：

- workspace 级 summary / memory / prompt
- workspace 级长期目标管理
- workspace 首页或重型文件管理中心
- workspace 时间线
- workspace display name 与重命名
- 单独的 workspace 目录表或 workspace 文件表
- 把 workspace 引入 transcript / session summary / compaction snapshot

## 核心定义

### 1. Workspace 是文件容器

workspace 的第一版职责只有三类：

- 承载文件归属
- 作为多个 chat 的共享文件范围
- 作为模型可见的当前工作区提示

它不负责：

- 承载对话历史
- 承载 tool loop 状态
- 承载 session summary
- 承载 runtime memory

### 2. Chat Group 仍是对话容器

当前项目中，`group` 仍然是：

- turn 的宿主
- transcript 的宿主
- session context 的宿主
- runtime marker 的宿主

因此第一版只给 `chat_groups` 增加 `workspace_id` 引用，不改变 group 作为 session 级对话容器的角色。

### 3. `.default` 是隐式默认 workspace

所有未绑定显式 workspace 的 chat，在运行时都逻辑上位于 `.default`。

这样做的目的：

- 默认 chat 也有稳定文件根
- 文件工具永远有确定作用域
- 不需要先弹出“请先创建 workspace”
- 用户仍然可以无感开始对话

`.default` 是底层稳定存在的 workspace 名称，不需要第一版在 UI 中高曝光，但模型必须知道它是默认 workspace。

## 数据模型

### ChatGroup 新增 `workspaceId`

第一版不新增独立 workspace 数据表。

只在现有 `chat_groups` 上增加：

- `workspace_id TEXT`

约束如下：

- 字段可以为 `NULL`
- 当 `NULL` 时，运行时解析为 `.default`
- 当有值时，该值同时表示：
  - workspace 名称
  - workspace 目录名
  - workspace 唯一标识

也就是说，第一版没有 `id` / `displayName` 双轨模型，只有一个稳定名字。

### Workspace 命名规则

第一版命名规则固定为：

- 默认 workspace：`.default`
- 自动创建 workspace：`ws_<yyyyMMdd>_<6位小写字母数字随机串>`

例如：

- `.default`
- `ws_20260602_a3k9qx`

约束：

- 创建后不可变
- 目录名即 workspace 名
- 模型注入与 UI 展示都直接使用这个名字

## 目录结构

统一采用 workspace 分区目录：

```text
/workspaces/.default/
  artifacts/
  attachments/
  tmp/

/workspaces/<workspaceId>/
  artifacts/
  attachments/
  tmp/
```

说明：

- `artifacts/` 用于 `create_artifact` 等长期产物
- `attachments/` 用于归档后的用户附件
- `tmp/` 用于 workspace 作用域下的临时工作文件

这样做的核心收益：

- 所有文件天然有归属
- 多个 chat 共享 workspace 时，共享文件天然成立
- file tools 后续可以基于 workspace 获得稳定默认根

## 自动创建与绑定规则

### 初始状态

新 chat 可以在数据库层保持 `workspace_id = NULL`。

但运行时必须将其解释为：

- `current workspace = .default`
- `file root = /workspaces/.default`

### 自动创建触发器

只有以下三类动作允许把 chat 从 `.default` 升级到显式 workspace：

1. `create_artifact`
2. `Write` 且目标文件此前不存在
3. 明确要长期归档的附件导入

明确不触发自动创建的动作：

- `Edit`
- 覆盖已有文件的 `Write`
- 普通文本对话
- 搜索 / 抓网页
- 纯临时运行结果

### 自动创建顺序

当触发自动创建时，顺序固定如下：

1. 检查当前 chat 是否仍处于 `.default`
2. 生成新的 `workspaceId`
3. 更新当前 `chat_group.workspace_id`
4. 本次文件直接写入新 workspace
5. 为当前 turn 注入一次 workspace change reminder

关键约束：

- 不允许先写 `.default` 再迁移文件
- 路径归属应在首次落盘前就确定

## 模型注入

workspace 注入必须复用现有“运行时 user context + turn runtime reminder”机制，而不是新建一套 prompt 层。

### 1. 常驻注入：Current Workspace

通过：

- `RuntimeUserContextService`
- `UserContextMessageBuilder`

在每次 planner context build 时注入当前 workspace 信息。

推荐格式：

默认 workspace：

```text
# currentWorkspace
Current workspace: .default (default workspace).
File root: /workspaces/.default
```

普通 workspace：

```text
# currentWorkspace
Current workspace: ws_20260602_a3k9qx.
File root: /workspaces/ws_20260602_a3k9qx
```

要求：

- 文案保持简洁
- 只告诉模型“当前 workspace 是谁、根路径在哪”
- 不主动列文件清单
- 不加入过长行为说明

### 2. 增量提醒：Workspace Change Reminder

当当前 chat 的 workspace 发生变化时，按日期变化 reminder 的同类机制，在当前 turn 的 runtime context 中增加一条 reminder。

推荐格式：

```text
<system-reminder>
The current chat is now using workspace ws_20260602_a3k9qx.
New files for this chat should be created under /workspaces/ws_20260602_a3k9qx.
</system-reminder>
```

若目标是默认 workspace，则额外注明：

```text
<system-reminder>
The current chat is now using workspace .default (default workspace).
New files for this chat should be created under /workspaces/.default.
</system-reminder>
```

### 3. 注入边界

workspace 信息属于 runtime context，不属于持久语义真相。

因此：

- 可以进入 planner-visible context
- 可以通过 runtime reminder 增量插入
- 不写入 transcript 作为长期事实
- 不进入 session summary
- 不进入 compaction snapshot

## 与现有架构的关系

### 1. 不改变 Session Context 真相源

现有事实边界继续保持：

- transcript 负责语义时间线
- ledger 负责执行状态
- session context 负责 planner 输入装配

workspace 只补充“当前工作区环境”与“文件归属范围”，不替代其中任何一层。

### 2. 不改变 Append-Only Transcript 主路径

workspace change reminder 只是发送时的 runtime injection，不是新的 transcript 事件类型。

因此不应：

- 新增 workspace 专属 `chat_event`
- 让 planner 依赖 workspace 专属持久化消息
- 让 workspace 成为 tool loop 的恢复依据

### 3. 与统一文件沙盒设计兼容

当前项目已在推进统一 agent 文件沙盒根。

workspace V1 在此基础上的新增要求只是：

- 在统一 agent root 下引入 `/workspaces/<id>/...`
- 把 artifact / attachments / tmp 的归属下沉到 workspace 目录
- 保持 agent 仍然使用 file-native 路径心智

## UI 浮现策略

第一版只做轻量浮现。

建议只包含：

1. chat 页显示当前 workspace 的轻量标识
2. 自动创建 workspace 后给一次轻提示
3. 新建 chat 或 chat 设置里允许选择已有 workspace

第一版不做：

- workspace 首页
- workspace 文件管理中心
- workspace 时间线
- workspace 级摘要

## 第一版范围收口

第一版只共享：

- workspace 内文件

第一版明确不共享：

- chat 历史
- session summary
- runtime memory
- workspace 级 prompt
- workspace 级长期目标

## 实施建议

建议按以下顺序落地：

1. 先给 `chat_groups` 增加 `workspace_id`
2. 再扩展统一 agent 文件沙盒为 `/workspaces/<id>/...`
3. 接着改造 artifact / attachment / file tool 的默认归属
4. 最后补 runtime context 注入与轻量 UI 浮现

## 最终结论

workspace V1 的正确定位是：

> 一个独立于 chat 的文件容器，默认通过 `.default` 托底，在首次文件型任务出现时自动升级到显式 workspace，并通过 runtime context 告知模型当前工作区，但不介入现有 session/transcript/context 的主语义边界。
