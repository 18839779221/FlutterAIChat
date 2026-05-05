# 优化流式 Artifact 预览更新体验 - 设计文档

## 背景

当前 `create_artifact` 工具在流式输出时存在严重的体验问题：

### 当前实现分析

在 `lib/widgets/chat_blocks/artifact_preview_surface.dart` 中：

```dart
@override
void didUpdateWidget(covariant ArtifactPreviewSurface oldWidget) {
  super.didUpdateWidget(oldWidget);
  if (oldWidget.source != widget.source ||
      oldWidget.isStale != widget.isStale) {
    _errorText = null;
    _previewHeight = _defaultArtifactPreviewHeight;
    _isPreviewTruncated = false;
    _controller = _createController();  // 每次都重建 WebViewController
  }
}
```

### 问题表现

1. **更新频率过高**：流式输出时，每次 `source` 变化都会触发 `didUpdateWidget`，导致每秒可能更新数十次
2. **WebView 重建**：每次更新都会重建 `WebViewController`，导致整个预览区域闪烁
3. **列表位置跳变**：高度频繁变化导致聊天列表位置不稳定
4. **性能问题**：频繁的 WebView 重建消耗大量资源

### 用户体验影响

- 预览区域持续闪烁，无法看清内容
- 列表滚动位置不断跳动，阅读体验极差
- 设备发热，电量消耗快
- 用户无法判断是否还在生成中

## 目标

1. **减少更新频率**：通过防抖机制，将更新频率降低到每秒 1 次
2. **消除闪烁**：使用增量更新而不是重建 WebViewController
3. **稳定位置**：平滑过渡高度变化，避免列表跳动
4. **提供反馈**：显示"更新中"指示器，让用户知道还在生成

## 非目标

1. 不改变 artifact 的数据流和状态管理
2. 不修改 `RuntimeArtifactPreviewParser` 的解析逻辑
3. 不改变 `StableArtifactBlock` 的缓存机制
4. 不影响非流式场景（如历史 artifact 的加载）

## 设计原则

### 1. 防抖优先，保证实时性

使用 1 秒防抖延迟，在流式输出期间减少更新频率，同时保证用户能看到进度。

### 2. 增量更新，避免重建

使用 `WebViewController.loadHtmlString()` 更新内容，而不是重建整个 controller。

### 3. 视觉反馈，消除焦虑

在流式更新期间显示"更新中"指示器，让用户知道系统正在工作。

### 4. 平滑过渡，稳定位置

使用 `AnimatedContainer` 平滑过渡高度变化，配合 `RepaintBoundary` 隔离重绘。

## 详细设计

### 1. 状态管理

在 `_ArtifactPreviewSurfaceState` 中添加以下状态：

```dart
class _ArtifactPreviewSurfaceState extends State<ArtifactPreviewSurface> {
  WebViewController? _controller;
  String? _errorText;
  double _previewHeight = _defaultArtifactPreviewHeight;
  bool _isPreviewTruncated = false;
  
  // 新增状态
  Timer? _debounceTimer;           // 防抖定时器
  String? _pendingSource;          // 待更新的源码
  String? _lastRenderedSource;     // 上次渲染的源码
  
  // ...
}
```

### 2. 防抖逻辑

修改 `didUpdateWidget` 实现防抖：

```dart
@override
void didUpdateWidget(covariant ArtifactPreviewSurface oldWidget) {
  super.didUpdateWidget(oldWidget);

  // 处理 stale 状态变化（立即处理）
  if (oldWidget.isStale != widget.isStale && widget.isStale) {
    _debounceTimer?.cancel();
    _pendingSource = null;
    return;
  }

  // 如果 source 变化，启动防抖
  if (oldWidget.source != widget.source) {
    _pendingSource = widget.source;
    _debounceTimer?.cancel();

    // 1 秒后执行更新
    _debounceTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted || _pendingSource == null) return;

      final newSource = _pendingSource!;
      _pendingSource = null;

      // 只有真正变化时才更新
      if (newSource == _lastRenderedSource) return;

      _lastRenderedSource = newSource;

      // 尝试增量更新，失败则重建
      if (_controller != null && newSource.isNotEmpty) {
        _updateControllerContent(newSource);
      } else {
        setState(() {
          _errorText = null;
          _previewHeight = _defaultArtifactPreviewHeight;
          _isPreviewTruncated = false;
          _controller = _createController();
        });
      }
    });
  }
}
```

### 3. 增量更新

添加 `_updateControllerContent` 方法：

```dart
void _updateControllerContent(String source) {
  final controller = _controller;
  if (controller == null) return;

  try {
    // 使用 loadHtmlString 更新内容，不重建 controller
    controller.loadHtmlString(buildArtifactPreviewDocument(source));
    
    // 重置高度状态，等待新内容的高度回调
    if (mounted) {
      setState(() {
        _previewHeight = _defaultArtifactPreviewHeight;
        _isPreviewTruncated = false;
      });
    }
  } catch (error) {
    if (mounted) {
      setState(() {
        _errorText = '$error';
      });
    }
  }
}
```

### 4. 视觉反馈

在 `build` 方法中添加"更新中"指示器：

```dart
@override
Widget build(BuildContext context) {
  final source = widget.source;
  
  // ... 错误处理 ...
  
  if (_controller == null) {
    return _buildSourceFallback(context, source);
  }

  // 判断是否有待更新的内容
  final isUpdating = _pendingSource != null && _pendingSource != _lastRenderedSource;

  return ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              height: _previewHeight,
              color: Colors.transparent,
              child: RepaintBoundary(
                child: WebViewWidget(
                  controller: _controller!,
                ),
              ),
            ),
            // 流式更新指示器
            if (isUpdating)
              Positioned(
                top: 8,
                right: 8,
                child: _buildStreamingIndicator(context),
              ),
          ],
        ),
        if (_isPreviewTruncated) _buildTruncationMessage(context),
      ],
    ),
  );
}

Widget _buildStreamingIndicator(BuildContext context) {
  final theme = Theme.of(context);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.1),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              theme.colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '更新中',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}
```

### 5. 资源清理

在 `dispose` 中清理定时器：

```dart
@override
void dispose() {
  _debounceTimer?.cancel();
  super.dispose();
}
```

## 实现步骤

1. **添加状态字段**
   - `_debounceTimer`
   - `_pendingSource`
   - `_lastRenderedSource`

2. **修改 `didUpdateWidget`**
   - 实现防抖逻辑
   - 区分 stale 状态变化和 source 变化

3. **添加 `_updateControllerContent`**
   - 使用 `loadHtmlString` 增量更新
   - 处理错误情况

4. **修改 `build` 方法**
   - 添加 `isUpdating` 判断
   - 使用 `Stack` 叠加指示器

5. **添加 `_buildStreamingIndicator`**
   - 设计视觉样式
   - 使用主题色

6. **添加 `dispose`**
   - 清理定时器资源

## 边界情况处理

### 1. 快速切换 artifact

如果用户在防抖期间切换到另一个 artifact：
- `_debounceTimer` 会被取消
- 新的 artifact 会重新创建 controller
- 不会出现内容错乱

### 2. Widget 被销毁

如果 widget 在防抖期间被销毁：
- `dispose` 会取消定时器
- 定时器回调中检查 `mounted` 状态
- 不会出现内存泄漏

### 3. Source 为空或无效

如果 source 为空或无效：
- 跳过增量更新
- 显示错误信息或降级到 fallback

### 4. Stale 状态变化

如果 artifact 变为 stale：
- 立即取消防抖定时器
- 显示 stale 提示信息
- 不再接受更新

## 性能考虑

### 1. 防抖延迟

- **1 秒延迟**：在流式输出期间，最多每秒更新 1 次
- **减少重建**：避免每次数据到达都重建 WebView
- **节省资源**：减少 CPU 和内存消耗

### 2. 增量更新

- **保持 controller**：不重建 WebViewController
- **复用 JS channel**：高度回调机制保持不变
- **减少闪烁**：WebView 内容平滑过渡

### 3. 重绘隔离

- **RepaintBoundary**：隔离 WebView 的重绘
- **AnimatedContainer**：平滑过渡高度变化
- **减少影响**：不影响列表其他部分

## 测试计划

### 1. 单元测试

- 测试防抖逻辑
- 测试状态转换
- 测试资源清理

### 2. Widget 测试

- 测试指示器显示/隐藏
- 测试高度变化动画
- 测试错误处理

### 3. 集成测试

- 测试流式输出场景
- 测试快速切换场景
- 测试 stale 状态变化

### 4. 手动测试

- 在真机上测试流式输出
- 观察闪烁是否消除
- 检查性能和电量消耗

## 风险和挑战

### 1. WebView 兼容性

不同平台的 WebView 实现可能有差异，`loadHtmlString` 的行为可能不一致。

**缓解措施**：在 iOS 和 Android 上分别测试，如果有问题则针对平台特殊处理。

### 2. 高度计算延迟

增量更新后，高度回调可能有延迟，导致短暂的高度不准确。

**缓解措施**：重置为默认高度，等待新的高度回调。

### 3. 内存泄漏

定时器如果没有正确清理，可能导致内存泄漏。

**缓解措施**：在 `dispose` 中清理，在回调中检查 `mounted`。

## 后续优化

1. **自适应防抖延迟**：根据更新频率动态调整防抖延迟
2. **预测性加载**：在防抖期间预加载内容，减少延迟感
3. **差异化更新**：只更新变化的部分，而不是整个文档
4. **用户控制**：提供"暂停更新"按钮，让用户控制更新时机
