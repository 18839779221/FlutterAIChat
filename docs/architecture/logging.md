# 日志与 Trace 架构

## 目标

本文档是项目内日志、trace、临时调试日志的唯一规范来源。

目标是：

- 为 agent loop、tool call、LLM 请求与恢复链路提供稳定排障入口
- 让开发期偶现问题可以通过本地文件日志高效复盘
- 明确 transcript、ledger、file log 三者职责，避免继续混用
- 让正式日志与临时日志有清晰边界，便于后续清理和演进

## 非目标

本文档不负责：

- 定义数据库 schema 细节
- 定义日志查看 UI
- 定义日志上传或远端 observability 平台
- 要求每条日志都携带完整结构化字段

## 当前阶段原则

项目当前仍处于开发阶段，没有真实用户负载约束。
因此本阶段的优先目标是排障效率，而不是日志量最小化。

基于这个前提：

- 日志主入口是本地文件 `logs/app.log`
- 数据库不是主要排障入口
- `logcat` 仍然有价值，但不应作为唯一稳定诊断来源

## 三层语义边界

### 1. Transcript

Transcript 记录用户与系统在一个 turn 内的可读时间线事实。
当前主要载体是 `chat_events`。

适用内容：

- 用户消息
- assistant 中间文本与最终文本
- tool call 的用户可见投影
- ask-user-question 的提问与回答投影
- 用户需要在 UI 或 transcript 中看到的状态节点

不适用内容：

- 仅用于开发排障的内部运行细节
- 高频临时调试文本
- 只服务于恢复控制流的内部执行状态

### 2. Ledger

Ledger 记录 turn 与 step 的执行状态真相。
当前主要载体是 `chat_turn` 与 `chat_turn_step`。

适用内容：

- turn 当前状态
- provider runtime state
- step 的 planned/running/completed/failed 状态
- tool result 摘要、错误码与 resume 所需结构化信息

不适用内容：

- 面向人类时序阅读的大量过程日志
- 单次调试插桩的自由文本

### 3. File Log

File log 是开发期排障的主入口。
当前主文件是原生平台上的 `logs/app.log`。

适用内容：

- turn 开始/结束/失败
- planner 开始/完成
- tool 开始/等待确认/成功/失败
- interaction 挂起/恢复
- LLM 请求开始、首 token、完成、失败
- 明确的临时调试插桩

不适用内容：

- 作为业务真相源参与恢复判断
- 替代 transcript 或 step 持久化

## 权威来源

当多个载体信息同时存在时，按以下规则解释：

- 执行状态真相以 `chat_turn` / `chat_turn_step` 为准
- 用户可见时间线以 `chat_events` 为准
- 原因分析、时序复盘与偶现问题排查以 `logs/app.log` 为主

这三者允许互相引用，但不能相互替代。

## 单文件策略

本阶段只维护一个主日志文件：

- `logs/app.log`

原因：

- 全局时序连续，适合一口气复盘一次 turn
- 避免跨多个文件来回跳转
- 导出、grep、分享都更直接

后续若出现明确需求，再讨论拆分文件；在此之前不新增 `trace.log`、`temp.log` 等多文件方案。

## 日志分类

所有正式日志都必须通过统一 `Logger` 入口输出，分为三类：

### runtime

正式运行日志，用于记录稳定且长期保留的运行信息。

例子：

- 应用启动
- 数据库初始化
- 运行时配置
- 服务执行状态说明

### trace

关键链路观察日志，用于 turn/planner/tool/LLM 的时序排障。

例子：

- `turn.start`
- `planner.start`
- `planner.done`
- `tool.start`
- `tool.done`
- `tool.failed`
- `interaction.awaiting_user`
- `interaction.resumed`

### temp

临时开发日志，用于短期定位具体问题。

要求：

- 必须显式调用临时日志 API
- 必须可通过统一标记检索
- 默认不提升为架构承诺
- 一旦发现长期有价值，应升级为 `runtime` 或 `trace`

## 临时日志治理

临时日志不是坏事，但必须被视为可清理的调试插桩，而不是长期架构资产。

规则如下：

- 禁止用裸 `print` 或任意自由文本模拟临时日志
- 临时日志必须走 `Logger.temp(...)`
- 临时日志应尽量附带 `reason`
- 临时日志必须能通过 `kind=temp` 一把检索
- 若某条临时日志被反复依赖，应将其升级为正式 `runtime` 或 `trace`

## 锚点日志规则

本项目不要求每条日志都重复携带完整上下文字段。
相反，我们要求每条关键链路至少出现可检索的锚点日志。

### turn 锚点

每个 turn 至少应有：

- `turn.start`
- `turn.done` 或 `turn.failed`

### app 运行锚点

每次应用启动至少应有：

- `app_run.start`

它用于切分同一个 `logs/app.log` 中的不同运行周期，避免重启后日志时序混淆。

### planner 锚点

每次 planner 决策至少应有：

- `planner.start`
- `planner.done`

若发生异常，可补：

- `planner.failed`

若 planner 对同一批 decision 内的 tool calls 做了本地收敛，也应补充可检索日志：

- `planner.sanitized`

它用于说明本次 decision 是否发生了静默过滤，例如：

- 同一 step 内模型重复输出了规格完全相同的 tool call
- planner 输出了当前不可见或不可用的 tool

注意：

- `planner.sanitized` 只描述“本次 planner decision 输出”上的本地收敛
- 不应用它表达跨 turn 或跨历史 step 的去重语义

### tool 锚点

每次 tool 流程至少应有：

- `tool.start`
- `tool.done` 或 `tool.failed`

若需要用户确认或补充信息，可补：

- `tool.awaiting_confirmation`
- `interaction.awaiting_user`

artifact / visualizer 相关日志建议沿用同一分类，不新增第二套日志体系：

- `tool.start` / `tool.done` / `tool.failed`
  - 适用于 `create_artifact`
- `runtime`
  - 适用于 artifact 文件保存、source 读取失败、registry 重建等基础设施日志
- `trace`
  - 适用于时间线 projection 阶段的 artifact refresh / stale 诊断
  - 也适用于 inline artifact render-session 的异常摘要，例如：
    - `artifact.preview.anomaly`
    - `artifact.preview.session_done`
  - 也适用于流式 timeline 的高信号阶段持久化，例如：
    - `streaming.trace.stage`
    - `streaming.trace.lifecycle`
  - 这些仍写入同一个 `logs/app.log`，不构成第二条 observability 通道

当前 repo 内与 `create_artifact` / 流式 timeline 相关的一键分析入口：

- `bash scripts/analyze_create_artifact_render.sh ...`
- `bash scripts/analyze_streaming_trace.sh ...`
- `bash scripts/analyze_create_artifact_incident.sh ...`

### interaction 锚点

发生用户交互挂起与恢复时至少应有：

- `interaction.awaiting_user`
- `interaction.resume_confirmation` 或 `interaction.resumed`

## 字段策略

不要求每条日志带完整 `turnId/groupId/stepId/...`。

要求是：

- 链路切换点的锚点日志应尽量带必要关联字段
- 同一连续上下文的跟随日志可以省略重复字段
- 日志正文优先保持可读性，不强制全量结构化

推荐但非强制字段：

- `turnId`
- `groupId`
- `stepId`
- `toolName`
- `reason`
- `error`

## 格式约定

单行日志格式为：

```text
<timestamp> <level> [<kind>] [<tag>] <message> <optional key=value...>
```

示例：

```text
2026-04-18T14:03:10.120Z INFO [trace] [TurnHarness] turn.start turnId=12 groupId=5
2026-04-18T14:03:10.500Z INFO [trace] [TurnHarness] tool.start turnId=12 stepId=3 toolName=read
2026-04-18T14:03:10.900Z DEBUG [temp] [ChatSendCoordinator] checking resumed payload mapping reason=ask-user-question-debug
```

## 平台策略

- 原生平台：控制台输出 + 追加写入 `logs/app.log`
- Web：只输出控制台，不做文件写入

Web 不具备本地文件日志能力，不应为兼容 Web 而降低原生日志架构质量。

## API 约束

允许使用：

- `Logger.runtime(...)`
- `Logger.trace(...)`
- `Logger.temp(...)`
- `Logger.d/i/w/e(...)` 作为兼容层

禁止新增：

- 裸 `print`
- 裸 `debugPrint`
- 新的平行日志工具类而不接入统一 `Logger`

## 与其他文档的关系

- `README.md` 只保留能力说明与本文档引用
- `AGENTS.md` 只保留实现约束入口与本文档引用
- 日志分类、锚点规则、临时日志治理不得在其他文档重复维护

## 本轮实施范围

本轮应完成：

- 统一 `Logger` API
- 原生平台单文件 `logs/app.log`
- `runtime` / `trace` / `temp` 三类日志入口
- `ChatTraceRecorder` 接入统一 logger
- 为 turn/planner/tool/interaction 主链路补齐关键锚点日志
- `README.md` 与 `AGENTS.md` 收敛为引用本文档

## 本轮明确不做

- 不做日志上传
- 不做日志查看面板
- 不做多文件日志拆分
- 不做新的复杂 trace 数据库表
- 不要求每个文本 chunk 都持久化为日志
