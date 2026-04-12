# Tool Call UI 设计系统实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**目标：** 按已确认 spec 完成全应用设计系统落地，重构聊天页与设置页 UI，并将剩余 `tool call` 能力接入新的 block 渲染与可折叠 workflow 展示。

**架构：** 先建立基于 `ThemeData + ColorScheme + ThemeExtension` 的全局设计系统，再把聊天页从“按消息类型分支渲染”迁移到“assistant turn blocks 渲染”。`tool call` 统一落到可折叠 workflow card 中，当前步骤展开、历史步骤折叠；首版 block 先以内存映射为主，避免立刻做重型数据库迁移。

**技术栈：** Flutter、Material 3、flutter_riverpod、现有 chat/tool service、SharedPreferences 设置存储、Android Droidrun 真机自动化

---

## 执行原则

- 严格以 [2026-03-29-toolcall-ui-design-system-design.md](/Users/skka/flutterSpace/FlutterAIChat/docs/superpowers/specs/2026-03-29-toolcall-ui-design-system-design.md) 为准。
- 本计划改为 `TDD`：
  - 状态机
  - block 映射
  - workflow 折叠规则
  - composer 交互
  - 设置页基础组件
  优先采用“先写失败测试，再做最小实现，再验证通过”的节奏。
- 纯视觉 token 抽取不需要为每个常量写测试，但至少要有轻量验证，确保主题扩展和关键语义色可用。
- 每个任务组完成后都要做最小验证，不把问题堆到最后一起爆。
- 继续保持频繁、小粒度提交。

## 计划文件映射

**设计系统 / 主题**
- 修改：`lib/main.dart`
- 新增：`lib/theme/app_theme.dart`
- 新增：`lib/theme/app_colors.dart`
- 新增：`lib/theme/app_spacing.dart`
- 新增：`lib/theme/app_radius.dart`
- 新增：`lib/theme/app_component_theme.dart`

**聊天 block 协议**
- 新增：`lib/models/chat/assistant_turn_block.dart`
- 新增：`lib/models/chat/tool_workflow_step.dart`
- 新增：`lib/services/chat_block_builder.dart`
- 修改：`lib/models/chat_message.dart`
- 修改：`lib/models/response/message_content_type.dart`

**聊天 UI 组件**
- 修改：`lib/pages/chat_page.dart`
- 修改：`lib/widgets/chat_message_list.dart`
- 修改：`lib/widgets/chat_input.dart`
- 新增：`lib/widgets/chat_blocks/user_anchor_bubble.dart`
- 新增：`lib/widgets/chat_blocks/assistant_doc_block.dart`
- 新增：`lib/widgets/chat_blocks/final_response_block.dart`
- 新增：`lib/widgets/chat_blocks/structured_output_block.dart`
- 新增：`lib/widgets/chat_blocks/tool_workflow_card.dart`
- 新增：`lib/widgets/chat_blocks/tool_result_summary_row.dart`

**tool workflow / 状态映射**
- 修改：`lib/services/chat_service.dart`
- 修改：`lib/services/tool_call_service.dart`
- 修改：`lib/services/tool_orchestrator_service.dart`
- 修改：`lib/providers/chat_providers.dart`
- 修改：`lib/models/tool/tool_invocation.dart`
- 修改：`lib/models/tool/tool_result.dart`
- 修改：`lib/services/tool_executor.dart`
- 修改：`lib/services/tool_registry.dart`

**设置页**
- 修改：`lib/pages/settings_page.dart`
- 新增：`lib/widgets/settings/settings_group_section.dart`
- 新增：`lib/widgets/settings/settings_row.dart`
- 新增：`lib/widgets/settings/settings_segmented_control.dart`

**测试**
- 新增：`test/theme/app_theme_test.dart`
- 新增：`test/services/chat_block_builder_test.dart`
- 新增：`test/providers/chat_send_state_test.dart`
- 新增：`test/services/tool_workflow_mapping_test.dart`
- 新增：`test/widgets/chat_blocks/`
- 新增：`test/widgets/settings/`

**文档**
- 修改：`README.md`
- 如确有必要才修改：`AGENTS.md`

## 任务 1：建立全局设计系统主题

**文件：**
- 新增：`lib/theme/app_theme.dart`
- 新增：`lib/theme/app_colors.dart`
- 新增：`lib/theme/app_spacing.dart`
- 新增：`lib/theme/app_radius.dart`
- 新增：`lib/theme/app_component_theme.dart`
- 修改：`lib/main.dart`
- 测试：`test/theme/app_theme_test.dart`

- [ ] **步骤 1：先写失败测试**

为主题层补一组轻量测试，至少覆盖：
- `ThemeExtension` 能被挂载到 app theme
- 亮色主题下关键语义色可读取
- chat / settings 语义色角色存在

- [ ] **步骤 2：运行测试确认失败**

运行：

```bash
flutter test test/theme/app_theme_test.dart
```

预期：
- 因为主题文件和扩展尚未实现而失败

- [ ] **步骤 3：实现最小主题骨架**

新增全局 token 文件，定义：
- `Quiet Research` 聊天页语义色
- `Precision Settings` 设置页语义色
- spacing / radius / component defaults

- [ ] **步骤 4：接入 MaterialApp**

修改 `lib/main.dart`，移除当前 seed theme，接入新的 theme builder。

- [ ] **步骤 5：再次运行测试与分析**

运行：

```bash
flutter test test/theme/app_theme_test.dart
flutter analyze
```

预期：
- 主题测试通过
- analyzer 无新增错误

- [ ] **步骤 6：提交**

```bash
git add lib/main.dart lib/theme test/theme/app_theme_test.dart
git commit -m "feat: add shared app theme system"
```

## 任务 2：建立 assistant turn block 协议

**文件：**
- 新增：`lib/models/chat/assistant_turn_block.dart`
- 新增：`lib/models/chat/tool_workflow_step.dart`
- 新增：`lib/services/chat_block_builder.dart`
- 修改：`lib/models/chat_message.dart`
- 修改：`lib/models/response/message_content_type.dart`
- 测试：`test/services/chat_block_builder_test.dart`

- [ ] **步骤 1：先写 block builder 失败测试**

覆盖至少这些映射：
- 普通 assistant 文本 -> `analysis`
- 结构化 payload -> `structured_output`
- tool invocation / tool result -> workflow 相关 block
- assistant 最后一个可见正文块 -> `final_response`

- [ ] **步骤 2：运行测试确认失败**

运行：

```bash
flutter test test/services/chat_block_builder_test.dart
```

预期：
- 因 block model / builder 尚不存在或逻辑缺失而失败

- [ ] **步骤 3：实现 block model**

新增：
- `AssistantTurnBlock`
- `ToolWorkflowStep`

字段按 spec 落地，不在渲染层猜内容类型。

- [ ] **步骤 4：实现 in-memory block builder**

让现有 message/tool 数据可先映射成 block 列表，不立刻依赖 DB schema 升级。

- [ ] **步骤 5：补齐历史兼容规则**

至少处理：
- 老纯文本消息
- 老 structured card
- 老 tool invocation / result

- [ ] **步骤 6：再次运行测试与分析**

运行：

```bash
flutter test test/services/chat_block_builder_test.dart
flutter analyze
```

- [ ] **步骤 7：提交**

```bash
git add lib/models/chat lib/services/chat_block_builder.dart lib/models/chat_message.dart lib/models/response/message_content_type.dart test/services/chat_block_builder_test.dart
git commit -m "feat: add assistant turn block protocol"
```

## 任务 3：把聊天列表重构为 block 渲染

**文件：**
- 修改：`lib/widgets/chat_message_list.dart`
- 新增：`lib/widgets/chat_blocks/user_anchor_bubble.dart`
- 新增：`lib/widgets/chat_blocks/assistant_doc_block.dart`
- 新增：`lib/widgets/chat_blocks/final_response_block.dart`
- 新增：`lib/widgets/chat_blocks/structured_output_block.dart`
- 新增：`lib/widgets/chat_blocks/tool_workflow_card.dart`
- 新增：`lib/widgets/chat_blocks/tool_result_summary_row.dart`
- 测试：`test/widgets/chat_blocks/`

- [ ] **步骤 1：先写 widget 失败测试**

至少覆盖：
- 用户锚点气泡渲染
- assistant 文档块渲染
- active workflow 默认展开
- completed workflow 默认折叠
- tool result summary 只显示摘要

- [ ] **步骤 2：运行测试确认失败**

运行：

```bash
flutter test test/widgets/chat_blocks
```

预期：
- 因新组件尚未存在或行为未实现而失败

- [ ] **步骤 3：拆分语义组件**

不要再把全部渲染逻辑堆在 `chat_message_list.dart` 中，按 block 角色拆出独立 widget。

- [ ] **步骤 4：将消息列表改为时间正序**

从当前 `reverse:true` 相关逻辑迁移到旧内容在上、新内容在下的文档流展示。

- [ ] **步骤 5：实现用户锚点气泡**

保留短消息锚点功能，但压缩视觉占用。

- [ ] **步骤 6：实现 assistant 文档块和最终回复块**

确保 assistant 长内容不再使用气泡承载。

- [ ] **步骤 7：实现 structured output block**

兼容现有结构化卡片与后续字段型输出。

- [ ] **步骤 8：实现 foldable workflow card**

实现：
- 当前步骤展开
- 历史步骤折叠
- 需要确认时显示操作按钮
- 失败步骤保持展开

- [ ] **步骤 9：实现 tool result summary row**

摘要内容控制在一行标题 + 一行说明的高度目标内。

- [ ] **步骤 10：再次运行测试与分析**

运行：

```bash
flutter test test/widgets/chat_blocks
flutter analyze
```

- [ ] **步骤 11：提交**

```bash
git add lib/widgets/chat_message_list.dart lib/widgets/chat_blocks test/widgets/chat_blocks
git commit -m "feat: rebuild chat ui with block renderers"
```

## 任务 4：重构发送状态机与 workflow 状态

**文件：**
- 修改：`lib/providers/chat_providers.dart`
- 修改：`lib/services/chat_service.dart`
- 修改：`lib/services/tool_call_service.dart`
- 修改：`lib/services/tool_orchestrator_service.dart`
- 修改：`lib/widgets/chat_input.dart`
- 测试：`test/providers/chat_send_state_test.dart`

- [ ] **步骤 1：先写状态机失败测试**

覆盖至少这些转移：
- `idle -> submitting`
- `submitting -> awaitingToolConfirmation`
- `submitting -> toolRunning`
- `toolRunning -> streamingAnswer`
- `streamingAnswer -> completed`
- composer 主按钮文案切换

- [ ] **步骤 2：运行测试确认失败**

运行：

```bash
flutter test test/providers/chat_send_state_test.dart
```

预期：
- 状态转移或按钮映射尚未满足 spec

- [ ] **步骤 3：实现顶层发送状态机**

将 spec 中确认的状态显式落地：
- `idle`
- `submitting`
- `awaitingToolConfirmation`
- `toolRunning`
- `streamingAnswer`
- `completed`
- `failed`

- [ ] **步骤 4：分离 tool workflow 状态与正文输出状态**

不要继续让一套状态同时驱动 tool 过程和 assistant 文本流。

- [ ] **步骤 5：重构 compact composer**

确保：
- 可发送时显示 `发送`
- 运行中显示 `停止`
- 等待确认时显示被动状态
- 输入区高度有上限

- [ ] **步骤 6：保持确认操作只出现在 workflow card**

避免输入区与 workflow card 双重确认。

- [ ] **步骤 7：手动验证关键交互**

至少验证：
- 用户消息立即上屏
- workflow 当前步骤展开
- workflow 完成后自动折叠
- 工具完成后 assistant 可继续输出正文

- [ ] **步骤 8：再次运行测试与分析**

运行：

```bash
flutter test test/providers/chat_send_state_test.dart
flutter analyze
```

- [ ] **步骤 9：提交**

```bash
git add lib/providers/chat_providers.dart lib/services/chat_service.dart lib/services/tool_call_service.dart lib/services/tool_orchestrator_service.dart lib/widgets/chat_input.dart test/providers/chat_send_state_test.dart
git commit -m "feat: align chat state machine with workflow ui"
```

## 任务 5：重做设置页为 Precision Settings 风格

**文件：**
- 修改：`lib/pages/settings_page.dart`
- 新增：`lib/widgets/settings/settings_group_section.dart`
- 新增：`lib/widgets/settings/settings_row.dart`
- 新增：`lib/widgets/settings/settings_segmented_control.dart`
- 测试：`test/widgets/settings/`

- [ ] **步骤 1：先写设置组件失败测试**

覆盖至少：
- 分组标题渲染
- row trailing control 对齐
- segmented control 选中状态

- [ ] **步骤 2：运行测试确认失败**

运行：

```bash
flutter test test/widgets/settings
```

预期：
- 因组件缺失或结构不符而失败

- [ ] **步骤 3：抽出分组设置基础组件**

建立：
- section
- row
- segmented control

- [ ] **步骤 4：重构 settings page 布局**

将设置页改成：
- 高对比
- 清晰分组
- 轻面板
- 精密控件感

亮色主题优先，但 token 结构需要兼容深色主题。

- [ ] **步骤 5：保证现有设置功能不回归**

至少保留：
- API / baseUrl 编辑
- tool execution mode
- trusted tools 管理
- 现有模型设置项

- [ ] **步骤 6：再次运行测试与分析**

运行：

```bash
flutter test test/widgets/settings
flutter analyze
```

- [ ] **步骤 7：手动验证手机宽度下的可用性**

重点检查：
- 点击热区
- 分组间距
- 文本对比度
- 控件对齐

- [ ] **步骤 8：提交**

```bash
git add lib/pages/settings_page.dart lib/widgets/settings test/widgets/settings
git commit -m "feat: rebuild settings page with precision ui"
```

## 任务 6：补齐剩余 tool call 行为并接入新 UI

**文件：**
- 修改：`lib/services/tool_executor.dart`
- 修改：`lib/services/tool_registry.dart`
- 修改：`lib/services/tool_call_service.dart`
- 修改：`lib/services/tool_orchestrator_service.dart`
- 修改：`lib/providers/chat_providers.dart`
- 视实现需要修改平台桥接文件
- 测试：`test/services/tool_workflow_mapping_test.dart`

- [ ] **步骤 1：先写 workflow 映射失败测试**

至少覆盖：
- 支持的工具成功后 -> 折叠摘要
- 需要确认的工具 -> active workflow
- 不支持的工具 -> 可读失败摘要

- [ ] **步骤 2：运行测试确认失败**

运行：

```bash
flutter test test/services/tool_workflow_mapping_test.dart
```

预期：
- workflow 映射或结果标准化未达到要求

- [ ] **步骤 3：梳理当前已声明工具的真实完成度**

当前至少包含：
- `search_chat_history`
- `fetch_webpage`
- `save_note`
- `create_reminder`
- `create_calendar_event`
- `share_result`

输出每个工具当前属于：
- 已可用
- 部分可用
- 仅声明未接通
- 平台暂不支持

- [ ] **步骤 4：按移动端价值排序补齐**

优先顺序：
1. `search_chat_history`
2. `fetch_webpage`
3. `save_note`
4. `create_reminder`
5. `share_result`
6. `create_calendar_event`

- [ ] **步骤 5：把工具执行过程映射到 workflow event**

UI 至少能收到：
- step start
- waiting confirmation
- success summary
- failure summary

- [ ] **步骤 6：统一 unsupported / failure 展示**

即使工具暂不可用，也要进入新 UI 的折叠摘要流，而不是直接消失或只报错。

- [ ] **步骤 7：再次运行测试与分析**

运行：

```bash
flutter test test/services/tool_workflow_mapping_test.dart
flutter analyze
```

- [ ] **步骤 8：按工具簇做最小人工验证**

至少覆盖：
- 一个只读工具
- 一个需要确认的工具
- 一个失败/不支持路径

- [ ] **步骤 9：提交**

```bash
git add lib/services/tool_executor.dart lib/services/tool_registry.dart lib/services/tool_call_service.dart lib/services/tool_orchestrator_service.dart lib/providers/chat_providers.dart test/services/tool_workflow_mapping_test.dart
git commit -m "feat: wire remaining tool calls into workflow ui"
```

## 任务 7：更新 README 为当前真实链路

**文件：**
- 修改：`README.md`
- 如确有必要才修改：`AGENTS.md`

- [ ] **步骤 1：更新 README 中聊天链路描述**

只描述当前实现后的真实状态：
- 时间正序
- assistant block 渲染
- workflow 折叠卡片
- compact composer

- [ ] **步骤 2：补充自动化验证说明**

保持简洁，仅写当前有效流程。

- [ ] **步骤 3：运行最终文档前验证**

运行：

```bash
flutter analyze
flutter test
```

- [ ] **步骤 4：提交**

```bash
git add README.md AGENTS.md
git commit -m "docs: update ui and workflow chain docs"
```

## 任务 8：最终集成验证

**文件：**
- 默认不改源文件，除非验证中发现问题

- [ ] **步骤 1：在手机尺寸目标上运行应用**

重点验证：
- 首屏信息密度
- 输入区压缩效果
- workflow 折叠逻辑
- settings grouped panel 效果

- [ ] **步骤 2：验证实际配色与对比度**

确认 Flutter 真机渲染后：
- 正文可读
- 辅助文本不过灰
- workflow 与正文有清晰区分但不过度抢眼

- [ ] **步骤 3：运行回归检查**

运行：

```bash
flutter analyze
flutter test
```

- [ ] **步骤 4：运行 Android Droidrun smoke**

确认：
- 仍能正常发送消息
- compact composer 不影响基本对话
- workflow card 不阻断主链路

- [ ] **步骤 5：修复最终集成问题**

仅修复在上述验证中发现的问题。

- [ ] **步骤 6：最终提交**

```bash
git add .
git commit -m "feat: finalize tool call design system rollout"
```
