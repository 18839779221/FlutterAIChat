# Delete Tool 设计

## 摘要

当前文件工具已经覆盖：

- `LS`
- `Glob`
- `Grep`
- `Read`
- `Write`
- `Edit`

其中：

- `Read` 负责读取文件内容
- `Write` 负责新建文件或整文件覆盖
- `Edit` 负责已有文件的小范围精确修改

为了补齐文件操作能力，需要新增 `Delete` tool，用于删除文件和递归删除目录。

本设计目标是：

- 让文件工具形成稳定的增删查改闭环
- 保持与现有 `Write` / `Edit` 一致的高风险变更语义
- 严格把删除范围限制在当前 chat 绑定的当前 workspace 内
- 不引入模糊的自动重定向或跨 workspace 删除行为

## 设计目标

### 产品目标

- Agent 可以在用户明确要求时删除单个文件。
- Agent 可以在用户明确要求时递归删除目录。
- 删除操作必须进入现有确认流，不能自动执行。
- 删除行为只允许作用于当前 workspace 内的路径。
- 用户能够从 tool result 中明确知道删除了什么，以及删除的是文件还是目录。

### 架构目标

- `Delete` 复用现有文件工具架构，而不是旁路实现。
- planner 通过正式 `ToolDefinition` 感知 `Delete` 的用途和边界。
- 删除类变更与 `Write` / `Edit` 一样，进入统一的文件变更服务层。
- 保持 agent path、sandbox path、workspace path 三层边界一致。

## 非目标

本次不包含：

- 回收站
- 撤销删除
- 软删除
- 批量多路径删除
- 跨 workspace 删除
- 删除 workspace 根目录
- 新的目录权限模型
- 额外的 `force` / `recursive` / `expected_type` 参数

## 核心行为定义

### 1. Delete 的能力边界

`Delete` 支持两种目标：

- 单个文件
- 目录

当目标是目录时，行为固定为递归删除。

因此第一版不引入 `recursive` 参数，避免让 planner 在“目录是否递归”上做多余决策。目录一旦作为合法目标传入，即按递归删除执行。

### 2. Delete 的风险级别

`Delete` 属于高风险变更操作，行为等级与 `Write` 对齐：

- `requiresConfirmation = true`
- 通过现有 tool confirmation 流程执行
- 未经确认不得实际删除

本设计不新增专属删除确认机制，直接复用当前已存在的确认体系。

### 3. Delete 的作用域

`Delete` 只允许删除当前 workspace 内的内容。

这里的“当前 workspace”以当前 turn runtime 解析出的 workspace 为准，而不是泛化为整个 agent sandbox。

也就是说：

- 路径即使仍在总 sandbox 内
- 只要不属于当前 workspace 根路径

也必须直接拒绝执行。

### 4. 根目录保护

`Delete` 绝不允许删除当前 workspace 根目录本身。

例如当前 workspace 根为：

```text
/workspaces/ws_20260603_xxxxxx
```

那么以下目标必须拒绝：

```text
/workspaces/ws_20260603_xxxxxx
```

拒绝原因不是“路径非法”，而是明确的语义保护：

- 允许删除 workspace 内文件或子目录
- 不允许把整个 workspace 容器本身删除掉

### 5. 不存在目标的处理

如果目标文件或目录不存在，`Delete` 应返回明确失败，而不是静默成功。

原因：

- 删除属于高风险变更
- 无声吞掉“不存在目标”会弱化模型和用户对真实文件状态的感知
- 与现有 `Read` / `Edit` 的失败语义更一致

## ToolDefinition

### 名称

- `name`: `Delete`
- `title`: `Delete`
- `localizedTitle.zh`: `删除文件`
- `localizedTitle.en`: `Delete`

### planner 描述

英文版：

```text
Use this when the user clearly wants content removed. It can delete a single file or recursively delete a directory inside the current workspace. Delete is a high-risk mutating action and must be used with great caution. Usually inspect the target with LS, Glob, Grep, or Read before deleting. Be especially careful with directory deletion and confirm the directory contents before proceeding. Any attempt to delete content outside the current workspace, or to delete the current workspace root itself, is strictly forbidden.
```

中文版：

```text
当用户明确要求删除内容时使用。它可以删除单个文件，也可以递归删除当前 workspace 内的目录。Delete 属于高风险变更操作，请务必谨慎使用。通常应先用 LS、Glob、Grep 或 Read 确认目标后再删除；对于目录删除，必须特别确认目录所包含的文件内容。任何删除当前 workspace 之外内容，或删除当前 workspace 根目录本身的行为，都将被绝对禁止。
```

### runtime 元数据

- `requiresConfirmation = true`
- `isConcurrencySafe = false`
- `supportedPlatforms` 与现有文件工具保持一致

理由：

- 删除是变更操作，不适合并发安全声明
- 删除结果依赖文件系统当前状态，不应与其他写操作无约束并发

## 入参设计

第一版只保留一个入参：

```json
{
  "file_path": "/workspaces/ws_xxx/artifacts/old"
}
```

### 字段定义

- `file_path: string`
  - 含义：待删除目标的 agent 绝对路径或相对路径
  - 目标可以是文件，也可以是目录

### required

```json
["file_path"]
```

### 为什么不加 recursive

因为目录删除在本设计里固定就是递归删除，额外增加 `recursive` 会让 planner 多承担一层不必要分支判断。

### 为什么不加 force

第一版已经通过确认流解决了高风险门槛。继续引入 `force` 只会增加模型侧误用空间。

### 为什么不加 expected_type

目标到底是文件还是目录，应该由运行时基于实际文件系统判断，而不是让 planner 额外维护一份可能过期的类型预期。

## 出参设计

`Delete` 通过现有 `ToolResult.data` 返回结构化结果。

成功时建议至少包含：

```json
{
  "filePath": "/workspaces/ws_xxx/artifacts/old",
  "message": "已删除路径：/workspaces/ws_xxx/artifacts/old",
  "deletedType": "directory",
  "deletedFileCount": 3,
  "deletedDirectoryCount": 2,
  "hadChildren": true
}
```

### 字段定义

- `filePath`
  - 被删除目标的 agent 路径
- `message`
  - 面向 transcript / UI 的简短摘要
- `deletedType`
  - `file` 或 `directory`
- `deletedFileCount`
  - 本次删除的文件数量
- `deletedDirectoryCount`
  - 本次删除的目录数量
- `hadChildren`
  - 目标是否包含子项

### 计数语义

建议固定如下：

- 删除单个文件时：
  - `deletedType = file`
  - `deletedFileCount = 1`
  - `deletedDirectoryCount = 0`
  - `hadChildren = false`
- 删除空目录时：
  - `deletedType = directory`
  - `deletedFileCount = 0`
  - `deletedDirectoryCount = 1`
  - `hadChildren = false`
- 删除非空目录时：
  - `deletedType = directory`
  - `deletedFileCount >= 1`
  - `deletedDirectoryCount >= 1`
  - `hadChildren = true`

## 错误语义

建议固定以下错误码：

- `invalid_file_path`
- `path_outside_workspace`
- `cannot_delete_workspace_root`
- `file_not_found`
- `unsupported_tool`

说明：

- `path_outside_workspace`
  - 路径虽可能位于总 sandbox 中，但不在当前 workspace 根内
- `cannot_delete_workspace_root`
  - 目标恰好等于当前 workspace 根路径
- `file_not_found`
  - 目标不存在

## 架构落点

### 1. Handler

新增：

- `lib/tools/handlers/delete_tool_handler.dart`

职责：

- 定义正式 `ToolDefinition`
- 做参数归一化
- 做当前 workspace 边界校验
- 调用底层文件变更服务
- 统一组装 `ToolResult`

### 2. Runtime Registry

在默认 runtime registry 注册：

- `DeleteToolHandler()`

应与 `Read` / `Write` / `Edit` 保持相邻，形成文件工具分组。

### 3. 文件变更服务

扩展：

- `lib/services/file_tools/file_tool_write_service.dart`

新增统一删除入口，例如：

- `deletePath(...)`

理由：

- `Delete` 本质上也是一种文件变更
- 当前 `Write` / `Edit` 已经收敛在统一写服务
- 不应再拆一套平行的删除 service，避免文件变更语义分裂

### 4. Host Adapters

复用现有：

- `FileToolHostAdapters.writeService`

不新增单独的 `deleteService` 字段。

## 删除执行规则

### 1. 路径解析顺序

执行时必须先后经过：

1. 现有 sandbox path normalization
2. 当前 workspace 根路径校验
3. workspace 根目录保护
4. 文件系统存在性检查
5. 实际删除

### 2. Workspace 边界校验

即使一个路径通过了总 sandbox 校验，也必须继续判断：

- 该路径是否位于 `context.workspace.fileRoot` 之下

若不在当前 workspace 内，直接失败。

### 3. 删除目录的递归行为

当目标是目录：

- 先遍历统计子文件和子目录数量
- 再执行递归删除

这样可以为 result payload 提供稳定计数。

### 4. Session guard 处理

删除完成后，相关已读快照不应再被视为可写依据。

实现上允许两种等价策略：

- 删除对应路径的 guard 记录
- 或让后续写检查自然因为目标不存在 / 版本不匹配而失败

但最终外部行为必须满足：

- 被删除目标不能继续沿用旧的“已读取且可写”状态

## UI 与结果卡片

`Delete` 应进入现有 tool result 投影链路。

第一版不要求专门做复杂删除 diff 视图，但至少应保证：

- workflow 卡片可以显示删除目标
- result 卡片可以显示删除类型和计数摘要
- transcript / context 中仍只暴露 agent path，不泄漏 host path

## 测试策略

### 1. Service 层测试

覆盖：

- 删除单文件成功
- 删除空目录成功
- 删除非空目录递归成功
- 目标不存在失败

### 2. Handler 层测试

覆盖：

- schema 与 `requiresConfirmation`
- 参数缺失失败
- workspace 外路径失败
- workspace 根目录删除失败
- 成功结果摘要与 payload

### 3. Planner / 集成验证

覆盖：

- `Delete` 被注册并暴露给 planner
- 文件场景下 planner 能看到 `Delete`
- 确认流能正确拦截删除操作

## 决策总结

本设计确认以下最终约束：

- 新增 `Delete` tool
- 支持删除单文件
- 支持递归删除目录
- 只接受 `file_path` 一个入参
- 必须经过确认流
- 只允许删除当前 workspace 内内容
- 严禁删除当前 workspace 根目录本身
- 删除逻辑归入统一文件变更服务，而不是旁路实现
