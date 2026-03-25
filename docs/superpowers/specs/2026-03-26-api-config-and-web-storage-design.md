# FlutterAIChat API 配置与 Web 存储适配设计

## 目标

同时解决两个问题：

1. 让应用不再把 `apiKey` 和 `baseUrl` 硬编码在 LLM 实现里，而是可以通过设置页编辑并持久化。
2. 让应用在 `Chrome` 上能够正常启动和运行，不再因为 `sqflite` 初始化失败而中断。

本次设计的范围是“配置可编辑”和“Web 可运行”。不顺带重构聊天业务，不引入新的模型供应商，不改现有桌面端的消息交互方式。

## 当前问题

### API 配置

当前 LLM HTTP 实现类在代码里直接持有固定 `apiKey` 和 `apiUrl`。这带来几个问题：

- 更换密钥或网关地址需要改代码并重新构建。
- 无法在不同环境间切换不同配置。
- 设置页虽然存在，但没有承担模型配置职责。

### Chrome 运行

当前应用启动时会直接初始化 `DatabaseHelper`，而它依赖 `sqflite`。这在桌面端可以工作，但在 Web 下会失败。结果是：

- `main.dart` 启动阶段就会报数据库工厂未初始化。
- `ChatController.loadGroups()` 也会继续触发相同问题。
- 浏览器端还没进入正常聊天流程就中断。

## 方案概览

采用两条并行但边界清晰的改动：

1. 引入“应用设置仓库”来管理 `apiKey` 和 `baseUrl`。
2. 引入“消息存储接口”，为原有 SQLite 实现保留桌面端支持，并给 Web 增加浏览器本地持久化实现。

推荐原则：

- 配置和消息存储都通过接口注入，避免业务层直接依赖某个平台实现。
- 桌面端保持原有 SQLite 路径。
- Web 端使用浏览器本地存储持久化分组和消息，刷新后仍能恢复。

## 设计细节

### 一、LLM 配置存储

新增一个轻量设置仓库，例如 `AppSettingsRepository`，负责读写以下字段：

- `apiKey`
- `baseUrl`

这个仓库应满足：

- 支持桌面端和 Web 端统一读写。
- 提供默认空值，而不是硬编码真实密钥。
- 读取失败时有明确兜底，不让应用直接崩溃。

设置页新增两个表单项：

- `API Key`
- `Base URL`

设置页保存后，仓库持久化配置。聊天服务在新请求发生时读取最新配置，不要求强制重启应用。

### 二、LLM 配置注入

可配置 HTTP LLM 实现不再在类内部写死：

- `apiKey`
- `apiUrl`

改为通过构造参数接收一个配置对象，或接收配置仓库并在请求时读取。

推荐做法是：

- `main.dart` 或 provider 层创建 `AppSettingsRepository`
- provider 层基于当前设置构建可配置 HTTP LLM
- `ChatService` 保持只依赖 `BaseLLM`

这样可以把“配置读取”限制在创建 LLM 的边界，不把设置仓库散落到业务逻辑里。

### 三、消息存储平台适配

新增统一消息存储接口，例如 `ChatStorage`，承载当前 `DatabaseHelper` 负责的核心职责：

- 分组增删改查
- 消息增删改查
- 分页加载
- 状态更新

桌面端：

- 继续由现有 SQLite 实现承担，原 `DatabaseHelper` 可以转为 `SqliteChatStorage`，也可以先保留类名但实现接口。

Web 端：

- 新增 `WebChatStorage`
- 使用浏览器本地存储保存分组和消息 JSON
- 至少持久化以下结构：
  - 群组列表
  - 每个群组的消息列表

推荐的最小实现：

- 一个 key 保存 `chat_groups`
- 一个 key 保存 `messages`
- 读出后在内存里筛选 `group_id`

虽然这不是最高性能方案，但对当前单机聊天规模足够，而且实现边界最小。

### 四、启动与平台注入

`main.dart` 启动时根据平台选择实现：

- 非 Web：注入 SQLite 存储
- Web：注入浏览器本地存储

同理，设置仓库也应通过统一 provider 注入，而不是直接在页面里 new。

启动流程会变成：

1. 初始化 Flutter 绑定
2. 初始化设置仓库
3. 根据平台初始化聊天存储
4. 构建 provider 覆盖
5. 运行应用

这样 Chrome 启动时就不会再碰 `sqflite`。

### 五、错误处理

API 配置为空时：

- 不让请求发到无效地址
- 给出清晰错误提示，例如“请先在设置页配置 API Key 和 Base URL”

Base URL 非法时：

- 在保存时做基本校验，至少要求是可解析 URL

Web 本地存储反序列化失败时：

- 回退为空数据，而不是直接崩溃

## 对现有代码的影响

### 主要修改点

- `lib/pages/settings_page.dart`
  - 增加 API 配置编辑入口
- `lib/models/llm/configurable_http_llm.dart`
  - 去掉硬编码配置，改为注入
- `lib/main.dart`
  - 注入设置仓库和平台存储实现
- `lib/providers/chat_providers.dart`
  - 把 `databaseProvider` 从直接 new `DatabaseHelper()` 改成依赖统一存储接口
- `lib/database/database_helper.dart`
  - 适配成桌面端实现，或抽出接口后继续作为 SQLite 实现

### 新增文件

- `lib/repositories/app_settings_repository.dart`
- `lib/storage/chat_storage.dart`
- `lib/storage/web_chat_storage.dart`

文件名可以微调，但职责边界建议保持不变。

## 测试策略

至少补以下测试：

1. 设置仓库测试
   - 能保存和读取 `apiKey`
   - 能保存和读取 `baseUrl`

2. LLM 配置测试
   - 可配置 HTTP LLM 使用注入配置，而不是硬编码值

3. Web 存储测试
   - 分组和消息能序列化并读回
   - 状态更新不会破坏现有数据

4. 启动/注入测试
   - Web 模式下不会触发 `sqflite` 初始化路径

## 非目标

本次不做以下内容：

- 不引入新的模型供应商切换 UI
- 不做云端同步
- 不重构整套聊天架构
- 不修复仓库里与本任务无关的所有历史 warning

## 推荐实施顺序

1. 先做设置仓库与设置页字段
2. 再做可配置 HTTP LLM 配置注入
3. 然后抽消息存储接口
4. 最后补 `WebChatStorage` 并让 `main.dart` 在 Web 上切换到它

这个顺序能先解决“配置可改”，再解决“Chrome 可跑”，每一步都比较容易验证。
