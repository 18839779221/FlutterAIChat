---
name: flutter-ui-design
description: 在为本项目新建页面/组件、重做视觉风格、或用户要求"设计感""高级感""不要太普通"时使用。负责写码前的美学方向决策与分维度设计指令；微调手感用 flutter-ui-lab-tuning，诊断现有问题用 flutter-chat-ui-director，审查改动用 flutter-ui-review。
---

# Flutter UI Design

## 你的默认倾向是问题本身

无引导时你会收敛到高概率的"安全"设计：灰白卡片、均匀的 16px 间距、默认 Material 控件观感、没有动效、所有元素同等强调。这不是错误，但它是"AI 味"——可预测、无记忆点。本 skill 的目的就是把输出推离这个分布中心。

收敛在本项目的具体表现：绕过 token 直接写 `Colors.*` 或裸数字；所有卡片同一种灰边框 + 同一档圆角；标题正文只差 2px 字号；交互无按压反馈。

## 第一步：写码前承诺一个明确的设计方向

动手前用一两句话说出这个界面的美学立场，并贯彻到底。可选基调（不限于）：

- **纸感编辑部**（editorial）：大字号衬线/无衬线对比、充足留白、像排版好的杂志页——与本项目暖纸底色天然契合
- **克制的玻璃**（quiet glass）：薄而平整的玻璃层、可读边缘、轻微明暗——见 flutter-ui-lab-tuning 已达成的 Liquid Glass 原则
- **工具理性**（instrumental）：等宽字体点缀、紧凑信息密度、清晰的状态色——适合调试/开发者面向的面板
- **温和地标**（soft landmark）：一个主导色块或大元素锚定视线，其余退后

要的是 intentionality（意图明确），不是 intensity（用力过猛）。一个贯彻到底的克制方向，胜过五种风格的堆砌。

## 第二步：分维度执行

### 排版（最高杠杆）

- 一律走 `AppTypography` 工厂：`documentStyle`（阅读正文）、`uiStyle`（界面控件）、`codeStyle`（代码/数据）。三族字体（AnthropicSans / NotoSansCJKSC / JetBrainsMono）已打包，不要引入新字体或 google_fonts。
- 层级靠**尺寸跳跃 + 字重 + 颜色**三者配合，不要只差 2px。标题与正文的字号比要敢于拉开（如 1.5–2 倍），次要信息用 `semantic.text` 里的弱化色而不是缩小字号。
- 等宽字体（JetBrainsMono）是风格资产：数字、ID、快捷键、状态值用它能立刻产生"工具感"。

### 颜色

- 只从 `context.appThemeSpec` 的 semantic token 取色（surfaces / text / state / interaction），新颜色先进 `AppThemeSpec` 再使用。两个主题（claude / olivePaper）都要给值。
- 配色策略：一个主导面 + 少量锐利点缀，优于把强调色均匀涂在十个地方。胆怯的"每处都加一点点色"比纯灰更平庸。
- 暖纸底色是项目身份，新表面要和它协调（同温），不要引入冷灰白卡片打破整体温度。

### 空间与构图

- 间距/圆角只用 `AppSpacing`（xxs–xl）和 `AppRadius`（sm/md/lg/pill）。节奏要有对比：组内紧、组间松，全部 `lg` 等距是没有节奏。
- 不是所有内容都要装进卡片。留白、分组标题、一条 hairline 往往比再套一层 Container + 边框更高级。先删层级，再加装饰。
- 敢于不对称：一个放大的关键元素 + 退后的次要元素，比均匀网格更有构图感。

### 动效

- 时长曲线只用 `AppMotion`（instant 到 ambient 八档 + easeOutCubic 等曲线）。
- 动效要有因果：出现/展开应能解释空间来源；按压应让对象本身回应（见 lab-tuning 的形变原则）。不做无来源的装饰动画。
- 默认从 implicit animations（AnimatedContainer/AnimatedOpacity/AnimatedSwitcher）起步，确有编排需求再上 explicit。

## NEVER 清单

- 不绕过 token：禁 `Colors.*`、裸 hex、裸数字间距/圆角/时长（实验新 token 除外，且实验通过后要回收进 theme）。
- 不用 Material 默认观感交差：默认 elevation 阴影、默认紫色调、默认 ListTile 长相。
- 不做"全卡片化"布局：每个元素都包一层圆角灰边框卡片。
- 不让交互表面无反馈：可点击的东西按下去必须有可感知变化。
- 不堆叠多层边框/分割线营造"精致"——那会显得内凹和杂乱。
- 不在每次生成里收敛到同一个安全答案：如果上一个界面已经用了"编辑部"方向，下一个独立界面应重新做方向决策。

## 验证闭环

设计方向只有渲染出来才算数，不要凭代码自评"好看"：

1. 走 flutter-ui-lab-tuning 的 Lab 工作流：`fvm flutter run -t lib/main_<topic>_lab.dart -d web-server --web-hostname 127.0.0.1 --web-port 7357`，截图检查。
2. 截图自审三问：**第一眼落在哪？**（应是你设计的视觉锚点）**层级一眼可分吗？**（标题/正文/次要信息）**两个主题下都成立吗？**（claude 与 olivePaper 各截一次）
3. 交互态至少检查 pressed/expanded 一种，不只看 idle。
4. `dart format` + 定向 `fvm flutter analyze` 通过后再给用户看。

升级路径（当前未配置，需要时再引入）：Dart/Flutter MCP server（`dart mcp-server`，可读运行时错误和 widget 树）、golden test 截图回归、Widget Previewer。

## 与其他 skill 的边界

- 现有页面"哪里不对" → 先用 **flutter-chat-ui-director** 诊断定方向，本 skill 负责把方向落成具体设计决策。
- 手感/质感/动效参数微调 → **flutter-ui-lab-tuning**。
- 改动完成后的多维审查 → **flutter-ui-review**。
