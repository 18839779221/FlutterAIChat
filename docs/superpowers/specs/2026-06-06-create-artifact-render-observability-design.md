# create_artifact 渲染观测与加载表现优化设计

## 1. 背景

当前 `create_artifact` 的 inline 预览已经具备以下基础能力：

- runtime preview 与 final artifact 已经明确分流
- runtime preview 会通过同一个 `WebViewController` 做增量 `apply`
- final artifact 会通过 hidden pending controller 做 takeover，避免直接白屏切换
- `ArtifactHeight` JavaScript channel 已经能把 WebView/DOM 高度回传到 Flutter
- 项目已经有 file log / trace 基建，以及 runtime-only 的 streaming trace overlay / inspector 入口

但就本轮要解决的问题来说，现状仍有两个明显不足：

1. 观测存在原始信号，但缺少“按一次 artifact 渲染生命周期聚合”的 session 语义  
   当前高度、source 更新、runtime apply 主要停留在 `ArtifactPreviewSurface` 本地状态与 `Logger.temp`。这不足以让后续自动化分析快速定位一场异常渲染。

2. 加载表现仍然过于“实现暴露”  
   当前存在 skeleton 式 placeholder 与右上角 `更新中` 角标，但它们仍偏开发态。对于 `create_artifact` 这种富内容 inline 卡片，用户真正感知到的是：
   - 有时流式渲染很久没有真正显示内容
   - 有时内容会出现高度冲高再回落
   - 有时 loading 状态与真实渲染节奏割裂

本轮重点不是马上修正所有跳变，而是先把渲染生命周期观测做完整、能自动识别关键异常，然后再替换 loading 表现，让后续优化建立在稳定证据之上。

## 2. 本轮目标

### 2.1 目标

1. 为每次 inline artifact 渲染建立稳定的 render session 语义
2. 把原始高度/渲染信号聚合为高信号 trace 事件与结束摘要
3. 自动识别两类关键异常：
   - 高度下降超过 `30px`
   - 整体流式加载时间超过 `3s`，且直到最后 `1s` 才首次成功渲染
4. 在不引入第二套日志体系的前提下，为后续人工与模型自动分析提供稳定入口
5. 用“静态承载面 + 45 度刀光 sweep overlay”替换当前 loading skeleton

### 2.2 非目标

本轮明确不做以下事情：

1. 不引入新的 transcript / ledger 持久化字段
2. 不在本轮就实现“防高度跳变”的 UI 修正策略
3. 不新增独立 observability 平台或第二套日志文件
4. 不泛化到所有 runtime preview 类型，本轮仅覆盖 `create_artifact`
5. 不要求 debug overlay 在本轮新增完整 artifact 专属可视化面板

## 3. 关键问题定义

### 3.1 异常一：高度异常回落

用户关注的不是“高度有没有波动”，而是“是否出现明显不符合预期的回落”。

本轮将该异常定义为：

- 在同一个 render session 内，若某次 `appliedHeight` 相比 `maxAppliedHeight` 下降超过 `30px`
- 即判定为异常

正式诊断码：

- `artifact_height_drop_over_30px`

### 3.2 异常二：直到最后才首次成功渲染

用户关注的不是 source 有没有持续增长，而是“UI 是否真的渐进显示过内容”。

本轮将该异常定义为：

- `totalStreamingDurationMs > 3000`
- 且 `firstSuccessfulRenderAtMs >= totalStreamingDurationMs - 1000`

正式诊断码：

- `artifact_first_render_in_final_second`

这里的 `firstSuccessfulRender` 不等于 source 增长，也不等于单次 JS apply 返回成功，而是一次更接近用户可见渲染的复合信号。定义见第 5 节。

## 4. 总体方案

### 4.1 方案概览

本轮引入一个很薄的 runtime-only 观测聚合层：

- `ArtifactRenderSessionRecorder`

它不负责控制 UI，不负责替代 `ArtifactPreviewSurface` 状态机，不进入 transcript truth，也不进入持久化 ledger。

它只负责三件事：

1. 给每次 artifact 渲染分配稳定的 `sessionId`
2. 汇聚 `ArtifactPreviewSurface` 已有与新增的渲染信号
3. 程序化判定异常，并输出高信号 `trace` 与 session 结束摘要

### 4.2 为什么不只在 widget 内局部打日志

仅在 `ArtifactPreviewSurface` 内部增加若干 `Logger.temp`，虽然改动小，但存在三个问题：

1. 缺少一场渲染的完整边界，很难回答“这场到底有没有异常”
2. 后续模型自动分析需要自己扫大量原始日志并推导 session，不稳定也不高效
3. 无法稳定形成 `session_done` 这种高信号摘要

因此，本轮需要把观测从“局部状态调试”提升到“session 级 trace 事件 + 摘要”。

## 5. Render Session 模型

### 5.1 session 标识

每次 inline artifact 渲染都建立一个稳定 `sessionId`。

建议组成字段：

- `turnId`
- `artifactId`
- `providerCallId`（若可得）
- `mountSeq`

`runtime` / `final` 不进入 `sessionId` 本体，而是作为每条事件的 `phase` 字段单独记录。

目标：

1. 让同一个 artifact 的 runtime 预览与 final takeover 能被串联分析
2. 避免单纯按 `artifactId` 聚合导致不同渲染实例互相污染

### 5.2 session 生命周期

一个 render session 的典型事件流为：

1. `session_started`
2. 多次 `source_progressed`
3. 多次 `runtime_apply_started` / `runtime_apply_completed`
4. 多次 `dom_commit`
5. 多次 `height_sampled`
6. 多次 `height_applied`
7. 可选 `final_controller_prepared`
8. 可选 `final_takeover`
9. `session_done`

### 5.3 为什么 session 只做 runtime-only

本轮观测数据用于：

- file log 排障
- 自动化诊断入口
- 后续高度模式归纳

它不承担业务真相，不参与恢复判断，不应写入 transcript / step ledger。

因此它必须继续留在 runtime-only / file log 侧。

## 6. 事件与字段设计

### 6.1 原始进度事件

#### `artifact.preview.session_started`

字段：

- `sessionId`
- `turnId`
- `artifactId`
- `providerCallId`
- `phase`
- `sourcePath`
- `isRuntimePreview`

#### `artifact.preview.source_progressed`

字段：

- `sessionId`
- `seq`
- `sourceLength`
- `deltaLength`

用途：

- 证明模型/tool arguments 的流式 source 确实在推进
- 为后续判断“流了很久但 UI 没显示”提供底层证据

#### `artifact.preview.runtime_apply_started`

字段：

- `sessionId`
- `seq`
- `sourceLength`
- `isControllerReady`

#### `artifact.preview.runtime_apply_completed`

字段：

- `sessionId`
- `seq`
- `sourceLength`
- `result`

#### `artifact.preview.dom_commit`

该事件由 WebView 注入脚本在一次有效 apply 后主动回传。

字段：

- `sessionId`
- `seq`
- `sourceLength`
- `artifactRectHeight`

用途：

- 区分“Flutter 已发起 apply”和“WebView/DOM 确实提交了新内容”

#### `artifact.preview.height_sampled`

字段：

- `sessionId`
- `seq`
- `rawHeight`
- `clampedHeight`
- `previousAppliedHeight`
- `artifactRectHeight`
- `bodyScrollHeight`
- `bodyOffsetHeight`
- `rootScrollHeight`
- `rootOffsetHeight`

说明：

- 该事件对应 JS channel 回传的原始高度测量
- 即使本轮尚未做跳变抑制，也要完整记录

#### `artifact.preview.height_applied`

字段：

- `sessionId`
- `seq`
- `appliedHeight`
- `maxAppliedHeight`
- `largestDropPx`
- `isPreviewTruncated`

#### `artifact.preview.final_controller_prepared`

字段：

- `sessionId`
- `sourceLength`

#### `artifact.preview.final_takeover`

字段：

- `sessionId`
- `sourceLength`

### 6.2 异常事件

#### `artifact.preview.anomaly`

这是正式 `trace`，不是 temp log。

字段：

- `sessionId`
- `diagnosticCode`
- `message`
- `phase`
- `artifactId`
- `providerCallId`
- `sourcePath`
- `details`

其中 `details` 按异常类型补充。

##### 高度回落异常

- `diagnosticCode=artifact_height_drop_over_30px`
- `details` 至少包含：
  - `maxAppliedHeight`
  - `currentAppliedHeight`
  - `largestDropPx`
  - `previousAppliedHeight`
  - `sourceLength`
  - `hasPendingFinalController`

##### 最后一秒才首次成功渲染异常

- `diagnosticCode=artifact_first_render_in_final_second`
- `details` 至少包含：
  - `totalStreamingDurationMs`
  - `firstSuccessfulRenderAtMs`
  - `tailWindowMs`
  - `sourceProgressCount`
  - `applyCount`
  - `domCommitCount`
  - `heightAppliedCount`

### 6.3 session 结束摘要

#### `artifact.preview.session_done`

该事件是模型与人工排障的主入口。

字段：

- `sessionId`
- `verdict`：`normal` / `anomalous`
- `anomalyCodes`
- `phaseSummary`
- `artifactId`
- `providerCallId`
- `sourcePath`
- `heightPattern`
- `maxAppliedHeight`
- `finalAppliedHeight`
- `largestDropPx`
- `heightSampleCount`
- `heightAppliedCount`
- `sourceProgressCount`
- `applyCount`
- `domCommitCount`
- `totalStreamingDurationMs`
- `firstSuccessfulRenderAtMs`
- `timeToFirstSuccessfulRenderMs`
- `tailWindowMs`

## 7. firstSuccessfulRender 定义

`firstSuccessfulRender` 必须尽量接近“用户真正看到内容”的时点，而不是内部某个中间信号。

本轮定义为：第一次满足以下条件的时刻

1. 至少发生一次 `runtime_apply_completed`
2. 至少发生一次 `dom_commit`
3. 且随后至少发生一次有效 `height_applied`

理由：

1. 单纯 `source_progressed` 只说明模型输出在前进，不代表 UI 变了
2. 单纯 `runtime_apply_completed` 只说明 Flutter 已请求 JS apply，不代表 DOM 已提交
3. `dom_commit + height_applied` 组合更接近“内容已经真实进入可见布局”

补充约束：

- `firstSuccessfulRender` 统计的是“本场 session 内首次成功显示内容”的时点，不区分 runtime 或 final
- 如果 runtime 阶段始终没有形成有效显示，而首次可见内容出现在 `final_takeover` 之后，则该时点仍计为 `firstSuccessfulRender`

## 8. 高度模式归类

本轮先做“观测归类”，不做修正策略。

每个 session 在结束时输出一个 `heightPattern`。首批分类如下：

1. `monotonic_growth`
   - 整体基本单调增长，无明显下降

2. `overshoot_then_drop`
   - 先达到较大高度，后续出现超过 `30px` 的明显回落

3. `sawtooth`
   - 存在多次上升/下降交替，不局限于一次冲高回落

4. `final_takeover_drop`
   - 明显下降主要出现在 `final_takeover` 前后

5. `no_height_signal`
   - 几乎没有有效高度信号，无法可靠判定渲染高度模式

分类优先级固定为：

1. `no_height_signal`
2. `final_takeover_drop`
3. `sawtooth`
4. `overshoot_then_drop`
5. `monotonic_growth`

说明：

- 若主要下降发生在 `final_takeover` 前后，则优先归到 `final_takeover_drop`
- 若存在多次明显上下交替，则优先归到 `sawtooth`
- 只有在不满足上述两类时，单次大幅回落才归到 `overshoot_then_drop`

这样后续分析不必直接从一串原始高度反推模式，而是先读摘要再决定是否展开证据。

## 9. 日志与自动化分析入口

### 9.1 不新增第二套日志系统

本轮完全沿用现有 `logs/app.log` 与 `Logger.trace` / `Logger.temp` 规范：

- session 原始进度事件可按价值分层落在 `trace` 或 `temp`
- 异常事件与 `session_done` 必须是正式 `trace`

不新增：

- `artifact.log`
- 独立 trace 文件
- 另一套 debug event 存储

### 9.2 自动化分析入口

后续人工或模型分析的最小闭环为两步：

1. 先搜高信号摘要  
   例如：
   - `artifact.preview.session_done verdict=anomalous`
   - `diagnosticCode=artifact_height_drop_over_30px`
   - `diagnosticCode=artifact_first_render_in_final_second`

2. 再按 `sessionId` 回拉该场次事件  
   仅展开：
   - `session_started`
   - `source_progressed`
   - `runtime_apply_started/completed`
   - `dom_commit`
   - `height_sampled`
   - `height_applied`
   - `final_controller_prepared`
   - `final_takeover`
   - `session_done`

关键原则：

- 异常识别必须程序化
- 模型只负责读取我们已经压缩好的“异常场次”与“同 session 证据”
- 不要求模型自己从大量原始日志中推导异常

## 10. Loading 表现优化

### 10.1 总原则

本轮新增 loading 动效后，当前 skeleton placeholder 应移除。

取而代之的是：

- 一个静态承载面
- 一个独立于 WebView 生命周期的 45 度刀光 sweep overlay
- 默认用户态不再同时依赖右上角 `更新中` 角标作为主 loading 表达

### 10.2 为什么不保留 skeleton

Skeleton line 会暗示并不存在的文本结构，这对 `create_artifact` 这种富内容 inline 卡片并不准确。

同时，skeleton 的视觉语言更像“列表加载”，而不是“一个可视化产物正在渐进生成”。

本轮改成静态壳层后：

- 不再伪造正文结构
- 让用户感知集中到“这张卡片正在生成/刷新”

### 10.3 Sweep overlay 约束

动效必须满足以下约束：

1. 在 Flutter 外层实现，而不是放进 HTML / WebView
2. 使用独立 `AnimationController.repeat`
3. 固定周期，不受 WebView 更新频率影响
4. 方向固定为从右上到左下的 `45°`
5. 仅在以下阶段显示：
   - `source` 尚未就绪
   - controller 尚未 ready
   - runtime update 进行中
   - final takeover 准备中

### 10.4 占位阶段表现

在首次成功渲染之前：

- 显示静态承载面
- 叠加 sweep overlay
- 不显示 skeleton lines

在首次成功渲染之后：

- 退掉静态承载面
- 保留真实 WebView 内容
- 当仍有流式更新时，可继续短暂显示 sweep overlay；但不再回退到 skeleton

## 11. 现有边界保持不变

本轮不改变以下架构边界：

1. runtime preview 与 final artifact 的分流结构不变
2. runtime preview 仍走同 controller 的 JS apply
3. final artifact 仍走 hidden pending controller takeover
4. `ChatTimelineProjectionService` 仍是 UI 汇聚层
5. 本轮观测仅挂在 `ArtifactPreviewSurface` 与其直接相关 runtime 路径，不上抬到 `TurnHarness`

## 12. 测试策略

### 12.1 重点

本轮重点验证：

1. 异常是否被正确识别
2. `session_done` 是否稳定输出完整摘要
3. loading 表现是否切换为“静态壳 + sweep overlay”

### 12.2 建议测试覆盖

#### 观测层

1. `artifact_height_drop_over_30px`
   - 构造一场 session：高度先增至较大值，再回落超过 `30px`
   - 断言异常被记录，且 `session_done.verdict == anomalous`

2. `artifact_first_render_in_final_second`
   - 构造一场总流时长超过 `3s`，且直到最后 `1s` 才首次满足 `firstSuccessfulRender`
   - 断言异常被记录，且摘要字段完整

3. `heightPattern` 分类
   - 至少覆盖：
     - `monotonic_growth`
     - `overshoot_then_drop`
     - `final_takeover_drop`
     - `no_height_signal`

4. `session_done` normal 路径
   - 无异常时输出 `verdict=normal`

#### Widget 层

1. 流式阶段不再显示旧 skeleton line 结构
2. 流式阶段显示 sweep overlay
3. 首次成功渲染后静态壳退场

### 12.3 本轮不要求

本轮不要求：

1. 精确到像素的视觉 golden 校验
2. Android/iOS 真机上对 sweep 运动轨迹做自动化验证
3. 直接在测试中量化“用户体感闪烁”

本轮先把观测正确性与状态切换测稳。

## 13. 实施顺序建议

1. 新增 `ArtifactRenderSessionRecorder` 与相应数据模型
2. 在 `ArtifactPreviewSurface` 里接入 session 生命周期与结构化事件采集
3. 为 WebView 注入 `dom_commit` 回传
4. 实现两类异常判定与 `session_done` 摘要
5. 去掉 skeleton placeholder，改为静态壳 + sweep overlay
6. 补齐单元测试与 widget 测试

## 14. 成功标准

本轮完成后，应满足：

1. 每次 `create_artifact` inline 渲染都能形成可检索的 `sessionId`
2. 异常场次可通过 `artifact.preview.session_done verdict=anomalous` 快速定位
3. 高度回落超过 `30px` 能被程序化识别
4. 流时长超过 `3s` 且直到最后 `1s` 才首次成功渲染能被程序化识别
5. loading skeleton 已移除，改为静态壳 + 固定频率刀光 overlay
6. 后续无论人工还是模型分析，都不需要从整份原始日志里手工推导“哪一场有问题”
