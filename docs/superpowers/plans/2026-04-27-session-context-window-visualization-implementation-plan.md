# Session 上下文窗口可视化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为聊天主界面增加一个极轻量、无文案的上下文占用状态条，并提供一个 Bottom Sheet 详情面板，展示当前 Session 上下文窗口的分段占比、总窗口占比、可用输入预算占比与压缩状态，且所有展示数据与真实 planner 上下文构建链路同源。

**Architecture:** 在现有 `SessionContextService` 与 `SessionTokenBudgetService` 基础上，抽出共享的 Session 上下文构建结果，再新增只读的 `SessionContextInspectorService` 生成 `ContextWindowSnapshot`。UI 通过 Riverpod provider 读取 snapshot，在 `ChatInput` 上方渲染极细状态条，在 `ChatPage` 中通过 Bottom Sheet 展示详情面板。实现遵循 TDD，优先覆盖服务层分段和 UI 基本交互。

**Tech Stack:** Flutter 3.29.2、Dart、flutter_riverpod、flutter_test、现有 SessionContext / Chat UI / Bottom Sheet 体系。

---

## 文件结构

### 新增文件

- `lib/models/session/context_window_segment.dart`
  - 定义上下文窗口 segment 类型、显示标签、占比字段和细节字段。
- `lib/models/session/context_window_snapshot.dart`
  - 定义 UI 只读快照模型，包括预算汇总、segment 列表和压缩状态。
- `lib/services/session_context_inspector_service.dart`
  - 生成最新 `ContextWindowSnapshot`，复用 Session 上下文构建规则。
- `lib/widgets/context_window/context_window_status_bar.dart`
  - 主界面极细无文案状态条。
- `lib/widgets/context_window/context_window_bottom_sheet.dart`
  - Bottom Sheet 详情面板。
- `test/services/session_context_inspector_service_test.dart`
  - 服务层快照与分段测试。
- `test/widgets/context_window/context_window_status_bar_test.dart`
  - 轻量状态条测试。
- `test/widgets/context_window/context_window_bottom_sheet_test.dart`
  - 详情面板测试。

### 修改文件

- `lib/services/session_context_service.dart`
  - 抽出共享的内部 build result，避免 planner messages 和 inspector 各算各的。
- `lib/providers/chat_dependency_providers.dart`
  - 注入 `SessionContextInspectorService` provider。
- `lib/providers/chat_ui_providers.dart`
  - 新增 `contextWindowSnapshotProvider` 等只读 provider。
- `lib/pages/chat_page.dart`
  - 增加打开上下文详情 Bottom Sheet 的入口。
- `lib/widgets/chat_input.dart`
  - 在输入区上方插入轻量状态条。
- `README.md`
  - 更新功能与架构说明。
- `docs/architecture/session-context-management.md`
  - 更新真实投影规则与可视化能力说明。

## 任务 1：定义上下文窗口快照模型

**Files:**
- Create: `lib/models/session/context_window_segment.dart`
- Create: `lib/models/session/context_window_snapshot.dart`
- Test: `test/services/session_context_inspector_service_test.dart`

- [ ] **Step 1: 先写失败测试，锁定快照模型最小 contract**

```dart
test('context window snapshot exposes total and usable ratios separately', () {
  const snapshot = ContextWindowSnapshot(
    modelName: 'gpt-5',
    maxContextTokens: 128000,
    usableInputBudget: 104000,
    totalEstimatedInputTokens: 64000,
    totalWindowUsageRatio: 0.5,
    usableInputUsageRatio: 64000 / 104000,
    compressionTriggerRatio: 0.8,
    didCompactHistory: false,
    recentCompletedTurnCount: 2,
    segments: [
      ContextWindowSegment(
        type: ContextWindowSegmentType.systemPrompt,
        label: 'system prompt',
        estimatedTokens: 8000,
        shareOfTotalWindow: 8000 / 128000,
        shareOfUsableInput: 8000 / 104000,
        isPlannerVisible: true,
      ),
    ],
  );

  expect(snapshot.totalWindowUsageRatio, 0.5);
  expect(snapshot.usableInputUsageRatio, greaterThan(0.6));
  expect(snapshot.segments.single.isPlannerVisible, isTrue);
});
```

- [ ] **Step 2: 运行测试，确认当前缺少模型类型**

Run: `fvm flutter test test/services/session_context_inspector_service_test.dart`

Expected: FAIL，提示缺少 `ContextWindowSnapshot` / `ContextWindowSegment` 类型。

- [ ] **Step 3: 实现最小模型与注释字段**

```dart
enum ContextWindowSegmentType {
  systemPrompt,
  runtimeUserContext,
  historySummary,
  recentCompletedTurns,
  currentTurnTranscript,
  reservedOutput,
  reasoningReserve,
  safetyMargin,
  freeHeadroom,
}

class ContextWindowSegment {
  /// Stable segment type so UI can map colors and grouping consistently.
  final ContextWindowSegmentType type;

  /// User-facing short label shown in the detail sheet.
  final String label;

  /// Locally estimated token cost for this segment.
  final int estimatedTokens;

  /// Share of the full provider-advertised context window.
  final double shareOfTotalWindow;

  /// Share of the planner-usable input budget.
  final double shareOfUsableInput;

  /// Whether this segment is actually visible to the planner.
  final bool isPlannerVisible;

  /// Optional structured explanation such as covered turn ids or item counts.
  final Map<String, Object?> details;
}
```

- [ ] **Step 4: 重新运行模型测试**

Run: `fvm flutter test test/services/session_context_inspector_service_test.dart`

Expected: PASS，基础模型 contract 通过。

- [ ] **Step 5: Commit**

```bash
git add lib/models/session/context_window_segment.dart \
  lib/models/session/context_window_snapshot.dart \
  test/services/session_context_inspector_service_test.dart
git commit -m "feat: add context window snapshot models"
```

## 任务 2：抽出 SessionContextService 共享构建结果

**Files:**
- Modify: `lib/services/session_context_service.dart`
- Test: `test/services/session_context_service_test.dart`

- [ ] **Step 1: 写失败测试，锁定共享 build result 不改变现有 planner 行为**

```dart
test('buildPlannerMessages remains derived from shared session context result', () async {
  final service = _buildSessionContextService(...);

  final messages = await service.buildPlannerMessages(
    groupId: groupId,
    currentTurnId: currentTurnId,
    currentTurnTranscript: transcript,
    config: ChatConfig(systemPrompt: '你是一个助手'),
  );

  expect(messages.first.text, contains('# currentDate'));
  expect(messages.last.text, contains('current-turn'));
});
```

- [ ] **Step 2: 运行相关测试，记录当前基线**

Run: `fvm flutter test test/services/session_context_service_test.dart`

Expected: PASS，确认重构前已有基线。

- [ ] **Step 3: 在 SessionContextService 中抽出内部 build result**

```dart
class SessionContextBuildResult {
  final ChatMessage runtimeUserContextMessage;
  final SessionContextSnapshot? activeSnapshot;
  final List<_TurnContextSegment> recentSegments;
  final List<ChatMessage> currentTurnMessages;
  final SessionPlannerBudgetEvaluation budgetEvaluation;
  final bool didCompactHistory;
}
```

要求：

- `buildPlannerMessages()` 继续返回现有 `List<ChatMessage>`
- 新内部 helper 统一负责：
  - 加载 snapshot
  - 选择 recent segments
  - 评估 budget
  - 触发 compaction
  - 生成 normalized current messages

- [ ] **Step 4: 运行 SessionContextService 测试回归**

Run: `fvm flutter test test/services/session_context_service_test.dart`

Expected: PASS，说明共享构建结果没有破坏既有 planner 上下文 contract。

- [ ] **Step 5: Commit**

```bash
git add lib/services/session_context_service.dart \
  test/services/session_context_service_test.dart
git commit -m "refactor: extract session context build result"
```

## 任务 3：实现 SessionContextInspectorService

**Files:**
- Create: `lib/services/session_context_inspector_service.dart`
- Modify: `lib/services/session_context_service.dart`
- Test: `test/services/session_context_inspector_service_test.dart`

- [ ] **Step 1: 写失败测试，锁定 segment 拆解与压缩状态**

```dart
test('buildLatestWindowSnapshot reports planner-visible segments and reserve segments', () async {
  final service = _buildInspectorService(...);

  final snapshot = await service.buildLatestWindowSnapshot(
    groupId: groupId,
    currentTurnId: currentTurnId,
    currentTurnTranscript: transcript,
    config: ChatConfig(systemPrompt: '你是一个助手'),
  );

  expect(snapshot.modelName, 'gpt-5');
  expect(snapshot.segments.map((item) => item.type), contains(
    ContextWindowSegmentType.currentTurnTranscript,
  ));
  expect(snapshot.segments.map((item) => item.type), contains(
    ContextWindowSegmentType.reservedOutput,
  ));
  expect(snapshot.totalWindowUsageRatio, greaterThan(0));
  expect(snapshot.usableInputUsageRatio, greaterThan(0));
});
```

- [ ] **Step 2: 运行测试，确认 service 不存在**

Run: `fvm flutter test test/services/session_context_inspector_service_test.dart`

Expected: FAIL，提示缺少 `SessionContextInspectorService`。

- [ ] **Step 3: 用共享 build result 生成 UI 快照**

```dart
final profile = _tokenBudgetService.resolveProfile(modelName);
final totalEstimatedInputTokens = result.budgetEvaluation.totalInputTokens;

return ContextWindowSnapshot(
  modelName: modelName,
  maxContextTokens: profile.maxContextTokens,
  usableInputBudget: profile.usableInputBudget,
  compressionTriggerRatio: profile.compactionConfig.compressionTriggerRatio,
  totalEstimatedInputTokens: totalEstimatedInputTokens,
  totalWindowUsageRatio: totalEstimatedInputTokens / profile.maxContextTokens,
  usableInputUsageRatio:
      totalEstimatedInputTokens / result.budgetEvaluation.usableInputBudget,
  didCompactHistory: result.didCompactHistory,
  snapshotCoveredUntilTurnId: result.activeSnapshot?.coveredUntilTurnId,
  recentCompletedTurnCount: result.recentSegments.length,
  segments: _buildSegments(...),
);
```

实现要求：

- planner 可见段与保留段必须分开
- `systemPrompt` 与 `runtimeUserContext` 必须单独成段
- `historySummary` 要带 `coveredUntilTurnId`
- `recentCompletedTurns` 要带保留轮数
- `currentTurnTranscript` 要带 item 数量或消息数
- `freeHeadroom` 以总窗口剩余量计算

- [ ] **Step 4: 增加一条压缩场景测试**

```dart
test('snapshot exposes compaction metadata when older history rolled into summary', () async {
  expect(snapshot.didCompactHistory, isTrue);
  expect(snapshot.snapshotCoveredUntilTurnId, historicalTurnId);
  expect(snapshot.recentCompletedTurnCount, 1);
});
```

- [ ] **Step 5: 运行 inspector 与 session context 测试**

Run: `fvm flutter test test/services/session_context_inspector_service_test.dart test/services/session_context_service_test.dart`

Expected: PASS。

- [ ] **Step 6: Commit**

```bash
git add lib/services/session_context_inspector_service.dart \
  lib/services/session_context_service.dart \
  test/services/session_context_inspector_service_test.dart \
  test/services/session_context_service_test.dart
git commit -m "feat: add session context inspector service"
```

## 任务 4：接入 providers，暴露上下文窗口快照

**Files:**
- Modify: `lib/providers/chat_dependency_providers.dart`
- Modify: `lib/providers/chat_ui_providers.dart`
- Test: `test/providers/chat_dependency_providers_test.dart`

- [ ] **Step 1: 写失败测试，锁定 provider 能解析 inspector service**

```dart
test('context window snapshot provider resolves inspector-backed snapshot', () async {
  final container = ProviderContainer(
    overrides: [...],
  );

  final snapshot = await container.read(contextWindowSnapshotProvider.future);
  expect(snapshot, isNotNull);
  expect(snapshot!.segments, isNotEmpty);
});
```

- [ ] **Step 2: 运行 provider 测试，确认新 provider 尚不存在**

Run: `fvm flutter test test/providers/chat_dependency_providers_test.dart`

Expected: FAIL，提示缺少 `contextWindowSnapshotProvider` 或 inspector provider。

- [ ] **Step 3: 注入 inspector service 与 snapshot provider**

```dart
final sessionContextInspectorServiceProvider =
    Provider<SessionContextInspectorService>((ref) {
  return SessionContextInspectorService(
    sessionContextService: ref.watch(sessionContextServiceProvider),
    tokenBudgetService: ref.watch(sessionTokenBudgetServiceProvider),
    chatService: ref.watch(chatServiceProvider),
  );
});

final contextWindowSnapshotProvider =
    FutureProvider<ContextWindowSnapshot?>((ref) async {
  final group = ref.watch(currentGroupProvider);
  if (group?.id == null) {
    return null;
  }
  return ref.watch(sessionContextInspectorServiceProvider)
      .buildLatestWindowSnapshotForGroup(group!.id!);
});
```

注意：

- 需要选择一个合理的“当前 turn”来源
- 若当前没有 active turn，可先退回到最近可解释的 session 快照入口
- 空态必须安全返回 `null`

- [ ] **Step 4: 运行 provider 测试**

Run: `fvm flutter test test/providers/chat_dependency_providers_test.dart`

Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add lib/providers/chat_dependency_providers.dart \
  lib/providers/chat_ui_providers.dart \
  test/providers/chat_dependency_providers_test.dart
git commit -m "feat: expose context window snapshot providers"
```

## 任务 5：实现主界面极细无文案状态条

**Files:**
- Create: `lib/widgets/context_window/context_window_status_bar.dart`
- Modify: `lib/widgets/chat_input.dart`
- Test: `test/widgets/context_window/context_window_status_bar_test.dart`

- [ ] **Step 1: 写失败测试，锁定状态条无文案且可点击**

```dart
testWidgets('status bar renders without text copy', (tester) async {
  await tester.pumpWidget(_buildStatusBar(snapshot: _snapshot(0.61)));

  expect(find.textContaining('%'), findsNothing);
  expect(find.textContaining('上下文'), findsNothing);
  expect(find.byType(LinearProgressIndicator), findsOneWidget);
});
```

- [ ] **Step 2: 运行 widget 测试，确认组件不存在**

Run: `fvm flutter test test/widgets/context_window/context_window_status_bar_test.dart`

Expected: FAIL。

- [ ] **Step 3: 实现极细低对比度状态条**

```dart
class ContextWindowStatusBar extends StatelessWidget {
  final ContextWindowSnapshot snapshot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ratio = snapshot.totalWindowUsageRatio.clamp(0.0, 1.0);
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(
          minHeight: 4,
          value: ratio,
          backgroundColor: colors.secondaryText.withValues(alpha: 0.10),
          valueColor: AlwaysStoppedAnimation<Color>(_resolveSubtleColor(ratio)),
        ),
      ),
    );
  }
}
```

要求：

- 默认无文案
- 无百分比
- 安全区间低对比度
- 接近阈值时仅轻微增强颜色

- [ ] **Step 4: 在 ChatInput 中把状态条插入输入面板上方**

要求：

- 空态时不渲染
- 与现有输入面板圆角和 spacing 保持一致
- 不影响确认条 `ToolConfirmationBottomBar`

- [ ] **Step 5: 运行状态条 widget 测试**

Run: `fvm flutter test test/widgets/context_window/context_window_status_bar_test.dart`

Expected: PASS。

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/context_window/context_window_status_bar.dart \
  lib/widgets/chat_input.dart \
  test/widgets/context_window/context_window_status_bar_test.dart
git commit -m "feat: add subtle context window status bar"
```

## 任务 6：实现 Bottom Sheet 详情面板

**Files:**
- Create: `lib/widgets/context_window/context_window_bottom_sheet.dart`
- Modify: `lib/pages/chat_page.dart`
- Test: `test/widgets/context_window/context_window_bottom_sheet_test.dart`

- [ ] **Step 1: 写失败测试，锁定面板展示双比例与 segment 列表**

```dart
testWidgets('bottom sheet shows total and usable ratios with segment breakdown', (tester) async {
  await tester.pumpWidget(_buildBottomSheet(snapshot: _richSnapshot()));

  expect(find.text('system prompt'), findsOneWidget);
  expect(find.text('current turn transcript'), findsOneWidget);
  expect(find.textContaining('maxContextTokens'), findsNothing);
  expect(find.textContaining('128000'), findsWidgets);
});
```

- [ ] **Step 2: 运行 widget 测试，确认组件不存在**

Run: `fvm flutter test test/widgets/context_window/context_window_bottom_sheet_test.dart`

Expected: FAIL。

- [ ] **Step 3: 实现 Bottom Sheet 内容**

实现要求：

- 顶部总览展示：
  - 模型名
  - 总窗口占比
  - 可用输入预算占比
  - token 绝对值
- 中部展示 planner 可见 segments
- 底部展示保留区与压缩状态
- 默认信息密度可扫读，不堆满工程术语

```dart
await showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: colors.chatBackground,
  builder: (_) => ContextWindowBottomSheet(snapshot: snapshot),
);
```

- [ ] **Step 4: 在 ChatPage 增加统一打开详情入口**

要求：

- 由 `ChatInput` 触发回调，或通过共享 action 触发
- 不与现有 debug cases sheet 混淆
- 仅当 snapshot 不为空时允许打开

- [ ] **Step 5: 运行详情面板 widget 测试**

Run: `fvm flutter test test/widgets/context_window/context_window_bottom_sheet_test.dart`

Expected: PASS。

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/context_window/context_window_bottom_sheet.dart \
  lib/pages/chat_page.dart \
  test/widgets/context_window/context_window_bottom_sheet_test.dart
git commit -m "feat: add context window detail bottom sheet"
```

## 任务 7：补齐集成测试与文档

**Files:**
- Modify: `README.md`
- Modify: `docs/architecture/session-context-management.md`
- Modify: `test/widgets/context_window/context_window_status_bar_test.dart`
- Modify: `test/widgets/context_window/context_window_bottom_sheet_test.dart`

- [ ] **Step 1: 补一条端到端 UI 测试，覆盖主条点击到详情展开**

```dart
testWidgets('tapping status bar opens context window bottom sheet', (tester) async {
  await tester.pumpWidget(_buildChatPageWithSnapshot());

  await tester.tap(find.byKey(const ValueKey('context-window-status-bar')));
  await tester.pumpAndSettle();

  expect(find.byKey(const ValueKey('context-window-bottom-sheet')), findsOneWidget);
});
```

- [ ] **Step 2: 运行新增 UI 测试并确认先失败**

Run: `fvm flutter test test/widgets/context_window/context_window_status_bar_test.dart test/widgets/context_window/context_window_bottom_sheet_test.dart`

Expected: 若集成入口未补齐则 FAIL。

- [ ] **Step 3: 更新 README 与架构文档**

README 需要说明：

- 主界面新增轻量上下文状态条
- 详情面板可查看分段占比
- 展示基于本地 token 估算

架构文档需要说明：

- `assistantToolCall` / tool use 当前真实会进入模型可见上下文
- 新增 `SessionContextInspectorService`
- 上下文窗口可视化是 SessionContext 层的只读观察能力

- [ ] **Step 4: 运行相关测试与分析**

Run: `fvm flutter test test/services/session_context_inspector_service_test.dart test/services/session_context_service_test.dart test/providers/chat_dependency_providers_test.dart test/widgets/context_window/context_window_status_bar_test.dart test/widgets/context_window/context_window_bottom_sheet_test.dart`

Expected: PASS。

Run: `fvm flutter analyze`

Expected: PASS，无新增 analyzer 错误。

- [ ] **Step 5: Commit**

```bash
git add README.md \
  docs/architecture/session-context-management.md \
  test/services/session_context_inspector_service_test.dart \
  test/providers/chat_dependency_providers_test.dart \
  test/widgets/context_window/context_window_status_bar_test.dart \
  test/widgets/context_window/context_window_bottom_sheet_test.dart
git commit -m "docs: document context window visualization"
```

## 执行备注

- 当前仓库要求新增 plan/spec 文档使用中文，本计划已遵循。
- 执行实现时优先使用 `fvm flutter`，以保证 Flutter 版本符合仓库约束。
- UI 实现应保持“克制、低焦虑”原则：
  - 主界面只保留细进度条
  - 不加文案
  - 不加显式警告文本
- `ContextWindowSnapshot` 必须明确区分：
  - planner 可见 segment
  - 预算保留 segment
  - 总窗口比例
  - 可用输入预算比例

## 交付完成标准

- 主界面输入区上方出现极细、无文案、无数字状态条
- 点击状态条可打开 Bottom Sheet
- Bottom Sheet 能展示总窗口占比、可用输入预算占比、分段拆解、保留区与压缩状态
- 展示数据与真实 SessionContext 构建链路同源
- 相关服务、provider、UI、文档和测试全部更新完成
