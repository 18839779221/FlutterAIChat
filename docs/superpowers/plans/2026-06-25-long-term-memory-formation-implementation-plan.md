# 长期记忆形成层 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 turn 结束时基于最近可见消息形成长期记忆，并通过现有 `/memories` 文件工具写入或更新 topic files，避免高频抽取导致 memory 膨胀和 token 成本失控。

**Architecture:** 新增一个后台记忆形成器，挂到 turn-end 钩子上；它只读取最近可见消息窗口，先检查显式记忆请求和本轮是否已有直接写入，再决定是否启动抽取。抽取器通过现有通用文件工具维护 `/memories/MEMORY.md` 与 topic files，优先更新已有记忆，抽取失败则静默降级，不影响主对话。

**Tech Stack:** Flutter 3.35.7（优先 `fvm flutter`）、Dart、现有 turn hook / session context、现有 file sandbox、Flutter test

---

## 相关设计

- Spec: `docs/superpowers/specs/2026-06-25-long-term-memory-formation-design.md`
- Usage Spec: `docs/superpowers/specs/2026-06-24-long-term-memory-usage-design.md`
- Storage Spec: `docs/superpowers/specs/2026-06-19-long-term-memory-storage-design.md`
- Related: `docs/architecture/session-context-management.md`
- Related: `docs/architecture/file-sandbox-architecture.md`

## 文件结构与职责

### 新增

- `lib/services/memory/memory_formation_service.dart`
  - 基于 turn 结束触发记忆形成
  - 读取最近可见消息窗口
  - 处理显式 remember / forget 请求
  - 计算节流与跳过条件
  - 调用记忆写入协作者

- `lib/services/memory/memory_extraction_service.dart`
  - 把最近消息整理成候选记忆
  - 保留四类记忆分类
  - 优先更新已有记忆
  - 控制单次抽取写入上限

- `test/services/memory/memory_formation_service_test.dart`
  - 覆盖 turn-end 触发、节流、显式请求优先、直接写入跳过、失败退化

- `test/services/memory/memory_extraction_service_test.dart`
  - 覆盖候选抽取、去重/更新、内容截断、空输出

### 修改

- `lib/services/session_context_service.dart`
  - 在 turn 完成或 stop hook 相关路径上接入 formation 触发
  - 传入当前可见消息窗口给 formation service

- `lib/services/turn_harness.dart` 或相邻 turn 协调入口
  - 提供 turn-end 的调用点
  - 确保 formation 在主对话完成后异步运行

- `lib/services/prompt/prompt_builder_service.dart`
  - 如果形成层需要额外 prompt guidance，在非 summary stage 注入最小化说明

- `README.md`
  - 把长期记忆描述补成“存储 + 使用 + 形成”

- `AGENTS.md`
  - 补充形成层边界：只看最近消息、turn 结束触发、优先更新已有记忆、失败不阻断聊天

- `docs/architecture/session-context-management.md`
  - 说明形成层不属于 session summary，也不改 workspace 归属

## 行为约定

### 形成触发

- turn 结束时触发。
- 默认每个 eligible turn 允许一次抽取。
- 如果本轮已显式写 memory，则后台抽取跳过。
- 如果用户明确要求 ignore memory，本轮不形成新记忆。

### 输入来源

- 只使用当前可见消息窗口。
- 不扫代码、不查 git、不做额外验证。
- 优先处理最近消息中的稳定事实、偏好、纠正和项目背景。

### 写入策略

- 先查已有记忆文件。
- 能更新就更新，不优先新建。
- `MEMORY.md` 只保留索引，不写正文。
- 单次写入保持少量、短小、可复用。

### 失败策略

- 任何记忆形成失败都不能阻断主对话。
- 只记录 debug，不对用户报错。

## 任务 1: 定义 formation service 的最小接口

**Files:**
- Create: `lib/services/memory/memory_formation_service.dart`
- Create: `test/services/memory/memory_formation_service_test.dart`

- [ ] **Step 1: 写失败测试，turn 结束时可调用 formation**

```dart
test('invokes formation at turn end', () async {
  var called = false;
  final service = MemoryFormationService(
    extractor: (_) async {
      called = true;
    },
  );

  await service.onTurnComplete(messages: fakeMessages);

  expect(called, isTrue);
});
```

- [ ] **Step 2: 写失败测试，ignore memory 时跳过**

```dart
test('skips formation when user asks to ignore memory', () async {
  var called = false;
  final service = MemoryFormationService(
    extractor: (_) async {
      called = true;
    },
  );

  await service.onTurnComplete(messages: fakeMessages, userInput: 'ignore memory');

  expect(called, isFalse);
});
```

- [ ] **Step 3: 运行测试确认失败**

Run:

```bash
fvm flutter test test/services/memory/memory_formation_service_test.dart
```

- [ ] **Step 4: 最小实现 formation 入口**

实现：

- `onTurnComplete`
- 显式 ignore 判断
- 触发 extractor 的最小协作接口

- [ ] **Step 5: 运行测试确认通过**

Run:

```bash
fvm flutter test test/services/memory/memory_formation_service_test.dart
```

## Task 2: 实现最近消息窗口与节流

**Files:**
- Modify: `lib/services/memory/memory_formation_service.dart`
- Modify: `test/services/memory/memory_formation_service_test.dart`

- [ ] **Step 1: 写失败测试，默认 N = 1**

```dart
test('extracts every eligible turn by default', () async {
  ...
});
```

- [ ] **Step 2: 写失败测试，支持跳过若干 eligible turns**

```dart
test('respects turn throttle', () async {
  ...
});
```

- [ ] **Step 3: 写失败测试，只处理最近可见消息**

```dart
test('uses only the recent visible message window', () async {
  ...
});
```

- [ ] **Step 4: 最小实现节流与窗口传递**

实现：

- 记录上次抽取游标
- 只向 extractor 传最近可见消息
- 支持按 eligible turn 数跳过

- [ ] **Step 5: 运行测试确认通过**

Run:

```bash
fvm flutter test test/services/memory/memory_formation_service_test.dart
```

## Task 3: 实现去重 / 更新 / 写入上限

**Files:**
- Create: `lib/services/memory/memory_extraction_service.dart`
- Create: `test/services/memory/memory_extraction_service_test.dart`

- [ ] **Step 1: 写失败测试，优先更新已有记忆**

```dart
test('updates existing memory instead of duplicating', () async {
  ...
});
```

- [ ] **Step 2: 写失败测试，单次抽取数量受限**

```dart
test('limits extracted memories per run', () async {
  ...
});
```

- [ ] **Step 3: 写失败测试，过大内容会被截断或拒绝**

```dart
test('drops or truncates oversized memory content', () async {
  ...
});
```

- [ ] **Step 4: 最小实现抽取协作**

实现：

- 最近消息 → 候选记忆
- 读取已有 memory 文件
- 更新优先于新建
- 保持索引简短

- [ ] **Step 5: 运行测试确认通过**

Run:

```bash
fvm flutter test test/services/memory/memory_extraction_service_test.dart
```

## Task 4: 把 formation 接到 turn 完成入口

**Files:**
- Modify: `lib/services/turn_harness.dart`
- Modify: `lib/services/session_context_service.dart`
- Modify: `test/services/session_context_service_test.dart` 或最贴近的 turn 完成测试

- [ ] **Step 1: 写失败测试，turn 完成时会触发 formation**

```dart
test('turn completion triggers memory formation', () async {
  ...
});
```

- [ ] **Step 2: 写失败测试，formation 失败不影响主对话**

```dart
test('formation failures do not block chat send', () async {
  ...
});
```

- [ ] **Step 3: 最小 wiring**

把 formation service 挂到 turn 完成路径上，确保异步执行、失败静默。

- [ ] **Step 4: 运行相关测试**

Run:

```bash
fvm flutter test test/services/memory/memory_formation_service_test.dart test/services/session_context_service_test.dart
```

## Task 5: 文档与边界更新

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `docs/architecture/session-context-management.md`
- Modify: `docs/superpowers/specs/2026-06-24-long-term-memory-usage-design.md`

- [ ] **Step 1: 更新长期记忆三阶段描述**
- [ ] **Step 2: 明确 formation 只看最近消息、turn 结束触发**
- [ ] **Step 3: 明确失败退化与节流默认值**
- [ ] **Step 4: 说明 formation 与 usage 的边界**

## 验证

建议在实现后至少跑：

```bash
fvm flutter test test/services/memory/memory_formation_service_test.dart test/services/memory/memory_extraction_service_test.dart test/services/session_context_service_test.dart
fvm flutter analyze
```
