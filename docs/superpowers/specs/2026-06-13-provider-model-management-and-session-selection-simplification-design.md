# Provider / Model 管理与 Session 选择语义简化设计

## 1. 背景

当前 provider / model 相关设计同时承载了三类语义：

- 设置页中的 provider / model 管理
- 首页与当前会话的实际运行时选择
- `defaultProviderId` / `defaultModelId` 这套全局兜底状态

这三类语义在产品上已经开始互相干扰：

1. 设置页承担了过多“运行时状态展示”职责，但用户真正来这里主要是管理 provider 和模型资源，而不是维护一套抽象的默认值。
2. 首页与当前会话已有自己的 runtime 选择语义，`default provider / model` 会制造第二套心智模型，让用户难以理解“当前在用谁”和“默认是谁”的区别。
3. `defaultProviderId` / `defaultModelId` 虽然最初用于首启和兜底，但现在已经被多个仓库层、runtime 层、空态判断路径复用，形成“实现方便但产品语义不自然”的结构。

与此同时，侧模型（side model）、生图模型、多模态能力也需要在这轮收敛中明确边界，否则容易重新引入新的隐式默认。

因此，这次需要把主模型、side model、生图模型三类语义分开，并删除 `default provider / model` 这套用户侧概念。

## 2. 目标

本次设计目标：

1. 删除 `defaultProviderId` / `defaultModelId` 这套产品语义与持久化状态。
2. 让设置页回归为 `provider / model 管理页`，而不是默认值维护页。
3. 当前会话的主模型选择继续以 session runtime 为第一事实源。
4. 新建会话时优先继承当前 session runtime；若无可继承 runtime，再回退到排序后的第一个 provider 的第一个 model。
5. side model 改为 provider 级可选配置，不引入新的默认体系。
6. 生图模型走独立入口，单独维护全局 image generation provider / model，不与聊天主链路绑定。
7. 本轮不引入新的多模态能力探测或设置承诺。

## 3. 非目标

本次不处理以下事项：

- 不重做首页已有的模型选择交互。
- 不在本轮为模型能力增加新的自动探测逻辑。
- 不把 side model 扩展成 session 级独立编辑交互。
- 不把生图模型并回聊天 provider 配置页。
- 不重做 provider / model 排序 UI；但新的 fallback 规则默认基于排序后的列表语义。

## 4. 当前问题归纳

### 4.1 `default provider / model` 是低价值高心智负担概念

对用户来说，真正关心的是：

- 当前会话正在使用哪个模型
- 新开对话时是否延续当前选择
- 设置页里如何增删 provider、维护模型列表

“默认 provider / 默认模型”并不是一个高频产品概念。它更多是实现层为了首启、脏数据回退和草稿会话初始化而保留下来的状态锚点。继续把这套概念暴露到设置页，会让页面围绕低价值状态组织。

### 4.2 设置页职责和运行时语义混在一起

设置页目前同时承担：

- provider 资源管理
- 运行时状态展示
- 默认值维护

这会导致页面视觉重心被“当前默认模型”之类的静态信息占据，而不是围绕用户最常见的管理动作展开。

### 4.3 现有兜底机制对 `default*` 依赖过重

当前多个路径使用 `selected -> default -> first` 解析链：

- `AppSettingsRepository.getLlmConfig()`
- `getSelectedModelIdSync()`
- `getSelectedModelCapabilityOverrideSync()`
- provider 删除后的 `_normalizeSelection()`
- 新建草稿会话的 `createDraftRuntime()`
- 空态“是否已配置模型”判断

这说明 `default*` 不只是 UI 状态，而是被用作实现上的回退锚点。但这些回退其实可以用更简单的规则替代，不必再保留用户侧“默认”概念。

## 5. 核心设计

## 5.1 主模型选择语义

主模型只保留两层事实：

1. `当前 session runtime`
2. `全局 selected 选择 / 列表首项回退`

删除以下概念：

- `default provider`
- `default model`
- `设为默认`

### 5.1.1 当前会话优先

只要存在当前 session runtime，聊天主链路中的真实运行模型都以它为准。

这包括：

- 实际发送时使用哪个 provider / model
- 当前输入区展示什么模型
- 当前会话后续 turn 使用什么 provider style

### 5.1.2 新建会话规则

新建会话时，初始化顺序改为：

1. 若当前 `currentSessionRuntimeConfigProvider` 存在，且其主 provider / model 仍然有效，则直接继承当前 runtime。
2. 若当前 runtime 不存在，或指向的 provider / model 已失效，则回退到“排序后的第一个 provider 的第一个 model”。

这里不再经过 `defaultProviderId` / `defaultModelId`。

### 5.1.3 全局 selected 的定位

在删除 `default*` 之后，全局仍可保留一份最小 `selectedProviderId` / `selectedModelId`，其职责仅限于：

- 在没有当前 session runtime 的同步读取场景下提供一个轻量锚点
- 当当前 runtime 不可用时，为部分非 session 场景提供最近一次选择偏好

它不再表达“默认”，也不应在设置页被当作产品概念展示。

### 5.1.4 唯一兜底规则

所有 provider/model 解析链统一为：

- 先尝试显式选择或当前 runtime
- 无效时回退到排序后的第一个 provider
- 在该 provider 下再回退到第一个 model

不再存在第二条 `default` 回退链。

## 5.2 设置页职责收缩

设置页中与主模型相关的职责改成：

- 新增 / 编辑 / 删除 provider
- 维护模型列表
- 执行模型探测
- 调整 provider / model 顺序
- 维护 side model

设置页不再承担：

- 展示“默认 provider / 默认模型”
- 提供“设为默认”动作
- 作为当前会话主模型的最终决策页

这里的核心原则是：设置页管理资源，首页与 session runtime 负责实际使用。

## 5.3 side model 语义

### 5.3.1 side model 是 provider 级配置

`side model` 定义为：

- 仅在当前 provider 内部选择
- 作为该 provider 的可选辅模型配置
- 不是跨 provider 的全局默认，也不是独立 session 级配置页中的状态

例如：

- Claude provider 的主模型可选 `Opus`
- 同一 provider 下可指定 `Haiku` 作为 side model

### 5.3.2 默认不指定

provider 默认不指定 side model。

未指定时，side model 的语义等同于：

- `side -> primary`

也就是 side task 默认沿用主模型，不强制引入额外配置。

### 5.3.3 用户有需要时再指定

只有当用户明确希望某个 provider 在 side task 中使用更轻或更快的模型时，才在该 provider 下单独指定 side model。

### 5.3.4 side model 失效规则

如果某个 provider 配置过 side model，但该模型后续被删除或失效，则：

- 直接清空 side model 配置
- 重新回到“未指定”，即 `side -> primary`

不再额外做自动改选或新的默认 side model 推断。

## 5.4 生图模型语义

### 5.4.1 生图模型走独立入口

生图模型不与聊天主 provider / model 绑定。

它的配置应通过独立入口维护一份全局：

- image generation provider
- image generation model

### 5.4.2 独立于聊天主链路

设计原因：

- 生图模型稀缺，通常不是每个聊天 provider 都有
- 没必要为了生图把主聊天 provider 配置复杂化
- 避免在设置页里重新引入“当前聊天 provider 是否也承担生图默认”的额外心智

因此：

- 当前聊天 provider 可以和生图 provider 完全不同
- 生图工具执行时只读取 image generation 独立配置
- 主模型去默认化，不影响生图模型的独立全局选择

## 5.5 多模态能力语义

本轮不新增“模型是否支持多模态”的新配置或探测契约。

原因：

- 现有自动探测效果不稳定
- 用户也尚未确认合适的长期交互方式

因此本轮 spec 中明确：

- 不新增新的多模态 capability 设置项
- 不承诺自动探测多模态能力
- 如现有代码里已有相关字段或能力缓存，本轮不以此为设计中心

## 6. 关键流程

### 6.1 新建会话

新建会话时：

1. 读取当前 `currentSessionRuntimeConfigProvider`
2. 校验其中主 provider / model 是否仍然存在
3. 若存在，继承该 runtime 作为新草稿会话的初始 runtime
4. 若不存在，取排序后的第一个 provider 的第一个 model
5. 若 provider 列表为空或目标 provider 无模型，则进入“尚未完成模型接入”空态

### 6.2 当前会话切换模型

当前会话中切换主模型时：

1. 更新当前 session runtime
2. 可同步更新最小全局 `selectedProviderId` / `selectedModelId`
3. 不再写入任何 `defaultProviderId` / `defaultModelId`

### 6.3 provider 删除

删除 provider 时：

1. 若当前 session runtime 指向被删 provider，则该 runtime 需要重新归一化
2. 归一化结果直接回退到排序后的第一个 provider 的第一个 model
3. 若删除后已无 provider 或模型，则进入未配置空态

### 6.4 model 删除

删除某个 model 时：

1. 若它是当前 session runtime 的主模型，则主模型回退到当前 provider 的第一个可用 model
2. 若当前 provider 已无模型，则主 runtime 失效并进一步走 provider 首项回退
3. 若它是 side model，则 side model 直接清空，重新等同主模型

## 7. 数据模型与持久化调整

### 7.1 `LlmSelectionState`

去掉：

- `defaultProviderId`
- `defaultModelId`

保留或收缩为：

- `selectedProviderId`
- `selectedModelId`

它只表达“最近一次全局选择”，不表达默认。

### 7.2 provider 配置

provider 配置层需要能承载：

- provider 基础连接信息
- 模型列表
- 可选 side model id

该 `side model id` 必须满足：

- 只引用本 provider 的模型列表
- 允许为空

### 7.3 image generation 配置

独立配置继续单独保存：

- image generation provider id
- image generation model id

不与主聊天 selection 状态合并。

## 8. UI 方向

### 8.1 设置页

设置页应明显去默认化：

- 不再强调“默认 provider / 默认模型”
- 不再提供“设为默认”
- 顶部不围绕默认状态做视觉中心

### 8.2 provider 管理页

provider 管理页重点围绕：

- provider 列表
- 模型探测
- side model 指定
- 排序
- 编辑与删除

而不是展示当前运行时是谁。

### 8.3 首页

本轮不改首页已有模型选择交互，但文档上明确：

- 首页/当前 session 负责实际选择
- 设置页不再承担默认语义

## 9. 迁移策略

本次允许硬切：

1. 读取旧 `selection_json` 时，不再保留 `default_provider_id` / `default_model_id`
2. 若旧数据存在 `default*`，仅在一次性归一化时把它折叠进 `selected*` 或首项 fallback
3. 之后重新写回只包含 `selected*` 的新结构

目标是快速消除双轨状态，而不是长期兼容。

## 10. 风险与防护

### 10.1 风险：当前 session runtime 指向失效模型

防护：

- 新建会话前必须做有效性校验
- 失效时直接回退首项，而不是保留脏引用

### 10.2 风险：删除 `default*` 后部分同步读取路径失效

防护：

- 所有同步/异步解析路径统一改成 `selected -> first`
- 测试必须覆盖仓库、session runtime、空态判断、首页切换

### 10.3 风险：side model 重新引入新默认体系

防护：

- side model 默认不指定
- 未指定就等同主模型
- 失效即清空，不做二次自动选举

## 11. 测试范围

本次实现至少需要覆盖：

1. `LlmSelectionState` 去掉 `default*` 后的归一化与持久化
2. 新会话继承当前 runtime
3. 当前 runtime 失效时回退到第一个 provider 的第一个 model
4. provider 删除后的 selection/runtime 归一化
5. model 删除后的 selection/runtime 归一化
6. side model 默认空值与失效清空语义
7. 生图配置不受主聊天 selection 去默认化影响
8. 设置页 / provider 管理页不再展示默认相关动作与文案

## 12. 结论

本次设计的核心不是“把默认 UI 隐藏一下”，而是把 provider/model 的产品语义真正简化成三套清晰边界：

- 主聊天模型：session-first，失效时首项回退
- side model：provider 级可选配置，默认等同主模型
- 生图模型：独立入口、独立全局配置

这样既能删除低价值的 `default provider / model` 心智负担，又能保留当前架构下真正需要的运行时兜底与专项模型配置能力。
