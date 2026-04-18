# 日志架构收敛 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立统一中文日志架构文档，并将应用日志收敛到单文件 `logs/app.log` 与统一 `Logger` 入口。

**Architecture:** 保留 transcript、ledger、file log 三层语义边界，不新造复杂日志数据库。本轮以原生平台单文件日志为主，统一 `runtime/trace/temp` 三类日志入口，并为 agent loop 补齐关键锚点日志。

**Tech Stack:** Flutter, Dart, path_provider, existing ChatTraceRecorder, existing agent loop services

---

## File Map

**Create:**

- `docs/architecture/logging.md`：日志与 trace 架构唯一规范来源
- `docs/superpowers/specs/2026-04-18-logging-architecture-design.md`：本轮设计记录
- `docs/superpowers/plans/2026-04-18-logging-architecture-implementation-plan.md`：本计划文档
- `lib/utils/log_file_sink_base.dart`：文件日志 sink 抽象
- `lib/utils/log_file_sink.dart`：平台日志 sink 入口
- `lib/utils/log_file_sink_stub.dart`：非原生平台 no-op 实现
- `lib/utils/log_file_sink_native.dart`：原生日志文件实现

**Modify:**

- `lib/utils/logger.dart`：统一 logger API 与单文件格式
- `lib/services/chat_trace_recorder.dart`：trace 接入统一 logger
- `lib/services/turn_harness.dart`：补 turn/planner/tool/interaction 锚点日志
- `lib/main.dart`：初始化 logger
- `README.md`：收敛为日志架构文档引用
- `AGENTS.md`：收敛为日志架构文档引用

### Task 1: 写文档并锁定边界

**Files:**

- Create: `docs/architecture/logging.md`
- Create: `docs/superpowers/specs/2026-04-18-logging-architecture-design.md`
- Modify: `README.md`
- Modify: `AGENTS.md`

- [ ] 写日志架构文档，明确 transcript、ledger、file log 边界
- [ ] 写明单文件 `logs/app.log` 与 `runtime/trace/temp` 分类
- [ ] 写明临时日志治理与锚点日志规则
- [ ] 将 README/AGENTS 改为引用日志架构文档

### Task 2: 实现统一 Logger 与单文件 sink

**Files:**

- Modify: `lib/utils/logger.dart`
- Create: `lib/utils/log_file_sink_base.dart`
- Create: `lib/utils/log_file_sink.dart`
- Create: `lib/utils/log_file_sink_stub.dart`
- Create: `lib/utils/log_file_sink_native.dart`
- Modify: `lib/main.dart`

- [ ] 为 logger 增加 `runtime/trace/temp` API
- [ ] 保留 `d/i/w/e` 兼容层，避免大面积调用点改造
- [ ] 原生平台将日志写入 `logs/app.log`
- [ ] Web 回退到控制台输出
- [ ] 应用启动时初始化 logger

### Task 3: 补 agent loop 锚点日志

**Files:**

- Modify: `lib/services/chat_trace_recorder.dart`
- Modify: `lib/services/turn_harness.dart`

- [ ] 将 `ChatTraceRecorder` 默认输出接入统一 logger
- [ ] 为 turn 开始/结束/失败补锚点日志
- [ ] 为 planner 开始/完成补锚点日志
- [ ] 为 tool 开始/完成/失败补锚点日志
- [ ] 为 interaction 挂起/恢复补锚点日志

### Task 4: 验证

**Files:**

- Verify: `test/services/chat_trace_recorder_test.dart`
- Verify: `test/services/tool_orchestrator_service_test.dart`
- Verify: `test/services/turn_harness_test.dart`

- [ ] 运行相关测试
- [ ] 运行 `flutter analyze` 或 `fvm flutter analyze`
- [ ] 根据结果修正实现
