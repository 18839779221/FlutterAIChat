# Debug 测试案例库设计

## 背景

当前调试与端到端验证使用的测试 case 分散在两个地方：

- `lib/widgets/chat_empty_state.dart` 中硬编码的 4 个空状态示例
- 已有 Markdown 文档中的人工测试步骤

这两个来源都不适合持续维护：

- 空状态案例数量有限，只适合演示，不适合作为完整测试库
- Markdown 适合阅读，不适合 App 内消费和自动化读取
- 案例没有单一数据源，容易出现内容漂移

用户希望建立一个更系统的 Debug 测试案例系统，满足以下目标：

- 测试 case 以本地文件持久化并进入版本管理
- Debug 阶段可以用最少交互选到全量 case
- 后续可以被自动化脚本或 E2E runner 直接读取
- 第一阶段先解决案例文本的统一维护，不引入复杂断言系统

## 目标

建立一套以结构化 JSON 为主数据源的 Debug 测试案例库，并在 Debug 模式下提供一个最短路径入口来选择和注入全量测试 case。

## 非目标

本阶段不包含以下内容：

- 不实现完整自动执行 runner
- 不为 case 增加复杂断言 DSL
- 不把调试案例存入 SQLite
- 不做搜索、排序、批量执行等高级 UI
- 不保留第二套 Markdown case 主数据源

## 方案概览

采用单一结构化数据源方案：

- 新增 `assets/debug/test_cases.json` 作为唯一测试 case 数据源
- App 通过轻量 loader / repository 读取并暴露案例数据
- 空状态精选案例从 JSON 中读取 `featured` 条目，不再硬编码
- Debug 模式下在聊天页增加一个常驻 `Cases` 入口
- 选择 case 后将 `prompt` 填充到输入框，由用户决定是否发送
- 删除 `docs/agent-loop-e2e-test-cases.md`，避免双份维护

该方案兼顾人工调试与未来自动化：

- 对人工调试来说，进入聊天页后只需 `点 Cases -> 点案例 -> 发送`
- 对自动化来说，结构化 JSON 比 Markdown 更稳定且更容易扩展

## 数据模型

### 文件位置

- `assets/debug/test_cases.json`

### 根结构

```json
{
  "version": 1,
  "cases": []
}
```

### Case 字段

每条 case 至少包含以下字段：

- `id`
  - 稳定唯一标识，供自动化与未来引用使用
- `title`
  - 列表展示标题
- `summary`
  - 列表中的一行简介
- `prompt`
  - 实际注入输入框或自动化消费的完整消息
- `tags`
  - 用于轻量分类和未来自动化筛选
- `featured`
  - 是否作为空状态精选案例展示
- `enabled`
  - 是否启用，便于临时屏蔽 case 而不删除记录

示例：

```json
{
  "id": "agent-loop-plain-answer",
  "title": "纯文本直答",
  "summary": "验证无需工具时能直接完成回答。",
  "prompt": "用一句话解释什么是 SQLite",
  "tags": ["agent-loop", "plain-answer"],
  "featured": true,
  "enabled": true
}
```

### 扩展策略

第一阶段不加入断言字段，但结构需要允许平滑扩展。未来如果接入自动化 runner，可以新增：

- `preconditions`
- `expected`
- `modeHints`
- `platforms`

这些新增字段不应破坏现有 UI 对基础字段的读取。

## 运行时边界

### Debug case loader / repository

新增一个专门的调试案例读取层，职责保持单一：

- 读取 JSON asset
- 反序列化为模型
- 过滤 `enabled == true`
- 提供全量列表与精选列表

不要把 JSON 读取逻辑塞进 `ChatDebugController` 或 Widget 中，避免后续 Debug 逻辑继续膨胀。

### 空状态接入

`ChatEmptyState` 不再维护默认常量案例。改为消费统一案例源中 `featured == true` 的前几个条目，保持当前轻量精选体验，同时避免双份数据源。

### 聊天页 Debug 入口

仅在 `kDebugMode` 下显示 `Cases` 入口。入口应满足：

- 任何时候都可打开，不依赖当前会话是否为空
- 打开后直接显示全量案例列表
- 无需额外分类跳转
- 选择后直接将 `prompt` 注入输入框

第一阶段默认行为是填充输入框而不是自动发送，原因如下：

- 更安全，避免误触发副作用型测试消息
- 允许在发送前根据当前上下文微调输入
- 与现有聊天提交流程解耦，实现更稳定

## UI 设计

### Debug 入口

聊天页在 Debug 模式下增加一个小型 `Cases` 操作入口。入口位置应靠近现有顶部操作区，使其始终可访问。

### Cases 面板

点击入口后展示一个简洁的底部面板，直接列出全量可用案例。每个条目展示：

- 标题
- 一行简述
- prompt 预览

第一阶段不实现搜索和复杂筛选，优先保证最少点击路径与稳定性。

### 选择行为

选择某个 case 后：

1. 关闭面板
2. 将 `prompt` 写入输入框
3. 聚焦输入框，方便用户直接发送或微调

## 测试策略

### 单元测试

- JSON 模型编解码测试
- repository / loader 读取与过滤测试
- `featured` 提取逻辑测试

### Widget 测试

- Debug 模式下 `Cases` 入口可见
- 打开面板后展示全量 enabled case
- 点击 case 后输入框被正确填充
- 空状态 suggestions 来源于统一 case 数据

### 回归关注点

- 非 Debug 模式下不应暴露 `Cases` 入口
- 输入框填充行为不能破坏现有发送流程
- 删除旧 Markdown 文档后，仓库内不应再有第二套主 case 数据源

## 文档影响

需要同步更新：

- `README.md`
  - 说明 Debug 测试案例库的存放位置和使用方式
- `AGENTS.md`
  - 当前已覆盖“需求变化时更新 AGENTS.md”的通用规则，本次无需额外新增专门流程约束

需要移除：

- `docs/agent-loop-e2e-test-cases.md`

## 验收标准

满足以下条件即可视为本阶段完成：

1. 仓库中存在唯一结构化 case 数据源 `assets/debug/test_cases.json`
2. 空状态案例从统一 JSON 数据读取，不再硬编码
3. Debug 模式下聊天页可直接访问全量案例列表
4. 选择案例后可用最少步骤将消息注入输入框
5. 测试覆盖 JSON 读取、精选案例映射和 Debug 入口注入流程
