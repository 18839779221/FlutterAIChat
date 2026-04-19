# 多提供方模型配置与设置管理设计

## 背景

当前应用的模型接入仍是“单组运行时配置”心智模型：

- `config/local_defaults.json` 只支持一组 `api_key / base_url / model`
- `AppSettingsRepository` 只持久化一组当前配置
- 设置页只有单模型表单
- `ConfigurableHttpLLM` 每次请求只读取这一组配置

这已经无法满足以下需求：

1. 支持配置多个提供方
2. 支持同一提供方下挂多个模型
3. 支持不同提供方使用不同的 `api_key / base_url`
4. 支持设置默认提供方和默认模型
5. 支持在设置界面切换模型并测试模型
6. 支持在设置界面新增、编辑、删除提供方项，并回写到本地持久化配置

同时，当前需求边界已经明确：

- `config/local_defaults.json` 只作为首次导入的默认种子
- 一旦本地持久化配置建立完成，后续运行只以本地持久化数据为准
- 模型测试采用真实请求，而不是纯连通性探测
- 模型配置仅使用 `SharedPreferences` 持久化，不引入数据库存储
- 当前 App 处于内部开发阶段，暂无外部用户；本次改造不考虑旧 `local_defaults.json` 结构兼容或迁移

## 目标

本次设计目标如下：

1. 将运行时模型配置从“单值”升级为“本地提供方目录 + 当前激活提供方/模型”
2. 保持 `config/local_defaults.json` 作为首次启动时的初始化来源，而不是长期真相源
3. 将模型管理从设置首页拆分为独立界面，避免首页过载
4. 允许用户在应用内新增、编辑、删除、设为默认、切换和测试提供方与模型
5. 让聊天请求、总结、planner 等现有 LLM 调用路径继续只消费一个最终解析出的 `LLMConfig`

## 非目标

本次不做以下内容：

1. 不实现按场景自动选模型，例如“总结用小模型、主对话用大模型”
2. 不实现云端同步提供方目录
3. 不直接回写 `config/local_defaults.json`
4. 不引入提供方类型枚举或复杂 provider DSL
5. 不在本轮改造聊天页发送入口或会话级模型绑定
6. 不接入自动模型探测能力

## 现状问题

### 1. `local_defaults` 无法表达提供方与模型的两层关系

当前 `LlmLocalDefaults` 只能解析：

- `api_key`
- `base_url`
- `model`

它表达不了：

- 一个提供方支持多个模型
- 多个提供方各自支持哪些模型
- 默认提供方与默认模型的组合选择

### 2. 设置仓库仍是单模型持久化

当前 `AppSettingsRepository` 只存储：

- `llm.api_key`
- `llm.base_url`
- `llm.model`

这导致：

- 无法保存多个提供方项
- 无法保存某个提供方下的模型列表
- 无法表达当前激活提供方与当前激活模型
- 无法表达默认提供方与默认模型

### 3. 设置页交互已经到达复杂度上限

当前 [`lib/pages/settings_page.dart`](/Users/skka/flutterSpace/FlutterAIChat/lib/pages/settings_page.dart) 只有单组表单。如果直接把“提供方列表 + 模型切换 + 默认切换 + 测试 + 增删改”全部塞进去，会显著提高页面噪声和状态管理复杂度。

### 4. 运行时读取入口需要稳定

虽然应用将支持多提供方和多模型，但 `ChatService` 和 `BaseLLM` 的调用链仍应保持“每次请求拿到一个完整 `LLMConfig`”的简单模型。多提供方管理应收敛在 repository 层，而不是散落进 controller 和 service。

## 方案总览

采用“首次导入种子配置 + 本地提供方目录接管 + 设置页入口 + 独立模型管理页”的方案。

核心原则如下：

1. `config/local_defaults.json` 直接改造成 `providers` 顶层结构
2. 本地持久化提供方目录是真相源
3. 运行时永远只读取“当前激活提供方 + 当前激活模型”解析后的 `LLMConfig`
4. 设置首页只负责展示当前选择和提供管理入口
5. 提供方增删改查、模型切换和模型测试放到独立管理流
6. 持久化仅使用 `SharedPreferences`

## 配置结构设计

### 一、`config/local_defaults.json` 新结构

配置文件从单模型结构升级为“提供方目录结构”，建议如下：

```json
{
  "default_provider_id": "aigocode",
  "default_model_id": "gpt-5.4",
  "providers": [
    {
      "id": "aigocode",
      "name": "AIGoCode",
      "api_key": "sk-xxx",
      "base_url": "https://api.aigocode.com",
      "models": [
        {
          "id": "gpt-5.4",
          "name": "GPT-5.4"
        },
        {
          "id": "gpt-5-mini",
          "name": "GPT-5 Mini"
        }
      ]
    },
    {
      "id": "anthropic-proxy",
      "name": "Anthropic Proxy",
      "api_key": "sk-ant-xxx",
      "base_url": "https://api.example.com/v1",
      "models": [
        {
          "id": "claude-sonnet-4",
          "name": "Claude Sonnet 4"
        }
      ]
    }
  ],
  "web_search": {
    "provider": "tavily",
    "tavily_api_key": "tvly-XXX"
  }
}
```

字段说明：

- `default_provider_id`：首次导入后应激活的默认提供方 ID
- `default_model_id`：首次导入后应激活的默认模型 ID
- `providers[]`：提供方目录
- `providers[].id`：稳定唯一标识
- `providers[].name`：用户可读名称
- `providers[].api_key / base_url`：该提供方的运行时接入配置
- `providers[].models[]`：该提供方支持的模型列表
- `providers[].models[].id`：真实传给兼容接口的模型 ID
- `providers[].models[].name`：模型展示名称

设计说明：

1. `model` 字段不再放在 provider 根上，而是改为 `models[]`
2. 顶层不再使用 `models` 命名，而是使用 `providers`
3. 第一阶段建议 `models[]` 使用对象数组而不是纯字符串数组，便于后续扩展展示名称、是否推荐、备注等字段

### 二、本地持久化结构

本地持久化应尽量复用 `local_defaults.json` 的结构，而不是再设计一套完全不同的数据模型。

建议持久化两部分：

1. 提供方目录 JSON
2. 当前选择 JSON

推荐 `SharedPreferences` 键如下：

- `llm.providers_json`
- `llm.selection_json`
- `llm.providers_seeded`

其中：

`llm.providers_json` 保存整个 `providers` 数组。

`llm.selection_json` 保存：

```json
{
  "selected_provider_id": "aigocode",
  "selected_model_id": "gpt-5.4",
  "default_provider_id": "aigocode",
  "default_model_id": "gpt-5.4"
}
```

`llm.providers_seeded` 表示是否已经完成首次导入。

这种设计的优点：

1. 键数量少
2. 与 `local_defaults.json` 结构接近，便于导入与调试
3. 后续扩展选择态字段时无需继续增加零散 key

### 三、首次导入规则

导入规则如下：

1. 若 `llm.providers_seeded != true` 且本地目录为空，则读取新的 `local_defaults`
2. 读到 `providers` 后，写入 `llm.providers_json`
3. 读到默认选择后，写入 `llm.selection_json`
4. 写入 `llm.providers_seeded = true`

之后不再自动用配置文件覆盖本地目录。

如果首次导入失败：

1. 不让应用崩溃
2. 本地目录保持空
3. 设置页模型区显示“暂无提供方，请先新增”

## Repository 设计

### 一、`LlmLocalDefaults` 升级为提供方目录解析器

[`lib/repositories/llm_local_defaults.dart`](/Users/skka/flutterSpace/FlutterAIChat/lib/repositories/llm_local_defaults.dart) 需要直接升级为新的提供方目录解析器：

1. 解析提供方目录
2. 解析默认提供方与默认模型
3. 保留 `web_search` 等与模型目录无关的附加配置

推荐新增以下对象：

- `LlmLocalDefaultProvider`
- `LlmLocalDefaultModel`
- `LlmLocalDefaults`

其中 `LlmLocalDefaults` 包含：

- `defaultProviderId`
- `defaultModelId`
- `providers`
- `additionalConfig`

### 二、`AppSettingsRepository` 升级为提供方目录仓库

[`lib/repositories/app_settings_repository.dart`](/Users/skka/flutterSpace/FlutterAIChat/lib/repositories/app_settings_repository.dart) 从“单组配置仓库”升级为“提供方目录仓库”，建议提供以下能力：

1. `Future<List<LlmProviderConfig>> getProviders()`
2. `Future<LlmProviderConfig?> getProviderById(String providerId)`
3. `Future<void> saveProvider(LlmProviderConfig provider)`
4. `Future<void> deleteProvider(String providerId)`
5. `Future<LlmSelectionState> getSelectionState()`
6. `Future<void> saveSelectionState(LlmSelectionState selection)`
7. `Future<void> selectProviderAndModel({required String providerId, required String modelId})`
8. `Future<void> setDefaultProviderAndModel({required String providerId, required String modelId})`
9. `Future<LLMConfig> getLlmConfig()`
10. `Future<void> ensureSeededProviders()`

行为规则：

1. `getLlmConfig()` 永远返回当前激活提供方和当前激活模型对应配置
2. 若当前激活模型不存在，则回退到默认模型
3. 若默认模型也不存在，则回退到提供方下首个模型
4. 若当前提供方不存在，则回退到默认提供方
5. 若默认提供方也不存在，则回退到目录首个提供方
6. 若目录为空，则抛出明确异常，例如“请先在设置中新增提供方”

删除回退规则：

1. 删除当前激活提供方时：
   - 若默认提供方仍存在，则切到默认提供方 + 其默认模型或首个模型
   - 否则切到剩余首个提供方
   - 若已无剩余提供方，则清空选择态
2. 删除默认提供方时：
   - 若仍有剩余提供方，则把默认切到剩余首个提供方
   - 若目录为空，则清空默认

提供方内部模型变更规则：

1. 编辑提供方时允许修改其 `models[]`
2. 若当前激活模型被移除，则回退到该提供方下默认模型或首个模型
3. 若默认模型被移除，则默认模型回退到该提供方下首个模型

### 三、旧接口收敛策略

当前已有：

- `getApiKey()`
- `getBaseUrl()`
- `getModel()`
- `saveLlmConfig(...)`

建议处理方式：

1. 第一阶段保留 `getApiKey/getBaseUrl/getModel`，内部转发到当前激活提供方和模型
2. 废弃 `saveLlmConfig(...)` 的“覆盖当前单配置”语义
3. 新 UI 不再直接依赖 `saveLlmConfig(...)`

这样可以控制改动面，避免一次性让所有调用点一起重构。

## 持久化模型设计

### 一、提供方对象

建议新增一个提供方配置实体，例如：

- [`lib/models/llm/llm_provider_config.dart`](/Users/skka/flutterSpace/FlutterAIChat/lib/models/llm/llm_provider_config.dart)

字段建议：

- `id`
- `name`
- `apiKey`
- `baseUrl`
- `models`

### 二、模型对象

建议新增模型配置实体，例如：

- [`lib/models/llm/llm_provider_model.dart`](/Users/skka/flutterSpace/FlutterAIChat/lib/models/llm/llm_provider_model.dart)

字段建议：

- `id`
- `name`

### 三、选择态对象

建议新增选择态实体，例如：

- [`lib/models/llm/llm_selection_state.dart`](/Users/skka/flutterSpace/FlutterAIChat/lib/models/llm/llm_selection_state.dart)

字段建议：

- `selectedProviderId`
- `selectedModelId`
- `defaultProviderId`
- `defaultModelId`

设计说明：

1. 默认态和当前态不冗余写进 provider 对象，避免双向同步问题
2. 提供方目录和选择态分开存，便于独立更新
3. 所有实体都应支持 `toJson/fromJson`

## UI 设计

### 一、设置首页职责收敛

[`lib/pages/settings_page.dart`](/Users/skka/flutterSpace/FlutterAIChat/lib/pages/settings_page.dart) 中的“模型接入”区域改为轻量摘要区，展示：

1. 当前提供方名称
2. 当前模型名称或模型 ID
3. 当前 `baseUrl` 摘要
4. 默认提供方/模型标识
5. “管理模型”入口
6. “测试当前模型”按钮

设置首页不再直接承载新增、编辑、删除表单。

### 二、独立模型管理页

新增模型管理页，例如：

- [`lib/pages/model_management_page.dart`](/Users/skka/flutterSpace/FlutterAIChat/lib/pages/model_management_page.dart)

页面职责：

1. 列表展示全部提供方项
2. 展开或进入二级视图查看该提供方下的模型列表
3. 支持设为当前使用
4. 支持设为默认
5. 支持新增提供方
6. 支持编辑提供方
7. 支持删除提供方
8. 支持测试某个提供方下的某个模型

列表建议展示：

- `provider.name`
- `provider.baseUrl`
- 模型数量
- “当前使用中”标签
- “默认”标签

提供方下的模型列表建议展示：

- `model.name`
- `model.id`
- “当前模型”标签
- “默认模型”标签

### 三、新增/编辑提供方表单

新增一个复用型表单页，例如：

- [`lib/pages/provider_form_page.dart`](/Users/skka/flutterSpace/FlutterAIChat/lib/pages/provider_form_page.dart)

表单字段：

- `提供方名称`
- `Base URL`
- `API Key`
- `模型列表`

其中“模型列表”支持：

1. 手动新增模型行
2. 编辑模型名称
3. 编辑模型 ID
4. 删除模型行

表单规则：

1. `提供方名称` 不能为空
2. `Base URL` 必须是合法 URL
3. `模型列表` 不能为空
4. 每个模型项的 `id` 不能为空
5. `API Key` 可以为空，但保存后测试或实际请求会失败，UI 应明确提示

新增时的 ID 策略：

1. 提供方 ID 不直接使用展示名
2. 新增时生成稳定唯一 ID
3. 编辑时保留原 ID 不变

## 模型测试设计

模型测试采用真实请求。

推荐实现：

1. 用户点击“测试”
2. 使用该提供方和该模型临时构造 `LLMConfig`
3. 向兼容端点发送一条固定测试请求，例如用户消息 `ping`
4. 成功时展示简短返回文本
5. 失败时展示接口错误信息

展示要求：

1. 不把测试结果写入聊天记录
2. 不污染当前会话状态
3. 支持测试任意提供方下的任意模型，而不要求先切换为当前模型

## 运行时接线设计

### 一、当前激活提供方与模型仍是唯一运行时入口

[`lib/models/llm/configurable_http_llm.dart`](/Users/skka/flutterSpace/FlutterAIChat/lib/models/llm/configurable_http_llm.dart) 继续通过 repository 读取运行时配置，但来源改为当前激活提供方与模型。

这意味着：

1. 主聊天请求读取当前激活提供方和模型
2. planner 请求读取当前激活提供方和模型
3. summary 请求读取当前激活提供方和模型
4. 结构化整理请求读取当前激活提供方和模型

这样可以保证多提供方能力不会把现有 service/controller 层扩散成“每个入口都得传 providerId/modelId”。

### 二、模型测试不应复用“当前激活模型”接口

为了支持“列表里直接测试某个提供方下的某个模型”，repository 或独立 service 需要提供“使用指定提供方和模型构造请求”的能力。

推荐新增一个轻量服务，例如：

- [`lib/services/llm_model_test_service.dart`](/Users/skka/flutterSpace/FlutterAIChat/lib/services/llm_model_test_service.dart)

职责：

1. 接收某个 provider 和某个 model
2. 构造临时 `LLMConfig`
3. 复用 `ApiProtocolResolver` 和 payload 构建逻辑
4. 返回测试文本或错误

这样可以避免在页面里直接 new HTTP 请求逻辑，也避免让 `ConfigurableHttpLLM` 背上“既管当前激活模型又管任意模型测试”的混合职责。

## 错误处理与边界规则

### 一、无提供方可用

当提供方目录为空时：

1. 聊天发送应返回明确错误
2. 文案建议为“请先在设置中新增提供方”
3. 设置首页应提供明显的管理入口

### 二、删除保护

建议第一阶段允许删除最后一个提供方，但要在删除前确认，并在删除后把应用置于“未配置模型”状态。

### 三、测试失败展示

测试失败时优先展示：

1. HTTP 状态码
2. 兼容端点返回的错误消息
3. 本地校验错误，例如 Base URL 非法

不要只显示“测试失败”。

## 对现有代码的影响

### 主要修改文件

- [`config/local_defaults.json`](/Users/skka/flutterSpace/FlutterAIChat/config/local_defaults.json)
- [`config/local_defaults.example.json`](/Users/skka/flutterSpace/FlutterAIChat/config/local_defaults.example.json)
- [`lib/repositories/llm_local_defaults.dart`](/Users/skka/flutterSpace/FlutterAIChat/lib/repositories/llm_local_defaults.dart)
- [`lib/repositories/app_settings_repository.dart`](/Users/skka/flutterSpace/FlutterAIChat/lib/repositories/app_settings_repository.dart)
- [`lib/pages/settings_page.dart`](/Users/skka/flutterSpace/FlutterAIChat/lib/pages/settings_page.dart)
- [`lib/models/llm/configurable_http_llm.dart`](/Users/skka/flutterSpace/FlutterAIChat/lib/models/llm/configurable_http_llm.dart)

### 建议新增文件

- [`lib/models/llm/llm_provider_config.dart`](/Users/skka/flutterSpace/FlutterAIChat/lib/models/llm/llm_provider_config.dart)
- [`lib/models/llm/llm_provider_model.dart`](/Users/skka/flutterSpace/FlutterAIChat/lib/models/llm/llm_provider_model.dart)
- [`lib/models/llm/llm_selection_state.dart`](/Users/skka/flutterSpace/FlutterAIChat/lib/models/llm/llm_selection_state.dart)
- [`lib/pages/model_management_page.dart`](/Users/skka/flutterSpace/FlutterAIChat/lib/pages/model_management_page.dart)
- [`lib/pages/provider_form_page.dart`](/Users/skka/flutterSpace/FlutterAIChat/lib/pages/provider_form_page.dart)
- [`lib/services/llm_model_test_service.dart`](/Users/skka/flutterSpace/FlutterAIChat/lib/services/llm_model_test_service.dart)

## 测试策略

至少补以下测试：

### 1. Repository 测试

- 首次运行时会从 `local_defaults` 导入提供方目录
- 导入后本地目录接管，后续不再被配置文件覆盖
- 能正确读取默认提供方和默认模型
- 能新增、编辑、删除提供方
- 能编辑提供方下模型列表
- 删除当前提供方和默认提供方时回退逻辑正确
- `getLlmConfig()` 始终返回当前激活提供方和模型

### 2. Local defaults 解析测试

- 能解析新提供方结构
- 空字段和非法字段能被合理过滤

### 3. 设置页与模型管理页测试

- 设置页显示当前提供方和当前模型摘要
- 点击入口可进入模型管理页
- 管理页能展示提供方列表和当前/默认标签
- 新增、编辑、删除、设默认、切换当前模型的交互可工作

### 4. 模型测试服务测试

- 成功时返回响应文本
- 失败时透出错误信息
- 使用指定提供方和模型测试时不会污染当前激活模型

### 5. LLM 运行时测试

- 聊天请求使用当前激活提供方和模型配置
- 切换当前模型后，新请求读取到新配置

## 推荐实施顺序

1. 先补 provider/model/selection 三个数据对象
2. 再升级 `local_defaults` 解析，支持 `providers` 顶层结构
3. 然后升级 `AppSettingsRepository`，完成首次导入与 `SharedPreferences` 持久化
4. 补 repository 测试，锁定回退和切换行为
5. 调整设置首页为摘要入口
6. 新增模型管理页与提供方表单页
7. 最后增加模型测试服务和相关交互测试

这个顺序可以先稳定数据边界，再展开 UI 和网络测试，回归成本最低。
