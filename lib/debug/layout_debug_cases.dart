import 'package:ai_chat/models/debug/layout_debug_block.dart';
import 'package:ai_chat/models/debug/layout_debug_case.dart';

const List<LayoutDebugCase> kLayoutDebugCases = <LayoutDebugCase>[
  LayoutDebugCase(
    id: 'basic-long-form',
    title: '基础长文',
    description: '验证标题层级、段落节奏、列表、引用和强调样式。',
    blocks: <LayoutDebugBlock>[
      LayoutDebugBlock(
        type: LayoutDebugBlockType.assistantDoc,
        label: 'DOCUMENT',
        markdownText: _basicLongFormMarkdown,
      ),
    ],
  ),
  LayoutDebugCase(
    id: 'complex-structures',
    title: '复杂结构',
    description: '验证表格、代码块、分割线、链接和行内代码的组合排版。',
    blocks: <LayoutDebugBlock>[
      LayoutDebugBlock(
        type: LayoutDebugBlockType.assistantDoc,
        label: 'TECHNICAL NOTE',
        markdownText: _complexStructureMarkdown,
      ),
    ],
  ),
  LayoutDebugCase(
    id: 'edge-pressure',
    title: '边界压力',
    description: '验证超长内容、宽表格和长代码行对容器与滚动的影响。',
    blocks: <LayoutDebugBlock>[
      LayoutDebugBlock(
        type: LayoutDebugBlockType.assistantDoc,
        label: 'STRESS CASE',
        markdownText: _edgePressureMarkdown,
      ),
    ],
  ),
  LayoutDebugCase(
    id: 'multilingual-mixed',
    title: '多语言混排',
    description: '验证中文、英文、日文和阿拉伯文在同一篇文档中的排版稳定性。',
    blocks: <LayoutDebugBlock>[
      LayoutDebugBlock(
        type: LayoutDebugBlockType.assistantDoc,
        label: 'GLOBAL MEMO',
        markdownText: _multilingualMarkdown,
      ),
    ],
  ),
  LayoutDebugCase(
    id: 'full-assistant-response',
    title: '完整助手回复',
    description: '验证 label、reasoning 和正文组合后的完整助手文档节奏。',
    blocks: <LayoutDebugBlock>[
      LayoutDebugBlock(
        type: LayoutDebugBlockType.assistantDoc,
        label: 'RESEARCH SUMMARY',
        reasoningText: '先梳理结构，再补充关键表格和风险提醒，确保文档块和思考区的节奏都可检查。',
        markdownText: _fullAssistantMarkdown,
      ),
      LayoutDebugBlock(
        type: LayoutDebugBlockType.assistantDoc,
        label: 'FOLLOW-UP',
        markdownText: _followUpMarkdown,
      ),
    ],
  ),
];

const String _basicLongFormMarkdown = r'''
# 春季学习计划说明

这份文档用于模拟一类典型的大模型长文回复：它不是零散的样式样本，而是一篇可以顺着读下去的说明文。我们希望在阅读过程中，自然看到**标题层级**、正文节奏、强调文本和留白是否协调，而不是只盯着某一个局部组件。

## 本周重点

本周的学习目标主要分成三部分。第一部分是梳理现有知识结构，把已经掌握但不够系统的内容重新整理出来；第二部分是安排固定练习时间，避免“知道应该学什么，却总在真正开始前被打断”；第三部分是通过复盘把输入变成输出，让笔记不只是堆积的信息碎片。

1. 每天上午保留一段完整、不被打断的阅读时间。
2. 下午安排一轮轻量练习，把当天吸收的内容转成可验证的输出。
3. 晚上用十分钟记录收获、问题和第二天的调整点。

## 方法建议

- 不要一开始就追求覆盖面，先把最重要的一条主线读顺。
- 遇到卡住的概念时，先用自己的话复述，再决定是否继续查资料。
- 如果某一段内容读起来明显吃力，优先调整结构和节奏，而不是硬撑着往下翻。

> 一篇真正易读的文档，往往不是信息更多，而是读者在每个段落都知道自己为什么继续往下读。

### 最后提醒

如果这一类基础长文在标题、段落、列表或引用块上已经显得发紧或者松散，那么后续更复杂的技术文档通常只会把这些问题放大。

> [!TIP] 阅读方式
> 先顺着读完整篇，再回头看标题、列表和引用块之间的节奏是否自然。
''';

const String _complexStructureMarkdown = r'''
# 文档调试页方案评估

如果我们要为文档排版建立一个稳定的调试入口，首先需要明确“页面服务的对象”是什么。它并不是一个抽象的 Markdown renderer，而是用户最终会在聊天时间线里读到的那种完整助手回复。因此，这里的技术文档案例应该既能读，又能自然带出表格、代码块和链接这些复杂结构。

下面的表格总结了几种实现方向在当前阶段的取舍：

| 方案 | 适用阶段 | 优点 | 主要风险 |
| --- | --- | --- | --- |
| 纯 Markdown 沙箱 | 非常早期的局部样式排查 | 上手快，改动小 | 和真实回复场景脱节 |
| 完整回复块调试页 | 当前最合适的首版方案 | 最接近真实用户阅读体验 | 页面结构需要稍微多做一点设计 |
| 全时间线模拟器 | 后续工具卡和多块混排阶段 | 扩展性最好 | 交付成本明显更高 |

> [!NOTE] 结构提醒
> 这类技术文档案例需要同时覆盖表格、代码块、链接和说明文字，才能看出阅读节奏是否被复杂结构打断。

---

## 一个最小实现片段

下面这段代码代表我们真正希望复用的能力边界：调试页不自己发明渲染逻辑，而是直接调用已有的回复块组件。

```dart
Widget buildPreview() {
  return const AssistantDocBlock(
    text: '# 页面标题\n\n这里是一段真实的文档正文。',
  );
}
```

继续往下看时，可以顺手观察 `inline code`、普通段落和链接的节奏是否依然统一。比如这个示例链接：<https://example.com/layout-debug/table-preview>，如果它在文中显得突兀，就说明正文和特殊元素之间的阅读韵律还不够顺。

### 小范围计算示例

为了确认数学公式不会在技术文档里显得过于跳脱，这里补一个行内表达式 $E = mc^2$，以及一个块级公式：

$$
\text{coverage score} = \frac{\text{supported blocks}}{\text{planned blocks}}
$$
''';

const String _edgePressureMarkdown = r'''
# 边界压力检查记录

真实的大模型回复里，经常会混入一些“并不友好但非常常见”的内容：没有自然断点的长链接、宽度失控的表格字段，以及一整行几乎不会自动换行的代码。这些内容单独看都不复杂，但只要和正文混排，就很容易把原本还算舒服的阅读节奏打散。

下面这个链接故意保持得很长，用来观察正文区域在没有自然换行点时会怎么处理：

https://debug.example.com/render/this-is-a-very-long-path-used-to-check-how-the-markdown-surface-wraps-really-long-links-without-natural-break-points

接下来是一张刻意偏宽的表格，它不只是为了测试表格本身，也是在看宽内容出现时，文档主体是否还能保持稳定：

| 列名非常长列名非常长列名非常长 | 内容 |
| --- | --- |
| 这个单元格会故意放入特别长特别长特别长特别长特别长特别长的一段连续文本，观察是否把容器撑坏 | 正常内容 |

最后是一行长度失控的代码，它通常能非常直接地暴露代码块容器、字体度量和横向滚动壳之间的协作问题：

```text
final previewUrl = "https://debug.example.com/render/this-line-is-intentionally-kept-extremely-long-so-we-can-check-horizontal-pressure-and-text-wrapping-behavior-in-code-blocks";
```

### 观察建议

阅读这一段时，不要只看有没有溢出。更重要的是判断：当宽内容出现后，正文是否仍然显得像一篇完整文档，而不是被迫切成几段互不相干的视觉碎片。

> [!WARNING] 宽内容风险
> 一旦宽表格、长链接和长代码行同时出现，最容易被牺牲的通常不是功能，而是整体可读性。
''';

const String _multilingualMarkdown = r'''
# 多语言排版检查 / Multilingual Layout Review

这篇文档专门用于验证多语言混排时的版面稳定性。它不是把几句外语随便拼在一起，而是模拟一篇真实的跨语言说明文，观察不同文字系统在同一个文档流里是否还能保持统一的阅读节奏。

## 中文段落

中文部分重点看正文宽度、标点间距和标题落点是否自然。如果一篇文档在中文里已经显得吃力，那么切到多语言场景后通常会更容易暴露字体回退和行高不一致的问题。

## English Section

The English section is useful for checking word spacing, sentence rhythm, and how Latin text sits next to Chinese paragraphs. A readable multilingual document should not feel like it switches to a completely different visual voice just because the language changed.

### 日本語の段落

日本語の文章では、漢字、ひらがな、カタカナが自然に混ざります。ここでは行間、見出しの余白、そして段落のまとまりが崩れていないかを見ます。

### فقرة عربية

هذه الفقرة القصيرة تُستخدم فقط لملاحظة شكل السطر وإيقاع الفقرة عندما تظهر لغة مختلفة الاتجاه داخل نفس المستند. حتى لو لم تكن الصفحة مصممة خصيصًا لسيناريو RTL، 也应该至少保证文本不会显得完全失控。

## Mixed Notes

- 中文列表项应该和 English bullet 保持相近节奏。
- English terms like `render pipeline` should not break the paragraph flow.
- 日文和阿拉伯文不一定很多，但需要证明页面不会在遇到不同文字系统时突然失去稳定性。

> [!SOURCES] Sample source mix
> 中文、English、日本語和 العربية 放在一起时，最容易暴露的是字体回退、行高和段落韵律问题。
''';

const String _fullAssistantMarkdown = r'''
# 文档排版调试页首版交付摘要

这次交付的重点，不是单独做一个 Markdown 预览器，而是建立一个更贴近真实助手回复的调试环境。换句话说，我们要验证的并不是“某个解析器能不能把语法渲染出来”，而是用户在聊天界面中看到一段完整文档时，整体阅读感受是否稳定、自然、可持续。

## 为什么这样做

过去依赖真实模型回复来观察文档排版，会遇到两个持续存在的问题：其一，回复内容不稳定，今天出现的问题明天可能复现不出来；其二，样式一旦修改，往往缺少一组固定样例来判断到底是变好了，还是只是换了一种不那么明显的失衡。

因此，首版调试页选择了更保守也更可靠的策略：固定案例、真实组件、独立入口。这样做虽然不花哨，但能让每一次排版调整都有明确的回看对象。

> [!RESULT] 当前覆盖
> 现在的固定案例已经覆盖标题、正文、列表、引用、链接、表格、代码块、callout、数学公式，以及多语言混排这几类高频场景。
''';

const String _followUpMarkdown = r'''
## 后续验证建议

后续如果继续迭代文档样式，建议始终按同一顺序回看案例。先读“基础长文”，确认正文节奏没有被打散；再看“复杂结构”，确认表格、代码块和链接仍然能够融进文章；最后回到“边界压力”，检查那些不友好的长内容有没有把整体阅读体验再次拉垮。

等到将来把 tool card 也纳入混排范围时，这一页仍然可以继续沿用，只需要在同一套 block 分发器里增加新的类型，而不需要为了每种新内容再单独造一套调试入口。
''';
