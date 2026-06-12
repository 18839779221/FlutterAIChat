# Session 级 Runtime 配置设计

## 1. 背景

当前应用中的 provider / model 选择仍然是全局状态：

- `AppSettingsRepository` 持有单份 `selectedProviderId` / `selectedModelId`
- `ChatSessionCoordinator.selectGroup(...)` 切换会话时，只切 `currentGroup` 与消息，不切换运行时模型配置
- 新建会话只从当前全局配置继承 `lockedProviderStyle`
- 发送链路、上下文预算、能力解析都默认从全局配置读取当前 runtime

这套设计在“单线程、单活跃会话、全局单模型”的早期阶段足够简单，但已经不再符合当前产品目标：

- 不同 session 应该可以使用不同的 provider / model
- 切换 session 时，运行时配置应该同步切换
- 在某个已有 session 中切换 provider / model，只应影响当前 session
- 新建 session 时，仍然应该从全局默认配置出发
- 后续多 agent 并行时，session 维度还需要继续承载能力、预算、策略等 runtime 绑定

因此，本次不应继续在全局选择态上打补丁，而应正式引入 session 级 runtime 配置层。

## 2. 目标

本次设计目标：

1. provider / model 选择改为以 session / group 为主维度
2. 切换 session 时，同步恢复该 session 的 runtime 配置
3. 在已有 session 内切换 provider / model 时，只影响当前 session
4. 新建 session 时，以全局默认 provider / model 作为初始值
5. 删除已经过时的 `lockedProviderStyle`
6. 为后续 session 级 capability / budget / 多 agent runtime 扩展预留稳定边界

## 3. 非目标

本次不尝试解决以下问题：

- 不实现多 agent 并行运行时，只为其预留架构边界
- 不在本次把 capability cache、budget policy、tool policy 全量迁移为 session 持久态
- 不为历史会话提供兼容迁移或精确恢复
- 不保留 `lockedProviderStyle` 兼容语义

## 4. 当前问题归纳

### 4.1 全局选择态与 session 语义冲突

`AppSettingsRepository.getLlmConfig()` 当前会把“全局当前选择”直接当成“当前会话正在使用的 runtime 配置”。这会导致：

- 切换 session 不会切 provider / model
- 在一个会话中改模型，会隐式污染所有其他会话
- 会话之间无法形成稳定的运行时边界

### 4.2 `lockedProviderStyle` 已经过时

`lockedProviderStyle` 来自旧设计，背后假设是“会话内 provider style 不可变”。但当前产品已经确认：

- 在已有 session 中切换 provider + model 是允许的
- 这次切换只影响当前 session

因此，`lockedProviderStyle` 的前提已经不成立。继续保留它只会让：

- `group` 元数据承担过时约束
- `TurnHarness` / send-flow 继续依赖错误的 active style 来源
- session runtime 设计被旧字段牵制

本次应直接删除该字段，而不是降级保留。

### 4.3 `SessionRuntimeMarker` 不是承载配置的正确位置

当前 `SessionRuntimeMarker` 只负责 session 级 runtime reminder marker，例如：

- 跨天后避免重复注入日期提醒
- 组装 turn 级 `runtime_context`

它表达的是“短期运行时提醒状态”，不是“稳定的 session 运行时配置”。把 provider / model / capability 也塞进去，会把两类语义混在一起。

## 5. 核心设计

### 5.1 引入独立的 `SessionRuntimeConfig`

新增一层独立的 session runtime 配置模型，建议命名为：

- `SessionRuntimeConfig`

最小字段集：

- `id`
- `groupId`
- `providerId`
- `modelId`
- `providerStyle`
- `updatedAt`

语义：

- 表示某个 session 当前绑定的 LLM runtime 选择
- 是切 session、发消息、解析能力、预算推导时的第一事实源
- 与全局默认配置分离

### 5.2 职责分层

改造后职责边界如下：

#### `AppSettingsRepository`

继续负责：

- provider catalog 持久化
- 全局默认 provider / model
- provider 编辑、删除、模型维护

不再负责：

- 当前 session 的真实 runtime 选择

它的角色从“当前运行时配置入口”收缩为“全局默认配置与 provider 目录入口”。

#### `SessionRuntimeConfigRepository` / `Service`

新增，负责：

- 读写某个 `groupId` 对应的 runtime 配置
- 为草稿 session 维护未落库的 runtime 配置
- 在 session 切换时恢复 runtime
- 在当前 session 切换 provider / model 时只更新当前 session

#### `ChatGroup`

回归为纯 session 元数据：

- `title`
- `systemPrompt`
- `workspaceId`
- 时间字段
- 其他与会话本身稳定相关的元数据

不再承载：

- provider style 锁定
- 当前 provider / model 绑定

#### `ChatTurn`

继续保留：

- `providerStyle`
- `modelName`

它表达的是：

- 这个 turn 当时实际使用的 runtime 事实

也就是说，session runtime 可以在 turn 之间切换，但 turn 历史记录必须冻结。

### 5.3 新规则

本次设计引入以下新规则：

#### Rule A：session runtime 是可变的

同一个 session 内，用户可以在 turn 之间切换 provider / model。

#### Rule B：turn runtime 是冻结的

一旦某个 turn 开始执行并写入记录，该 turn 的 `providerStyle` / `modelName` 表示当时真实运行时，不随 session 后续切换而改变。

#### Rule C：全局默认只影响新 session

全局默认 provider / model 仅在新建 session 时用于提供初始 runtime 配置，不回流影响已有 session。

#### Rule D：session runtime 优先于全局默认

只要存在当前 session，所有实际 runtime 解析都必须优先读取该 session 对应的 `SessionRuntimeConfig`，而不是全局 `selectedProviderId` / `selectedModelId`。

## 6. 关键流程设计

### 6.1 新建 session

创建新 session 时：

1. 从全局默认 provider / model 读取初始值
2. 在内存中生成一份草稿 `SessionRuntimeConfig`
3. 将其与当前草稿 `ChatGroup` 绑定

此时还不要求立刻写库，因为当前草稿 session 可能尚未发送任何消息。

### 6.2 草稿 session 内切换 provider / model

如果当前 session 还未落库：

- 只更新内存中的草稿 `SessionRuntimeConfig`
- 不回写全局默认

这样可以保证：

- 草稿 session 立即显示与使用最新选择
- 不会污染其他 session
- 首次发送时能够按草稿 session 的 runtime 落地

### 6.3 草稿 session 首次发送

首次发送时：

1. 先落库 `ChatGroup`
2. 拿到正式 `groupId`
3. 将当前草稿 `SessionRuntimeConfig` 写为正式记录
4. 当前 turn 按该 session runtime 执行

这保证：

- 新会话从全局默认出发
- 但如果用户在首次发送前已经切过 provider / model，最终仍以草稿 session 的真实选择落库

### 6.4 切换到已有 session

用户切换到某个已存在 session 时：

1. 先切换 `currentGroup`
2. 加载该 `groupId` 对应的 `SessionRuntimeConfig`
3. 更新当前页面使用的 runtime 视图状态
4. model chip、send-flow、capability/budget 解析全部跟随切换

这一步不需要改写全局默认。

### 6.5 在已有 session 内切换 provider / model

如果当前 session 已落库：

- 只更新该 `groupId` 对应的 `SessionRuntimeConfig`
- 当前 session 后续 turn 使用新的 runtime
- 其他 session 不受影响
- 全局默认不受影响

### 6.6 新建 session 的初始值来源

用户确认要求：

- 在已有 session 内切换 provider + model，只影响当前 session
- 新建 session 时，基于“上次选择的全局配置”作为新 session provider / model

因此全局默认配置仍然保留，且与 session runtime 并行存在，但两者语义不同：

- 全局默认：未来新会话的起点
- session runtime：当前会话的真实运行时绑定

## 7. Runtime 配置解析边界

### 7.1 停止把 `AppSettingsRepository.getLlmConfig()` 视为当前 session runtime 入口

当前 `getLlmConfig()` 的问题不是返回结构，而是输入事实源错误。改造后应拆出新的解析入口，例如：

- `SessionLlmConfigResolver`

它的职责是：

1. 读取当前 session runtime 配置
2. 在 provider catalog 中找到对应 provider
3. 校验 model 是否仍存在
4. 解析 `providerStyle`
5. 输出实际执行所需的 `LLMConfig`

### 7.2 解析优先级

运行时解析优先级应为：

1. 当前 session 对应的 `SessionRuntimeConfig`
2. 如果是草稿 session，则读取草稿 runtime 配置
3. 仅在新建 session 初始化时，才读取全局默认

不允许 send-flow、session-context、capability resolver 直接绕回全局选择态。

## 8. 与 capability / budget 的关系

这次改造不能只解决 `modelId`，而应为后续 session 级能力改造预留结构。

### 8.1 当前问题

现在能力与预算解析大量依赖当前 runtime config，而 runtime config 又依赖全局选择态，因此：

- capability 事实天然是“全局当前值”
- budget 评估天然是“全局当前值”
- 无法支持不同 session 并行持有不同能力视图

### 8.2 本次预留边界

本次先不要求把所有能力信息都持久化到 session runtime，但必须让能力解析的输入边界改正确：

- `ModelCapabilityResolver`
- `SessionContextService`
- `SessionTokenBudgetService` 的上游 runtime 解析

都应从当前 session runtime 配置出发。

### 8.3 后续扩展方向

未来可以在 `SessionRuntimeConfig` 层或其邻接对象上扩展：

- session 级 capability snapshot
- session 级 budget binding
- session 级 tool policy
- agent 级 runtime override

也就是说，本次先把“session runtime 绑定”从全局状态中抽离出来，后续 capability 改造直接沿这一层扩展，不再重新拆构。

## 9. 数据重建策略

### 9.1 删除 `lockedProviderStyle`

本次直接删除：

- `ChatGroup.lockedProviderStyle`
- `chat_groups.locked_provider_style`
- 所有基于 `lockedProviderStyle` 的 UI 展示与运行时判断

不保留兼容语义。

### 9.2 新增 `session_runtime_configs` 表

新增独立表，建议字段：

- `id INTEGER PRIMARY KEY AUTOINCREMENT`
- `group_id INTEGER NOT NULL UNIQUE`
- `provider_id TEXT NOT NULL`
- `model_id TEXT NOT NULL`
- `provider_style TEXT NOT NULL`
- `updated_at INTEGER NOT NULL`

约束：

- 一个 session 仅有一条当前 runtime 配置
- 该配置可被覆盖更新

### 9.3 历史数据处理

用户已明确说明：

- 不需要过度考虑兼容以前
- 即使卸载重装也是可接受的

因此本次采用硬切策略，而不是兼容迁移策略。

建议做法：

1. 数据库 schema 直接升级到新版本
2. 删除 `chat_groups.locked_provider_style`
3. 新增 `session_runtime_configs`
4. 对旧会话数据不做 provider / model 归属回填
5. 如当前升级路径实现复杂或风险偏高，可直接 drop 并重建会话相关表

这次的优先级是：

- 保证新架构语义正确
- 保证代码边界干净
- 不为了旧数据兼容保留脏逻辑

换句话说，本次允许以“重建会话数据”为代价换取架构简化。

## 10. 对现有模块的影响

### 10.1 `ChatSessionCoordinator`

需要新增能力：

- 管理草稿 session runtime
- 切 session 时同步加载 runtime config
- 新建 session 时从全局默认初始化草稿 runtime

不再维护：

- `syncDraftGroupProviderStyle()`

这类基于旧 `lockedProviderStyle` 的修补逻辑应被移除。

### 10.2 `ChatInput`

model chip 的显示与切换逻辑应改为：

- 显示当前 session runtime 对应的 model
- 切换 provider / model 时只更新当前 session runtime

不再通过全局 `selection.selectedProviderId / selectedModelId` 直接驱动当前会话显示。

### 10.3 `ChatSendCoordinator`

发送前的 runtime 解析应改为：

- 从当前 session runtime 读取 provider / model / style
- 在创建 turn 时写入真实的 `providerStyle` / `modelName`

### 10.4 `TurnHarness`

`activeApiStyle` 不再从 `group.lockedProviderStyle` 获取，而应从：

- 当前 turn 自身的 provider style
- 或当前 session runtime 解析结果

### 10.5 `SessionContextService`

构建 planner 上下文与预算时，读取的 runtime config 必须来自当前 session，而不是全局当前选择态。

### 10.6 Drawer / 调试面板

凡是展示“当前 session provider 信息”的 UI，必须改为读取当前 session runtime，而不是 `ChatGroup` 上的旧字段。

## 11. 测试要求

本次改造至少需要覆盖以下场景：

### 11.1 repository / service 层

- 新建 session 时从全局默认初始化草稿 runtime
- 草稿 session 切换 provider / model 不影响全局默认
- 草稿 session 首次发送后能正确落库 runtime config
- 已有 session 切换 provider / model 只更新当前 session
- 切换 session 时能恢复各自 runtime config

### 11.2 widget / coordinator 层

- model chip 随 session 切换同步更新
- 在 session A 中切换模型后，session B 不受影响
- 返回 session A 时，model chip 恢复 A 的选择

### 11.3 send-flow / runtime 层

- 新 turn 记录正确的 `providerStyle` 与 `modelName`
- capability / budget 解析使用当前 session runtime
- 删除 `lockedProviderStyle` 后，planner / send-flow 不再依赖 group 旧字段

### 11.4 migration

- 新 schema 能创建 `session_runtime_configs`
- 旧数据迁移时，能够为可识别会话补出 runtime config
- 无法识别时，能够安全回退到全局默认

## 12. 风险与取舍

### 12.1 风险

- 当前大量 runtime 调用路径默认依赖 `AppSettingsRepository.getLlmConfig()`，遗漏替换会导致局部仍然读取全局状态
- 草稿 session 与已落库 session 共存时，需要明确临时 runtime state 的单一事实源

### 12.2 取舍

本次选择：

- 不做“最小补丁”
- 不复用 `SessionRuntimeMarker`
- 不保留 `lockedProviderStyle`
- 不为旧会话维持兼容迁移
- 必要时直接重建会话相关数据

而是直接建立新的 session runtime 层。

这样做的成本更高，但能一次性把语义边界摆正，避免后续做 session 级 capability、多 agent runtime 时再拆第二次。

## 13. 结论

本次 provider / model 改造的本质，不是“把 model 选中态从全局搬到 session”，而是：

- 正式引入 session 级 runtime 配置层
- 让全局默认与当前 session 运行时彻底解耦
- 删除已失效的 provider 锁定设计
- 为后续 session 级 capability / budget / 多 agent runtime 扩展建立稳定边界

在该设计下：

- 已有 session 内切换 provider + model，只影响当前 session
- 切 session 时，runtime 同步切换
- 新建 session 时，从全局默认起步
- 未来更复杂的 session 级能力，也有清晰的挂载位置
