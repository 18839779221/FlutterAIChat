# 动效设计系统 (Motion Design System)

## 设计哲学

FlutterAIChat 的动效设计对标 **Claude 和 Apple** 的交互标准，追求**克制、精准、有呼吸感**的专业体验。动画不是装饰，而是信息传达和状态反馈的核心手段。

### 设计参考

- **Claude**：专业、流畅、有节奏感的 AI 对话体验
- **Apple HIG**：自然、精准、人性化的交互标准
- **Material Design Motion**：系统化的动画语言

### 核心特质

#### 1. 时间感知的精准度 (Temporal Precision)
- 动画时长基于人类感知研究，而非随意数值
- 小元素快速响应（触觉反馈），大元素有惯性（空间感知）
- 有"重量感"：轻的东西快，重的东西慢

#### 2. 缓动曲线的人性化 (Humanized Easing)
- 几乎不用线性动画
- 进入用 `easeOut`（快速响应，缓慢停止）
- 退出用 `easeIn`（缓慢启动，快速消失）
- 循环用正弦曲线（平滑无顿挫）

#### 3. 状态转换的连贯性 (State Continuity)
- 状态变化有明确的"完成时刻"
- 不是简单的颜色切换，而是有仪式感的转换
- 工具执行完成有"结算动画"

#### 4. 微交互的即时反馈 (Instant Feedback)
- 按钮按下瞬间就有反馈
- 视觉模拟触觉体验
- 有"按下去"的真实感

#### 5. 信息出现的节奏感 (Rhythmic Appearance)
- 内容不是"突然出现"，而是"生长出来"
- 有从无到有的过程，符合认知预期
- 消息、卡片、列表项都有出场节奏

#### 6. 性能与可访问性 (Performance & Accessibility)
- 优先使用 GPU 加速属性
- 尊重系统减少动画设置
- 60fps 流畅体验

---

## 动画规范

### 时长规范 (Duration Scale)

基于人类感知研究的时长体系，每个数值都有科学依据：

```dart
// lib/theme/app_motion.dart
class AppMotion extends ThemeExtension<AppMotion> {
  /// 即时反馈 - 基于触觉反馈延迟（人手指触感）
  final Duration instant;      // 100ms
  
  /// 快速过渡 - 基于视觉跟随延迟（眼球追踪速度）
  final Duration quick;        // 200ms
  
  /// 标准动画 - 基于阅读节奏（一个词的识别时间）
  final Duration standard;     // 300ms
  
  /// 强调动画 - 基于空间感知（房间大小的判断）
  final Duration emphasized;   // 400ms
  
  /// 柔和动画 - 基于注意力转移周期
  final Duration gentle;       // 600ms
  
  // 循环动画的节奏
  /// 脉冲节奏 - 基于人的静息呼吸周期（12-20次/分钟）
  final Duration pulse;        // 800ms
  
  /// 扫光节奏 - 基于视觉扫描速度（横向阅读一行）
  final Duration sweep;        // 1200ms
  
  /// 氛围节奏 - 不干扰主任务的背景动画
  final Duration ambient;      // 2000ms
}
```

**使用指南：**

| 时长 | 人体工程学依据 | 适用场景 | 示例 |
|------|---------------|---------|------|
| `instant` (100ms) | 触觉反馈延迟 | 即时反馈 | 按钮按下、开关切换 |
| `quick` (200ms) | 视觉跟随速度 | 快速过渡 | 小卡片展开、颜色变化 |
| `standard` (300ms) | 词汇识别时间 | 标准动画 | 消息出现、对话框弹出 |
| `emphasized` (400ms) | 空间感知时间 | 强调动画 | 页面转场、工具完成 |
| `gentle` (600ms) | 注意力转移 | 柔和动画 | 背景渐变、大面积变化 |
| `pulse` (800ms) | 呼吸周期 | 循环脉冲 | 工具执行中的呼吸效果 |
| `sweep` (1200ms) | 阅读扫描 | 扫光效果 | 工具卡片的扫光动画 |
| `ambient` (2000ms) | 背景感知 | 氛围动画 | 空状态浮动、背景动态 |

---

### 缓动曲线规范 (Easing Curves)

基于 Apple HIG 和 Material Design 的曲线标准：

```dart
class AppMotion extends ThemeExtension<AppMotion> {
  /// 元素进入 - 快速响应，缓慢停止（符合物理惯性）
  final Curve easeOut;         // Curves.easeOutCubic
  
  /// 元素退出 - 缓慢启动，快速消失（减少干扰）
  final Curve easeIn;          // Curves.easeInCubic
  
  /// 元素移动 - 自然的加速减速（模拟物理运动）
  final Curve easeInOut;       // Curves.easeInOutCubic
  
  /// 弹性效果 - 完成时刻的仪式感（工具执行完成）
  final Curve spring;          // Curves.elasticOut
  
  /// 呼吸曲线 - 循环动画的平滑过渡（无顿挫感）
  final Curve breathing;       // Curves.easeInOutSine
  
  /// 柔和曲线 - 大面积变化的缓慢过渡
  final Curve gentle;          // Curves.easeOutQuart
}
```

**曲线选择指南：**

```
easeOut (进入) - Apple 推荐的默认进入曲线
  ▲
  │     ╱─────
  │   ╱
  │ ╱
  └──────────▶
  快速响应用户操作，缓慢停止给予确认感
  用于：消息出现、卡片展开、对话框弹出

easeIn (退出) - Apple 推荐的默认退出曲线
  ▲
  │ ─────╲
  │       ╲
  │         ╲
  └──────────▶
  缓慢启动减少突兀感，快速消失不占用注意力
  用于：消息消失、卡片收起、对话框关闭

easeInOutCubic (移动) - Material Design 标准曲线
  ▲
  │   ╱───╲
  │ ╱       ╲
  │╱         ╲
  └──────────▶
  两端缓慢，中间快速，符合物理运动规律
  用于：元素在屏幕内移动、位置调整、布局变化

spring (弹性) - 完成时刻的仪式感
  ▲
  │     ╱╲╱─
  │   ╱
  │ ╱
  └──────────▶
  带有回弹效果，强调"完成"的瞬间
  用于：工具执行完成、重要操作成功、成就解锁

easeInOutSine (呼吸) - 循环动画专用
  ▲
  │   ╱───╲
  │ ╱       ╲
  │╱         ╲
  └──────────▶
  正弦曲线，循环时无顿挫感，像呼吸一样自然
  用于：脉冲动画、呼吸效果、加载指示器

⚠️ 避免使用：
- Curves.linear：机械感，缺少人性化
- Curves.easeInOut（非Cubic）：循环时有顿挫感
- 过度弹性的曲线：分散注意力
```

---

## 动画模式库

基于 Claude/Apple 体验标准的核心动画模式。

### 1. 消息生长动画 (Message Growth) ⭐⭐⭐⭐⭐

**设计意图**：消息不是"突然出现"，而是"生长出来"，符合对话的自然节奏。

**Claude 的实现**：
- 从下方滑入（20px）
- 同时渐入（0 → 1）
- 轻微缩放（96% → 100%）
- 三者组合产生"生长"的感觉

**规范**：
- 时长：`standard` (300ms) - 基于阅读节奏
- 曲线：`easeOut` - 快速响应，缓慢停止
- 对齐：`Alignment.topCenter` - 从顶部锚点生长

```dart
class MessageGrowthAnimation extends StatelessWidget {
  final Widget child;
  
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 300),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),  // 从下方20px滑入
            child: Transform.scale(
              scale: 0.96 + (0.04 * value),  // 从96%放大到100%
              alignment: Alignment.topCenter,
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }
}
```

**应用场景**：
- 新消息出现
- AI 回复渲染完成
- 工具结果卡片出现

**注意事项**：
- 不要在滚动列表中对所有可见项同时应用
- 只对新增的项应用动画
- 当前主路径通过 `ChatTimelineRow.shouldAnimate` 精确控制新增项动画，不额外引入列表级动画容器

---

### 2. 工具完成反馈 (Tool Completion Feedback) ⭐⭐⭐⭐⭐

**设计意图**：工具从 running → success 的瞬间，需要明确的"完成感"和"仪式感"。

**Claude 的体验特征**：
- 运行态与完成态有明确区分
- 完成反馈清晰，但不过度抢占注意力

**规范**：
- 终态切换优先使用克制的 `AnimatedSwitcher`
- 运行态信号优先由 `RunningStatusDot` 和 `ToolStatusBadge` 承担
- 不为了制造“完成感”强制引入高弹性图标动画

```dart
ToolStatusBadge(
  label: '完成',
  statusColor: colors.workflowSuccess,
  icon: Icons.check_rounded,
)
```

**应用场景**：
- 工具执行完成
- 文件保存成功
- 操作确认反馈

**注意事项**：
- 完成反馈要清晰，但不要为了“庆祝感”放大动效存在感
- 完成图标应该保持可见，不要立即消失
- 配合颜色变化增强反馈

---

### 3. 输入框焦点呼吸 (Input Focus Breathing) ⭐⭐⭐⭐⭐

**设计意图**：输入框是对话的入口，获得焦点时应该"浮起来"，有邀请感。

**Apple 的实现**：
- 阴影增强（模拟高度提升）
- 轻微缩放（1.0 → 1.02）
- 阴影扩散（模拟光晕）

**规范**：
- 时长：`quick` (200ms) - 快速响应焦点变化
- 曲线：`easeOut` - 快速响应，缓慢停止
- 阴影模糊：20 → 28
- 阴影偏移：(0, 9) → (0, 12)
- 缩放：1.0 → 1.02

```dart
class FocusBreathingInput extends StatelessWidget {
  const FocusBreathingInput({
    super.key,
    required this.child,
    required this.focusNode,
  });

  final Widget child;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeSpec.of(context);
    final motion = theme.core.motion;
    final radius = theme.core.radius;
    final isFocused = focusNode.hasFocus;

    return AnimatedScale(
      scale: isFocused ? 1.02 : 1.0,
      duration: motion.quick,
      curve: motion.easeOut,
      child: AnimatedContainer(
        duration: motion.quick,
        curve: motion.easeOut,
        decoration: BoxDecoration(
          color: theme.assistantSurface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(radius.lg),
          boxShadow: [
            BoxShadow(
              color: theme.primaryText.withValues(
                alpha: isFocused ? 0.12 : 0.065,
              ),
              blurRadius: isFocused ? 28 : 20,
              offset: Offset(0, isFocused ? 12 : 9),
              spreadRadius: isFocused ? 1 : 0,
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}
```

**应用场景**：
- 聊天输入框
- 搜索框
- 表单输入

**注意事项**：
- 缩放幅度要克制（1.02 而非 1.1）
- 阴影变化要平滑
- 配合边框高亮增强效果

---

### 4. 按钮按下反馈 (Button Press Feedback) ⭐⭐⭐⭐⭐

**设计意图**：按钮按下瞬间就要有反馈，模拟真实的"按下去"的感觉。

**Apple 的实现**：
- 轻微缩小（1.0 → 0.98）
- 阴影降低（模拟高度下降）
- 瞬间响应（100ms）

**规范**：
- 时长：`instant` (100ms) - 触觉反馈延迟
- 曲线：`easeOut` - 快速响应
- 缩放：1.0 → 0.98
- 阴影模糊：20 → 12
- 阴影偏移：(0, 9) → (0, 4)

```dart
class PressableButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  
  @override
  State<PressableButton> createState() => _PressableButtonState();
}

class _PressableButtonState extends State<PressableButton> {
  bool _isPressed = false;
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onPressed?.call();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: _isPressed ? 12 : 20,
                offset: Offset(0, _isPressed ? 4 : 9),
              ),
            ],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
```

**应用场景**：
- 发送按钮
- 工具确认按钮
- 所有可点击的按钮

**注意事项**：
- 必须在 `onTapDown` 时立即响应
- 不要等到 `onTap` 才反馈
- 缩放幅度要克制（0.98 而非 0.9）

---

### 5. 流式态连续性 (Streaming Continuity) ⭐⭐⭐⭐⭐

**设计意图**：流式回复应该保持阅读连续性，让用户清楚系统仍在生成，但不要为了“像打字”强行叠加噪声动效。

**当前结论**：
- 不再使用内联打字光标
- 流式态与完成态共享同一 Markdown 渲染通道
- “仍在生成”的信号由更克制的运行状态条、工具运行态、文本持续增长来承担

**规范**：
- 不为正文尾部额外追加闪烁光标
- 不为了制造“打字感”引入高频局部闪烁
- 优先保证流式态与完成态之间无重挂载、无视觉断层
- 运行中反馈应放在正文外层的低噪音状态面板，而不是正文末尾装饰

**实现要求**：
```dart
FinalResponseBlock(
  text: streamedText,
  isStreaming: true,
)

UnifiedTurnStatusBar(
  status: activeTurnStatus,
)
```

**应用场景**：
- AI 流式回复
- 实时输入提示
- 加载状态指示

**注意事项**：
- 光标必须紧跟文本末尾
- 使用 `easeInOutSine` 而非 `easeInOut`
- 流式结束后立即隐藏光标

---

### 6. 工具执行呼吸效果 (Tool Running Pulse)

**设计意图**：工具执行中，通过呼吸效果传达"正在工作"的状态。

**现有实现分析**：
- ✅ `RunningStatusDot` 已实现脉冲效果
- ✅ 使用 760ms 周期（接近呼吸节奏）
- ⚠️ 曲线使用 `easeInOut`，建议改为 `easeInOutSine`

**优化建议**：
```dart
// 当前实现（tool_running_effects.dart:28）
duration: const Duration(milliseconds: 760),
curve: Curves.easeInOut,  // ⚠️ 有轻微顿挫感

// 优化后
duration: const Duration(milliseconds: 800),  // 标准呼吸周期
curve: Curves.easeInOutSine,  // 更平滑的呼吸曲线
```

**规范**：
- 时长：`pulse` (800ms) - 人的呼吸周期
- 曲线：`breathing` (easeInOutSine) - 平滑无顿挫
- 缩放：1.0 → 1.42
- 透明度：0.78 → 1.0
- 光晕：10 → 18 blur radius

**应用场景**：
- 工具执行中的状态点
- 加载指示器
- 实时状态指示

---

### 7. 工具卡片扫光效果 (Tool Card Sweep)

**设计意图**：工具执行中，扫光效果增强"正在处理"的感知。

**现有实现分析**：
- ✅ `RunningSweepSurface` 已实现扫光
- ✅ 使用 1100ms 周期（接近阅读扫描速度）
- ✅ 对角线扫光，视觉效果自然

**优化建议**：
```dart
// 当前实现（tool_running_effects.dart:210）
duration: const Duration(milliseconds: 1100),

// 优化后
duration: const Duration(milliseconds: 1200),  // 标准扫描周期
```

**规范**：
- 时长：`sweep` (1200ms) - 视觉扫描速度
- 曲线：`easeInOut` - 平滑循环
- 角度：-0.32 弧度（约 -18°）
- 宽度：容器宽度的 56%
- 透明度：0 → 0.42 → 0

**应用场景**：
- 工具执行中的卡片背景
- 大面积加载状态
- 强调正在处理的区域

---

### 8. Reasoning 折叠动画 (Reasoning Collapse)

**设计意图**：思考过程的展开/折叠应该平滑，有高度变化的过渡。

**现有实现分析**：
- ⚠️ 当前直接显示/隐藏，无过渡动画
- 需要添加 `AnimatedSize`

**规范**：
- 时长：`standard` (300ms) - 标准动画
- 曲线：`easeInOutCubic` - 平滑的高度变化
- 对齐：`Alignment.topCenter` - 从顶部展开

```dart
// 优化 reasoning_section.dart
Widget _buildCollapsibleContent({
  required BuildContext context,
  required String normalized,
}) {
  final theme = AppThemeSpec.of(context);
  final colors = theme;
  final spacing = theme.core.spacing;
  final motion = theme.core.motion;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: spacing.xxs),
          child: Row(
            children: [
              Expanded(
                child: Text('思考过程', ...),
              ),
              AnimatedRotation(
                turns: _isExpanded ? 0.5 : 0,
                duration: motion.standard,
                curve: motion.easeInOut,
                child: Icon(Icons.keyboard_arrow_down, ...),
              ),
            ],
          ),
        ),
      ),
      AnimatedSize(
        duration: motion.standard,
        curve: motion.easeInOut,
        alignment: Alignment.topCenter,
        child: _isExpanded
            ? Padding(
                padding: EdgeInsets.only(top: spacing.xxs),
                child: SelectableText(normalized, ...),
              )
            : const SizedBox.shrink(),
      ),
    ],
  );
}
```

**应用场景**：
- Reasoning 区域展开/折叠
- 工具详情展开/折叠
- FAQ 手风琴

---

### 9. 页面转场动画 (Page Transition)

**设计意图**：页面切换应该有空间感，从右侧滑入 + 渐入。

**规范**：
- 时长：`emphasized` (400ms) - 强调空间变化
- 曲线：`easeOut` - 快速响应，缓慢停止
- 位移：从右侧 100% 滑入
- 透明度：0.0 → 1.0

```dart
class AppPageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  
  AppPageRoute({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = Offset(1.0, 0.0);
            const end = Offset.zero;
            
            var slideTween = Tween(begin: begin, end: end)
                .chain(CurveTween(curve: Curves.easeOutCubic));
            var slideAnimation = animation.drive(slideTween);
            
            var fadeTween = Tween<double>(begin: 0.0, end: 1.0);
            var fadeAnimation = animation.drive(fadeTween);
            
            return SlideTransition(
              position: slideAnimation,
              child: FadeTransition(
                opacity: fadeAnimation,
                child: child,
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 400),
        );
}

// 使用
Navigator.of(context).push(
  AppPageRoute(page: SettingsPage()),
);
```

**应用场景**：
- 设置页面
- 详情页面
- 模型管理页面

---

### 10. 空状态浮动动画 (Empty State Float)

**设计意图**：空状态的建议卡片轻微浮动，增加活力和吸引力。

**规范**：
- 时长：`ambient` (2000ms + index * 200ms) - 错位节奏
- 曲线：`easeInOut` - 平滑循环
- 位移：±4px - 微妙的浮动

```dart
class FloatingCard extends StatefulWidget {
  final Widget child;
  final int index;
  
  @override
  State<FloatingCard> createState() => _FloatingCardState();
}

class _FloatingCardState extends State<FloatingCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _floatAnimation;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(milliseconds: 2000 + (widget.index * 200)),
      vsync: this,
    )..repeat(reverse: true);
    
    _floatAnimation = Tween<double>(
      begin: -4.0,
      end: 4.0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _floatAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _floatAnimation.value),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
```

**应用场景**：
- 空状态建议卡片
- 引导页装饰元素
- 非核心的氛围动画

**注意事项**：
- 浮动幅度要克制（±4px）
- 不同卡片错位启动
- 可以提供禁用选项

---

## 现有动画审查与优化建议

基于对现有代码的分析，以下是需要优化的地方：

### 1. `tool_running_effects.dart` 优化

#### RunningStatusDot
```dart
// 当前实现
duration: const Duration(milliseconds: 760),  // ⚠️ 非标准数值
curve: Curves.easeInOut,  // ⚠️ 循环时有轻微顿挫

// 建议优化
duration: const Duration(milliseconds: 800),  // ✅ 标准呼吸周期
curve: Curves.easeInOutSine,  // ✅ 更平滑的呼吸曲线
```

#### SubtleRunningBreathingSurface
```dart
// 当前实现
duration: const Duration(milliseconds: 1500),  // ⚠️ 偏慢

// 建议优化
duration: const Duration(milliseconds: 1200),  // ✅ 标准扫描周期
```

#### RunningSweepSurface
```dart
// 当前实现
duration: const Duration(milliseconds: 1100),  // ⚠️ 非标准数值

// 建议优化
duration: const Duration(milliseconds: 1200),  // ✅ 标准扫描周期
```

---

### 2. `tool_workflow_card.dart` 优化

```dart
// 当前实现（第77行）
AnimatedContainer(
  duration: const Duration(milliseconds: 180),  // ⚠️ 非标准数值
  curve: Curves.easeOut,  // ✅ 曲线正确
  
// 建议优化
AnimatedContainer(
  duration: const Duration(milliseconds: 200),  // ✅ 标准快速过渡
  curve: Curves.easeOutCubic,  // ✅ 更精确的曲线
```

---

### 3. `reasoning_section.dart` 优化

**当前问题**：折叠/展开无过渡动画

**建议添加**：
```dart
AnimatedSize(
  duration: const Duration(milliseconds: 300),
  curve: Curves.easeInOutCubic,
  alignment: Alignment.topCenter,
  child: _isExpanded ? content : const SizedBox.shrink(),
)

// 同时添加箭头旋转动画
AnimatedRotation(
  turns: _isExpanded ? 0.5 : 0,
  duration: const Duration(milliseconds: 300),
  curve: Curves.easeInOutCubic,
  child: Icon(Icons.keyboard_arrow_down),
)
```

---

### 4. `chat_timeline_row.dart` 现状

**当前实现**：消息出现动画已落在 `MessageGrowthAnimation`，并由 `shouldAnimate` 只对新增行启用。

```dart
final displayRow = shouldAnimate
    ? MessageGrowthAnimation(child: row)
    : row;
```

---

### 5. `chat_input.dart` 优化

**当前问题**：焦点状态无动画反馈

**建议添加**：
```dart
// 监听焦点变化
focusNode.addListener(() {
  setState(() {});
});

// 添加焦点动画
AnimatedScale(
  scale: focusNode.hasFocus ? 1.02 : 1.0,
  duration: const Duration(milliseconds: 200),
  curve: Curves.easeOutCubic,
  child: AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    curve: Curves.easeOutCubic,
    decoration: BoxDecoration(
      boxShadow: [
        BoxShadow(
          blurRadius: focusNode.hasFocus ? 28 : 20,
          offset: Offset(0, focusNode.hasFocus ? 12 : 9),
          spreadRadius: focusNode.hasFocus ? 1 : 0,
        ),
      ],
    ),
  ),
)
```

---

### 6. 流式正文块优化

**当前要求**：保持流式正文和完成正文走同一渲染路径，不再追加打字光标。

**建议方向**：
```dart
MarkdownBody(data: text)
```

配合独立的运行状态展示，而不是在正文尾部附着装饰性光标。

---

## 可访问性支持

### 尊重系统设置

```dart
// 检测系统减少动画设置
bool get reduceMotion {
  return MediaQuery.of(context).disableAnimations;
}

// 条件性应用动画
Duration get animationDuration {
  return reduceMotion 
      ? Duration.zero 
      : const Duration(milliseconds: 300);
}
```

### 提供禁用选项

```dart
// 在设置页面提供开关
class AnimationSettings {
  static bool enableAnimations = true;
  
  static Duration getDuration(Duration standard) {
    return enableAnimations ? standard : Duration.zero;
  }
}
```

---

## 动画测试指南

### 视觉测试
1. **流畅度**：动画是否流畅，无卡顿
2. **时机**：动画触发时机是否合理
3. **完整性**：动画是否完整播放，无中断
4. **一致性**：相同场景动画是否一致

### 性能测试
```dart
// 使用 Flutter DevTools 的 Performance 面板
// 检查指标：
// - FPS 应保持在 60fps
// - 帧渲染时间 < 16ms
// - 避免 jank（掉帧）
```

### 边界测试
- 快速连续触发动画
- 动画进行中切换页面
- 低端设备测试
- 减少动画模式测试

---

## 实施检查清单

### 新增动画前
- [ ] 动画是否有明确的功能目的？
- [ ] 是否符合现有动画规范？
- [ ] 是否考虑了性能影响？
- [ ] 是否支持可访问性？

### 代码审查
- [ ] 使用了规范的时长和曲线
- [ ] AnimationController 正确 dispose
- [ ] 使用了 GPU 加速属性
- [ ] 添加了必要的注释

### 测试验证
- [ ] 在真机上测试流畅度
- [ ] 测试减少动画模式
- [ ] 测试快速交互场景
- [ ] 测试低端设备表现

---

## 参考资源

### 内部文档
- `lib/theme/app_theme.dart`
- `lib/theme/app_colors.dart`
- `lib/theme/app_motion.dart`
- [性能优化指南](../architecture/performance.md)

### 外部参考
- [Material Design Motion](https://m3.material.io/styles/motion/overview)
- [Flutter Animation Docs](https://docs.flutter.dev/ui/animations)
- [Human Interface Guidelines - Motion](https://developer.apple.com/design/human-interface-guidelines/motion)

---

## 版本历史

| 版本 | 日期 | 变更说明 |
|------|------|---------|
| 1.0.0 | 2026-05-07 | 初始版本，定义核心动画规范 |

---

## 维护者

- 设计负责人：待定
- 技术负责人：待定

如有疑问或建议，请在项目 Issue 中讨论。
