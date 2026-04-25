# WebFetch Prompt 驱动处理与卡片重设计 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `fetch_webpage` 从“读取网页正文”改造成“按 `url + prompt` 处理公共网页内容”的工具，并让卡片默认展示 `host + prompt + 处理结果预览`。

**Architecture:** 保持现有 tool runtime、turn loop 和 tool-specific renderer 体系不变，围绕 `fetch_webpage` 做定向重构。先收敛 handler 的 schema、`descriptionForModel`、side model 调用与 result payload，再同步更新 `ChatBlockBuilder` 与 `fetch_webpage` 专属 renderer，让 workflow/result 共用单卡片生命周期并以 prompt 为主展示线索。

**Tech Stack:** Flutter, Dart, Riverpod, flutter_test, fvm Flutter 3.29.2

---

## File Boundaries

### Create

- `test/tools/handlers/fetch_webpage_tool_handler_test.dart`
  - 锁定 `fetch_webpage` 的 schema、参数归一化、`descriptionForModel` 与上下文消息投影行为。

### Modify

- `lib/tools/handlers/fetch_webpage_tool_handler.dart`
  - 将参数从 `url + extractMode` 改为 `url + prompt`，更新 `descriptionForModel` / `localizedDescriptionForModel`，并把执行逻辑切换为“抓取网页 + side model 处理”。
- `lib/services/default_tool_adapters.dart`
  - 收敛 `fetch_webpage` 结果 payload，稳定输出 `url`、`host`、`prompt`、`resultPreview`、`processedContent`、`finalUrl`、`redirectUrl`、`rawExcerpt`、`failureReason` 等 renderer 需要的字段。
- `lib/services/chat_block_builder.dart`
  - 确保 `fetch_webpage` workflow/result 的原位替换逻辑继续成立，并让结果卡能稳定拿到 prompt 与结果预览字段。
- `lib/widgets/tool_renderers/fetch_webpage_tool_workflow_card.dart`
  - workflow 卡改为两行布局，展示 `host + prompt`，不再强调原始网页正文。
- `lib/widgets/tool_renderers/fetch_webpage_tool_result_card.dart`
  - result 卡改为折叠态 `host + prompt + 处理结果预览`，展开态改为 `Prompt / 处理结果 / 来源与细节` 三段。
- `test/widgets/tool_renderers/fetch_webpage_tool_cards_test.dart`
  - 覆盖 workflow/result 卡片的新字段与交互。
- `README.md`
  - 更新 `fetch_webpage` 的能力描述与工具卡片展示说明。
- `AGENTS.md`
  - 仅在实现确实改变了工具契约或 tool-use UI 约束时补充规则，避免和 spec 重复。

### Review During Implementation

- `lib/widgets/tool_renderers/research_tool_card_shell.dart`
  - 确认现有 shared shell 是否还能满足 `fetch_webpage` 新展开结构；若不能，则仅做最小扩展，不引入新的统一业务 model。
- `lib/providers/chat_providers.dart`
  - 确认 renderer 注册处无需额外改动；若 result/workflow 类型签名变化，则做最小接线调整。

---

## Task 1: Lock the New Tool Contract with Tests

**Files:**
- Create: `test/tools/handlers/fetch_webpage_tool_handler_test.dart`
- Modify: `lib/tools/handlers/fetch_webpage_tool_handler.dart`

- [ ] **Step 1: Write the failing handler contract tests**

Add tests that define the new contract before changing implementation:

```dart
test('definition exposes only url and prompt arguments', () {
  final handler = FetchWebpageToolHandler(
    webpageFetcher: ({
      required String url,
      required String prompt,
    }) async =>
        ToolResult.success(
          toolName: 'fetch_webpage',
          summary: 'ok',
          payload: {'url': url, 'prompt': prompt},
        ),
  );

  expect(handler.definition.parameters, {
    'url': 'string',
    'prompt': 'string',
  });
  expect(
    handler.definition.argumentSchema.required,
    ['url', 'prompt'],
  );
  expect(
    handler.definition.argumentSchema.properties['prompt']?.description,
    contains('extract, summarize, inspect, compare, or transform'),
  );
});

test('descriptionForModel mentions internal side model and does not repeat Input section', () {
  final definition = FetchWebpageToolHandler(
    webpageFetcher: ({
      required String url,
      required String prompt,
    }) async =>
        ToolResult.success(toolName: 'fetch_webpage', summary: 'ok'),
  ).definition;

  expect(definition.descriptionForModel, contains('internal side model'));
  expect(definition.descriptionForModel, isNot(contains('Input:')));
});

test('normalizeArguments requires both url and prompt', () async {
  final handler = FetchWebpageToolHandler(
    webpageFetcher: ({
      required String url,
      required String prompt,
    }) async =>
        ToolResult.success(toolName: 'fetch_webpage', summary: 'ok'),
  );

  final invalid = await handler.normalizeArguments(
    rawArguments: {'url': 'https://flutter.dev'},
    userMessage: 'read it',
    history: const [],
    now: DateTime(2026, 4, 25),
  );

  expect(invalid.isValid, isFalse);
  expect(invalid.errorSummary, contains('prompt'));
});
```

- [ ] **Step 2: Run the new handler test to confirm failure**

Run:

```bash
fvm flutter test test/tools/handlers/fetch_webpage_tool_handler_test.dart
```

Expected: FAIL because the current handler still uses `extractMode` and the old description.

- [ ] **Step 3: Update `ToolDefinition` and argument normalization**

Implement the new handler contract:

```dart
parameters: {
  'url': 'string',
  'prompt': 'string',
},
argumentSchema: ToolArgumentSchema(
  properties: {
    'url': ToolArgumentProperty.string(
      description: 'Fully qualified public URL to read.',
      localizedDescription: LocalizedToolText(
        english: 'Fully qualified public URL to read.',
        chinese: '要读取的完整公共网页链接。',
      ),
      format: 'uri',
    ),
    'prompt': ToolArgumentProperty.string(
      description:
          'Instructions describing what to extract, summarize, inspect, compare, or transform from the page content.',
      localizedDescription: LocalizedToolText(
        english:
            'Instructions describing what to extract, summarize, inspect, compare, or transform from the page content.',
        chinese: '描述要从网页内容中提取、总结、检查、比较或转换什么信息的指令。',
      ),
    ),
  },
  required: ['url', 'prompt'],
),
```

And in `normalizeArguments()`:

```dart
final prompt = rawArguments['prompt'];
if (prompt is! String || prompt.trim().isEmpty) {
  return ToolArgumentResolution.invalid(
    errorCode: 'invalid_prompt',
    errorSummary: '读取网页失败：缺少处理网页内容的 prompt',
  );
}

return ToolArgumentResolution.valid({
  'url': url.trim(),
  'prompt': prompt.trim(),
});
```

- [ ] **Step 4: Replace `descriptionForModel` and localized copy**

Set `descriptionForModel` to the spec-approved version and keep the Chinese localization structurally aligned:

```dart
descriptionForModel:
    'Read a public webpage at a specific URL and process its content according to a prompt.\n\n'
    'IMPORTANT: This tool is for public, unauthenticated webpages. It may fail for private or authenticated URLs such as Google Docs, Confluence, Jira, GitHub pages that require login, or other workspace-only content. Before using this tool, check whether a specialized MCP tool or another authenticated integration is available, and prefer that when possible.\n\n'
    'Use this tool when you already have a concrete URL and need to read or process that page for a specific purpose.\n\n'
    'This tool fetches the webpage, extracts readable content, and uses an internal side model to process that content according to the prompt. It returns the processed result rather than simply returning the raw page text. If the page is very long, the result may be condensed. If the URL redirects to a different host, the tool may require a new request using the redirected URL.\n\n'
    'Do not use this tool just to discover relevant pages; use web_search first when you need to find candidate sources. Do not use this tool for GitHub resources that are better handled by Bash or dedicated tools.\n\n'
    'This tool is read-only and does not modify files.',
```

- [ ] **Step 5: Re-run the handler tests**

Run:

```bash
fvm flutter test test/tools/handlers/fetch_webpage_tool_handler_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit the contract change**

```bash
git add \
  lib/tools/handlers/fetch_webpage_tool_handler.dart \
  test/tools/handlers/fetch_webpage_tool_handler_test.dart
git commit -m "refactor: redefine fetch_webpage as prompt-driven reader"
```

---

## Task 2: Introduce Side-Model Processing and Stable Result Payload Fields

**Files:**
- Modify: `lib/tools/handlers/fetch_webpage_tool_handler.dart`
- Modify: `lib/services/default_tool_adapters.dart`
- Modify: `test/tools/handlers/fetch_webpage_tool_handler_test.dart`

- [ ] **Step 1: Extend tests for side-model processing and context projection**

Add failing tests that lock the new runtime behavior:

```dart
test('execute passes url and prompt to webpageFetcher', () async {
  late String capturedUrl;
  late String capturedPrompt;
  final handler = FetchWebpageToolHandler(
    webpageFetcher: ({
      required String url,
      required String prompt,
    }) async {
      capturedUrl = url;
      capturedPrompt = prompt;
      return ToolResult.success(
        toolName: 'fetch_webpage',
        summary: '已返回网页处理结果',
        payload: {
          'url': url,
          'host': 'flutter.dev',
          'prompt': prompt,
          'processedContent': '处理后的正文',
        },
      );
    },
  );

  await handler.execute(
    ToolExecutionContext(
      toolCallId: 'call_1',
      toolName: 'fetch_webpage',
      arguments: {
        'url': 'https://flutter.dev',
        'prompt': '提取文中和 TextField 焦点问题相关的信息',
      },
      userMessage: 'read this',
      conversationHistory: const [],
      now: DateTime(2026, 4, 25),
    ),
  );

  expect(capturedUrl, 'https://flutter.dev');
  expect(capturedPrompt, contains('TextField'));
});

test('buildContextMessages uses processed result instead of raw webpage body label', () {
  final messages = FetchWebpageToolHandler(
    webpageFetcher: ({
      required String url,
      required String prompt,
    }) async =>
        ToolResult.success(toolName: 'fetch_webpage', summary: 'ok'),
  ).buildContextMessages(
    result: ToolResult.success(
      toolName: 'fetch_webpage',
      summary: '已返回网页处理结果',
      payload: {
        'url': 'https://flutter.dev',
        'prompt': '总结动画抖动成因',
        'processedContent': '页面提到频繁 rebuild 可能导致抖动。',
      },
    ),
    context: ToolExecutionContext(
      toolCallId: 'call_1',
      toolName: 'fetch_webpage',
      arguments: const {},
      userMessage: 'read',
      conversationHistory: const [],
      now: DateTime(2026, 4, 25),
    ),
  );

  expect(messages.single.text, contains('处理结果'));
  expect(messages.single.text, isNot(contains('网页正文')));
});
```

- [ ] **Step 2: Run the handler test again to confirm failure**

Run:

```bash
fvm flutter test test/tools/handlers/fetch_webpage_tool_handler_test.dart
```

Expected: FAIL because the execute path and context projection still follow the old raw-page wording.

- [ ] **Step 3: Update the fetcher signature to take `prompt`**

Adjust the `WebpageFetcher` usage in `fetch_webpage_tool_handler.dart` so `execute()` forwards both `url` and `prompt`:

```dart
@override
Future<ToolResult> execute(ToolExecutionContext context) {
  return _webpageFetcher(
    url: context.arguments['url'] as String,
    prompt: context.arguments['prompt'] as String,
  );
}
```

If the typedef still expects `extractMode`, update the source typedef in `lib/services/tool_executor.dart` or its home file to:

```dart
typedef WebpageFetcher = Future<ToolResult> Function({
  required String url,
  required String prompt,
});
```

- [ ] **Step 4: Rebuild the context text around processed content**

Update `_buildContextText()` so it projects prompt and processed result first:

```dart
final prompt = (payload['prompt'] ?? '').toString().trim();
if (prompt.isNotEmpty) {
  buffer.writeln('处理目标：$prompt');
}

final processedContent = (payload['processedContent'] ?? '').toString().trim();
if (processedContent.isNotEmpty) {
  buffer.writeln(
    '处理结果：${_truncateContextText(processedContent, maxLength: 1200)}',
  );
} else if (toolResult.summary.isNotEmpty) {
  buffer.writeln('结果摘要：${toolResult.summary}');
}
```

- [ ] **Step 5: Normalize adapter payload fields for renderer consumption**

In `lib/services/default_tool_adapters.dart`, update the `fetch_webpage` adapter result shape so success/failure both produce stable keys:

```dart
return ToolResult.success(
  toolName: 'fetch_webpage',
  summary: '已返回网页处理结果',
  payload: {
    'url': requestUrl,
    'host': Uri.tryParse(requestUrl)?.host ?? requestUrl,
    'prompt': prompt,
    'processedContent': processedContent,
    'resultPreview': processedContent.trim(),
    'finalUrl': finalUrl,
    'redirectUrl': redirectUrl,
    'rawExcerpt': rawExcerpt,
  },
);
```

And failure:

```dart
return ToolResult.failure(
  toolName: 'fetch_webpage',
  summary: '读取失败：$reason',
  errorMessage: reason,
  payload: {
    'url': requestUrl,
    'host': Uri.tryParse(requestUrl)?.host ?? requestUrl,
    'prompt': prompt,
    'failureReason': reason,
    'finalUrl': finalUrl,
    'redirectUrl': redirectUrl,
  },
);
```

- [ ] **Step 6: Re-run the handler tests**

Run:

```bash
fvm flutter test test/tools/handlers/fetch_webpage_tool_handler_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit the side-model payload work**

```bash
git add \
  lib/tools/handlers/fetch_webpage_tool_handler.dart \
  lib/services/default_tool_adapters.dart \
  test/tools/handlers/fetch_webpage_tool_handler_test.dart
git commit -m "feat: add prompt-driven fetch_webpage result payload"
```

---

## Task 3: Keep Block Projection Aligned with the New Single-Card Lifecycle

**Files:**
- Modify: `lib/services/chat_block_builder.dart`
- Modify: `test/services/chat_block_builder_test.dart`

- [ ] **Step 1: Add a regression test for fetch_webpage result replacement**

Extend `test/services/chat_block_builder_test.dart` with a case that ensures `fetch_webpage` result still replaces workflow in place and retains prompt/result preview fields:

```dart
test('fetch_webpage result replaces workflow block in place and keeps prompt preview', () {
  final builder = ChatBlockBuilder();
  final blocks = builder.buildAssistantTurnBlocks([
    _toolWorkflowMessage(
      toolName: 'fetch_webpage',
      details: {
        'url': 'https://flutter.dev',
        'prompt': '提取和焦点丢失相关的信息',
      },
    ),
    _toolResultMessage(
      toolName: 'fetch_webpage',
      data: {
        'url': 'https://flutter.dev',
        'host': 'flutter.dev',
        'prompt': '提取和焦点丢失相关的信息',
        'resultPreview': '页面提到频繁 rebuild 可能导致焦点丢失。',
      },
    ),
  ]);

  expect(blocks, hasLength(1));
  expect(blocks.single.type, AssistantTurnBlockType.toolResultSummary);
  expect(blocks.single.payload['data']['prompt'], contains('焦点丢失'));
});
```

- [ ] **Step 2: Run the block-builder test to confirm failure or gap**

Run:

```bash
fvm flutter test test/services/chat_block_builder_test.dart
```

Expected: FAIL or expose that the result replacement path is not preserving the new payload fields.

- [ ] **Step 3: Patch block projection only if needed**

If the new test fails, make the smallest possible change in `chat_block_builder.dart` so the existing replacement path keeps the full `ToolResult.data` intact for `fetch_webpage`:

```dart
case 'fetch_webpage':
  return _replaceWorkflowBlockWithResult(
    existingWorkflowBlock: existing,
    resultBlock: incoming,
  );
```

And avoid trimming `data['prompt']` / `data['resultPreview']` during projection.

- [ ] **Step 4: Re-run the block-builder tests**

Run:

```bash
fvm flutter test test/services/chat_block_builder_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit the projection guard**

```bash
git add \
  lib/services/chat_block_builder.dart \
  test/services/chat_block_builder_test.dart
git commit -m "test: lock fetch_webpage block replacement semantics"
```

---

## Task 4: Rebuild the Workflow Card Around Host and Prompt

**Files:**
- Modify: `lib/widgets/tool_renderers/fetch_webpage_tool_workflow_card.dart`
- Modify: `test/widgets/tool_renderers/fetch_webpage_tool_cards_test.dart`

- [ ] **Step 1: Add a failing workflow-card widget test**

Add a test that defines the new collapsed workflow layout:

```dart
testWidgets('workflow card shows host and prompt summary', (tester) async {
  await tester.pumpWidget(
    _wrapToolCard(
      FetchWebpageToolWorkflowCard(
        step: ToolWorkflowStep(
          stepId: 'step_1',
          toolName: 'fetch_webpage',
          title: '读取网页',
          summary: '读取网页中',
          status: ToolWorkflowStepStatus.running,
          details: const {
            'url': 'https://flutter.dev/docs',
            'prompt': '提取和键盘焦点丢失相关的信息',
          },
        ),
      ),
    ),
  );

  expect(find.text('阅读网页 · flutter.dev'), findsOneWidget);
  expect(find.textContaining('键盘焦点丢失'), findsOneWidget);
  expect(find.textContaining('https://flutter.dev/docs'), findsNothing);
});
```

- [ ] **Step 2: Run the widget test to confirm failure**

Run:

```bash
fvm flutter test test/widgets/tool_renderers/fetch_webpage_tool_cards_test.dart
```

Expected: FAIL because the current workflow card still follows the old webpage-centric layout.

- [ ] **Step 3: Update the workflow card renderer**

Refactor `fetch_webpage_tool_workflow_card.dart` to derive host and prompt from `step.details`:

```dart
final details = step.details;
final url = (details['url'] ?? '').toString();
final host = Uri.tryParse(url)?.host.trim().isNotEmpty == true
    ? Uri.parse(url).host
    : url;
final prompt = (details['prompt'] ?? '').toString().trim();
```

Render a compact body:

```dart
Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text('阅读网页 · $host', maxLines: 1, overflow: TextOverflow.ellipsis),
    if (prompt.isNotEmpty) ...[
      const SizedBox(height: 4),
      Text(prompt, maxLines: 1, overflow: TextOverflow.ellipsis),
    ],
  ],
)
```

- [ ] **Step 4: Re-run the workflow widget tests**

Run:

```bash
fvm flutter test test/widgets/tool_renderers/fetch_webpage_tool_cards_test.dart
```

Expected: PASS for the workflow scenario.

- [ ] **Step 5: Commit the workflow-card redesign**

```bash
git add \
  lib/widgets/tool_renderers/fetch_webpage_tool_workflow_card.dart \
  test/widgets/tool_renderers/fetch_webpage_tool_cards_test.dart
git commit -m "feat: streamline fetch_webpage workflow card"
```

---

## Task 5: Rebuild the Result Card Around Prompt and Processed Output

**Files:**
- Modify: `lib/widgets/tool_renderers/fetch_webpage_tool_result_card.dart`
- Review: `lib/widgets/tool_renderers/research_tool_card_shell.dart`
- Modify: `test/widgets/tool_renderers/fetch_webpage_tool_cards_test.dart`

- [ ] **Step 1: Add failing widget tests for the collapsed and expanded result card**

Extend `test/widgets/tool_renderers/fetch_webpage_tool_cards_test.dart` with:

```dart
testWidgets('result card collapsed state shows host prompt and result preview', (tester) async {
  await tester.pumpWidget(
    _wrapToolCard(
      FetchWebpageToolResultCard(
        result: ToolResult.success(
          toolName: 'fetch_webpage',
          summary: '已返回网页处理结果',
          data: const {
            'url': 'https://flutter.dev/docs',
            'host': 'flutter.dev',
            'prompt': '提取和焦点丢失相关的信息',
            'resultPreview': '页面提到频繁 rebuild 可能导致焦点丢失。',
            'processedContent': '页面提到频繁 rebuild 可能导致焦点丢失，并建议减少输入节点被替换的次数。',
          },
        ),
      ),
    ),
  );

  expect(find.text('阅读网页 · flutter.dev'), findsOneWidget);
  expect(find.textContaining('焦点丢失'), findsWidgets);
  expect(find.textContaining('频繁 rebuild'), findsOneWidget);
});

testWidgets('result card expanded state shows Prompt and processed content sections', (tester) async {
  await tester.pumpWidget(
    _wrapToolCard(
      FetchWebpageToolResultCard(
        result: ToolResult.success(
          toolName: 'fetch_webpage',
          summary: '已返回网页处理结果',
          data: const {
            'url': 'https://flutter.dev/docs',
            'host': 'flutter.dev',
            'prompt': '提取和焦点丢失相关的信息',
            'resultPreview': '页面提到频繁 rebuild 可能导致焦点丢失。',
            'processedContent': '页面提到频繁 rebuild 可能导致焦点丢失，并建议减少输入节点被替换的次数。',
            'rawExcerpt': 'When the input node is replaced too often...',
          },
        ),
      ),
    ),
  );

  await tester.tap(find.byType(FetchWebpageToolResultCard));
  await tester.pumpAndSettle();

  expect(find.text('Prompt'), findsOneWidget);
  expect(find.text('处理结果'), findsOneWidget);
  expect(find.text('来源与细节'), findsOneWidget);
});
```

- [ ] **Step 2: Run the result-card widget tests to confirm failure**

Run:

```bash
fvm flutter test test/widgets/tool_renderers/fetch_webpage_tool_cards_test.dart
```

Expected: FAIL because the current result card still centers around page title/content and old detail affordances.

- [ ] **Step 3: Refactor the collapsed result view**

In `fetch_webpage_tool_result_card.dart`, derive display values from `result.data`:

```dart
final data = result.data;
final host = (data['host'] ?? _hostFromUrl(data['url'])).toString();
final prompt = (data['prompt'] ?? '').toString().trim();
final preview = (data['resultPreview'] ?? data['processedContent'] ?? result.summary)
    .toString()
    .trim();
```

Render the collapsed body as:

```dart
Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text('阅读网页 · $host', maxLines: 1, overflow: TextOverflow.ellipsis),
    if (prompt.isNotEmpty) ...[
      const SizedBox(height: 4),
      Text(prompt, maxLines: 1, overflow: TextOverflow.ellipsis),
    ],
    if (preview.isNotEmpty) ...[
      const SizedBox(height: 8),
      Text(preview, maxLines: 2, overflow: TextOverflow.ellipsis),
    ],
  ],
)
```

- [ ] **Step 4: Refactor the expanded content sections**

Replace the page-centric expanded content with three sections:

```dart
Widget _buildExpandedContent() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SectionTitle('Prompt'),
      _SelectableBodyText(prompt),
      const SizedBox(height: 12),
      _SectionTitle('处理结果'),
      _SelectableBodyText(processedContent.isNotEmpty ? processedContent : preview),
      const SizedBox(height: 12),
      _SectionTitle('来源与细节'),
      _buildSourceDetails(
        url: url,
        finalUrl: finalUrl,
        redirectUrl: redirectUrl,
        rawExcerpt: rawExcerpt,
        failureReason: failureReason,
      ),
    ],
  );
}
```

If `research_tool_card_shell.dart` does not allow this composition cleanly, add only the smallest reusable UI helper needed for section headings or tap affordance; do not introduce a new shared business model.

- [ ] **Step 5: Re-run the widget tests**

Run:

```bash
fvm flutter test test/widgets/tool_renderers/fetch_webpage_tool_cards_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit the result-card redesign**

```bash
git add \
  lib/widgets/tool_renderers/fetch_webpage_tool_result_card.dart \
  lib/widgets/tool_renderers/research_tool_card_shell.dart \
  test/widgets/tool_renderers/fetch_webpage_tool_cards_test.dart
git commit -m "feat: redesign fetch_webpage result card around prompt"
```

---

## Task 6: Verify, Then Sync Docs

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Review: `docs/superpowers/specs/2026-04-25-webfetch-prompt-driven-processing-and-card-design.md`

- [ ] **Step 1: Run focused verification**

Run:

```bash
fvm flutter test \
  test/tools/handlers/fetch_webpage_tool_handler_test.dart \
  test/services/chat_block_builder_test.dart \
  test/widgets/tool_renderers/fetch_webpage_tool_cards_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run analyzer on touched files**

Run:

```bash
fvm flutter analyze \
  lib/tools/handlers/fetch_webpage_tool_handler.dart \
  lib/services/default_tool_adapters.dart \
  lib/services/chat_block_builder.dart \
  lib/widgets/tool_renderers/fetch_webpage_tool_workflow_card.dart \
  lib/widgets/tool_renderers/fetch_webpage_tool_result_card.dart \
  test/tools/handlers/fetch_webpage_tool_handler_test.dart \
  test/widgets/tool_renderers/fetch_webpage_tool_cards_test.dart
```

Expected: no issues found.

- [ ] **Step 3: Update README capability text**

Adjust the tool-use UI section so `fetch_webpage` is described as prompt-driven processing rather than raw page reading:

```md
- `fetch_webpage` 会读取指定公共网页，并按 `url + prompt` 生成网页处理结果；卡片默认展示站点、prompt 与结果预览，原始摘录退居详情区
```

- [ ] **Step 4: Update AGENTS only if implementation changed repository rules**

If the implementation introduces a new stable constraint worth preserving, add one concise rule under the existing tool-use UI guidance, for example:

```md
- `fetch_webpage` should be modeled as prompt-driven webpage processing: show `host + prompt + result preview` in primary UI, and keep raw excerpts as secondary evidence
```

Skip this edit if it would merely duplicate the spec.

- [ ] **Step 5: Commit verification and docs**

```bash
git add \
  README.md \
  AGENTS.md
git commit -m "docs: align webfetch docs with prompt-driven design"
```

---

## Self-Review

### Spec coverage

- `url + prompt` 参数收敛：Task 1
- `descriptionForModel` 去重且引入 side model：Task 1
- side model 语义与处理链路：Task 2
- payload 稳定字段：Task 2
- workflow/result 单卡生命周期与 block replacement：Task 3
- `host + prompt + 处理结果预览` 卡片结构：Task 4、Task 5
- 原始摘录退居详情区：Task 5
- 文档同步：Task 6

### Placeholder scan

- 计划中没有 `TODO` / `TBD`
- 每个代码步骤都给出具体改动片段
- 每个验证步骤都给出精确命令与预期结果

### Type consistency

- 统一使用 `url`、`prompt`、`processedContent`、`resultPreview`、`rawExcerpt`、`failureReason`
- `WebpageFetcher` 在计划中统一改为接收 `required String url, required String prompt`

