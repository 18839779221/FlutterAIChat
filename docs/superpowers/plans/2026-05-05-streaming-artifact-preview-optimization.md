# 优化流式 Artifact 预览更新体验 - 实现计划

## 概述

本计划用于实现流式 artifact 预览的防抖优化，消除闪烁和位置跳变问题。

**设计文档**：`docs/superpowers/specs/2026-05-05-streaming-artifact-preview-optimization.md`

## 实现步骤

### 步骤 1：添加防抖相关常量和状态字段

**文件**：`lib/widgets/chat_blocks/artifact_preview_surface.dart`

**操作**：
1. 在文件顶部添加防抖延迟常量：
   ```dart
   const Duration _streamingDebounceDelay = Duration(seconds: 1);
   ```

2. 在 `_ArtifactPreviewSurfaceState` 类中添加状态字段：
   ```dart
   Timer? _debounceTimer;
   String? _pendingSource;
   String? _lastRenderedSource;
   ```

3. 在 `initState` 中初始化 `_lastRenderedSource`：
   ```dart
   _lastRenderedSource = widget.source;
   ```

**验证**：代码编译通过，无语法错误。

---

### 步骤 2：实现防抖逻辑

**文件**：`lib/widgets/chat_blocks/artifact_preview_surface.dart`

**操作**：
1. 修改 `didUpdateWidget` 方法，实现防抖逻辑
2. 区分 stale 状态变化（立即处理）和 source 变化（防抖处理）
3. 在防抖回调中检查 `mounted` 状态和 source 是否真正变化

**关键代码**：
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

    _debounceTimer = Timer(_streamingDebounceDelay, () {
      if (!mounted || _pendingSource == null) return;

      final newSource = _pendingSource!;
      _pendingSource = null;

      if (newSource == _lastRenderedSource) return;

      _lastRenderedSource = newSource;

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

**验证**：
- 流式输出时，更新频率降低到每秒 1 次
- stale 状态变化时立即响应

---

### 步骤 3：实现增量更新方法

**文件**：`lib/widgets/chat_blocks/artifact_preview_surface.dart`

**操作**：
1. 添加 `_updateControllerContent` 方法
2. 使用 `controller.loadHtmlString` 更新内容
3. 重置高度状态，等待新的高度回调
4. 处理错误情况

**关键代码**：
```dart
void _updateControllerContent(String source) {
  final controller = _controller;
  if (controller == null) return;

  try {
    controller.loadHtmlString(buildArtifactPreviewDocument(source));
    
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

**验证**：
- WebView 内容更新，不重建 controller
- 没有闪烁现象

---

### 步骤 4：添加流式更新指示器

**文件**：`lib/widgets/chat_blocks/artifact_preview_surface.dart`

**操作**：
1. 修改 `build` 方法，添加 `isUpdating` 判断
2. 使用 `Stack` 在预览区域右上角叠加指示器
3. 实现 `_buildStreamingIndicator` 方法

**关键代码**：
```dart
@override
Widget build(BuildContext context) {
  final source = widget.source;
  
  // ... 现有的错误处理逻辑 ...
  
  if (_controller == null) {
    return _buildSourceFallback(context, source);
  }

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

**验证**：
- 流式更新时显示"更新中"指示器
- 更新完成后指示器消失
- 指示器样式符合设计规范

---

### 步骤 5：添加资源清理

**文件**：`lib/widgets/chat_blocks/artifact_preview_surface.dart`

**操作**：
1. 添加 `dispose` 方法
2. 取消防抖定时器

**关键代码**：
```dart
@override
void dispose() {
  _debounceTimer?.cancel();
  super.dispose();
}
```

**验证**：
- Widget 销毁时定时器被正确取消
- 没有内存泄漏

---

### 步骤 6：添加 dart:async 导入

**文件**：`lib/widgets/chat_blocks/artifact_preview_surface.dart`

**操作**：
1. 在文件顶部添加 `import 'dart:async';`

**验证**：代码编译通过。

---

## 测试计划

### 单元测试

**文件**：`test/widgets/chat_blocks/artifact_preview_surface_test.dart`

**测试用例**：
1. 测试防抖逻辑
   - 快速连续更新 source，验证只触发一次更新
   - 验证防抖延迟为 1 秒

2. 测试状态转换
   - 测试 stale 状态变化立即响应
   - 测试 source 变化触发防抖

3. 测试资源清理
   - 测试 dispose 取消定时器
   - 测试 widget 销毁时不会崩溃

### Widget 测试

**测试用例**：
1. 测试指示器显示/隐藏
   - 流式更新时显示指示器
   - 更新完成后隐藏指示器

2. 测试高度变化动画
   - 验证 AnimatedContainer 平滑过渡

3. 测试错误处理
   - 测试 source 为空的情况
   - 测试 controller 为 null 的情况

### 集成测试

**测试场景**：
1. 流式输出场景
   - 创建一个 artifact，模拟流式输出
   - 验证更新频率降低
   - 验证没有闪烁

2. 快速切换场景
   - 快速切换不同的 artifact
   - 验证没有内容错乱

3. Stale 状态变化
   - 将 artifact 标记为 stale
   - 验证立即显示 stale 提示

### 手动测试

**测试步骤**：
1. 在真机上运行应用
2. 创建一个复杂的 HTML artifact
3. 观察流式输出过程
4. 检查：
   - 是否还有闪烁
   - 更新频率是否降低
   - 指示器是否正常显示
   - 列表位置是否稳定
   - 性能和电量消耗

---

## 关键文件

- `lib/widgets/chat_blocks/artifact_preview_surface.dart` - 主要修改文件
- `test/widgets/chat_blocks/artifact_preview_surface_test.dart` - 测试文件（可能需要创建）

---

## 依赖关系

无新增依赖，使用现有的：
- `dart:async` - Timer
- `package:flutter/material.dart` - UI 组件
- `package:webview_flutter/webview_flutter.dart` - WebView

---

## 风险缓解

1. **WebView 兼容性**
   - 在 iOS 和 Android 上分别测试
   - 如果有问题，添加平台特定处理

2. **高度计算延迟**
   - 重置为默认高度，等待新的高度回调
   - 使用 AnimatedContainer 平滑过渡

3. **内存泄漏**
   - 在 dispose 中清理定时器
   - 在回调中检查 mounted 状态

---

## 完成标准

- [ ] 所有代码修改完成
- [ ] 代码编译通过，无警告
- [ ] 单元测试通过
- [ ] Widget 测试通过
- [ ] 集成测试通过
- [ ] 手动测试验证体验改善
- [ ] 代码审查通过
- [ ] 文档更新（如需要）

---

## 预估工作量

- 代码实现：1-2 小时
- 测试编写：1-2 小时
- 手动测试和调优：1 小时
- 总计：3-5 小时

---

## 后续工作

完成本次优化后，可以考虑：
1. 自适应防抖延迟（根据更新频率动态调整）
2. 预测性加载（在防抖期间预加载内容）
3. 差异化更新（只更新变化的部分）
4. 用户控制（提供"暂停更新"按钮）
