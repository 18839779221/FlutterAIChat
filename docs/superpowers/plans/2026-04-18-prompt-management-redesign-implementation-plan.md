# Prompt 管理重构实施计划

> **给执行型 agent 的要求：** 必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans` 按任务逐项执行本计划。任务步骤使用 checkbox（`- [ ]`）语法跟踪。

**目标：** 为聊天主链路、planner、summary 建立统一的 prompt 组装入口，引入默认英文/对照中文的双语 prompt 文本，移除极简模式，并将 final answer 从固定流程节点改为按需阶段。

**架构：** 保持“4 类 prompt 组成部分”的心智模型，但实现上只维护可直接编辑的命名文本块，由轻量 builder 按阶段和运行时信息拼接出最终 prompt。主链路使用完整 prompt 组装，summary / 标题生成等轻量调用走独立轻量 prompt；planner 只增加 next-action policy 增量，不再被视为 tool scheduler。

**技术栈：** Flutter 3.29.2、Dart、flutter_riverpod、flutter_test、现有 ChatService / TurnHarness / AgentPlannerService / BaseLLM / ConfigurableHttpLLM 架构。

---

## 文件地图

**Prompt 基础设施**

- 新增：`lib/services/prompt/prompt_builder_service.dart`
- 新增：`lib/services/prompt/prompt_catalog.dart`
- 新增：`lib/services/prompt/prompt_runtime_context_builder.dart`
- 新增：`lib/services/prompt/prompt_stage.dart`
- 新增：`lib/services/prompt/prompt_locale.dart`
- 新增：`test/services/prompt/prompt_builder_service_test.dart`
- 新增：`test/services/prompt/prompt_catalog_test.dart`

**主链路接入**

- 修改：`lib/services/chat_service.dart`
- 修改：`lib/services/agent_planner_service.dart`
- 修改：`lib/services/transcript_builder_service.dart`
- 修改：`lib/services/turn_harness.dart`
- 修改：`lib/controllers/chat_send_coordinator.dart`
- 修改：`lib/controllers/chat_summary_controller.dart`
- 修改：`lib/models/llm/base_llm.dart`
- 修改：`lib/models/llm/configurable_http_llm.dart`

**状态与偏好**

- 修改：`lib/controllers/chat_preferences_controller.dart`
- 修改：`lib/controllers/chat_controller.dart`
- 修改：`lib/providers/chat_collection_providers.dart`
- 修改：`lib/providers/chat_ui_providers.dart`
- 修改：`lib/pages/chat_page.dart`
- 修改：`lib/pages/settings_page.dart`

**测试**

- 修改：`test/services/agent_planner_service_test.dart`
- 修改：`test/services/transcript_builder_service_test.dart`
- 修改：`test/services/turn_harness_test.dart`
- 修改：`test/services/chat_service_structured_output_test.dart`
- 修改：`test/models/llm/configurable_http_llm_test.dart`
- 修改：`test/providers/chat_controller_tool_flow_test.dart`
- 修改：`test/providers/chat_ui_providers_test.dart`
- 修改：`test/pages/chat_page_test.dart`
- 修改：`test/widgets/chat_drawer_test.dart`
- 修改：`test/widgets/chat_message_list_interaction_test.dart`
- 修改：`test/controllers/chat_controller_test.dart`

**文档**

- 修改：`README.md`
- 修改：`AGENTS.md`
- 参考：`docs/superpowers/specs/2026-04-18-prompt-management-redesign-design.md`

## 任务 1：建立 Prompt Catalog 与 Builder 基础设施

**文件：**
- 新增：`lib/services/prompt/prompt_stage.dart`
- 新增：`lib/services/prompt/prompt_locale.dart`
- 新增：`lib/services/prompt/prompt_catalog.dart`
- 新增：`lib/services/prompt/prompt_runtime_context_builder.dart`
- 新增：`lib/services/prompt/prompt_builder_service.dart`
- 新增：`test/services/prompt/prompt_catalog_test.dart`
- 新增：`test/services/prompt/prompt_builder_service_test.dart`

- [ ] **步骤 1：先写 catalog 与 builder 的失败测试**

```dart
test('默认使用英文 chat prompt，并包含真实性与问题解决优先约束', () {
  final result = PromptBuilderService(
    catalog: PromptCatalog(),
    runtimeContextBuilder: PromptRuntimeContextBuilder(),
  ).buildSystemPrompt(
    stage: PromptStage.chat,
    locale: PromptLocale.english,
  );

  expect(result, contains('Solve the user\\'s problem'));
  expect(result, contains('Do not fabricate'));
});

test('planner prompt 包含直接回答优先级，而不是直接鼓励工具调用', () {
  final result = PromptBuilderService(
    catalog: PromptCatalog(),
    runtimeContextBuilder: PromptRuntimeContextBuilder(),
  ).buildSystemPrompt(
    stage: PromptStage.planner,
    locale: PromptLocale.english,
  );

  expect(result, contains('answer directly'));
  expect(result, contains('clarify'));
  expect(result, contains('use a tool only when'));
});
```

- [ ] **步骤 2：运行基础设施测试，确认实现尚不存在**

运行：`fvm flutter test test/services/prompt/prompt_catalog_test.dart test/services/prompt/prompt_builder_service_test.dart`

预期：FAIL，因为 prompt 目录与 builder 还不存在。

- [ ] **步骤 3：实现最小 prompt 类型与 catalog**

创建最小类型：

```dart
enum PromptStage { chat, planner, finalAnswer, summary }

enum PromptLocale { english, chinese }
```

在 `prompt_catalog.dart` 中维护双语命名文本块，至少包含：

- `base`
- `plannerDelta`
- `finalAnswerDelta`
- `summaryLightPrompt`
- `runtimeUserPromptWrapper`

- [ ] **步骤 4：实现 runtime context builder 与主 builder**

`PromptRuntimeContextBuilder` 只负责将运行时输入整理为文本块，不做复杂 schema 映射。`PromptBuilderService` 只负责选择、排序、拼接：

```dart
String buildSystemPrompt({
  required PromptStage stage,
  PromptLocale locale = PromptLocale.english,
  String? userSystemPrompt,
  List<String> runtimeSections = const [],
})
```

- [ ] **步骤 5：补齐双语一致性测试**

覆盖：

- 英文版为默认选择
- 中英文都包含关键底座约束
- `planner` 只追加 next-action delta
- 传入用户自定义 prompt 时会被包裹进 runtime section

- [ ] **步骤 6：重新运行基础设施测试**

运行：`fvm flutter test test/services/prompt/prompt_catalog_test.dart test/services/prompt/prompt_builder_service_test.dart`

预期：PASS。

- [ ] **步骤 7：提交**

```bash
git add lib/services/prompt/prompt_stage.dart lib/services/prompt/prompt_locale.dart lib/services/prompt/prompt_catalog.dart lib/services/prompt/prompt_runtime_context_builder.dart lib/services/prompt/prompt_builder_service.dart test/services/prompt/prompt_catalog_test.dart test/services/prompt/prompt_builder_service_test.dart
git commit -m "feat: add prompt catalog and builder foundation"
```

## 任务 2：接管聊天主链路与 Planner Prompt

**文件：**
- 修改：`lib/services/chat_service.dart`
- 修改：`lib/services/agent_planner_service.dart`
- 修改：`lib/controllers/chat_send_coordinator.dart`
- 修改：`lib/services/transcript_builder_service.dart`
- 修改：`lib/models/llm/configurable_http_llm.dart`
- 修改：`test/services/agent_planner_service_test.dart`
- 修改：`test/services/transcript_builder_service_test.dart`
- 修改：`test/models/llm/configurable_http_llm_test.dart`

- [ ] **步骤 1：先写主链路接入失败测试**

```dart
test('planner 请求使用 builder 产出的 planner prompt', () async {
  await service.planNextDecision(
    turn: _turn('解释 Riverpod provider 和 notifier 的区别'),
    transcript: [_userEvent('解释 Riverpod provider 和 notifier 的区别')],
    steps: const [],
    config: ChatConfig(useReasoning: false, systemPrompt: '用户偏好'),
    limits: const AgentLoopLimits(),
  );

  expect(fakeLlm.lastMessages.first.role, MessageRole.system);
  expect(fakeLlm.lastMessages.first.text, contains('next best action'));
  expect(fakeLlm.lastMessages.first.text, contains('answer directly'));
});
```

- [ ] **步骤 2：运行主链路聚焦测试**

运行：`fvm flutter test test/services/agent_planner_service_test.dart test/services/transcript_builder_service_test.dart test/models/llm/configurable_http_llm_test.dart`

预期：FAIL，因为主链路仍在直接透传原始 `systemPrompt` 字符串。

- [ ] **步骤 3：为主回答与 planner 接入 PromptBuilderService**

调整 `ChatSendCoordinator` 与 `AgentPlannerService`：

- chat 主回答使用 `PromptStage.chat`
- planner 使用 `PromptStage.planner`
- 用户自定义 prompt 作为 runtime section 注入
- 先保持 `ChatConfig.systemPrompt` 字段存在，用于兼容调用栈；但其值改为 builder 生成结果，而不是原始用户输入

- [ ] **步骤 4：整理 Final Answer transcript 的 system prompt 来源**

`TranscriptBuilderService.buildFinalAnswerMessages()` 不再无脑使用当前存储的原始 `systemPrompt`，而是接受调用方传入的阶段化 prompt 文本。先完成接口收口，再在下一任务处理中决定 final answer 是否需要触发。

- [ ] **步骤 5：补齐回归测试**

覆盖：

- chat prompt 默认英文
- planner prompt 含 next-action policy
- 用户自定义 prompt 会被包裹而不是顶替底座
- Anthropic / Chat Completions payload 能收到 builder 生成的 system prompt

- [ ] **步骤 6：重新运行主链路聚焦测试**

运行：`fvm flutter test test/services/agent_planner_service_test.dart test/services/transcript_builder_service_test.dart test/models/llm/configurable_http_llm_test.dart`

预期：PASS。

- [ ] **步骤 7：提交**

```bash
git add lib/services/chat_service.dart lib/services/agent_planner_service.dart lib/controllers/chat_send_coordinator.dart lib/services/transcript_builder_service.dart lib/models/llm/configurable_http_llm.dart test/services/agent_planner_service_test.dart test/services/transcript_builder_service_test.dart test/models/llm/configurable_http_llm_test.dart
git commit -m "refactor: route chat and planner prompts through builder"
```

## 任务 3：把 Final Answer 改成按需阶段

**文件：**
- 修改：`lib/services/turn_harness.dart`
- 修改：`lib/controllers/chat_send_coordinator.dart`
- 修改：`lib/services/transcript_builder_service.dart`
- 修改：`lib/services/chat_service.dart`
- 修改：`test/services/turn_harness_test.dart`
- 修改：`test/providers/chat_controller_tool_flow_test.dart`

- [ ] **步骤 1：先写 final answer 按需触发的失败测试**

```dart
test('无需工具且 planner 已给出可直接答复时，不再追加 final answer 调用', () async {
  final events = await harness
      .runTurn(
        turn: _turn(userInput: '解释什么是 SQLite'),
        config: ChatConfig(useReasoning: false, systemPrompt: 'base'),
      )
      .toList();

  expect(fakeChatService.finalAnswerCallCount, 0);
  expect(events.any((event) => event.eventType == ChatEventType.finalAnswer), isTrue);
});
```

- [ ] **步骤 2：运行 turn loop 聚焦测试**

运行：`fvm flutter test test/services/turn_harness_test.dart test/providers/chat_controller_tool_flow_test.dart`

预期：FAIL，因为当前流程在工具回合后仍固定走 final answer 收束。

- [ ] **步骤 3：为 TurnHarness 增加按需 final answer 判定**

明确规则：

- planner 已经给出终态用户答复且无后续工具需求时，直接落最终事件
- 只有在存在工具结果汇总、复杂 transcript 整理需求时才触发 `ChatService.streamFinalAnswer()`

可增加一个最小判定函数，例如：

```dart
bool shouldGenerateFinalAnswer({
  required ModelTurnDecision decision,
  required List<ChatEvent> transcript,
})
```

- [ ] **步骤 4：将 final answer 的 prompt 切到 `PromptStage.finalAnswer`**

当且仅当进入 final answer 阶段时，才由 builder 生成 `finalAnswer` prompt，并通过 transcript builder 投影到最终模型调用。

- [ ] **步骤 5：补齐边界测试**

覆盖：

- 直接回答回合不触发 final answer 调用
- 工具回合在需要总结时才触发 final answer
- final answer prompt 不含 planner 的动作选择语言

- [ ] **步骤 6：重新运行 turn loop 聚焦测试**

运行：`fvm flutter test test/services/turn_harness_test.dart test/providers/chat_controller_tool_flow_test.dart`

预期：PASS。

- [ ] **步骤 7：提交**

```bash
git add lib/services/turn_harness.dart lib/controllers/chat_send_coordinator.dart lib/services/transcript_builder_service.dart lib/services/chat_service.dart test/services/turn_harness_test.dart test/providers/chat_controller_tool_flow_test.dart
git commit -m "refactor: make final answer stage conditional"
```

## 任务 4：为 Summary / 标题生成切换到轻量 Prompt 路径

**文件：**
- 修改：`lib/controllers/chat_summary_controller.dart`
- 修改：`lib/models/llm/base_llm.dart`
- 修改：`lib/models/llm/configurable_http_llm.dart`
- 修改：`test/services/chat_service_structured_output_test.dart`
- 修改：`test/services/agent_planner_service_test.dart`
- 修改：`test/providers/chat_dependency_providers_test.dart`

- [ ] **步骤 1：先写 summary prompt 的失败测试**

```dart
test('summarizeConversation 使用轻量 summary prompt，而不是主聊天 prompt', () async {
  await llm.summarizeConversation(
    [ChatMessage(text: '用户问：SQLite 是什么', role: MessageRole.user)],
  );

  expect(fakeHttpClient.lastRequestBody, contains('Summarize and compress'));
  expect(fakeHttpClient.lastRequestBody, isNot(contains('next best action')));
});
```

- [ ] **步骤 2：运行 summary 聚焦测试**

运行：`fvm flutter test test/services/chat_service_structured_output_test.dart test/providers/chat_dependency_providers_test.dart`

预期：FAIL，因为当前 `summarizeConversation()` 仍依赖内置固定字符串或无专门 prompt builder。

- [ ] **步骤 3：为 summary 调用接入轻量 prompt**

`BaseLLM.summarizeConversation()` 与 `ConfigurableHttpLLM.summarizeConversation()` 接入 `PromptStage.summary`，只注入轻量任务说明与输出约束，不继承完整主对话 prompt。

- [ ] **步骤 4：在 ChatSummaryController 中去掉 prompt 直觉分支**

`ChatSummaryController` 只负责收集消息和更新标题，不再直接持有 prompt 文案逻辑；prompt 选择统一下沉到 prompt builder / LLM 层。

- [ ] **步骤 5：补齐回归测试**

覆盖：

- summary prompt 默认英文
- summary prompt 不带聊天或 planner 语气
- 标题生成仍然能更新 `isSummarized`

- [ ] **步骤 6：重新运行 summary 聚焦测试**

运行：`fvm flutter test test/services/chat_service_structured_output_test.dart test/providers/chat_dependency_providers_test.dart`

预期：PASS。

- [ ] **步骤 7：提交**

```bash
git add lib/controllers/chat_summary_controller.dart lib/models/llm/base_llm.dart lib/models/llm/configurable_http_llm.dart test/services/chat_service_structured_output_test.dart test/providers/chat_dependency_providers_test.dart
git commit -m "refactor: add lightweight summary prompt path"
```

## 任务 5：删除极简模式与相关状态

**文件：**
- 修改：`lib/controllers/chat_preferences_controller.dart`
- 修改：`lib/controllers/chat_controller.dart`
- 修改：`lib/providers/chat_ui_providers.dart`
- 修改：`lib/pages/chat_page.dart`
- 修改：`test/pages/chat_page_test.dart`
- 修改：`test/widgets/chat_drawer_test.dart`
- 修改：`test/widgets/chat_message_list_interaction_test.dart`
- 修改：`test/controllers/chat_controller_test.dart`
- 修改：`test/providers/chat_controller_tool_flow_test.dart`

- [ ] **步骤 1：先写删除极简模式后的失败测试**

```dart
testWidgets('聊天页不再展示简洁模式开关', (tester) async {
  await tester.pumpWidget(_buildChatPage());

  expect(find.text('开启简洁模式'), findsNothing);
  expect(find.text('关闭简洁模式'), findsNothing);
});
```

- [ ] **步骤 2：运行 UI 与控制器聚焦测试**

运行：`fvm flutter test test/pages/chat_page_test.dart test/controllers/chat_controller_test.dart test/widgets/chat_drawer_test.dart test/widgets/chat_message_list_interaction_test.dart test/providers/chat_controller_tool_flow_test.dart`

预期：FAIL，因为当前页面、controller 接口和 fake 仍引用 `setUseConciseMode()` 与相关 provider。

- [ ] **步骤 3：删除 provider、controller 接口与 UI 入口**

删除：

- `useConciseModeProvider`
- `cachedSystemPromptProvider`
- `ChatPreferencesController.setUseConciseMode()`
- `ChatController.setUseConciseMode()`
- 聊天页中的简洁模式按钮与状态依赖

- [ ] **步骤 4：清理测试 fake 和无关断言**

移除所有测试桩中的 `setUseConciseMode()`，改为只保留 `setSystemPrompt()`；同步删除与极简模式相关的断言。

- [ ] **步骤 5：重新运行 UI 与控制器聚焦测试**

运行：`fvm flutter test test/pages/chat_page_test.dart test/controllers/chat_controller_test.dart test/widgets/chat_drawer_test.dart test/widgets/chat_message_list_interaction_test.dart test/providers/chat_controller_tool_flow_test.dart`

预期：PASS。

- [ ] **步骤 6：提交**

```bash
git add lib/controllers/chat_preferences_controller.dart lib/controllers/chat_controller.dart lib/providers/chat_ui_providers.dart lib/pages/chat_page.dart test/pages/chat_page_test.dart test/controllers/chat_controller_test.dart test/widgets/chat_drawer_test.dart test/widgets/chat_message_list_interaction_test.dart test/providers/chat_controller_tool_flow_test.dart
git commit -m "refactor: remove concise mode prompt override"
```

## 任务 6：补齐文档、双语约束与全量验证

**文件：**
- 修改：`README.md`
- 修改：`AGENTS.md`
- 修改：`docs/superpowers/specs/2026-04-18-prompt-management-redesign-design.md`（如实施后需补充差异）
- 修改：相关测试文件中的说明性注释

- [ ] **步骤 1：先写或更新文档约束测试 / 快照断言**

如已有测试能读取文档内容则更新；若没有，至少在 prompt catalog 测试中加入双语关键句存在性断言：

```dart
test('中英文 prompt 都覆盖真实性与用户偏好不可覆盖底座', () {
  final catalog = PromptCatalog();

  expect(catalog.baseEn, contains('Do not fabricate'));
  expect(catalog.baseZh, contains('不要伪造'));
});
```

- [ ] **步骤 2：更新 README 与 AGENTS**

README 至少补充：

- prompt 管理入口
- 默认英文 prompt
- summary 轻量 prompt 路径

AGENTS 至少补充：

- prompt 双语维护策略
- 用户自定义 prompt 是 runtime section
- 极简模式已删除

- [ ] **步骤 3：运行聚焦的 prompt 与页面测试**

运行：`fvm flutter test test/services/prompt/prompt_catalog_test.dart test/services/prompt/prompt_builder_service_test.dart test/pages/chat_page_test.dart`

预期：PASS。

- [ ] **步骤 4：运行主回归测试批次**

运行：`fvm flutter test test/services/agent_planner_service_test.dart test/services/transcript_builder_service_test.dart test/services/turn_harness_test.dart test/services/chat_service_structured_output_test.dart test/models/llm/configurable_http_llm_test.dart test/providers/chat_controller_tool_flow_test.dart`

预期：PASS。

- [ ] **步骤 5：运行全量测试**

运行：`fvm flutter test`

预期：PASS。

- [ ] **步骤 6：提交**

```bash
git add README.md AGENTS.md docs/superpowers/specs/2026-04-18-prompt-management-redesign-design.md test/services/prompt/prompt_catalog_test.dart test/services/prompt/prompt_builder_service_test.dart
git commit -m "docs: finalize prompt management redesign guidance"
```

## 执行注意事项

- 优先最小化接口震荡。第一轮可以保留 `ChatConfig.systemPrompt` 字段，但要改变它的生成来源，避免一次性改穿整个调用栈。
- `PromptBuilderService` 不要演变成复杂 DSL 解释器。它只做文本块选择、排序、拼接。
- 默认英文并不意味着删除中文。两份文本必须同步维护，不能让中文版长期漂移。
- 对 `final answer` 的改造必须以测试先行，避免误伤当前 turn timeline 和事件持久化。
- 删除极简模式时，注意同步清理测试 fake，否则会留下大量接口编译错误。

## 审核备注

按技能要求，这里原本应进入计划审查循环。当前会话未获得用户对并行子 agent 审查的明确授权，因此本计划先由当前会话自审完成；若后续用户希望，我再单独发起计划审查或直接进入执行。
