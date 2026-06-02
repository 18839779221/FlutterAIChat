# Agent 文件访问沙盒统一设计

## 摘要

当前项目内已经存在多条并行的文件访问路径：

- 文件工具通过平台私有 app sandbox 下的 `agent` 目录访问自己的沙盒内容。
- artifact 当前通过独立平台私有目录读写。
- skills 当前通过独立平台私有目录读写。
- attachments 在导入后持有 app 内部真实路径，在导入前还会短暂持有外部真实路径。
- 少量调试与投影逻辑直接依赖宿主真实路径。

这些路径并不共享统一的路径语义、目录布局和可见性规则，结果是：

- agent 看到的路径模型不一致。
- 真实宿主路径容易渗透进 transcript、tool result 和 skill context。
- `LS/Grep/Glob/Read/Edit/Write` 这套 file-native 工具心智只覆盖了部分子系统。
- 各模块都在自行拼接 root，文件访问边界分散。

本次设计不引入新的上层抽象语法，不要求 agent 学习 namespace 或 URI。目标是保留 file-native 使用体验，同时把底层文件访问逻辑彻底收口。

## 设计目标

### 产品目标

- agent 看到的是一套统一、连续、可导航的内部文件系统。
- `LS/Grep/Glob/Read/Edit/Write` 保持原生文件工具体验，不因治理改造变得笨重。
- agent 能同时使用“沙盒绝对路径”和“相对路径”。
- 真实宿主路径不再进入 agent 可见上下文。

### 架构目标

- 所有内部持久化文件统一收敛到单一物理 root。
- 所有模块通过统一路径解析层访问文件，不再各自拼接 root。
- 路径解析同时产出 agent 视角路径和 host 视角真实路径，并严格区分二者。
- 可见性、可写性、导入来源等规则在统一访问层集中治理。

## 非目标

本阶段不包含：

- 宿主机真实文件系统直接暴露给 agent。
- 新增 `sandbox://`、`skill://` 之类对 agent 显式可见的新协议。
- 保留旧目录、旧数据、旧字段的兼容层。
- 把文件访问完全对象化为 `fileId` 风格仓储接口。
- 对 `LS/Grep/Glob` 增加非文件式语义。

## 核心决策

### 1. 保持 file-native，而不是引入显式 namespace 协议

agent 和大多数业务层继续使用普通文件路径，而不是 `sandbox://...` 形式的新语法。

原因：

- `LS/Grep/Glob/Read/Edit/Write` 的核心价值就是“像真实项目目录一样工作”。
- 强推 namespace 或 URI 会损伤路径直觉，降低多步工具调用的自然性。
- 当前项目更需要统一解析和隔离规则，而不是新的上层抽象。

因此，治理逻辑只存在于底层解析层，不变成上层显式概念。

### 2. agent 视角拥有自己的根目录 `/`

agent 看到的不是宿主机文件系统，而是一套独立的沙盒文件系统。

在这套文件系统里：

- `/` 表示沙盒根。
- `/artifacts/42/homepage.html` 是 agent 绝对路径。
- `artifacts/42/homepage.html`、`./foo.md`、`../tmp/a.txt` 是相对路径。
- `.`、`..`、重复 `/`、相对当前目录这些 shell 风格路径语义全部成立。

这让 agent 同时拥有绝对路径和相对路径的心智模型，且两者都只作用于沙盒内部。

### 3. 单一物理 root

所有内部持久化内容统一放到：

```text
<platform app-private root>/agent
```

这里的 `<platform app-private root>` 是平台相关的宿主私有目录：

- Android 下是应用私有存储目录。
- iOS / macOS 下通常由 `getApplicationSupportDirectory()` 一类平台目录提供。
- Windows / Linux 等桌面平台也应映射到各自的 app-private 数据目录。

也就是说，跨端统一的是“平台私有目录下的 `agent` root”，不是某个具体平台路径名。

统一后的目录布局：

```text
agent/
  artifacts/
  skills/
    installed/
  attachments/
    persisted/
    thumbs/
  memories/
  tmp/
```

此后：

- artifact 不再使用独立 `inline_artifacts` root。
- skills 不再使用独立 `skills` root。
- attachments 不再在持久化后保留独立真实路径根。
- 文件工具、调试页、skill 运行时、artifact 读写都基于同一物理沙盒。

### 4. 真实宿主路径只允许存在于最底层

系统内存在两类“绝对路径”：

1. `agent absolute path`
   例如 `/artifacts/42/homepage.html`
2. `host absolute path`
   例如 Android 下的 `.../files/agent/artifacts/42/homepage.html`
   或 Apple 平台下的 `.../Application Support/agent/artifacts/42/homepage.html`

前者可以进入 tool argument、tool result、planner context、UI 调试展示。  
后者只能存在于最底层文件系统访问实现，不能进入：

- transcript
- tool result projection
- planner-visible context
- skill invoked context
- 持久化给 agent 使用的业务字段

## 文件系统模型

### Agent 路径语义

统一支持以下路径类型：

- 绝对路径：`/artifacts/42/homepage.html`
- 相对路径：`artifacts/42/homepage.html`
- 当前目录路径：`./draft.md`
- 父目录路径：`../tmp/cache.json`

统一归一化规则：

- `////artifacts//42///a.html` 归一化为 `/artifacts/42/a.html`
- `/artifacts/42/../43/a.html` 归一化为 `/artifacts/43/a.html`
- 相对路径基于显式传入的当前工作目录解析
- 任何归一化结果都不得逃出沙盒根 `/`

### Host 路径语义

统一访问层将 agent 路径映射到：

```text
<platform app-private root>/agent + normalized_relative_path
```

示例：

- agent 路径 `/artifacts/42/homepage.html`
- host 路径 `.../agent/artifacts/42/homepage.html`

agent 不感知这条映射，只感知自己的沙盒文件树。

## 统一访问层设计

### 总体职责

新增统一访问层，负责：

- 接受 agent 绝对路径或相对路径
- 结合当前工作目录做路径归一化
- 输出稳定的 agent 绝对路径
- 输出对应的 host 真实路径
- 校验是否逃出沙盒根
- 根据路径前缀应用可见性、可写性和来源规则

这层的本质不是“显式 namespace 系统”，而是“单一沙盒下的统一路径解析与访问策略层”。

### 建议接口

建议统一访问层至少提供以下能力：

- `resolvePath(rawPath, cwd)`
  - 输入 agent 绝对路径或相对路径
  - 输出归一化后的 agent 绝对路径与 host 真实路径
- `resolveFile(rawPath, cwd)`
  - 基于统一解析结果返回文件访问对象
- `resolveDirectory(rawPath, cwd)`
  - 基于统一解析结果返回目录访问对象
- `ensureDirectory(agentAbsolutePath)`
  - 确保沙盒内部目录存在
- `list/read/write/edit/glob/grep`
  - 对文件工具常用行为提供共享实现或共享底层能力

### 内部前缀规则

虽然上层不显式使用 namespace，但底层仍需要对路径前缀做集中治理：

- `/artifacts/...`
- `/skills/...`
- `/attachments/...`
- `/memories/...`
- `/tmp/...`

这些前缀规则用于：

- 约束默认读写能力
- 限制哪些路径允许进入 agent 上下文
- 区分 internal 文件与 external 导入来源
- 为调试和工具执行提供统一语义

前缀规则只属于实现细节，不构成新的 agent 协议。

## 目录与模块案例

### 案例 1：agent 读取 artifact

agent 执行：

```text
Read /artifacts/42/homepage.html
```

流程：

1. 统一访问层把 `/artifacts/42/homepage.html` 解析为 agent 绝对路径。
2. 解析层映射出平台私有目录下的 host 路径，例如 `.../agent/artifacts/42/homepage.html`。
3. 读取文件内容。
4. 返回给 agent 的仍然是 `/artifacts/42/homepage.html` 与文件内容。

agent 从始至终都不会知道宿主真实路径。

### 案例 2：skill 加载

skill 文件位于：

```text
/skills/installed/flutter-ui-review/SKILL.md
```

skill 运行时可以从统一访问层读取该文件，但投影到 agent 上下文时，只暴露：

- skill id
- agent 路径 `/skills/installed/flutter-ui-review/SKILL.md`
- 指令正文

不再暴露：

- `baseDirectory` 的宿主真实路径
- `qualifiedPath` 的宿主真实路径
- 任何绝对宿主目录信息

### 案例 3：用户导入附件

用户从系统选择器导入图片时，系统可能短暂给出外部真实路径，例如：

```text
/private/var/mobile/.../DCIM/IMG_001.png
```

该路径只允许存在于导入瞬间。

后续流程必须是：

1. 导入服务读取外部真实路径。
2. 复制到内部沙盒 `/attachments/persisted/<id>.png`。
3. 缩略图写入 `/attachments/thumbs/<id>.png`。
4. 业务层、数据库、agent 可见字段只再持有内部 agent 路径。

也就是说，外部真实路径不进入长期数据模型。

### 案例 4：调试页查看 artifact

调试页不再自己拼接某个平台上的真实 artifact 根目录。

而是通过统一访问层：

1. 枚举 `/artifacts`
2. 读取某个 `/artifacts/...` 文件
3. 在 UI 中继续使用 agent 路径标识内容来源

这样调试页与文件工具、artifact runtime 使用同一套文件世界观。

## 可见性与写入策略

统一访问层需要对不同路径前缀定义默认策略。

建议首版规则：

- `/artifacts`
  - agent 可见
  - 可读可写
- `/memories`
  - agent 可见
  - 可读可写
- `/tmp`
  - agent 可见
  - 可读可写
- `/skills`
  - agent 可见
  - 默认只读
- `/attachments`
  - agent 可见
  - 默认只读

原因：

- `artifacts/memories/tmp` 是典型工作区目录，应保留 agent 读写能力。
- `skills` 属于已安装指令资源，默认不应让 agent 任意改写。
- `attachments` 是已导入素材，默认不应让 agent 覆盖原图和缩略图。

这些策略不改变 file-native 心智，只在底层执行时起作用。

## 现有字段调整方向

当前部分字段混合了 agent 路径和 host 路径语义，需要收敛。

### 应保留为 agent 路径语义的字段

- artifact `sourcePath`
- file tool `filePath`
- 调试展示中的 path

这些字段应统一保存为 agent 路径，且推荐统一为以 `/` 开头的 agent 绝对路径。

### 应改造成 host-only 的字段

- skill `qualifiedPath`
- skill `baseDirectory`
- attachment `localPath`
- attachment `thumbnailPath`

这些字段当前要么直接是宿主真实路径，要么默认承载真实路径语义。

改造方向：

- 对 agent 可见链路，替换为 agent 路径。
- 对纯宿主层内部流程，如图片解码、文件复制、预览渲染，可在访问层局部解析出 host 路径。

### 外部来源字段

导入瞬间的外部真实路径不应进入长期业务模型。  
如果确实需要记录来源，只能以 host-only、非 agent 可见的临时导入上下文存在。

## 对文件工具的影响

本设计明确要求：

- `LS/Grep/Glob/Read/Edit/Write` 继续保持 file-native。
- 参数继续是普通路径字符串。
- 路径既可以是绝对路径，也可以是相对路径。
- 不引入新的 URI、namespace 声明或对象式文件 id。

因此，文件工具的用户体验应增强而不是退化：

- 绝对路径更稳定，适合多步链路。
- 相对路径保留 shell 风格灵活性。
- 所有内部文件都处于同一文件树下，跨模块搜索更自然。

## 风险

### 风险 1：字段语义重写范围较大

artifact、skills、attachments、tool result、debug page 都涉及路径字段，需要统一改写。

缓解方式：

- 先统一底层解析层和单一物理 root
- 再逐模块替换字段语义
- 最后封锁真实路径外泄点

### 风险 2：相对路径解析引入当前目录状态

一旦支持相对路径，`cwd` 语义必须稳定，否则多步工具调用可能出现歧义。

缓解方式：

- 首版默认 `cwd = /`
- 所有执行链路显式传入 `cwd`
- tool result 展示优先使用 agent 绝对路径

### 风险 3：附件链路容易残留外部真实路径

附件导入天然从宿主外部文件开始，最容易留下真实路径残余。

缓解方式：

- 导入完成后立即转换为内部 agent 路径
- UI 展示、数据库持久化、provider payload 统一消费内部路径
- 外部真实路径只保留在导入函数的局部上下文

## 验收标准

完成后应满足：

1. 项目内部只保留一个文件沙盒 root：平台私有 app sandbox 下的 `agent` 目录。
2. artifact、skills、attachments、memories、tmp 全部收进该 root。
3. `Read/Write/Edit/LS/Glob/Grep` 接受 agent 绝对路径和相对路径。
4. agent 看到的绝对路径一律是沙盒绝对路径 `/...`，不是宿主绝对路径。
5. transcript、tool result、planner context、skill context 中不再出现宿主真实路径。
6. attachments 导入后不再长期保存外部真实路径。
7. 调试页和业务服务不再各自拼接独立 root，而是走统一访问层。

## 推荐后续实施顺序

1. 建立单一物理 root 和统一路径解析层。
2. 统一文件工具路径模型，补绝对路径与相对路径解析。
3. 迁移 artifact、skills、attachments 到统一 root。
4. 改写相关字段语义，统一为 agent 路径或 host-only 路径。
5. 清理 tool result、skill context、debug 页面中的真实路径外泄。
6. 最后补齐读写权限、路径归一化和跨模块回归测试。
