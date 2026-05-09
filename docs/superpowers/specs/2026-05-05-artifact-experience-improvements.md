# Artifact 体验优化设计

## 背景

当前项目的 `create_artifact` 工具已经实现了基本的 HTML/SVG artifact 创建和预览功能，但在实际使用中存在以下三个主要问题：

1. **设计风格不统一**：生成的 artifact UI 与主应用界面风格不一致，缺乏统一的设计系统
2. **流式更新体验差**：在流式 tool call 输出时，页面更新频率过高导致闪烁和位置跳变
3. **格式支持有限**：目前仅支持 HTML 和 SVG，缺少对 React 和 Three.js 等现代前端技术的支持

这些问题影响了用户体验和 artifact 的表达能力。

## 目标

本次优化的目标如下：

1. **建立统一的设计系统**
   - 参考 Claude Code 的 visualizer design system
   - 通过 CSS 变量实现主题继承
   - 提供设计规范指导模型生成符合风格的 artifact

2. **优化流式更新体验**
   - 实现防抖机制，减少更新频率
   - 避免 WebView 重建导致的闪烁
   - 提供流式状态的视觉反馈

3. **扩展格式支持**
   - 支持 React 组件（JSX）
   - 支持 Three.js 3D 可视化
   - 提供运行时和转译机制

## 非目标

本轮明确不做以下事情：

1. 不改变 artifact 的核心存储和执行模型
2. 不引入需要网络请求的外部依赖
3. 不支持需要构建步骤的复杂前端框架（如 Vue、Angular）
4. 不为 artifact 添加持久化的版本控制
5. 不改变 tool definition 的基本结构（保持向后兼容）

## 设计原则

### 1. 渐进增强，不破坏现有功能

所有改进都应该是向后兼容的，现有的 HTML/SVG artifact 应该继续正常工作。

### 2. 设计系统注入，不依赖模型记忆

设计规范应该通过 tool result 动态注入，而不是依赖模型训练数据或 tool description（因为 tool description 不可变）。

### 3. 客户端渲染，不依赖服务端

所有运行时（React、Three.js）都应该在 WebView 中通过 UMD 构建加载，不需要服务端支持。

### 4. 性能优先，避免过度渲染

流式更新应该平衡实时性和性能，避免每次数据到达都触发完整重渲染。

## 详细设计

### 任务 1：统一设计系统

#### 问题分析

当前 `create_artifact` 的 tool description 包含设计指南，但：
- Tool description 是静态的，无法根据当前主题（亮色/暗色）动态调整
- 缺少具体的 CSS 变量和工具类
- 模型生成的 artifact 风格与主应用不一致

参考 Claude Code 的 visualizer design system，其核心机制是：
1. 通过 CSS 变量继承宿主主题
2. 透明背景 + 无外框
3. 严格的排版约束（字号、字重、大小写）
4. Flat 美学（禁止渐变、阴影、模糊）
5. 9色语义化调色板

#### 解决方案

**方案 A：创建 `create_artifact:readme` 工具**

- 新增一个 `create_artifact:readme` 工具
- 在首次使用 `create_artifact` 前，模型必须先调用 `create_artifact:readme`
- 该工具返回当前主题的设计系统规范（CSS 变量、工具类、设计原则）
- 将可变部分（主题相关）放在 tool result 中，不可变部分保留在 tool description 中

**方案 B：自动注入设计系统**

- 在 `buildArtifactPreviewDocument` 中自动注入设计系统 CSS
- 根据当前主题（亮色/暗色）动态生成 CSS 变量
- 更新 tool description，引导模型使用预定义的 CSS 变量和工具类

**推荐方案：B（自动注入）**

理由：
- 更简单，不需要模型额外调用工具
- 保证所有 artifact 都有统一的设计系统
- 减少模型的认知负担

#### 实现要点

1. 创建 `ArtifactDesignSystem` 类
   - 生成 CSS 变量（颜色、字体、间距、圆角）
   - 生成工具类（.t, .ts, .c-purple, .bg-teal 等）
   - 根据 isDarkMode 动态调整颜色值

2. 更新 `buildArtifactPreviewDocument`
   - 在 `<head>` 中注入设计系统 CSS
   - 传入当前主题状态（isDarkMode）

3. 更新 tool description
   - 添加设计系统使用指南
   - 列出可用的 CSS 变量和工具类
   - 强调 flat 设计原则和禁止项

#### 待确认问题

1. 是否需要支持用户自定义主题色？
2. 是否需要在 artifact 详情页也应用相同的设计系统？
3. 9色调色板是否足够，是否需要扩展？

---

### 任务 2：优化流式更新体验

#### 问题分析

当前实现在 `artifact_preview_surface.dart` 的 `didUpdateWidget` 中：
- 每次 `source` 变化都会重建 `WebViewController`
- 没有防抖机制，流式输出时更新过于频繁
- WebView 重新加载会导致整个预览区域闪烁
- 列表位置会因为高度变化而跳变

#### 解决方案

**核心策略：防抖 + 增量更新**

1. **防抖机制**
   - 使用 `Timer` 实现防抖（建议 300-500ms）
   - 在流式输出期间延迟更新，避免每次数据到达都触发渲染
   - 在流式完成后立即应用最终版本

2. **增量更新**
   - 不重建 `WebViewController`，使用 `loadHtmlString` 更新内容
   - 保持 WebView 实例稳定，减少闪烁

3. **视觉反馈**
   - 在流式更新期间显示"更新中"指示器
   - 使用 `AnimatedContainer` 平滑过渡高度变化

4. **位置稳定**
   - 使用 `RepaintBoundary` 隔离重绘
   - 考虑使用 `SliverPersistentHeader` 固定位置（如果在列表中）

#### 实现要点

1. 在 `_ArtifactPreviewSurfaceState` 中添加：
   - `Timer? _debounceTimer` - 防抖定时器
   - `String? _pendingSource` - 待更新的源码
   - `String? _lastRenderedSource` - 上次渲染的源码

2. 修改 `didUpdateWidget`：
   - 检测 source 变化时启动防抖定时器
   - 不立即重建 controller

3. 添加 `_updateControllerContent` 方法：
   - 使用 `controller.loadHtmlString` 更新内容
   - 避免重建整个 controller

4. 添加流式状态指示器：
   - 在预览区域右上角显示"更新中"标签
   - 使用小型 `CircularProgressIndicator`

#### 待确认问题

1. 防抖延迟设置为多少合适？（建议 400ms）
2. 是否需要区分"首次加载"和"流式更新"的行为？
3. 是否需要提供"暂停流式更新"的选项？

---

### 任务 3：扩展格式支持（React 和 Three.js）

#### 问题分析

当前 `ArtifactType` 只有 `html` 和 `svg`，限制了表达能力：
- 无法使用 React 组件化开发
- 无法创建 3D 可视化
- 模型需要手写大量 vanilla JS 代码

#### 解决方案

**方案 A：添加 `react` 和 `threejs` 类型**

- 扩展 `ArtifactType` 枚举：`html`, `svg`, `react`, `threejs`
- 在 WebView 中注入 React 和 Three.js 运行时（UMD 构建）
- 提供 JSX 转译（使用 Babel standalone）

**方案 B：保持 `html` 类型，通过约定支持 React/Three.js**

- 不修改 `ArtifactType` 枚举
- 在 `buildArtifactPreviewDocument` 中检测源码特征
- 如果检测到 JSX 或 Three.js 代码，自动注入相应运行时

**推荐方案：A（显式类型）**

理由：
- 更清晰，模型明确知道要生成什么类型的代码
- 可以针对不同类型提供不同的模板和约束
- 便于后续扩展其他类型

#### 实现要点

1. **扩展 `ArtifactType`**
   ```dart
   enum ArtifactType {
     html,
     svg,
     react,
     threejs,
   }
   ```

2. **注入 React 运行时**
   - 使用 React UMD 构建（react.production.min.js + react-dom.production.min.js）
   - 使用 Babel standalone 转译 JSX
   - 提供 `ReactDOM.render` 入口

3. **注入 Three.js 运行时**
   - 使用 Three.js UMD 构建（three.min.js）
   - 提供常用的 helpers（OrbitControls, GLTFLoader 等）

4. **更新 `buildArtifactPreviewDocument`**
   - 根据 `ArtifactType` 选择不同的模板
   - 注入相应的运行时库
   - 提供错误处理和降级方案

5. **更新 tool description**
   - 添加 `react` 和 `threejs` 类型说明
   - 提供示例代码
   - 说明约束和限制

#### React 模板示例

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <script crossorigin src="https://unpkg.com/react@18/umd/react.production.min.js"></script>
  <script crossorigin src="https://unpkg.com/react-dom@18/umd/react-dom.production.min.js"></script>
  <script src="https://unpkg.com/@babel/standalone/babel.min.js"></script>
  <!-- Design system CSS -->
</head>
<body>
  <div id="root"></div>
  <script type="text/babel">
    // User's React code here
  </script>
</body>
</html>
```

#### Three.js 模板示例

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <script src="https://unpkg.com/three@0.150.0/build/three.min.js"></script>
  <!-- Design system CSS -->
</head>
<body>
  <div id="canvas-container"></div>
  <script>
    // User's Three.js code here
  </script>
</body>
</html>
```

#### 待确认问题

1. 是否允许从 CDN 加载运行时？（需要修改 CSP）
2. 是否需要将运行时库打包到 assets 中？（增加包体积）
3. 是否需要支持 TypeScript？（需要更复杂的转译）
4. Three.js 需要支持哪些扩展？（OrbitControls, GLTFLoader, etc.）
5. 是否需要限制 React 版本？（建议使用 React 18）

---

## 实现优先级

建议按以下顺序实现：

1. **任务 2：优化流式更新体验**（最紧急，影响当前使用）
   - 实现防抖机制
   - 添加流式状态指示器
   - 优化渲染性能

2. **任务 1：统一设计系统**（中等优先级，提升视觉一致性）
   - 创建 `ArtifactDesignSystem` 类
   - 更新 `buildArtifactPreviewDocument`
   - 更新 tool description

3. **任务 3：扩展格式支持**（低优先级，增强表达能力）
   - 扩展 `ArtifactType` 枚举
   - 实现 React 支持
   - 实现 Three.js 支持

## 风险和挑战

1. **CSP 限制**：当前 CSP 策略禁止外部脚本，需要调整以支持 CDN 或使用本地资源
2. **包体积**：打包 React 和 Three.js 会显著增加应用体积
3. **性能**：Babel 转译和 React 渲染可能影响性能，需要测试
4. **兼容性**：不同版本的 React/Three.js 可能有 API 差异
5. **安全性**：执行用户生成的 JSX 代码存在安全风险，需要沙箱隔离

## 后续工作

1. 添加 artifact 编辑功能（在详情页直接编辑源码）
2. 支持 artifact 导出（下载为 HTML 文件）
3. 支持 artifact 分享（生成分享链接）
4. 添加 artifact 模板库（常用图表、组件等）
5. 支持更多格式（Mermaid、D3.js、Chart.js 等）
