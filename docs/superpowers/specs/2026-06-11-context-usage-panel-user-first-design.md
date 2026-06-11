# Context Usage 面板用户视角重构设计

## 摘要

当前 App 内的 `context usage` 面板已经具备较完整的预算与分段数据，但整体仍更像诊断页而不是用户面板：

- 主信息以预算字段和技术口径为中心
- 分段文案直接暴露内部实现结构
- 缺少一眼可扫的整体占用形状
- 用户难以快速判断“谁最占 context”
- 用户也难以定位“具体是哪一次操作最重”

本设计不重新发明新的上下文预算体系，也不引入新的 LLM 解释层，而是在复用现有 `SessionContextInspectorService`、`ContextWindowSnapshot`、`ChatEvent` 与 tool result projection 数据的前提下，把面板重构为一张更接近 Claude Code 的“上下文占用地图”：

- 顶部先给整体占用图
- 中间给按重要度排序的分类占用
- 下面给最占 context 的 Top 5 操作
- 技术字段整体下沉到折叠区

目标是让用户打开面板后，先看到“用了多少”，再看到“哪一类最占”，最后看到“具体是哪几个操作最占”。

## 目标

### 体验目标

- 用户能在 1 秒内看懂当前上下文整体占用压力
- 用户能快速识别当前最主要的 context 消耗来源
- 用户能定位到具体是哪次工具 / 网页 / 文件操作最占
- 面板更有“打开看一眼”的价值，而不是只在排障时才会进入

### 架构目标

- 尽量复用现有数据，只做轻量二次加工
- 不新增额外 LLM 总结，不生成解释性长文案
- 不改变已有 compaction、budget、planner 语义边界
- 保留诊断数据，但不让它们占据主视觉与主叙事

## 非目标

- 不重做 composer 小圆环的主触发口径
- 不修改自动压缩或 trigger token 的算法
- 不引入 Claude Code 的 memory / MCP / skill 那种 coding-agent 专属分类体系
- 不在本轮给用户生成“为什么大”“建议怎么做”这类解释句
- 不把普通长对话也塞进 Top 5 重点列表

## 现状问题

### 1. 信息是对的，但主叙事不对

当前 bottom sheet 继续保留了：

- `planner 输入占触发阈值`
- `总窗口占比`
- `effective input 占比`
- `snapshot 覆盖至 turn`
- `recent completed turns`

这些字段对于诊断有价值，但不是用户最关心的第一问题。用户真正想知道的是：

- 现在整体占了多少
- 主要是哪一类内容吃掉了 context
- 具体是哪一次操作最重

### 2. 分段名称更像实现结构，不像用户来源

当前分段主要围绕：

- `system prompt`
- `runtime user context`
- `history summary`
- `recent completed turns`
- `current turn transcript`

它们能准确反映内部构成，但用户很难直接把它们映射成“最近聊天太长了”或“刚才那次网页抓取太重了”。

### 3. 缺少整体占用形状

现在的面板更接近一张数字清单。用户需要自己在脑内拼出：

- 整体还剩多少
- 每类大概是什么比例
- 哪些部分体量明显更大

这也是 Claude Code 那种 grid/waffle 可视化更容易被扫读的原因。

## 设计原则

### 1. 先结论，后归因，最后技术细节

主面板必须遵守以下顺序：

1. 整体占用
2. 分类占用
3. 具体大户
4. 技术字段

### 2. 信息结构向 Claude Code 学，视觉气质留在 App 内

本轮吸收 Claude Code 的是：

- 高密度、可扫读的整体占用图
- 分类优先、明细其次的层级
- 具体大户列表

但不直接复刻终端 / 控制台风格。面板仍应保持 App 当前的 surface、圆角、色彩和节奏。

### 3. 尽量用已有数据，不做重解释

Top 5 的对象命名优先直接取已有字段：

- `web_search` 取 `query`
- `fetch_webpage` 取 `url` 或 `title`
- `Read / Write / Edit / create_artifact` 取 `path`
- 其他工具取已有 `title / name / id / message`

只做简单拼接，不做额外总结。

### 4. 主视图只讲用户视角来源

一级分类必须让用户能直接理解来源，而不是暴露内部预算层。

## 信息结构

### 一、顶部总览

顶部区域由两部分组成：

1. 左侧主图
2. 右侧主数字

#### 1. 主图

采用紧密小圆角方块组成的 `waffle/grid`：

- 吸收 Claude Code 的“整体形状”优点
- 不做字符块终端风格
- 保持 App 内更柔和、更克制的 surface 语言

grid 负责表达：

- 已使用区域
- 各主要来源之间的占比差异
- 预留 / 剩余空间

#### 2. 主数字

右侧主数字区只保留最核心数据：

- 主视觉：`百分比`
- 副信息：`tokens / max context`

不在顶部附加解释句。

### 二、分类占用

分类区负责回答“哪一类最占”。

采用按占用从高到低排序的短条形图，每行只保留：

- 分类名
- tokens
- 百分比
- 一根对应比例的短条

#### 一级分类

一级分类收敛为：

- `最近对话`
- `工具 / 网页 / 文件结果`
- `历史摘要`
- `系统设定`
- `预留 / 剩余空间`

其中：

- 前四项参与动态排序
- `预留 / 剩余空间` 固定放在最后一行，不参与“问题来源”排序

#### 弱化细分

如果实现成本不高，可以在 `工具 / 网页 / 文件结果` 内部做弱化细分，例如：

- 网页
- 文件
- 其他工具

但它只能作为次级补充，不得抢占一级分类焦点。

### 三、Top 5

Top 5 只回答“具体是哪几个操作最占”。

#### 数据范围

只统计：

- `工具 / 网页 / 文件结果`

不统计：

- 普通长对话
- 技术保留项
- system prompt / summary

#### 排序

按当前实际进入 context 的 estimated tokens 从高到低排序。

如果不足 5 条，则显示实际条数。

#### 命名方式

每条使用：

`工具名 + 对象`

例如：

- `fetch_webpage · openai.com/pricing`
- `web_search · Claude Code context usage`
- `Read · /workspaces/demo/README.md`

并配合：

- `tokens + 百分比`
- 一个轻量 mini bar

不做复杂说明，不写解释句。

### 四、技术细节

技术细节整体下沉并默认折叠。

保留当前已有诊断字段，例如：

- `planner 输入占触发阈值`
- `effective input 占比`
- `自动压缩阈值`
- `snapshot 覆盖`
- `recent completed turns`

这些信息继续服务排障，但不应抢占主面板焦点。

## 数据映射建议

### 1. 系统设定

来源：

- `system prompt`
- `runtime user context`

### 2. 历史摘要

来源：

- `history summary`

### 3. 最近对话

来源：

- 当前 turn 与 recent completed turns 中的普通用户输入 / 交互文本

### 4. 工具 / 网页 / 文件结果

来源：

- 当前 turn 与 recent completed turns 中的 `toolResult / toolError`
- 继续复用现有 tool result context projection 的 planner-visible 文本

### 5. 预留 / 剩余空间

来源：

- `reserved output`
- `reasoning reserve`
- `safety margin`
- `free headroom`

## UI 层次建议

视觉权重建议如下：

1. 顶部 grid + 主数字
2. 分类占用条
3. Top 5
4. 技术细节

其中：

- 主图负责整体形状
- 分类条负责大小对比
- Top 5 负责可定位性
- 技术区负责可排障性

## 验证重点

本轮实现后应重点验证：

1. 用户是否能一眼看出整体占用
2. 分类是否稳定按占用从高到低排序
3. `预留 / 剩余空间` 是否固定在最后且不抢焦点
4. Top 5 是否都能清楚指向具体操作
5. 没有因为弱化技术区而丢失现有诊断能力

## 结论

本轮 `context usage` 面板重构的核心，不是再加更多数字，而是把现有正确的数据重新组织成一张更像“上下文占用地图”的用户面板：

- 顶部用 grid 告诉用户整体占多少
- 中段用分类条告诉用户哪一类最占
- 底部用 Top 5 告诉用户哪几个具体操作最重
- 技术字段保留，但下沉

这样既不破坏已有预算与 compaction 语义，也能明显提升用户打开这个面板的价值。
