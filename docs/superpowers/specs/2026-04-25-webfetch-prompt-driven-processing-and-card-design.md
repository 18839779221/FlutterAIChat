# WebFetch Prompt 驱动处理与卡片重设计

## 背景

当前仓库中的 `fetch_webpage` 已经接入专属 workflow/result 卡片，但它的产品语义与展示方式仍然偏向“抓取网页正文”，而不是“按调用意图处理网页内容”。

这带来了四个连续问题：

1. 工具输入过于偏底层，当前只强调 `url`，没有把“为什么读这页、想怎么处理”正式纳入工具契约
2. `descriptionForModel` 仍然偏向“当已有 URL 时去读网页正文”，不足以指导 planner 产出高质量的网页处理调用
3. result 卡片默认心智偏向“读取了什么网页”，而不是“基于这次 prompt 处理出了什么结果”
4. 工具内部二次处理与主模型回答的边界不清晰，容易在日志、上下文和 UI 认知上混淆

结合近期对 `Read` / `LS` / `Grep` / `Glob` / `web_search` / `fetch_webpage` 卡片的连续优化，这一轮需要把 `fetch_webpage` 的语义、提示词和结果卡交互一起收敛，避免继续围绕“网页原文展示”做局部修修补补。

## 目标

1. 将 `fetch_webpage` 明确定义为“读取指定公共网页，并按 prompt 处理网页内容”的工具
2. 将工具入参收敛为 `url + prompt`
3. 明确工具内部使用独立的 `side model` 处理网页内容，而不是语义上复用主模型
4. 让 `descriptionForModel` 以工具定位、边界、失败模式为主，不与参数描述重复
5. 将 `fetch_webpage` 卡片改造成单卡片生命周期，默认展示 `host + prompt + 处理结果预览`
6. 让原始网页摘录退居证据层，而不是主展示内容

## 非目标

1. 本轮不讨论 `web_search` 的 `descriptionForModel` 与 planner 文案改造细节
2. 本轮不设计新的统一 tool 展示 schema
3. 本轮不把 `fetch_webpage` 的输出强制约束为“结论 + 关键发现”固定结构
4. 本轮不在工具外层强制注入“必须服务当前任务”或“必须得出结论”的产品约束
5. 本轮不改变主模型消费 tool result 的主流程，只收紧语义边界

## 现状问题

### 一、工具契约偏向读取网页正文

当前 `fetch_webpage` handler 的模型侧描述主要表达：

- 用户已给出 URL 时可直接读取网页
- 不要把它用于泛化的网上搜索

这个方向本身没有错，但它缺少对“如何处理网页内容”的正式描述，也没有把 prompt 作为工具契约的一部分纳入。

结果是：

- planner 容易把它理解成“网页抓取器”
- UI 也容易围绕“网页标题 / 网页正文 / 打开网页”组织主展示

### 二、结果卡默认展示对象不对

用户使用 `fetch_webpage` 时，很少是为了看“原始网页长什么样”。更常见的需求是：

- 按某个问题阅读网页
- 从网页中提取某类信息
- 比较网页中的几种说法
- 判断网页是否相关
- 将网页内容按指定格式整理

这些需求的真正动作是：

- `读取网页 + 按 prompt 处理内容`

而不是：

- `抓取网页原文 + 直接展示`

### 三、工具内部二次处理与主模型角色边界不清

`fetch_webpage` 实际需要先抓取网页，再做一次内部处理。但如果在命名、日志或 UI 上不刻意区分，很容易出现两种误解：

1. 看起来像主模型已经直接阅读了网页并给出回答
2. side model 和主模型即便配置相同，也被视为同一职责

这会影响：

- tool transcript 语义
- planner 上下文投影
- 用户对“工具结果”和“主模型最终回答”的理解

## 设计原则

### 1. 工具语义保持中性，具体目标交给 prompt

`fetch_webpage` 应提供的是一个通用的“网页定向处理”能力，而不是预先强加：

- 必须完成某个任务
- 必须得出结论
- 必须输出固定结构

真正的目标应由 `url + prompt` 的组合表达。

### 2. `descriptionForModel` 只负责定位，不复述参数描述

参数字段的具体语义应由 argument schema 自己承担，例如：

- `url` 是 fully qualified public URL
- `prompt` 描述要从网页中抽取、总结、比对或转换什么内容

`descriptionForModel` 不再重复 `Input:` 小节，避免一处修改后另一处文案漂移。

### 3. `side model` 与主模型语义分离

`fetch_webpage` 的处理结果属于工具内部产物。

即使当前配置允许 side model 与主模型使用相同 provider/model，也必须在语义上区分：

- 主模型：对话主线程中的 planner / assistant
- side model：`fetch_webpage` 工具内部的网页内容处理模型

### 4. 卡片默认展示“这次调用在做什么”和“得到了什么处理结果”

对用户而言，一次 `fetch_webpage` 调用至少包含两条核心信息：

- 读的是哪个网页
- 按什么 prompt 去处理

因此 `prompt` 必须进入主展示，而不是隐藏到二级详情里。

### 5. 原始网页内容是证据层，不是主展示层

无论是标题、正文摘录还是最终 URL，都应服务于可追溯性，而不是占据主视觉。

## 方案总览

本轮推荐将 `fetch_webpage` 收敛为以下语义：

- 输入：`url + prompt`
- 执行：抓取网页 -> 提取可读内容 -> 交给内部 `side model` 按 prompt 处理
- 输出：网页处理结果
- UI：`workflow` 与 `result` 共用一张卡片的生命周期，默认展示 `host + prompt + 结果预览`

这意味着它不再是“网页抓取卡”，而是“网页定向处理结果卡”。

## 详细设计

### 一、工具定义

#### 1. 参数

`fetch_webpage` 的参数收敛为：

- `url`
- `prompt`

不再保留 `extractMode` 这类偏实现层、对 planner 不稳定且对用户不可感知的参数。

参数语义在 argument schema 中表达，不在 `descriptionForModel` 重复。

#### 2. `descriptionForModel`

推荐文案：

```text
Read a public webpage at a specific URL and process its content according to a prompt.

IMPORTANT: This tool is for public, unauthenticated webpages. It may fail for private or authenticated URLs such as Google Docs, Confluence, Jira, GitHub pages that require login, or other workspace-only content. Before using this tool, check whether a specialized MCP tool or another authenticated integration is available, and prefer that when possible.

Use this tool when you already have a concrete URL and need to read or process that page for a specific purpose.

This tool fetches the webpage, extracts readable content, and uses an internal side model to process that content according to the prompt. It returns the processed result rather than simply returning the raw page text. If the page is very long, the result may be condensed. If the URL redirects to a different host, the tool may require a new request using the redirected URL.

Do not use this tool just to discover relevant pages; use web_search first when you need to find candidate sources. Do not use this tool for GitHub resources that are better handled by Bash or dedicated tools.

This tool is read-only and does not modify files.
```

#### 3. 参数描述

参数字段的推荐描述：

- `url`: fully qualified public URL to read
- `prompt`: instructions describing what to extract, summarize, inspect, compare, or transform from the page content

### 二、side model 处理语义

`fetch_webpage` 在执行时分为三步：

1. 抓取目标网页
2. 提取可读正文
3. 使用内部 `side model` 按 `prompt` 处理正文

其中第三步的产物直接作为 tool result，而不是伪装成主模型的中间回答。

#### 1. 设计要求

- 代码、日志、配置命名中要显式区分 `side model`
- 即使 side model 与主模型可配置为同一模型，也不能在语义上混同
- planner 和主模型消费的是 tool result，不是 side model 被包装后的 assistant 文本

#### 2. side model 内部 prompt

推荐模板：

```text
Web page content:
---
${markdownContent}
---

Prompt:
${prompt}

Use only the webpage content above to answer the prompt.

Requirements:
- Follow the prompt closely and produce the result in the format it asks for when possible.
- Do not rely on outside knowledge.
- If the page does not contain enough relevant information, say so clearly.
- Prefer concise paraphrase over copying long passages from the page.
- Keep quotes minimal and only use them when exact wording matters.
- Ignore unrelated navigation, boilerplate, repeated page chrome, and marketing copy.
- Return processed page content, not meta commentary about the tool.
```

### 三、UI 交互

#### 1. 单卡片生命周期

`fetch_webpage` 始终只有一张卡片：

- 执行中：`workflow` 卡
- 有结果后：原位替换为 `result` 卡

不再出现“workflow 卡保留在上方，result 卡追加在下方”的双卡并存状态。

#### 2. workflow 卡

`workflow` 卡默认两行：

- 第一行：`阅读网页 · {host}`
- 第二行：`prompt` 单行省略

右侧只保留状态表达：

- `进行中`
- `已完成`
- `失败`
- `已跳转`

这里不展示长 URL、正文摘录或额外实现信息。

#### 3. result 卡折叠态

折叠态默认展示：

- 第一行：`阅读网页 · {host}`
- 第二行：`prompt` 单行省略
- 第三行：处理结果预览，单行或双行省略

其中第三行的内容是 side model 处理结果的预览，而不是强制定义为“结论”。

这样可以同时覆盖：

- 总结类 prompt
- 提取类 prompt
- 比对类 prompt
- 判断相关性类 prompt
- 转换/整理类 prompt

#### 4. result 卡展开态

展开后建议固定为三个分区：

1. `Prompt`
2. `处理结果`
3. `来源与细节`

其中：

- `Prompt` 展示完整 prompt
- `处理结果` 展示 side model 的最终文本输出
- `来源与细节` 展示原始摘录、最终 URL、跳转信息、打开原网页、失败原因等

这三块的顺序体现了产品优先级：

- 先理解这次读取的目的
- 再看处理结果
- 最后在需要时查看原始依据

#### 5. 状态文案

建议使用中性状态预览，不把结果强绑定为“结论”：

- 成功：`已返回网页处理结果`
- 信息不足：`页面内容不足以完成该请求`
- 跳转未继续：`页面跳转到了其他地址，需要重新读取`
- 失败：`读取失败：{reason}`

### 四、与现有工具体系的边界

#### 1. 与 `web_search` 的边界

`web_search` 用于发现候选来源。

`fetch_webpage` 用于对已知 URL 进行定向读取与处理。

如果用户还没有明确目标网页，或只是笼统地“去网上找资料”，应先使用 `web_search`。

#### 2. 与专用工具 / 认证访问的边界

对于需要登录、私有工作区或已有专门 MCP/CLI 接入的目标源，不应优先使用 `fetch_webpage`。

例如：

- Google Docs
- Confluence
- Jira
- 需要认证的 GitHub 页面

#### 3. 与主模型回答的边界

`fetch_webpage` 的 result 卡展示的是工具产物。

如果主模型随后基于多个 tool result、上下文和用户问题产出更高层的综合回答，那是后续 assistant 回复的职责，不应提前混入 `fetch_webpage` 卡片语义。

## 方案权衡

### 方案 A：继续强调网页正文展示

优点：

- 实现改动较小
- 对底层抓取过程透明

缺点：

- 用户很难从卡片主视图判断“这次读取到底要解决什么”
- prompt 价值被弱化
- result 卡容易沦为原文浏览器

### 方案 B：强制输出“结论 + 关键发现”

优点：

- 卡片形态稳定
- 对问题解决类场景很友好

缺点：

- 过度绑定结果结构
- 对提取、比对、转换类 prompt 不够自然

### 方案 C：以 `url + prompt` 为核心，卡片展示网页定向处理结果

优点：

- 通用性最好
- 与真实调用意图最一致
- 同时兼容摘要、提取、判断、比对和转换类 prompt

缺点：

- 需要在 UI 中明确展示 prompt
- 需要把原始摘录退居次级层，重排已有卡片层级

推荐采用方案 C。

## 对现有实现的影响

### 一、tool handler

- `fetch_webpage` 的参数 schema 需要从 `url + extractMode` 改为 `url + prompt`
- `descriptionForModel` 需要改为新的任务中性文案
- `localizedDescriptionForModel` 需要保持与英文结构一致

### 二、tool result 结构

现有 result payload 需要能承载：

- 原始 `url`
- `host`
- `prompt`
- side model 处理结果
- 最终 URL / 跳转信息
- 原始摘录或可供详情区读取的文本
- 失败原因

本轮不要求引入统一展示 schema，但这些字段需要在 `data` 中稳定可取。

### 三、卡片 renderer

- `fetch_webpage_tool_workflow_card.dart`
- `fetch_webpage_tool_result_card.dart`

这两个 renderer 需要从“网页信息展示”切换到“prompt + 处理结果展示”。

### 四、转录与上下文投影

tool result 继续以工具结果身份进入 transcript 和 planner 上下文，不应被提前压扁成主模型口吻的 assistant 摘要。

## 验收标准

1. `fetch_webpage` 的 schema 只包含 `url` 与 `prompt`
2. `descriptionForModel` 不再重复参数说明，并显式说明 `side model`
3. `fetch_webpage` 结果卡默认可看见 `host + prompt + 处理结果预览`
4. `prompt` 在折叠态可见，在展开态完整可见
5. 原始摘录和最终 URL 被收纳到次级详情区
6. workflow 与 result 不再双卡并存
7. 工具结果与主模型回答在语义、日志和 UI 上保持分离

## 风险与后续

### 风险

1. side model 输出如果过长，result 卡展开态可能再次变得冗长
2. 如果 payload 字段设计不稳定，renderer 容易出现兼容分支堆积
3. `web_search` 与 `fetch_webpage` 的文案边界若不同步，planner 仍可能误用

### 后续

1. 在 implementation plan 中细化 payload 字段映射与 renderer 改造步骤
2. 同步补测试，覆盖 schema、tool result 映射与 widget 展示
3. 视实现效果再决定是否为 `fetch_webpage` 增加更细的长文本折叠策略
