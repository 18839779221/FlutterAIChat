# 文件沙盒架构

## 目标

本文档固定项目内文件访问的稳定架构约束，供后续所有涉及文件读写、路径解析、目录枚举、技能加载、artifact 存储和附件持久化的改动共同遵守。

本文档关注的是当前稳定架构与必须遵守的边界，不描述实现演进过程，也不讨论历史改造路径。

## 核心原则

### 1. file-native

Agent 继续使用普通文件路径工作，不引入显式 namespace、URI 或 `fileId` 风格协议。

允许的心智模型是：

- 绝对路径：`/artifacts/42/homepage.html`
- 相对路径：`artifacts/42/homepage.html`
- 当前目录：`./draft.md`
- 父目录：`../tmp/cache.json`

### 2. Agent 拥有自己的根目录 `/`

Agent 看到的是一套独立沙盒文件系统，不是宿主机文件系统。

在这套文件系统里：

- `/` 是沙盒根
- 所有 agent 路径都必须归一化到 `/` 之下
- `.`、`..`、重复 `/` 都按普通文件路径规则处理

### 3. 物理存储是平台私有的

沙盒的底层物理 root 位于各平台的 app-private 目录下，具体宿主路径由平台决定。

项目只约束这件事：

- 所有内部持久化文件都落在同一个平台私有 `agent` root 下
- 平台之间的真实目录名可以不同
- Agent 永远只看到统一的 `/...` 语义

## 路径模型

### Agent absolute path

以 `/` 开头的路径，例如：

- `/artifacts/42/homepage.html`
- `/skills/installed/verify/SKILL.md`
- `/attachments/persisted/att-1_demo.png`

这是 agent 可见的绝对路径，也是 tool result、planner context、skill context 和 UI 投影允许使用的路径形式。

### Relative path

不以 `/` 开头的路径，例如：

- `artifacts/42/homepage.html`
- `./draft.md`
- `../tmp/cache.json`

相对路径必须结合显式 `cwd` 解析。

### Host absolute path

宿主真实路径只允许出现在底层文件系统实现中。

它不允许进入：

- transcript
- planner-visible context
- tool result projection
- skill invoked context
- agent 可见的业务字段

## 单一物理 root

统一的物理目录布局为：

```text
agent/
  artifacts/
  skills/
    installed/
  attachments/
    persisted/
    thumbs/
  memories/
  tmp/
```

其中：

- `artifacts` 存放可编辑的可视化产物
- `skills` 存放已安装的技能
- `attachments` 存放导入后的持久化附件与缩略图
- `memories` 存放长期记忆存储层内容，是全局 agent 资产，不属于当前 workspace
- `tmp` 存放临时中间文件

## 统一解析规则

统一解析层必须同时产出两种视角：

- agent 绝对路径
- host 真实路径

解析规则要求：

- 接受 agent absolute path 和 relative path
- 相对路径必须结合 `cwd` 解析
- 所有路径必须归一化
- 任何结果都不得逃出沙盒根
- 解析结果必须稳定、可重复、可测试

## 可见性约束

### 允许进入 agent 视角

以下内容可以使用 agent 路径：

- 文件工具参数与返回值
- artifact 的 `sourcePath`
- skill 的 `qualifiedPath` / `entryFilePath`
- 附件的 `localPath` / `thumbnailPath`
- 调试页中展示的文件位置

### 禁止进入 agent 视角

以下内容必须隐藏 host 真实路径：

- 平台私有真实目录
- 外部导入时的原始宿主路径
- 任何底层实现为了访问文件而使用的绝对 host path

## 模块边界

### 文件工具

`ls`、`glob`、`grep`、`read`、`write`、`edit` 都只接受 agent 路径语义。

`/memories` 可由通用文件工具维护，但它不是 workspace-scoped 路径。删除长期记忆时必须保护 `/memories` 根目录和 `/memories/MEMORY.md`，只允许删除具体 topic file 或明确的子内容。

长期记忆的运行时使用不通过专用 tool 暴露，而是作为 `runtime user context` 的一部分进入模型上下文。

要求：

- 对外只回写 agent 绝对路径
- session guard 以 agent 绝对路径作为稳定 key
- `cwd` 必须显式参与解析

### Artifact

artifact 只使用沙盒内 `/artifacts/...` 路径。

要求：

- 对外暴露稳定的 agent 绝对路径
- 读写通过统一访问层
- 不保留可见的宿主真实路径字段

### Skills

技能只使用 `/skills/installed/...` 路径。

要求：

- `qualifiedPath`、`baseDirectory`、`entryFilePath` 均使用 agent 路径
- skill context 不包含 host path

### Attachments

导入后的附件只保留沙盒内路径。

要求：

- 持久化路径使用 `/attachments/persisted/...`
- 缩略图路径使用 `/attachments/thumbs/...`
- provider 可见上传内容使用 `data_url` 或远程 URL，而不是沙盒路径

## 未来迭代约束

后续任何文件相关改动都必须满足：

1. 不能把 host 真实路径带回 agent 侧
2. 不能再引入第二套并行文件 root
3. 不能绕过统一解析层直接拼接宿主路径
4. 不能把路径语义改回“只支持相对路径”
5. 不能为兼容历史数据引入长期分叉语义

如果某个新能力需要文件访问，它必须复用这套路径模型，而不是另起一套路径协议。

## 验证要求

涉及文件访问的改动至少应验证：

- agent absolute path / relative path 解析
- 沙盒越界拒绝
- tool result 是否只回写 agent 路径
- skill / artifact / attachment 是否仍保持路径隔离
