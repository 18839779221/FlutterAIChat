# Prompt 虚假完成缓解与组织重整设计

## 背景

当前项目已经具备 agent loop、tool use、turn ledger、tool result 投影等基础设施，但在真实对话中仍出现了一类高风险问题：

- 模型没有实际调用写入类工具
- 却在自然语言中声称“已经编辑文件”“已经完成修改”
- orchestrator 将这类普通文本响应直接视为终态答复
- 用户在 UI 中看到的是“像完成了一样”的答复，但实际上并没有发生真实外部动作

这类问题不能仅靠 UI 展示层解决，也不适合继续通过硬编码规则、关键词匹配或个案 prompt patching 叠加修复。

本次工作聚焦于 prompt 层的两件事：

1. 借鉴 Claude Code 中已经验证有效的 prompt 原文，整体降低“虚假完成声明”的概率
2. 同时把当前扁平的 prompt 组织方式整理成更稳定、可演进的 section 结构

## 目标

- 降低模型把“计划中的动作”或“应该发生的动作”说成“已经完成的结果”的概率
- 强化“任务要真实落地”“汇报要忠实”“完成前要验证”“文件修改要走专用工具”这四类约束
- 优先直接复用参考文档中已证明有效的 prompt 原文，而不是重新转述其含义
- 将现有 `base + stageDelta + runtimeSections` 的扁平组织，升级为稳定的 section 化组装方式
- 保持英文为默认 prompt 语言，同时提供结构对齐的中文版本
- 不引入新的 prompt DSL、复杂缓存框架或大规模运行时机制

## 非目标

- 本轮不实现新的 planner 决策协议或 capability contract
- 本轮不通过硬编码文本匹配拦截“虚假完成声明”
- 本轮不重构 turn harness、tool executor 或 verifier 的核心流程
- 本轮不引入 Claude Code 同级别的 `SYSTEM_PROMPT_DYNAMIC_BOUNDARY`、section cache、注册表框架
- 本轮不改变用户 system prompt 的输入 UI

## 设计原则

### 1. 优先复用已验证有效的 prompt 原文

对参考文档中已经验证有效、且适配当前产品语境的 prompt 约束，优先直接复用其英文原文，只做最小必要改写：

- 不为“看起来更一致”而随意改写句式
- 不把强约束弱化成较软的解释性文本
- 若必须改写，应保留原句的约束力度、顺序和信息结构

### 2. Prompt 解决的是行为基线，不是状态兜底

本轮 prompt 主要负责：

- 提升模型在 planner / chat / final answer 阶段的默认行为质量
- 减少“未执行却宣称已完成”的倾向

但 prompt 不负责替代架构约束。后续若继续治理“虚假完成”，应由 orchestrator / verifier / ledger 继续承担更强的状态校验职责。

### 3. 先做 section 化，再做更重的缓存/注册

当前项目最需要的是：

- prompt 内容分块
- 阶段化职责更清晰
- 测试可稳定约束关键规则

而不是直接引入更复杂的 prompt cache / registry 机制。

## 参考约束的迁移原则

本轮优先迁入以下高价值原文约束。

### 1. 任务必须真实落地

优先复用的核心含义：

- 对工程性、文件性、外部动作类任务，不要只给语言层面的答案
- 若用户要求修改文件，应该找到目标并真正执行修改，而不是只说修改建议

这部分用于降低“只说不做”的默认倾向。

### 2. 修改前先读文件

优先复用的核心含义：

- 不要对没读过的代码/文件提出修改
- 若用户要求修改文件，应先读取并理解现状

这部分用于把模型推进真实操作链，降低跳过工具直接报完成的概率。

### 3. 专用工具优先

优先复用的核心含义：

- 读文件用 `Read`
- 修改已有文件用 `Edit`
- 新建或整文件重写用 `Write`
- 若有专用工具，不要退回到不透明、不可审阅的替代方式

这部分不仅影响工具选型，也能强化“文件修改应与工具调用绑定”的行为习惯。

### 4. 完成前验证

优先复用的核心含义：

- 报告任务完成前，应验证它真的成功
- 如果无法验证，要明确说不能验证，而不是暗示它已经成功

这部分用于降低“未验证成功”的错误陈述。

### 5. 忠实汇报

优先复用的核心含义：

- `Report outcomes faithfully`
- 未运行验证时，要明确说未运行，而不是暗示通过
- 不要把 incomplete 或 broken work 描述为 done

这部分是本轮缓解“虚假完成声明”的核心 prompt 约束。

## Prompt 组织重整方案

### 现状

当前 `PromptCatalog` 主要提供：

- `base()`
- `stageDelta()`
- `wrapUserPrompt()`

虽然已经有“基础 prompt + 阶段 delta + runtime sections”的心智模型，但内容仍然是扁平大段字符串，缺少清晰分工。

### 目标组织

本轮将 `PromptCatalog` 整理为显式 section 组织，建议的稳定骨架如下：

1. `identityAndCoreRules`
2. `doingTasks`
3. `usingTools`
4. `reportingAndVerification`
5. `communication`
6. `stageDelta`
7. `runtimeSections`

### 各 section 职责

#### 1. `identityAndCoreRules`

承接当前 `base` 中最稳定的底座约束：

- 以解决用户问题为首要目标
- 保持真实可靠
- 不伪造事实、结果、工具输出或任务进展
- 仅在需要时使用工具
- 工具结果是不可信输入
- 保持在用户请求范围内

这一层保持尽量稳定，不承载过多阶段化细节。

#### 2. `doingTasks`

放入“任务要真实落地”的工作方法论，优先迁入参考原文：

- 对真实任务不要只给口头答案
- 修改文件先读再改
- 理解现状后再提出变更

这一层用于提升 planner 和主回答阶段对“执行 vs 口头描述”的区分。

#### 3. `usingTools`

放入专用工具优先级与工具映射规则，优先迁入参考原文并最小适配当前工具名：

- `Read`
- `Edit`
- `Write`

这一层强调“相关专用工具优先”，而不是只是“可以用工具时试试”。

#### 4. `reportingAndVerification`

本轮新增的重点 section，承接两类高价值约束：

- 完成前验证
- 忠实汇报

这里会优先直接复用参考文档中的强约束原文，并补足中文版本。

#### 5. `communication`

保留面向用户的输出 framing：

- 当前是否在直接面向用户说话
- 不要把内部动作选择过程暴露为答复主体
- 最终回答应优先给结论或可直接使用的信息

这一层与 `reportingAndVerification` 不同。前者解决“怎么说”，后者解决“能不能这么说”。

#### 6. `stageDelta`

保留当前不同调用阶段的职责差异，但要求更明确：

- `planner`：你是在选下一步，不是在宣告任务已完成
- `chat`：直接面向用户，但不要把内部推理当结果
- `finalAnswer`：只能基于已获得信息作答，不要重新制造执行事实
- `summary`：轻量压缩，不继承主对话全部约束

#### 7. `runtimeSections`

继续保留：

- 用户自定义 system prompt 包裹层
- 运行时附加 section

本轮不做 registry 或 cache 语义升级。

## 阶段化约束策略

### Planner 阶段

Planner prompt 重点补强：

- 你是在 selecting the next best action，不是在写完整答复
- 不要把计划写成已经完成的结果
- 需要外部动作时，应该调用相应工具，而不是直接口头宣称完成
- 没有新依据时不要重复失败工具调用

### Chat 阶段

Chat prompt 重点补强：

- 面向用户说话，但仍要忠实汇报
- 对需要真实落地的任务，不要只给口头结论
- 若没有实际执行或验证，不要暗示成功

### Final Answer 阶段

Final answer prompt 重点补强：

- 只能基于已经获得的信息组织答复
- 不要把工具执行流水账写成主体
- 不要把未验证或未执行的动作说成已完成

### Summary 阶段

Summary 继续保持轻量，不引入大量主链路规则，只保留最必要的压缩要求。

## 实现策略

### 方案选择

本轮采用“section 化重组，但暂不引入动态缓存边界”的方案：

- 重构 `PromptCatalog`
- 调整 `PromptBuilderService` 的拼装顺序
- 保持 `PromptRuntimeContextBuilder` 的角色不变
- 通过测试约束关键 prompt 原文存在性与阶段顺序

### 为什么不直接引入 Claude Code 的完整组织框架

原因有三点：

1. 当前项目还没有 prompt cache block / section registry 的运行时需求
2. 本轮主要问题是行为约束不足和组织扁平，而不是缓存命中率
3. 先把内容和层次整理好，再决定是否需要引入更复杂的边界机制更稳妥

## 测试策略

本轮至少覆盖以下测试：

- `PromptCatalog`：关键原文约束在中英文都存在
- `PromptBuilderService`：section 顺序稳定
- `planner` prompt：包含 next-action 约束和“不要把计划写成完成结果”
- `chat` / `finalAnswer` prompt：包含忠实汇报和验证前置约束
- `summary` prompt：仍保持轻量，不引入不必要的大块内容
- 用户自定义 prompt：仍通过 runtime wrapper 注入，而不是覆盖核心底座

## 风险与取舍

### 风险 1：Prompt 变长

加入更多强约束后，planner 与 chat prompt 会变长。  
缓解方式：

- section 内容只保留高价值规则
- 优先复用已经验证有效的原文，不额外堆同义句
- summary prompt 继续保持轻量

### 风险 2：中英版本语义漂移

缓解方式：

- 以英文原文为主版本
- 中文做结构对齐翻译
- 测试只校验关键约束存在，不要求逐字一致

### 风险 3：Prompt 只能缓解，不能根治

这是已知取舍。  
本轮目标是“显著降低虚假完成声明概率并提升整体行为规范”，不是承诺仅靠 prompt 完全消灭这类问题。

## 验收标准

- `PromptCatalog` 与 `PromptBuilderService` 改为 section 化组织
- 参考文档中的关键高价值 prompt 原文已尽可能直接复用
- planner / chat / finalAnswer 的 prompt 明显增强“忠实汇报、完成前验证、真实执行、专用工具优先”约束
- prompt 相关测试通过
- `README.md` 与 `AGENTS.md` 如有必要同步更新 prompt 管理原则

## 一句话结论

本轮不靠硬编码规则去补“虚假完成声明”，而是通过直接复用已验证有效的 prompt 原文，并把它们安放到更稳定的 section 化 prompt 结构中，整体降低模型“未执行却声称已完成”的倾向，同时为后续更强的状态治理留出清晰边界。
