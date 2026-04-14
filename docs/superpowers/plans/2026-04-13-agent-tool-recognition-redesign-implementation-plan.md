# Agent Tool 识别重构实施计划

> **给执行型 agent 的要求：** 必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans` 按任务逐项执行本计划。任务步骤使用 checkbox（`- [ ]`）语法跟踪。

**目标：** 把当前基于工具名白名单的脆弱 tool 识别流程，升级为基于 schema、上下文和工具暴露裁剪的规划链路，提高“该不该调工具、该调哪个工具、参数该怎么填”的准确率，并让工具结果/错误能正确回灌下一轮决策。

**架构：** 保留现有 Flutter 侧 tool runtime 和 handler 体系，重点强化 decision layer。先扩展 `ToolDefinition`，让 runtime 能导出模型侧 schema 元数据；再增加 planner 的工具暴露裁剪和 prompt 构造；最后升级 LLM planner 接口，让原生 tool-calling 可以逐步替代文本 JSON 规划，而不是一次性重写全部链路。

**技术栈：** Flutter 3.29.2（优先使用 `fvm flutter`）、Dart、flutter_test、现有 tool handler/runtime registry 架构。

---

## 文件地图

**核心模型**

- 修改：`lib/models/tool/tool_definition.dart`
- 新增：`lib/models/tool/tool_argument_schema.dart`
- 新增：`lib/models/tool/tool_argument_property.dart`

**planner 决策链路**

- 修改：`lib/services/agent_planner_service.dart`
- 修改：`lib/services/transcript_builder_service.dart`
- 新增：`lib/services/planner_tool_exposure_service.dart`
- 新增：`lib/services/planner_prompt_builder.dart`

**LLM 接口**

- 修改：`lib/models/llm/base_llm.dart`
- 修改：`lib/models/llm/configurable_http_llm.dart`
- 新增：`lib/models/agent/planner_tool_option.dart`
- 新增：`lib/models/agent/planner_tool_choice.dart`

**runtime 元数据回填**

- 修改：`lib/tools/core/tool_runtime_registry.dart`
- 修改：`lib/tools/default_tool_runtime_registry.dart`
- 修改：`lib/tools/handlers/search_chat_history_tool_handler.dart`
- 修改：`lib/tools/handlers/web_search_tool_handler.dart`
- 修改：`lib/tools/handlers/fetch_webpage_tool_handler.dart`
- 修改：`lib/tools/handlers/save_note_tool_handler.dart`
- 修改：`lib/tools/handlers/create_reminder_tool_handler.dart`
- 修改：`lib/tools/handlers/create_calendar_event_tool_handler.dart`
- 修改：`lib/tools/handlers/share_result_tool_handler.dart`

**测试**

- 新增：`test/models/tool/tool_definition_test.dart`
- 新增：`test/services/planner_tool_exposure_service_test.dart`
- 新增：`test/services/planner_prompt_builder_test.dart`
- 修改：`test/services/agent_planner_service_test.dart`
- 修改：`test/services/transcript_builder_service_test.dart`
- 修改：`test/tools/core/tool_runtime_registry_test.dart`

**文档**

- 修改：`README.md`
- 修改：`AGENTS.md`

### 任务 1：增强 ToolDefinition 与 schema 导出

**文件：**
- 新增：`lib/models/tool/tool_argument_property.dart`
- 新增：`lib/models/tool/tool_argument_schema.dart`
- 修改：`lib/models/tool/tool_definition.dart`
- 修改：`lib/tools/core/tool_runtime_registry.dart`
- 新增：`test/models/tool/tool_definition_test.dart`
- 修改：`test/tools/core/tool_runtime_registry_test.dart`

- [ ] **步骤 1：先写失败测试**

```dart
test('导出给 planner 的 json schema 包含 required 字段', () {
  const definition = ToolDefinition(
    name: 'web_search',
    title: '联网搜索',
    description: '搜索外部网页',
    descriptionForModel: '当用户需要实时外部信息时使用。',
    category: ToolCategory.retrieval,
    argumentSchema: ToolArgumentSchema(
      properties: {
        'query': ToolArgumentProperty.string(
          description: '短而具体的搜索词',
        ),
      },
      required: ['query'],
    ),
  );

  expect(definition.toPlannerJsonSchema()['required'], ['query']);
});
```

- [ ] **步骤 2：运行测试，确认先红灯**

运行：`fvm flutter test test/models/tool/tool_definition_test.dart test/tools/core/tool_runtime_registry_test.dart`

预期：FAIL，因为新的 schema 模型和导出方法还不存在。

- [ ] **步骤 3：实现元数据模型**

```dart
enum ToolCategory { retrieval, productivity, outputAction }

class ToolArgumentProperty {
  final String type;
  final String description;
  final List<String>? enumValues;
  final String? format;
}
```

扩展 `ToolDefinition`，新增：

- `category`
- `descriptionForModel`
- `whenToUse`
- `whenNotToUse`
- `argumentSchema`
- `argumentExamples`
- `toPlannerJsonSchema()`
- `toPlannerDescriptor()`

- [ ] **步骤 4：让 runtime registry 暴露结构化定义**

```dart
List<ToolDefinition> getDefinitionsForPlatform(String platform) {
  return _handlersByName.values
      .map((handler) => handler.definition)
      .where((definition) => definition.supportedPlatforms.contains(platform))
      .toList(growable: false);
}
```

- [ ] **步骤 5：重新运行聚焦测试**

运行：`fvm flutter test test/models/tool/tool_definition_test.dart test/tools/core/tool_runtime_registry_test.dart`

预期：PASS。

- [ ] **步骤 6：提交**

```bash
git add lib/models/tool/tool_definition.dart lib/models/tool/tool_argument_schema.dart lib/models/tool/tool_argument_property.dart lib/tools/core/tool_runtime_registry.dart test/models/tool/tool_definition_test.dart test/tools/core/tool_runtime_registry_test.dart
git commit -m "feat: add schema-rich tool definitions"
```

### 任务 2：为所有内置工具补齐模型侧元数据

**文件：**
- 修改：`lib/tools/handlers/search_chat_history_tool_handler.dart`
- 修改：`lib/tools/handlers/web_search_tool_handler.dart`
- 修改：`lib/tools/handlers/fetch_webpage_tool_handler.dart`
- 修改：`lib/tools/handlers/save_note_tool_handler.dart`
- 修改：`lib/tools/handlers/create_reminder_tool_handler.dart`
- 修改：`lib/tools/handlers/create_calendar_event_tool_handler.dart`
- 修改：`lib/tools/handlers/share_result_tool_handler.dart`
- 修改：`test/tools/core/tool_runtime_registry_test.dart`

- [ ] **步骤 1：先扩展 registry 测试，断言每个工具都有 category、长描述和 required schema**

```dart
expect(webSearch.descriptionForModel, contains('实时'));
expect(webSearch.category, ToolCategory.retrieval);
expect(webSearch.argumentSchema.required, contains('query'));
```

- [ ] **步骤 2：运行测试，确认失败**

运行：`fvm flutter test test/tools/core/tool_runtime_registry_test.dart`

预期：FAIL，因为现有 handler 仍然只有极简 metadata。

- [ ] **步骤 3：先补 retrieval 工具**

为 `search_chat_history`、`web_search`、`fetch_webpage` 补：

- 长 `descriptionForModel`
- `whenToUse`
- `whenNotToUse`
- 结构化参数 schema
- 能区分工具边界的 examples

- [ ] **步骤 4：再补 write/action 工具**

为 `save_note`、`create_reminder`、`create_calendar_event`、`share_result` 补：

- confirmation 预期
- 缺失参数时的补槽说明
- `productivity` 或 `outputAction` 分类
- required 参数说明

- [ ] **步骤 5：重跑 metadata 测试**

运行：`fvm flutter test test/tools/core/tool_runtime_registry_test.dart`

预期：PASS。

- [ ] **步骤 6：提交**

```bash
git add lib/tools/handlers/search_chat_history_tool_handler.dart lib/tools/handlers/web_search_tool_handler.dart lib/tools/handlers/fetch_webpage_tool_handler.dart lib/tools/handlers/save_note_tool_handler.dart lib/tools/handlers/create_reminder_tool_handler.dart lib/tools/handlers/create_calendar_event_tool_handler.dart lib/tools/handlers/share_result_tool_handler.dart test/tools/core/tool_runtime_registry_test.dart
git commit -m "feat: enrich built-in tool metadata for planner use"
```

### 任务 3：增加 planner 工具暴露裁剪和 prompt 构造

**文件：**
- 新增：`lib/services/planner_tool_exposure_service.dart`
- 新增：`lib/services/planner_prompt_builder.dart`
- 修改：`lib/services/agent_planner_service.dart`
- 新增：`test/services/planner_tool_exposure_service_test.dart`
- 新增：`test/services/planner_prompt_builder_test.dart`
- 修改：`test/services/agent_planner_service_test.dart`

- [ ] **步骤 1：先写失败测试，覆盖工具暴露规则和 prompt 渲染**

```dart
test('用户消息包含 url 时优先暴露 fetch_webpage', () {
  final visible = service.selectVisibleTools(
    userInput: '请帮我读一下 https://example.com 这篇文章',
    allTools: definitions,
  );

  expect(visible.map((tool) => tool.name), contains('fetch_webpage'));
  expect(visible.map((tool) => tool.name), isNot(contains('share_result')));
});
```

```dart
test('prompt builder 会输出工具描述和退出规则', () {
  final prompt = builder.buildSystemPrompt(visibleTools: [webSearch]);
  expect(prompt, contains('什么时候使用'));
  expect(prompt, contains('什么时候不要使用'));
  expect(prompt, contains('如果已有足够信息则直接回答用户'));
});
```

- [ ] **步骤 2：运行新测试和 planner 测试，确认失败**

运行：`fvm flutter test test/services/planner_tool_exposure_service_test.dart test/services/planner_prompt_builder_test.dart test/services/agent_planner_service_test.dart`

预期：FAIL，因为服务和 prompt 接线还不存在。

- [ ] **步骤 3：实现工具暴露服务**

先上确定性规则：

- 用户输入包含 URL：暴露 `fetch_webpage`
- 明显是“搜索/最新/网上/资料”：暴露 `web_search`
- 明显是“提醒/日程/笔记/分享”：暴露对应写工具
- 纯检索轮次默认隐藏高风险写工具

- [ ] **步骤 4：实现 prompt builder**

输出内容至少包含：

- 当前可见工具列表
- 每个工具的模型侧描述
- 参数要求
- 选工具规则
- 直接回答的退出规则

然后把 `AgentPlannerService` 里原来的静态 whitelist prompt 替换掉。

- [ ] **步骤 5：重跑聚焦测试**

运行：`fvm flutter test test/services/planner_tool_exposure_service_test.dart test/services/planner_prompt_builder_test.dart test/services/agent_planner_service_test.dart`

预期：PASS，并且 planner prompt 断言不再只依赖 `_allowedToolNames`。

- [ ] **步骤 6：提交**

```bash
git add lib/services/planner_tool_exposure_service.dart lib/services/planner_prompt_builder.dart lib/services/agent_planner_service.dart test/services/planner_tool_exposure_service_test.dart test/services/planner_prompt_builder_test.dart test/services/agent_planner_service_test.dart
git commit -m "feat: expose planner tools dynamically and render rich prompts"
```

### 任务 4：把结构化 tool 状态回灌给 planner

**文件：**
- 修改：`lib/services/transcript_builder_service.dart`
- 修改：`lib/repositories/chat_event_repository.dart`
- 修改：`lib/models/chat_event.dart`
- 修改：`lib/services/agent_planner_service.dart`
- 修改：`test/services/transcript_builder_service_test.dart`
- 修改：`test/services/agent_planner_service_test.dart`

- [ ] **步骤 1：先写失败测试，覆盖 planner state 摘要**

```dart
expect(context, contains('最近一次工具失败：invalid_due_at'));
expect(context, contains('最近一次工具结果：已读取网页正文'));
expect(context, contains('已尝试工具：web_search, fetch_webpage'));
```

- [ ] **步骤 2：运行 transcript/planner 测试，确认失败**

运行：`fvm flutter test test/services/transcript_builder_service_test.dart test/services/agent_planner_service_test.dart`

预期：FAIL，因为当前 planner context 只包含最新工具结果的一条文本摘要。

- [ ] **步骤 3：把 transcript builder 扩展成结构化 planner state 渲染器**

优先用 event payload 汇总：

- 已尝试工具列表
- 最近一次工具调用
- 最近一次工具结果摘要
- 最近一次工具错误码
- 已知 URL

- [ ] **步骤 4：补足 planner 需要的 payload 存储**

如果当前 repository 并没有稳定保存 planner 需要的字段，就在不破坏现有 UI 的前提下补齐 payload。

- [ ] **步骤 5：重跑聚焦测试**

运行：`fvm flutter test test/services/transcript_builder_service_test.dart test/services/agent_planner_service_test.dart`

预期：PASS。

- [ ] **步骤 6：提交**

```bash
git add lib/services/transcript_builder_service.dart lib/repositories/chat_event_repository.dart lib/models/chat_event.dart lib/services/agent_planner_service.dart test/services/transcript_builder_service_test.dart test/services/agent_planner_service_test.dart
git commit -m "feat: add structured planner context from tool events"
```

### 任务 5：引入原生 planner tool-calling 接口

**文件：**
- 新增：`lib/models/agent/planner_tool_option.dart`
- 新增：`lib/models/agent/planner_tool_choice.dart`
- 修改：`lib/models/llm/base_llm.dart`
- 修改：`lib/models/llm/configurable_http_llm.dart`
- 修改：`lib/services/agent_planner_service.dart`
- 修改：`test/services/agent_planner_service_test.dart`
- 修改：`test/services/chat_service_structured_output_test.dart`

- [ ] **步骤 1：先写失败测试，覆盖结构化 planner 请求**

```dart
test('会把可见工具 schema 传给 llm planner 请求', () async {
  await service.planNextAction(...);
  expect(llm.lastToolOptions.single.name, 'web_search');
});
```

```dart
test('能直接解析原生 planner tool choice，不再依赖 json 抓取', () async {
  final result = await service.planNextAction(...);
  expect(result.toolCall!.toolName, 'fetch_webpage');
});
```

- [ ] **步骤 2：运行 planner 相关测试，确认失败**

运行：`fvm flutter test test/services/agent_planner_service_test.dart test/services/chat_service_structured_output_test.dart`

预期：FAIL，因为 `BaseLLM.planNextAction()` 目前只接收 `messages` 和 `config`，并返回 `String`。

- [ ] **步骤 3：新增结构化 planner request/response 模型**

```dart
class PlannerToolOption {
  final String name;
  final Map<String, dynamic> inputSchema;
  final String description;
}

class PlannerToolChoice {
  final String? response;
  final String? toolName;
  final Map<String, dynamic>? arguments;
}
```

- [ ] **步骤 4：升级 `BaseLLM` 和 `ConfigurableHttpLLM`**

采用非一次性切换的迁移路径：

- 临时保留 legacy string planner helper
- 增加新的结构化 planner 方法
- `AgentPlannerService` 优先走结构化输出，不支持时再回退到旧解析逻辑

- [ ] **步骤 5：重跑 planner 测试**

运行：`fvm flutter test test/services/agent_planner_service_test.dart test/services/chat_service_structured_output_test.dart`

预期：PASS，且至少有一个测试证明 service 已经可以绕开自由文本 JSON 解析。

- [ ] **步骤 6：提交**

```bash
git add lib/models/agent/planner_tool_option.dart lib/models/agent/planner_tool_choice.dart lib/models/llm/base_llm.dart lib/models/llm/configurable_http_llm.dart lib/services/agent_planner_service.dart test/services/agent_planner_service_test.dart test/services/chat_service_structured_output_test.dart
git commit -m "feat: add native planner tool-calling interface"
```

### 任务 6：补回归夹具、更新文档并做总验证

**文件：**
- 新增：`test/services/planner_decision_regression_test.dart`
- 修改：`README.md`
- 修改：`AGENTS.md`

- [ ] **步骤 1：先写 planner 回归夹具**

至少覆盖：

- 搜聊天记录
- 联网搜索
- 读取 URL
- 无需工具直接回答
- reminder 缺时间时不能盲目执行
- 纯检索轮次不暴露写工具

- [ ] **步骤 2：运行回归测试，确认先失败**

运行：`fvm flutter test test/services/planner_decision_regression_test.dart`

预期：FAIL，直到前面的 planner 改造全部到位。

- [ ] **步骤 3：实现夹具测试 harness 并稳定预期**

优先使用 deterministic fake LLM 和 prompt 检查，不依赖真实网络调用。

- [ ] **步骤 4：更新项目文档**

在 `README.md` 和 `AGENTS.md` 里补充：

- 更强的 `ToolDefinition` 职责
- planner 工具暴露策略
- 结构化 planner state
- 原生 tool-calling 支持与 fallback 路径

- [ ] **步骤 5：运行最终验证**

运行：

```bash
fvm flutter test test/models/tool/tool_definition_test.dart test/tools/core/tool_runtime_registry_test.dart test/services/planner_tool_exposure_service_test.dart test/services/planner_prompt_builder_test.dart test/services/transcript_builder_service_test.dart test/services/agent_planner_service_test.dart test/services/chat_service_structured_output_test.dart test/services/planner_decision_regression_test.dart
fvm flutter analyze
```

预期：上述测试全部 PASS，analyze 不引入新的问题。

- [ ] **步骤 6：提交**

```bash
git add test/services/planner_decision_regression_test.dart README.md AGENTS.md
git commit -m "test: add planner regression coverage and update docs"
```

## 执行说明

- 先完成任务 1 到任务 4，再触碰 `BaseLLM`。这样可以先拿到低风险增益，再进入接口升级。
- 任务 5 是接口迁移，不是重写。legacy planner 解析要临时保留，等结构化路径稳定后再考虑清理。
- 当前工作区已经有用户自己的未提交改动，执行时不要回滚、不要覆盖无关编辑。
- 默认使用 `fvm flutter ...`，除非已经明确确认当前 `flutter` 就是 `3.29.2`。

## 说明

本轮没有额外跑“计划评审 subagent”，因为当前会话未获得显式的多 agent 委派授权。后续如果允许委派，再补一次计划 review 即可。
