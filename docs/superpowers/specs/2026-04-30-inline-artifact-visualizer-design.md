# Inline Artifact Visualizer 设计

## 背景

当前项目已经具备较完整的 agent loop 主链路：

- `TurnHarness` 作为单轮执行入口
- `ToolDefinition -> ToolOrchestratorService -> ChatTurnStep -> chat_events` 作为标准工具执行管线
- `SessionContextService` / `SessionContextProjector` 负责 planner-visible context
- 聊天 UI 已经支持基于 `AssistantTurnBlock` 的结构化块渲染

用户希望新增一类类似 Claude Visualizer 的能力：模型在回答过程中，不只输出文字，还可以在回复里直接交付一个可交互、可视化的小型 HTML/SVG 内容块，用来辅助解释、展示、比较、计算或演示。

本次需求的重点不是把 artifact 作为唯一产物，也不是把会话升级成完整 workspace 系统，而是把 artifact 作为回答的一部分进行内联展示，并允许模型在必要时继续改写它，使其在同一轮回答中逐步完善。

## 目标

本次设计目标如下：

1. 新增正式 `create_artifact` 工具，让模型可以在回复中发布自包含 HTML/SVG artifact
2. artifact 默认作为回答增强型内容块，而不是唯一交付物
3. 同一 turn 内，artifact 在用户感知上应作为回答正文的一部分原位刷新
4. 跨 turn 继续修改同一 artifact 时，保留旧回答快照，并在新 turn 中展示新的 artifact 卡片
5. 后续模型优先通过已有 `Read/Edit/Write` 工具持续编辑 artifact 文件，而不是每次重发整段 `source`
6. artifact 与 `Edit/Write` 的联动必须局部收敛，避免污染整个 agent loop
7. App 重启、group 切换、group reload 后，artifact 展示必须可由持久化数据重新构建

## 非目标

本轮明确不做以下事情：

1. 不把 artifact 建成完整 workspace / project / export 子系统
2. 不在 artifact 内支持 JS 到 Dart 的桥接调用
3. 不允许 artifact 内按钮直接再次调用模型或工具
4. 不为了 artifact 改写 `TurnHarness` 主状态机或 planner decision contract
5. 不给 `Write/Edit` 工具增加 artifact 专属参数或返回字段
6. 不要求恢复流式生成中的未持久化中间态
7. 不把 Flutter Web 作为首发完整验收平台

## 核心定位

### 1. 回答增强型渲染工具

`create_artifact` 的首要职责不是“生产最终产物”，而是“把一个可交互的可视化块嵌入当前回答中”。它更接近回答表达能力，而不是外部动作型工具。

典型使用场景包括：

- 用图表解释数据分布
- 用优雅表格呈现对比信息
- 用小型计算器说明公式与参数变化
- 用交互 demo 演示某个概念
- 用 SVG/HTML 小页面辅助分析推理结果

它可以偶尔成为某种最终产物，但这不是当前架构的默认假设。

### 2. 局部增强，而非全局语义

artifact 必须是一种局部增强能力，而不是让整个 agent loop 增加一套新的全局状态语义。

本轮设计原则如下：

- 只有 `create_artifact` 显式理解 artifact
- `Read/Edit/Write` 保持纯文件工具语义
- artifact 与文件工具的联动只发生在 registry / projection / renderer 这一小段 read-model 层
- `TurnHarness`、planner、通用 tool execution contract 不应因为 artifact 引入全局分支

## 方案选择

### 方案 A：正式工具原生化

本轮采用。

做法：

- 把 `create_artifact` 作为正式 `ToolDefinition + ToolHandler`
- 走现有 `ToolOrchestratorService -> ChatTurnStep -> chat_events` 主管线
- 新增 artifact registry / resolver
- 新增 artifact 专属 block renderer

优点：

- 与现有 tool ledger 和 transcript 体系一致
- 与 append-only 聊天历史兼容
- 后续扩展为 share/export/workspace 时有稳定锚点

### 方案 B：assistant 文本块内嵌特殊 JSON / code fence

不采用。

原因：

- 会绕开正式 tool runtime
- 很难和 `chat_turn_steps`、恢复、联动、上下文投影保持一致
- 后续大概率仍需重构回正式工具体系

### 方案 C：独立 artifact 工作区系统

不采用。

原因：

- 明显超出当前需求范围
- 会把“回复增强能力”膨胀成“产物管理子系统”

## 工具协议设计

### `create_artifact` ToolDefinition

`create_artifact` 作为标准 `ToolDefinition` 注册到 runtime registry。

建议能力描述：

- 用于在回答中发布一个内联可渲染 artifact
- artifact 必须是自包含 HTML 或 SVG
- 首次创建后，应优先通过返回的 `sourcePath` 配合 `Read/Edit/Write` 持续修改
- artifact 默认服务于回答说明、可视化分析、交互解释，而非取代整个回答

建议参数：

- `id`
  - artifact 稳定标识
  - kebab-case
- `type`
  - `html | svg`
- `title`
  - 用户可见标题
- `source`
  - 完整自包含内容

建议对模型的额外提示：

- 首次创建 artifact 时必须提供完整 `source`
- 创建成功后，如需改进同一个 artifact，优先读取并编辑返回的 `sourcePath`
- 不要每次为了微调而重发整段新的 artifact `source`
- 该工具适合用于图表、表格、表单、计算器、可视化解释页面
- 输出应注重布局、视觉层级、可读性和基础可访问性

### tool result contract

成功时返回：

- `ok`
- `artifactId`
- `title`
- `type`
- `sourcePath`
- `bytes`

失败时返回：

- `ok`
- `error`
- `reason` 或必要的错误细节

这里不引入 `summary` 回传，也不依赖“总结后再喂回模型”的二次派生描述。

## 数据模型设计

### Artifact registry 记录

为了支持重启恢复、group 切换重建和跨 turn 关系判断，v1 需要新增一份很小的持久化 registry。

建议字段：

- `artifactId`
- `groupId`
- `title`
- `type`
- `sourcePath`
- `originTurnId`
- `createdAt`
- `lastUpdatedAt`

这个 registry 只保存稳定身份与定位信息，不保存每次编辑历史。编辑顺序仍由现有 append-only ledger 负责。

### 文件存储

原生平台使用稳定路径存储 artifact 文件，例如：

`{app_documents}/artifacts/{groupId}/{artifactId}.html`

本轮不以“多版本多文件”为基础设计，而采用：

- 一个 artifact 一个稳定文件路径
- 后续 `Read/Edit/Write` 围绕同一路径持续修改

这样更符合“先创建一个 artifact，再逐步改好它”的使用方式。

### 版本语义

v1 不把 `v1/v2/v3` 作为底层存储主概念。

原因：

- 同一 artifact 的编辑历史已经存在于完整 tool transcript 中
- 当前需求的重点是同 turn 内原位刷新与跨 turn 的快照语义
- 如果一开始引入显式版本链，会和“稳定路径持续编辑”形成重复抽象

版本展示语义仅在跨 turn UI 表达中作为可选增强：

- 同 turn 内默认不强调版本
- 跨 turn 如果同一 artifact 再次出现，可以把新卡片视为较新的展示版本

## 同 turn / 跨 turn 展示语义

### 同一 turn 内

同一 turn 内，artifact 在用户感知上应当是回答正文中的同一块内容。

规则如下：

1. 第一次 `create_artifact` 成功后，在当前 assistant turn 中插入一张 `ArtifactBlock`
2. 后续同一 turn 中若模型通过 `Edit/Write` 修改该 artifact 文件：
   - 不新增第二张 artifact 卡片
   - 刷新原有卡片的预览内容
3. 用户看到的是“这一轮回答中的同一部分内容正在完善”，而不是一串重复卡片

### 跨 turn

跨 turn 后，历史回答应保留当时的展示快照。

规则如下：

1. 如果新的 turn 再次创建或继续修改同一 artifact 文件：
   - 在新 turn 中渲染新的 `ArtifactBlock`
2. 历史 turn 中旧卡片保留
3. 旧卡片显示轻量 stale 提示，例如“已在后续回复中更新”

这样可以同时满足：

- 当前回答内的内容连续性
- 历史回答的 append-only 时间语义

## 工具联动设计

### 基本原则

`create_artifact` 是唯一显式懂 artifact 的工具。

`Read/Edit/Write` 保持原有独立 contract，不增加 artifact 专属字段，不增加 artifact-aware 分支。

artifact 联动只通过“文件路径命中 + registry / resolver 推断”发生。

### 联动方式

1. `create_artifact` 创建 artifact 文件并登记 registry
2. tool result 返回 `sourcePath`
3. 模型后续使用已有 `Read/Edit/Write` 读取或修改这个路径
4. artifact resolver 在构建 read model 时，通过已登记的 `sourcePath` 集合判断：
   - 某次 `Write/Edit` 是否修改了 artifact 文件
   - 该修改发生在当前 turn 还是后续 turn
5. UI 层基于 resolver 结果决定：
   - 同 turn 刷新现有卡片
   - 跨 turn 生成新卡片并把旧卡片标 stale

### 为什么不在 `Write/Edit` 返回中显式带 `artifactId`

本轮明确不这么做。

原因：

- 会污染通用文件工具 contract
- 会把 artifact 语义扩散到 execution 层
- 不利于保持“artifact 是一个局部 read-model 能力”这一边界

## 持久化与恢复设计

### 持久化真相来源

artifact 的“当前该如何展示”不能依赖内存中的临时关联。

必须持久化的最小事实包括：

- 哪些文件是 artifact 文件
- 某个 artifact 首次出现在哪个 turn
- 当前 group 下有哪些 artifact registry 记录

编辑历史与工具顺序则继续依赖：

- `chat_turn_steps`
- `chat_events`

### 重启恢复

App 被杀或退出后，artifact 运行时缓存失效。恢复策略如下：

1. 读取当前 group 的 artifact registry
2. 读取当前 group 的 turn ledger
3. 重新解析哪些 `Write/Edit` 命中了 artifact 文件
4. 重建每个 turn 中应显示的 artifact block
5. 重新判断哪些旧卡片应标 stale

v1 只保证恢复到“最后一个成功持久化的文件状态”，不承诺恢复流式中的未落盘中间态。

### group 切换 / reload

group 切换与重启属于同一类问题。

规则如下：

- artifact 内存态只能作为即时缓存，不能作为关联真相
- 切换 group、reload group、重新进入 group 时，artifact runtime cache 必须失效
- 重建只依赖当前 group 的持久化 registry、turn ledger 和文件内容
- resolver 应按 `groupId` 作用域工作，避免跨 group 串台

## 上下文与 transcript 规则

本轮不引入 artifact 专属 summary 回投。

原因：

- 当前项目明确强调 transcript fidelity
- append-only 历史中不应再插入“派生总结文本”替代真实 tool/use 结果
- artifact 的编辑与展示关系应尽量由真实 tool transcript 和局部 read model 解释，而不是靠新的总结层

因此：

- `create_artifact` 在模型上下文中仍表现为标准 tool use / tool result
- `Write/Edit` 在模型上下文中仍表现为普通文件工具
- 不额外创造一套“artifact 摘要回传协议”

## 渲染与安全沙盒

### 展示结构

聊天 UI 中新增 artifact 专属 block renderer，但不新增第二套消息状态机。

建议结构：

- `ArtifactBlock`
- `ArtifactPreviewSurface`
- `ArtifactDetailPage`

其中：

- block 负责标题、stale 提示、源码入口、展开入口
- preview surface 负责 WebView / source fallback
- detail page 负责全屏查看

### 安全边界

artifact 首期只允许本地沙盒前端交互。

要求如下：

- 不注册 JS -> Dart bridge
- 不允许 artifact 内再次调用模型或工具
- 默认阻断外部脚本与外部网络请求
- 允许自包含 inline `style` / `script`

这与“渲染型工具无额外副作用”的目标保持一致。

### Web 平台降级

首发正式验收平台为：

- Android
- iOS
- macOS

Flutter Web 首期只做降级兼容思路，不作为完整联动验收门槛。

原因：

- 当前设计依赖稳定文件路径与原生平台落盘恢复
- Web 的文件持久化与路径语义天然更复杂

因此 v1 可以接受：

- Web 支持基础初次渲染
- 但不承诺完整“`sourcePath` + `Edit/Write` 持续联动”体验

## 最小落地结构

### 新增能力

v1 建议新增如下局部能力：

1. `create_artifact` ToolHandler
2. artifact registry 持久化表 / repository
3. `ArtifactRegistryService` 或 `ArtifactResolverService`
4. artifact block projection helper
5. `ArtifactBlock` / `ArtifactDetailPage`

### 应改动的现有位置

建议只改这些位置：

- tool runtime registry：注册 `create_artifact`
- tool handler 层：新增 `create_artifact`
- 持久化层：新增 artifact registry repository / table
- chat block 构建链路：支持从 ledger 派生 artifact block
- UI renderer：接入 artifact block

### 应刻意避免的大改动

本轮应尽量不碰：

- `TurnHarness` 主循环语义
- planner decision contract
- `ToolOrchestratorService` 的全局分支结构
- `Write/Edit` 的 contract
- 通用 `ToolWorkflowStep` 生命周期
- ask-user-question / confirmation 主语义

## 失败态设计

### 1. 创建失败

当 `create_artifact` 参数非法、文件写入失败、内容不合法时：

- tool result 返回失败
- 不创建 artifact registry 记录
- 不生成 artifact block

### 2. 渲染失败

当 artifact 文件已成功写入，但预览加载失败时：

- 仍视为 tool 执行成功
- block 显示 `Preview unavailable` 一类降级态
- 允许查看源码或继续修改修复

### 3. 编辑后内容损坏

当后续 `Edit/Write` 把 artifact 改坏时：

- transcript 保持真实记录
- 最新 artifact 预览显示失败态
- 不自动回滚
- 允许后续继续修复

## 测试与验收标准

### 功能验收

需要验证：

1. 模型可通过 `create_artifact` 在回答中插入自包含 HTML/SVG artifact
2. 同一 turn 内后续 `Edit/Write` 修改 artifact 文件时，原卡片自动刷新
3. 跨 turn 继续修改同一 artifact 文件时，新 turn 渲染新卡片，旧卡片标 stale
4. artifact 默认作为回答增强内容，而非唯一产物

### 架构验收

需要满足：

1. `Write/Edit` contract 不增加 artifact 专属字段
2. `TurnHarness`、planner、通用 tool execution 不因 artifact 新增全局特判
3. artifact 联动主要收敛在 registry / resolver + projection / renderer 层
4. transcript 仍保持 append-only 真实语义

### 恢复验收

需要验证：

1. App 重启后能恢复 artifact 展示
2. group 切换后 artifact runtime context 不串台
3. 回到原 group 后，能正确重建该 group 的 artifact blocks 与 stale 状态

### 平台验收

正式验收平台：

- Android
- iOS
- macOS

Web 为降级兼容，不作为首期完整联动门槛。

### 自动化测试建议

至少覆盖：

1. artifact registry / resolver 单测
2. `create_artifact` handler 单测
3. 同 turn block 合并与刷新逻辑测试
4. 跨 turn 新 block + stale 标记测试
5. 重启 / group reload 后 read model 重建测试

### 手动验证建议

原生平台至少验证以下流程：

1. 创建一个图表或表格 artifact
2. 同一 turn 内通过 `Edit/Write` 改进外观或内容，观察卡片原位刷新
3. 下一 turn 再次修改同一 artifact，观察新卡片与旧卡片 stale 状态
4. 退出 App 重进，验证恢复结果
5. 切换 group 后再切回，验证不串台且可正确重建

## 总结

本轮设计把 Inline Artifact Visualizer 定义为一种“回答增强型渲染工具”，而不是产物系统或新的全局 agent loop 语义。

它通过：

- 正式 `create_artifact` tool
- 稳定文件路径
- 小型 artifact registry
- 基于路径命中的局部 resolver / projection
- 同 turn 原位刷新、跨 turn 新卡片 + stale

在尽量小的改动范围内，把“在回复里直接交付可交互界面”的能力接入现有架构。

这个方案的关键价值在于：

- 保住 append-only transcript 和 tool ledger 的真实性
- 不污染 `Write/Edit` 与主 loop contract
- 能覆盖重启、group 切换、历史回看等真实使用场景
- 为后续逐步扩展成更强的 artifact/workspace 能力留下空间
