# 日志架构设计

## 背景

当前项目已经同时存在三类与排障相关的信息：

- 数据库中的 transcript 事件
- 数据库中的 turn / step 执行状态
- 控制台中的自由文本日志与部分 trace

这些信息各自有价值，但排障入口并不统一：

- 数据库更偏业务与恢复真相，不适合直接做时序分析
- `logcat` 容易被冲掉，无法稳定保留偶现问题上下文
- 临时日志没有明确治理方式，容易逐步污染正式日志体系

## 设计目标

- 将日志与 trace 规范收敛到单独文档
- 提供稳定、可持续追加的本地文件日志
- 保留 transcript / ledger / file log 的边界，不重复造业务真相源
- 给临时日志提供明确入口，降低后续清理成本

## 核心设计

### 三层语义边界

- Transcript：给 UI 与模型上下文看的可读时间线
- Ledger：给恢复和执行控制看的状态真相
- File Log：给开发排障看的时序主入口

### 单文件日志

- 原生平台统一落到 `logs/app.log`
- 按时间顺序追加
- 不拆多个日志文件

### 统一 Logger

统一提供：

- `runtime`
- `trace`
- `temp`
- 兼容层 `d/i/w/e`

### 锚点而非全量字段

不要求每条日志都带完整字段，而是要求关键链路存在可检索锚点：

- turn.start / turn.done / turn.failed
- planner.start / planner.done
- tool.start / tool.done / tool.failed
- interaction.awaiting_user / interaction.resumed

### 临时日志治理

- 临时日志必须显式使用 `Logger.temp`
- 临时日志必须能被 `kind=temp` 检索
- 若长期保留，应升级为正式日志

## 实施边界

本轮不做：

- 复杂日志数据库
- 日志 UI
- 上传与远端查询
- 多文件拆分

## 预期结果

- `logs/app.log` 成为开发期最稳定的排障入口
- 数据库继续承担业务真相，不再被期望直接替代日志
- 文档约束集中，避免后续 README/AGENTS 再次散落维护
