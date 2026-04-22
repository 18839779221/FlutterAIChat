# 动态意图识别与交互卡片设计

**日期**: 2026-04-15
**状态**: 设计完成，等待评审

## 1. 背景与目标

### 问题陈述
当前应用中，大模型输出的自然语言常包含「期待用户响应」的隐式信号（如「如果你要，我就...」「建议 A 或 B」），但用户必须通过文本输入来回应，摩擦成本高。

### 目标
实现一个**动态意图识别层**，在大模型输出完成后自动分析文本，识别交互意图，并动态渲染交互按钮，让用户通过点击而非文本输入来响应。

该层应满足以下边界：
- **非阻塞**：不改变 turn 完成态，不进入 `awaitingUserInteraction`
- **可忽略**：用户可以无视按钮，继续在输入框自由输入
- **直接发送**：用户点击按钮后，直接发送按钮对应的 `replyText`，等价于一条普通用户消息
- **渐进学习**：MVP 可以使用种子样例启动，但后续识别能力应可由副模型异步沉淀和扩展，而不是长期依赖人工硬编码 pattern

### MVP 范围
- **确认类**：「如果你要，我就...」「要我现在做吗」→ [确认] [取消]
- **选择类**：「建议 A 或 B」「做 X 还是 Y」→ [选项 A] [选项 B]

## 2. 架构设计

### 整体流程

```
大模型输出完成
      │
      ▼
┌─────────────────┐
│ IntentRecognizer │ ← 二级 LLM 分类
└────────┬────────┘
         │
  ┌──────┴──────┐
  │ 有交互意图?   │
  └──────┬──────┘
   yes   │   no
  ┌──────┴──────┐
  ▼             ▼
DynamicIntentCard   (无操作)
  │
  ▼
渲染到消息列表
```

### 模块划分

| 模块 | 职责 | 位置 |
|------|------|------|
| IntentClassifier | 意图识别与动作提取核心逻辑 | lib/services/intent_classifier.dart |
| IntentPatternStore | 种子样例与学习结果存储 | lib/services/intent_pattern_store.dart |
| IntentClassificationResult | 识别结果数据模型 | lib/models/interaction/intent_classification_result.dart |
| DynamicIntentCard | 动态交互卡片 UI | lib/widgets/interaction/dynamic_intent_card.dart |
| IntentCardProvider | Riverpod Provider | lib/providers/intent_card_provider.dart |
| IntentFeedbackRepository | 展示/点击/忽略反馈记录 | lib/repositories/intent_feedback_repository.dart |

## 3. 数据模型

### IntentClassificationResult

```dart
class IntentClassificationResult {
  /// none | confirm | choice
  final String intentType;

  /// 0.0 - 1.0 置信度
  final double confidence;

  /// 匹配的原文片段（用于展示或调试）
  final List<String> evidenceSpans;

  /// 当前消息的可点击动作列表
  final List<IntentAction> actions;

  /// 可选的调试摘要，用于日志或开发态排查
  final String? debugSummary;
}

class IntentAction {
  /// 稳定动作键，用于点击统计和学习归因
  final String actionKey;

  /// 展示在按钮上的短文案
  final String label;

  /// 点击后直接发送的用户回复文本
  final String replyText;

  /// 当前动作的局部置信度
  final double confidence;
}
```

### IntentPatternStore 存储格式

```json
{
  "version": 1,
  "seedExamples": [
    {
      "input": "如果你要，我现在就帮你修改代码。",
      "output": {
        "intentType": "confirm",
        "confidence": 0.95,
        "evidenceSpans": [
          "如果你要，我现在就帮你修改代码。"
        ],
        "actions": [
          {
            "actionKey": "confirm_continue",
            "label": "直接改",
            "replyText": "那你直接改吧。",
            "confidence": 0.94
          }
        ]
      }
    }
  ],
  "learnedPatterns": [
    {
      "patternId": "model/openairesponses/confirm-001",
      "status": "trial",
      "intentType": "confirm",
      "surfaceAnchors": [
        "如果你要",
        "我下一步就"
      ],
      "semanticFrame": {
        "hasExplicitProposal": true,
        "hasConfirmationCue": true
      },
      "stats": {
        "shownCount": 5,
        "clickedCount": 3,
        "ignoredCount": 2
      }
    },
    {
      "patternId": "model/openairesponses/choice-001",
      "status": "whitelist",
      "intentType": "choice",
      "surfaceAnchors": [
        "建议",
        "还是",
        "或者"
      ],
      "semanticFrame": {
        "hasExplicitProposal": true,
        "hasMultipleBranches": true
      }
    }
  ]
}
```

## 4. 接口设计

### IntentClassifier

```dart
abstract class IntentClassifier {
  /// 注入的 LLM 实例（支持自定义）
  final LLM llm;

  /// 对单条 assistant 完成消息进行识别，返回当前消息的可点击动作。
  Future<IntentClassificationResult> classify(String text);

  /// 设置/更新模式存储
  void setPatternStore(IntentPatternStore store);
}
```

### IntentPatternStore

```dart
class IntentPatternStore {
  /// 从 JSON 文件加载种子样例和学习结果
  Future<void> loadFromJson(String path);

  /// 获取种子样例
  List<FewShotExample> getSeedExamples();

  /// 获取当前可用的学习模式（包含 trial / whitelist）
  List<IntentPattern> getActivePatterns();
}
```

## 5. UI 设计

### DynamicIntentCard

```
┌────────────────────────────────────────┐
│  是否确认执行?                           │
│                                         │
│                    [确认]  [取消]        │
└────────────────────────────────────────┘
```

```
┌────────────────────────────────────────┐
│  你选择哪个?                            │
│                                         │
│            [选项 A]  [选项 B]           │
└────────────────────────────────────────┘
```

### 样式复用
- 复用到目前为止已有的 `AskUserQuestionCard` 样式风格
- 使用 Material Design 3 组件
- 按钮使用 FilledButton 和 OutlinedButton

### 位置关系
- 大模型输出（原文）先完整显示
- 动态交互卡片作为独立 widget 追加到消息列表
- 卡片位于对应 assistant 消息之后
- 用户可以无视卡片，继续通过输入框自由输入

## 6. 集成点

### 识别触发时机
当 assistant 消息状态从 `generating` 变为 `completed`，且最终文本已经稳定落库后，触发识别流程。

MVP 推荐在消息完成后的 service/coordinator 层触发识别，不在 `ChatMessageList` 渲染层直接发起 LLM 调用。`ChatMessageList` 仅负责消费识别结果并渲染卡片。

### 消息列表集成
在 `_buildAssistantBlocks` 方法中，新增 `AssistantTurnBlockType.dynamicIntent` 类型，当识别到意图时，追加 `DynamicIntentCard` widget。

### 点击回调
用户点击按钮后：
1. 直接读取对应 action 自带的 `replyText`
2. 通过 `ChatController` 发送该消息
3. 触发正常的 agent 循环继续执行

### 反馈记录
MVP 至少记录以下反馈事件：
1. `shown`：该 assistant 消息是否展示了动态交互卡片
2. `clicked`：用户点击了哪个 action
3. `ignored`：用户未点击而继续手动输入

这些反馈用于后续学习模式的晋升、降级和用户偏好叠加。

## 7. 实现步骤

### Phase 1: 基础框架
1. 创建 IntentClassificationResult 数据模型
2. 创建 IntentPatternStore 加载种子样例与学习结果 JSON
3. 实现 IntentClassifier 基类和默认实现

### Phase 2: UI 组件
1. 实现 DynamicIntentCard widget
2. 在消息完成后的 service/coordinator 层触发识别
3. 实现按钮点击回调

### Phase 3: 渐进学习
1. 准备种子样例
2. 记录 `shown/clicked/ignored` 反馈
3. 通过副模型异步沉淀更多 trial / whitelist pattern

## 8. 待定事项

- [ ] 置信度阈值设定（目前建议 0.7）
- [ ] PatternStore 文件位置和加载方式
- [ ] 学习结果的本地持久化格式
- [ ] 模型层模式与用户偏好层的分桶方式
- [ ] 是否需要在 UI 上暴露“忽略这类建议”的开关

## 9. 风险与限制

1. **识别准确率**：初期依赖种子样例和 prompt tuning，仍可能需要人工观察和迭代
2. **延迟**：每次识别需要一次额外 LLM 调用（约 500ms-2s）
3. **覆盖范围**：MVP 仅支持确认类和选择类
4. **误识别风险**：可能把非交互内容误判为需要确认
5. **replyText 质量**：当前版本点击即发送，若副模型产出的 `replyText` 不自然，会直接影响交互体验
