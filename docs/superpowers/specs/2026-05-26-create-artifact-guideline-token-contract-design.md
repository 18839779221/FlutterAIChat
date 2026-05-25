# create_artifact guideline 与全局设计 token 对齐设计

## 背景

当前项目已经具备正式 `create_artifact` 工具，可在聊天回答中插入内联 HTML / SVG artifact，用于图表、表格、交互说明等增强表达。

但现状仍有两个明显问题：

1. `create_artifact` 当前更像“直接生成一个可视化产物”，而不是“先读取当前原生设计规范，再生成回答增强型 artifact”
2. artifact 的 HTML 预览尚未复用项目已有设计语言，主题、字体、色值、背景与 App 原生界面之间仍有割裂感

本次需求希望把 `create_artifact` 的“解释增强”方向单独强化出来，使其形成明确的两步流程：

1. 先读取与 `create_artifact` 配套的当前规范
2. 再基于该规范生成 artifact

同时，本次不希望为 artifact 单独发展一套平行设计系统，而是要求：

- artifact 只引用项目级 design token
- 如果项目当前缺少图表辅助等 token，应先扩展项目全局 token
- WebView 只是把项目 token 映射为 HTML 可用的 CSS variables，而不是拥有第二套视觉真相源

## 目标

本次设计目标如下：

1. 新增前置工具 `create_artifact:guideline`，作为解释增强型 artifact 的显式前置参考步骤
2. 在 `create_artifact:guideline` 与 `create_artifact` 两个 tool desc 中同时强化“首次 `create_artifact` 前必须先读 guideline”的 prompt 约束
3. guideline 返回结构以 `JSON + 代码化宿主包裹示意` 为主，避免纯抽象 token 列表导致理解偏差
4. artifact 生成时只引用项目级 design token，不直接硬编码主题特定的视觉值
5. 如果项目现有 token 不够支撑可视化场景，应优先扩展项目全局 token，而不是在 artifact/WebView 私有层补一套
6. WebView 采用“宿主统一包裹 + 主题变化整页重载”的方案，使相同 source 能在不同主题下自然重渲染

## 非目标

本轮明确不做以下事情：

1. 不把 `create_artifact:guideline` 设计成会直接生成 artifact 的复合工具
2. 不把 artifact 升级成完整页面系统、模板系统或组件系统
3. 不为 artifact 引入以 `class` 为主的预制组件语义
4. 不让 WebView 持有独立于项目主题系统之外的第二套 token 真相源
5. 不继续在 tool desc 中推荐 `Read/Edit/Write` 作为 artifact 默认迭代路径
6. 不在本轮实现 execution-time 硬阻断，例如未读 guideline 时强制拒绝 `create_artifact`

## 问题分析

### 1. `create_artifact` 当前职责过宽

当前 `create_artifact` 的模型描述中，同时承担了：

- 何时适合生成 artifact
- artifact 的布局审美建议
- 颜色与背景使用建议
- 后续如何继续编辑 artifact

这会带来两个问题：

1. 动态经常变化的规范被塞进静态 desc，维护成本高
2. 模型拿到的是一份通用说明，而不是“当前这次宿主真实会怎么包裹和渲染 artifact”

### 2. artifact 设计语言尚未与 App 原生主题对齐

当前预览层会包裹一个统一的 HTML 文档壳，但默认字体与配色仍偏 Web 通用兜底风格，并未真正消费项目中的 `AppThemeSpec`。

这意味着：

- artifact 更像一个嵌入式网页
- 而不是与聊天页面共享设计语言的原生解释增强块

### 3. `class` 方案并不符合本次目标

本轮目标不是给模型一组预制 UI 组件，也不是让 artifact 成为一个“搭积木式”的页面系统。

如果以 `class` 为主，就会默认把“规范”升级为“已经组合好的视觉角色”，例如：

- 卡片
- 标题
- 说明
- 指标块

这会在无形中把 artifact 推向轻量组件系统，而不是“只给基本设计规范”的方向。

因此本轮应明确选择：

- 不以 `class` 作为主 contract
- 以 CSS 变量 / token 引用作为唯一主路径

## 方案选择

### 方案 A：仅强化 `create_artifact` 自身 desc

不采用。

做法：

- 不新增前置 tool
- 继续把所有规范写进 `create_artifact` description
- 由宿主负责注入 token

问题：

- 动态规范仍被写死在静态 desc 中
- 模型没有显式“先读规范再生成”的步骤
- 无法体现 `create_artifact` 与 guideline 的配套关系

### 方案 B：新增 `create_artifact:guideline`，并只暴露项目级 token 引用规范

本轮采用。

做法：

- 新增前置工具 `create_artifact:guideline`
- 其返回值提供当前宿主包裹环境、可引用 token、布局约束与渲染规则
- `create_artifact` 负责真正生成 artifact
- WebView 只负责注入项目级 token 的 CSS 映射

优点：

- 动态规范与生成动作分离
- 能明确建立 `guideline -> create_artifact` 的两步流程
- artifact 不拥有独立设计系统
- 后续主题新增、主题切换、图表 token 扩展都更容易演进

### 方案 C：artifact/WebView 私有 token 先行

不采用。

做法：

- guideline 与 WebView 先自行补齐图表 token
- 暂不进入项目主主题系统

问题：

- 会形成第二套视觉真相源
- 后续再并回项目主 token 的成本更高
- 与本次“设计 token 全局性”目标相冲突

## 核心设计

### 1. 四层职责拆分

本次能力拆分为四层：

#### `create_artifact:guideline`

前置读取工具，只负责返回：

- 当前宿主设计 token 的引用规范
- artifact 运行时包裹环境示意
- inline artifact 的布局约束
- 渲染规则与禁止事项

它不生成 artifact。

#### `create_artifact`

生成工具，只负责：

- 基于 guideline 返回的规范生成 HTML / SVG
- 将 artifact 作为回答增强内容发布到回复中

它不定义设计语言，也不返回主题具体值规范。

#### 项目级 design token

这是唯一视觉真相源，继续由现有主题系统承载。

如果 artifact 需要图表辅助、轴线、网格线等语义 token，应优先扩展项目全局 token，再供 artifact 复用。

#### WebView 注入层

这是一层薄适配器，负责：

- 把项目级 token 转成 CSS variables
- 把宿主默认包裹样式注入 HTML
- 在主题变化时重载整页文档

它不是独立设计系统。

### 2. `create_artifact:guideline` 的工具定位

本工具应被明确塑造成 `create_artifact` 的配套前置工具，而不是泛化的“查设计规范”工具。

命名采用：

- `create_artifact:guideline`

命名意图：

- 强调它和 `create_artifact` 强绑定
- 强调它承担“生成前置参考”的职责
- 避免被理解成通用 UI 规范工具

### 3. prompt 约束策略

本轮不只是“在语气上稍微提醒”，而是要在两个 tool desc 中都放入高显著性规则。

但为了贴合项目当前 tool desc 风格，本轮不采用大量 XML/tag 结构，而是采用：

- 靠前位置的 `IMPORTANT:` 强提示
- 短段落
- 明确触发时机
- 在两个 tool desc 中镜像重复一次关键规则

#### `create_artifact:guideline` desc 约束

应包含以下核心语义：

1. 当模型准备创建“用于可视化/描述增强”的 artifact 时，第一次 `create_artifact` 调用前必须先调用 `create_artifact:guideline`
2. 不要跳过这一步直接生成首版 artifact
3. 本工具是 `create_artifact` 的前置配套步骤，而不是 artifact 生成步骤本身
4. 对同一个 artifact，通常只应在首次创建前调用一次
5. 只有当 guideline 上下文缺失或很可能已变化时，才应再次调用

建议英文 desc 草案：

```text
Read the current design-token contract and host rendering constraints for explanatory artifacts that should feel native to the app.

IMPORTANT: If you are about to create an artifact for visualization or explanatory enhancement, you MUST call `create_artifact:guideline` before the first `create_artifact` call for that artifact. Do not skip this step for the first version.

Use this tool immediately before the first `create_artifact` call for a new explanatory artifact. This tool is a paired prerequisite for `create_artifact`, not the artifact creation step itself.

This tool returns the current host markup contract, token references, layout constraints, and rendering rules that the artifact must follow. Use the returned token references and host contract instead of hardcoding theme-specific visual values.

After reading the guideline for the same artifact, do not call this tool again unless the guideline context is missing or likely changed.
```

#### `create_artifact` desc 约束

应在当前 desc 最前部补充以下核心语义：

1. 对任何“用于可视化/描述增强”的首次 `create_artifact` 调用，必须先调用 `create_artifact:guideline`
2. 不要直接跳过 guideline 生成首版 artifact
3. guideline 的结果应被视为当前 artifact 渲染环境的宿主 contract
4. 当 guideline 提供了 token 引用时，不要硬编码主题特定的颜色、间距尺度或其他视觉值

建议英文开头草案：

```text
Publish an interactive, self-contained HTML artifact inline in your reply.

IMPORTANT: Before the first `create_artifact` call for any artifact used for visualization or explanatory enhancement, you MUST first call `create_artifact:guideline`. Do not create the first version directly without reading the guideline.

Use the guideline result as the current host contract for artifact rendering. Follow its token references, layout constraints, and rendering rules. Do not hardcode theme-specific colors, spacing scales, or other visual values when guideline references are available.
```

### 4. guideline 返回结构

返回格式采用：

- `JSON + 简短说明`

但以结构化 JSON 为主，避免长期演进时变成纯 prompt 文本。

第一版建议包含以下字段：

1. `usage`
2. `host_markup_contract`
3. `layout_constraints`
4. `rendering_rules`

#### `usage`

该字段不承担完整工具语义，只做简短职责说明，例如：

- 这是本次 `create_artifact` 使用的宿主规范上下文
- 请优先引用下方 token 与宿主包裹约定
- 不要把这些规范直接原样输出给最终用户

#### `host_markup_contract`

这是主体字段。

本轮不再把 `tokens` 和 `host_wrapper_contract` 完全拆成两块文字说明，而是把它们合并成一个“接近真实运行时的代码化宿主包裹示意”。

设计意图：

- 让模型理解自己最终运行在怎样的 HTML 壳中
- 明确哪些 CSS variables 由宿主注入
- 明确 `html/body` 与根容器的默认行为
- 减少“理解抽象 token 清单但不知道实际运行面”的偏差

示意结构例如：

```html
<html>
  <head>
    <style>
      :root {
        --app-artifact-page-bg: ...;
        --app-artifact-surface: ...;
        --app-artifact-surface-muted: ...;
        --app-artifact-text-primary: ...;
        --app-artifact-text-secondary: ...;
        --app-artifact-text-tertiary: ...;
        --app-artifact-border-subtle: ...;
        --app-artifact-border-strong: ...;
        --app-artifact-accent: ...;
        --app-artifact-success: ...;
        --app-artifact-warning: ...;
        --app-artifact-error: ...;
        --app-artifact-info: ...;
        --app-artifact-chart-1: ...;
        --app-artifact-chart-2: ...;
        --app-artifact-chart-3: ...;
        --app-artifact-chart-4: ...;
        --app-artifact-chart-5: ...;
        --app-artifact-chart-grid: ...;
        --app-artifact-chart-axis: ...;
        --app-artifact-chart-highlight: ...;
        --app-artifact-space-2: ...;
        --app-artifact-space-3: ...;
        --app-artifact-space-4: ...;
        --app-artifact-space-6: ...;
        --app-artifact-radius-sm: ...;
        --app-artifact-radius-md: ...;
        --app-artifact-radius-lg: ...;
        --app-artifact-font-ui: ...;
        --app-artifact-font-code: ...;
        --app-artifact-shadow-soft: ...;
      }

      html, body {
        margin: 0;
        padding: 0;
        background: var(--app-artifact-page-bg);
        color: var(--app-artifact-text-primary);
        font-family: var(--app-artifact-font-ui);
      }

      * {
        box-sizing: border-box;
      }

      #artifact-root {
        width: 100%;
        background: var(--app-artifact-page-bg);
        color: var(--app-artifact-text-primary);
      }
    </style>
  </head>
  <body>
    <div id="artifact-root">
      <!-- model-generated content goes here -->
    </div>
  </body>
</html>
```

代码外只补少量说明：

- 该片段是宿主包裹环境示意，不是要求模型原样重复输出
- 模型应优先引用其中已有 token
- 模型主要生成 `#artifact-root` 内部内容，除非明确要求完整文档

#### `layout_constraints`

该字段描述 artifact 作为 inline 增强内容时的宿主约束，例如：

- 内容应以正常文档流为主
- 不要依赖超大固定高度外层包裹
- 优先控制在 1 屏内，尽量不超过 2 屏
- 避免横向滚动
- 在手机上优先窄屏、触控友好布局

注意：

- 本轮不再要求页面背景默认透明
- 应优先使用宿主提供的背景与 surface token
- 不要假设纯白背景或完全透明背景

#### `rendering_rules`

该字段描述“如何生成”，例如：

- 当有 token 引用时，不要硬编码主题色
- 图表轴线、网格线、提示色也应使用 token
- 允许内联 `<style>` / `<script>`
- 禁止依赖外部 CDN、远程 CSS、网络请求
- 不要把 artifact 写成独立产品页面式舞台

### 5. token 设计原则

artifact 不应拥有独立主题对象，而应复用项目主主题系统中的全局语义 token。

第一版建议对齐并补齐以下四组语义：

#### Surface / Text

用于基础阅读与表面层次：

- page background
- surface
- surface muted
- text primary
- text secondary
- text tertiary
- border subtle
- border strong

#### State

用于语义状态表达：

- success
- warning
- error
- info

#### Chart

这是本轮最需要新增到项目主 token 的部分：

- chart-1
- chart-2
- chart-3
- chart-4
- chart-5
- chart-grid
- chart-axis
- chart-highlight

这些 token 应进入项目全局语义层，而不是只在 artifact/WebView 私有层定义。

#### Scale

用于基础尺寸与排版：

- spacing scale
- radius scale
- ui font
- code font
- soft shadow

### 6. 与现有 `AppThemeSpec` 的对齐方式

实现方向上，不建议新增一套 artifact 专属 `ThemeSpec`，而应在现有 [app_theme_spec.dart](/Users/skka/flutterSpace/FlutterAIChat/lib/theme/app_theme_spec.dart) 上补充可视化所需的全局语义 token。

建议原则：

1. 已有 surface / text / state 语义尽量复用
2. 缺失的 chart token 进入项目全局语义层
3. WebView 只做“项目 token -> CSS variables”的映射

这样后续：

- 新增主题
- 调整 Claude / Olive Paper 视觉语言
- 扩展更多 artifact 可视化形态

都仍然只有一套视觉真相源。

### 7. WebView 注入与主题切换策略

WebView 注入层采用：

- 宿主统一包裹
- 主题变化整页重载

不采用“在已加载文档内局部动态替换 CSS”作为第一版主方案。

原因：

1. 与现有 `loadHtmlString(...)` 路径更一致
2. token、背景、字体、图表色、测高逻辑可一次性同步更新
3. 可避免热替换样式时的状态不一致、测高不同步、脚本缓存初始样式等问题

第一版明确策略：

- `source` 变化时重载文档
- `theme` 变化时，即使 `source` 不变，也重载文档

### 8. planner / tool 协作规则

本轮希望把 `guideline -> create_artifact` 建立成解释增强场景下的默认主路径，但不把系统写成 brittle 的 execution-time 硬路由。

规则如下：

1. 当模型判断自己需要用 artifact 做可视化/描述增强时，首次 `create_artifact` 前必须先调用 `create_artifact:guideline`
2. 该规则在两个 tool desc 中都要重复出现，避免遗漏
3. `create_artifact:guideline` 通常只在同一个 artifact 的首次创建前调用一次
4. 如果 guideline 上下文缺失或可能变化，可以再次调用
5. 本轮不把这条规则下沉为 execution-time 硬阻断，而是先作为 prompt-contract 强约束

不采用以下策略：

- 只要出现图表关键词就写死路由
- 只要是 HTML 就无条件拦截
- 未调用 guideline 时立即执行失败

这与项目当前“避免用越来越多硬编码路由修补模型行为”的总体方向保持一致。

## 对现有设计的修正

本设计会修正当前 artifact 相关设计中的两点假设：

1. 不再继续强调“后续优先使用 `Read/Edit/Write` 持续编辑 artifact 文件”
   - 因为实际联动效果并不好
   - 本轮不再在 tool desc 中把它写成推荐默认路径

2. 不再继续强调“页面背景默认透明”
   - 因为项目现在能够提供背景引用
   - WebView 中透明背景实际可能表现为不理想的白底观感
   - 本轮改为优先引用宿主背景与 surface token

## 验收标准

本轮设计完成后，应满足以下标准：

1. 项目中存在正式 `create_artifact:guideline` 设计，并与 `create_artifact` 建立明确前置关系
2. `create_artifact:guideline` 与 `create_artifact` 的 desc 中都包含高显著性的首次调用顺序约束
3. guideline 返回结构以 `host_markup_contract` 代码化示意为主，而不是只给抽象 token 列表
4. artifact 只引用项目级 token，不新建独立视觉真相源
5. 图表辅助 token 若缺失，应先进入项目主主题系统
6. WebView 采用统一包裹 + 主题变化整页重载策略

## 风险与后续关注点

### 1. prompt 强约束仍可能被模型偶发忽略

虽然本轮会在两个 desc 中都补充 `IMPORTANT:` 约束，但它仍然属于 prompt-level 约束，不等同于 execution-time 校验。

后续若观察到遗忘频率较高，可再评估是否加入更轻量的运行时提醒或 planner 上下文提示，但不应直接回退成大规模硬编码路由。

### 2. token 规模膨胀风险

如果一次性引入过多 artifact 专用 token，可能会削弱主题系统可维护性。

因此第一版应保持：

- 基础 surface/text/state 复用优先
- chart token 只补最小够用集
- 避免引入过细、过业务化的图表 token

### 3. 主题切换重载可能带来轻微刷新感

整页重载是第一版最稳方案，但在主题切换时可能出现轻微重绘。

这属于可以接受的首版权衡，优先保证一致性与正确性。

## 结论

本轮设计采用：

- 新增 `create_artifact:guideline`
- 用它承载 `create_artifact` 的前置规范读取
- 以项目级全局 design token 作为唯一视觉真相源
- 以 `host_markup_contract` 代码化返回宿主包裹环境
- 以 WebView 注入层完成 `AppThemeSpec -> CSS variables` 映射
- 以“首次必须先读 guideline，再 create_artifact”为 prompt-contract 强约束

这样，artifact 将更清晰地从“生成一个独立小网页”转向“生成一个贴合 App 原生设计语言的回答增强型可视化块”。
