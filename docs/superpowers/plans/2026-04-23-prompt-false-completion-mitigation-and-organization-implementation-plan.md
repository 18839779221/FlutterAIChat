# Prompt 虚假完成缓解与组织重整实施计划

> 执行原则：先按本计划完成 prompt 文档与结构调整，再进入具体实现；不要一边补规则一边继续散落式修改 prompt 文案。

## 目标

- 将当前 prompt 从扁平字符串组织升级为稳定的 section 化拼装
- 优先直接复用参考文档中已验证有效的 prompt 原文
- 增强 planner / chat / finalAnswer 对“忠实汇报、完成前验证、真实落地执行、专用工具优先”的行为约束
- 保持 summary prompt 轻量

## 范围

### 涉及文件

- `lib/services/prompt/prompt_catalog.dart`
- `lib/services/prompt/prompt_builder_service.dart`
- `lib/services/prompt/prompt_runtime_context_builder.dart`
- `test/services/prompt/prompt_catalog_test.dart`
- `test/services/prompt/prompt_builder_service_test.dart`
- 如有必要：
  - `README.md`
  - `AGENTS.md`

### 本轮不改

- `TurnHarness`
- `AgentPlannerService` 的决策协议
- `TurnVerifier`
- tool executor / tool ledger
- UI 展示逻辑

## 实施步骤

### 任务 1：整理参考原文并映射到 section

- [ ] 从参考文档中提取可直接复用的高价值 prompt 原文
- [ ] 标注哪些原文进入 `doingTasks`
- [ ] 标注哪些原文进入 `usingTools`
- [ ] 标注哪些原文进入 `reportingAndVerification`
- [ ] 明确哪些内容只适合 `planner`、哪些应进入 `chat/finalAnswer`

验收：

- 形成一份清晰的原文映射表
- 不新增无必要的意译式改写

### 任务 2：重构 PromptCatalog 为 section 化组织

- [ ] 保留当前 `base/stageDelta/wrapUserPrompt` 的对外语义兼容能力，或以新的内部 section 组合方式实现同等能力
- [ ] 新增稳定 section 方法，例如：
  - `identityAndCoreRules`
  - `doingTasks`
  - `usingTools`
  - `reportingAndVerification`
  - `communication`
- [ ] `stageDelta` 继续负责阶段职责差异，不承载所有底座规则
- [ ] 中英文内容结构尽量对齐

验收：

- `PromptCatalog` 不再只是两大段扁平字符串
- 高价值规则有清晰归属

### 任务 3：调整 PromptBuilderService 拼装顺序

- [ ] 定义稳定拼装顺序：
  1. identity/core
  2. doing tasks
  3. using tools
  4. reporting and verification
  5. communication
  6. stage delta
  7. runtime sections
- [ ] `summary` 阶段继续走轻量路径，不拼入全部 section
- [ ] 保持 user system prompt 仍通过 runtime wrapper 注入

验收：

- 各阶段 prompt 顺序稳定
- summary prompt 未被意外加重

### 任务 4：强化阶段化规则

- [ ] planner prompt 明确“不要把计划写成完成结果”
- [ ] chat prompt 明确“不要把未执行或未验证的动作说成成功”
- [ ] finalAnswer prompt 明确“只能基于已获得信息和已确认结果作答”
- [ ] 保持原有“直接回答优先、必要时澄清、需要时再用工具”的 planner 优先级

验收：

- planner / chat / finalAnswer 之间的职责边界更清楚
- 防虚假完成约束已进入正确阶段

### 任务 5：补测试并回归

- [ ] 更新 `prompt_catalog_test.dart`
- [ ] 更新 `prompt_builder_service_test.dart`
- [ ] 增加断言：
  - 参考原文关键句存在
  - planner 包含 next-action 约束
  - reporting/verification section 被正确拼入 chat/finalAnswer
  - summary 不包含重型 section
  - user prompt wrapper 仍正常工作
- [ ] 运行聚焦测试

建议命令：

```bash
flutter test test/services/prompt/prompt_catalog_test.dart test/services/prompt/prompt_builder_service_test.dart
```

### 任务 6：文档同步

- [ ] 如 prompt 组织方式已经发生明显变化，更新 `README.md`
- [ ] 若形成新的长期约束或写作原则，更新 `AGENTS.md`

## 风险控制

- 不通过继续追加散乱 prompt 句子来“快速修好”问题
- 不把参考原文随意改写成语义接近但力度变弱的新文案
- 不在本轮混入状态机、verifier、capability contract 等架构层改动
- 若发现 prompt 变更不足以解决问题，后续单独开架构治理方案，而不是在本轮继续堆启发式规则

## 完成定义

当以下条件全部满足时，本计划完成：

- `PromptCatalog` 已 section 化
- 关键参考 prompt 原文已尽量直接复用
- `PromptBuilderService` 已按新顺序拼装
- prompt 相关测试全部通过
- 文档已同步到位

## 实施后下一步

本计划完成后，再单独进入“虚假完成声明”的架构层治理，包括但不限于：

- planner 终态约束
- turn verifier 扩展
- tool capability 与真实完成态绑定
- UI 上对“计划 / 已执行 / 已验证”的显式区分
