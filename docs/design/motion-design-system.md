# 动效设计系统 (Motion Design System)

## 设计哲学

FlutterAIChat 的动效设计遵循 **"自然流动"（Natural Flow）** 的核心理念，通过克制而有意义的动画提升用户体验，而非单纯的视觉装饰。

### 核心原则

#### 1. 功能性优先 (Functional First)
- 动画必须服务于功能理解和信息传达
- 避免纯装饰性动画，每个动效都应有明确目的
- 动画应帮助用户理解状态变化、层级关系和交互反馈

#### 2. 自然流动 (Natural Flow)
- 模拟物理世界的运动规律
- 使用缓动曲线而非线性动画
- 遵循惯性、重力、弹性等自然特性

#### 3. 性能至上 (Performance First)
- 优先使用 GPU 加速的属性（opacity, transform）
- 避免触发 layout 的动画（width, height 需谨慎）
- 控制同时运行的动画数量
- 大列表使用 `AnimatedList` 而非全量重建

#### 4. 一致性 (Consistency)
- 统一的时长规范
- 统一的缓动曲线
- 相同场景使用相同动画模式

#### 5. 可访问性 (Accessibility)
- 尊重系统的 `减少动画` 设置
- 提供禁用动画的选项
- 避免快速闪烁可能引发不适的动画

---

## 动画规范

### 时长规范 (Duration Scale)

```dart
// lib/theme/app_motion.dart
class AppMotion extends ThemeExtension<AppMotion> {
  /// 即时反馈 - 用于按钮按下、开关切换等即时响应
  final Duration instant;      // 100ms
  
  /// 快速过渡 - 用于小元素的显示/隐藏、颜色变化
  final Duration quick;        // 200ms
  
  /// 标准动画 - 用于大多数UI元素的过渡
  final Duration standard;     // 300ms
  
  /// 强调动画 - 用于需要引起注意的重要变化
  final Duration emphasized;   // 400ms
  
  /// 柔和动画 - 用于背景、大面积元素的缓慢变化
  final Duration gentle;       // 600ms
}
```

**使用指南：**

| 时长 | 适用场景 | 示例 |
|------|---------|------|
| `instant` (100ms) | 即时反馈 | 按钮按下、开关切换、Ripple效果 |
| `quick` (200ms) | 快速过渡 | 小图标显示/隐藏、颜色变化、小卡片翻转 |
| `standard` (300ms) | 标准动画 | 消息卡片出现、抽屉展开、对话框弹出 |
| `emphasized` (400ms) | 强调动画 | 页面转场、重要状态变化、大卡片展开 |
| `gentle` (600ms) | 柔和动画 | 背景渐变、大面积布局变化、氛围动画 |

---

### 缓动曲线规范 (Easing Curves)

```dart
class AppMotion extends ThemeExtension<AppMotion> {
  /// 标准进出 - 元素在屏幕内移动
  final Curve easeInOut;       // Curves.easeInOutCubic
  
  /// 元素进入 - 元素从外部进入屏幕
  final Curve easeOut;         // Curves.easeOutCubic
  
  /// 元素退出 - 元素从屏幕退出
  final Curve easeIn;          // Curves.easeInCubic
  
  /// 弹性效果 - 需要强调的交互反馈
  final Curve spring;          // Curves.elasticOut
  
  /// 柔和曲线 - 大面积、慢速的变化
  final Curve gentle;          // Curves.easeOutQuart
}
```

**曲线选择指南：**

```
easeOut (进入)
  ▲
  │     ╱─────
  │   ╱
  │ ╱
  └──────────▶
  快速启动，缓慢结束
  用于：元素进入、展开、显示

easeIn (退出)
  ▲
  │ ─────╲
  │       ╲
  │         ╲
  └──────────▶
  缓慢启动，快速结束
  用于：元素退出、收起、隐藏

easeInOut (移动)
  ▲
  │   ╱───╲
  │ ╱       ╲
  │╱         ╲
  └──────────▶
  两端缓慢，中间快速
  用于：元素在屏幕内移动、位置变化

spring (弹性)
  ▲
  │     ╱╲╱─
  │   ╱
  │ ╱
  └──────────▶
  带有回弹效果
  用于：按钮点击、重要提示、强调反馈
```

---

## 动画模式库

### 1. 渐入动画 (Fade In)

**用途**：元素首次出现、内容加载完成

**规范**：
- 时长：`standard` (300ms)
- 曲线：`easeOut`
- 透明度：0.0 → 1.0

```dart
FadeTransition(
  opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
    CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutCubic,
    ),
  ),
  child: child,
)
```

---

### 2. 滑动渐入 (Slide Fade In)

**用途**：列表项出现、消息卡片进入、页面内容加载

**规范**：
- 时长：`standard` (300ms) 或 `emphasized` (400ms)
- 曲线：`easeOut`
- 位移：Y轴 15% → 0%
- 透明度：0.0 → 1.0

```dart
// 组合动画
SlideTransition(
  position: Tween<Offset>(
    begin: const Offset(0, 0.15),
    end: Offset.zero,
  ).animate(
    CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutCubic,
    ),
  ),
  child: FadeTransition(
    opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: controller,
        curve: Curves.easeOutCubic,
      ),
    ),
    child: child,
  ),
)
```

**变体**：
- **从左滑入**：`Offset(-0.3, 0)` → `Offset.zero` - 用于侧边栏列表项
- **从右滑入**：`Offset(0.3, 0)` → `Offset.zero` - 用于用户消息气泡
- **从下滑入**：`Offset(0, 0.15)` → `Offset.zero` - 用于AI回复、工具卡片

---

### 3. 缩放动画 (Scale)

**用途**：按钮按下反馈、强调效果、模态弹出

**规范**：
- 时长：`instant` (100ms) 或 `quick` (200ms)
- 曲线：`easeOut`
- 缩放：1.0 → 0.92 → 1.0（按下）或 0.8 → 1.0（弹出）

```dart
// 按钮按下
AnimatedScale(
  scale: isPressed ? 0.92 : 1.0,
  duration: const Duration(milliseconds: 100),
  curve: Curves.easeOut,
  child: child,
)

// 模态弹出
ScaleTransition(
  scale: Tween<double>(begin: 0.8, end: 1.0).animate(
    CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutCubic,
    ),
  ),
  child: child,
)
```

---

### 4. 高度动画 (Elevation)

**用途**：输入框获得焦点、卡片悬停、强调状态

**规范**：
- 时长：`quick` (200ms)
- 曲线：`easeOut`
- 阴影模糊半径：20 → 32
- 阴影偏移：(0, 9) → (0, 12)
- 可选：轻微缩放 1.0 → 1.02

```dart
AnimatedContainer(
  duration: const Duration(milliseconds: 200),
  curve: Curves.easeOut,
  decoration: BoxDecoration(
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(isFocused ? 0.1 : 0.065),
        blurRadius: isFocused ? 32 : 20,
        offset: Offset(0, isFocused ? 12 : 9),
      ),
    ],
  ),
  child: child,
)
```

---

### 5. 展开/折叠动画 (Expand/Collapse)

**用途**：Reasoning区域、工具详情、FAQ手风琴

**规范**：
- 时长：`standard` (300ms)
- 曲线：`easeInOutCubic`
- 使用 `AnimatedSize` 或 `AnimatedCrossFade`

```dart
AnimatedSize(
  duration: const Duration(milliseconds: 300),
  curve: Curves.easeInOutCubic,
  alignment: Alignment.topCenter,
  child: isExpanded
      ? Column(children: expandedContent)
      : const SizedBox.shrink(),
)
```

**注意事项**：
- 避免在长列表中使用，可能导致性能问题
- 优先使用 `AnimatedSize` 而非手动计算高度
- 折叠时使用 `SizedBox.shrink()` 而非 `Container(height: 0)`

---

### 6. 错位动画 (Staggered)

**用途**：列表批量出现、侧边栏菜单项、卡片网格

**规范**：
- 基础时长：`standard` (300ms)
- 错位延迟：50ms/项（最多300ms）
- 曲线：`easeOut`

```dart
// 每个列表项
Future.delayed(Duration(milliseconds: index * 50), () {
  if (mounted) controller.forward();
});
```

**最佳实践**：
- 限制错位项数量（最多6-8项）
- 超过限制的项直接显示，避免等待过长
- 使用 `AnimatedList` 处理动态列表

---

### 7. 页面转场 (Page Transition)

**用途**：页面导航、路由切换

**规范**：
- 时长：`emphasized` (400ms)
- 曲线：`easeOutCubic`
- 效果：滑动 + 渐变

```dart
PageRouteBuilder(
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
)
```

---

### 8. 加载动画 (Loading)

**用途**：数据加载、AI思考、工具执行

**规范**：

#### 8.1 线性进度条
- 时长：循环 1500ms
- 曲线：`easeInOut`
- 高度：3px
- 位置：顶部或内容区域顶部

```dart
LinearProgressIndicator(
  minHeight: 3,
  backgroundColor: Colors.transparent,
  valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
)
```

#### 8.2 脉冲动画（工具执行中）
- 时长：循环 1200ms
- 曲线：`easeInOut`
- 透明度：0.4 → 1.0 → 0.4
- 缩放：1.0 → 1.05 → 1.0

```dart
// 已在 tool_running_effects.dart 中实现
PulsingDot(
  size: 8,
  color: workflowRunningColor,
)
```

#### 8.3 打字光标
- 时长：循环 800ms
- 曲线：`easeInOut`
- 透明度：0.2 → 1.0 → 0.2
- 尺寸：2x16px

```dart
FadeTransition(
  opacity: Tween<double>(begin: 0.2, end: 1.0).animate(
    CurvedAnimation(
      parent: controller,
      curve: Curves.easeInOut,
    ),
  ),
  child: Container(
    width: 2,
    height: 16,
    decoration: BoxDecoration(
      color: cursorColor,
      borderRadius: BorderRadius.circular(1),
    ),
  ),
)
```

---

### 9. 微交互动画 (Micro-interactions)

**用途**：按钮点击、开关切换、复选框勾选

**规范**：
- 时长：`instant` (100ms)
- 曲线：`easeOut` 或 `spring`
- 效果：缩放 + 颜色变化

```dart
// 按钮点击反馈
GestureDetector(
  onTapDown: (_) => setState(() => isPressed = true),
  onTapUp: (_) => setState(() => isPressed = false),
  onTapCancel: () => setState(() => isPressed = false),
  child: AnimatedScale(
    scale: isPressed ? 0.92 : 1.0,
    duration: const Duration(milliseconds: 100),
    curve: Curves.easeOut,
    child: child,
  ),
)
```

---

### 10. 氛围动画 (Ambient)

**用途**：背景渐变、空状态浮动、装饰性元素

**规范**：
- 时长：`gentle` (600ms) 或更长（2-10秒）
- 曲线：`easeInOut`
- 幅度：微妙（位移 ±4px，透明度 ±0.1）

```dart
// 浮动动画
AnimatedBuilder(
  animation: controller,
  builder: (context, child) {
    return Transform.translate(
      offset: Offset(0, sin(controller.value * 2 * pi) * 4),
      child: child,
    );
  },
  child: child,
)
```

**注意事项**：
- 氛围动画应极其克制，避免分散注意力
- 仅在空状态、引导页等非核心交互场景使用
- 提供禁用选项

---

## 性能优化指南

### GPU 加速属性（推荐）
✅ **优先使用**：
- `opacity` - 透明度
- `transform` - 位移、旋转、缩放
- `decoration.color` - 颜色变化

### 触发重排属性（谨慎使用）
⚠️ **需要优化**：
- `width` / `height` - 使用 `AnimatedSize` 包装
- `padding` / `margin` - 使用 `AnimatedPadding`
- `alignment` - 使用 `AnimatedAlign`

### 性能检查清单
- [ ] 避免在 `build` 方法中创建 `AnimationController`
- [ ] 使用 `const` 构造函数
- [ ] 大列表使用 `AnimatedList` 而非 `ListView` 全量重建
- [ ] 限制同时运行的动画数量（建议 ≤ 3个复杂动画）
- [ ] 使用 `RepaintBoundary` 隔离动画区域
- [ ] 动画完成后及时 `dispose` controller

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
- [主题系统](../theme/README.md)
- [组件库](../components/README.md)
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
