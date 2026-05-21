# SDK 接入交接文档

## 任务目标

引入 `openai_dart` v5.0.0 SDK 替代自实现的 Chat Completions 协议层，修复 DeepSeek 400 错误（tool_calls 消息序列问题）。保留自实现作为可回退 backup。

## 当前进度

### ✅ 已完成（代码层面）

| 文件 | 状态 | 说明 |
|------|------|------|
| `pubspec.yaml` | 已修改 | 添加了 `openai_dart` 本地路径依赖 + `web_socket` dependency_override |
| `lib/models/llm/adapters/sdk_message_converter.dart` | 已新建 | 消息转换层，含相邻 assistant + toolUse 合并逻辑 |
| `lib/models/llm/adapters/sdk_chat_completions_adapter.dart` | 已新建 | SDK 主适配器，实现 `ApiStyleAdapter` |
| `lib/models/llm/adapters/sdk_stream_adapter.dart` | 已新建 | 流式事件适配（SDK → StreamingPlannerChunk） |
| `lib/models/llm/adapters/chat_completions_adapter.dart` | 已修改 | class 重命名为 `LegacyChatCompletionsAdapter` |
| `lib/models/llm/configurable_http_llm.dart` | 已修改 | 默认用 SDK adapter，添加 `setChatCompletionsAdapter()` |
| `lib/models/llm/llm_factory.dart` | 已修改 | 传递 adapter 类型参数 |
| `lib/main.dart` | 已修改 | 读取 adapter 设置 |
| `lib/repositories/app_settings_repository.dart` | 已修改 | 添加 `get/setChatCompletionsAdapterType` |
| `test/models/llm/adapters/sdk_chat_completions_adapter_test.dart` | 已新建 | 18 个测试用例 |
| `test/models/llm/adapters/chat_completions_adapter_test.dart` | 已修改 | 类名更新为 `LegacyChatCompletionsAdapter` |
| `docs/superpowers/specs/2026-05-21-openai-dart-sdk-integration-design.md` | 已新建 | 设计文档 |
| `docs/superpowers/plans/2026-05-21-openai-dart-sdk-integration-plan.md` | 已新建 | 实现计划 |

### ❌ 未完成

1. **`fvm flutter pub get` 未执行** — 沙箱环境无法访问 pub.dev（代理 403）
2. **测试未运行** — 依赖未安装
3. **设备验证未做** — DeepSeek 400 修复未实机验证

## 关键阻塞问题

### 网络代理限制

当前环境有一个 HTTP 代理 `localhost:52117`，只允许白名单域名（api.anthropic.com 等），**pub.dev 被拦截返回 403**。

### 解决方案

**方案 A（推荐）：直接在终端执行**
```bash
cd <项目目录>
fvm flutter pub get
fvm flutter test test/models/llm/adapters/sdk_chat_completions_adapter_test.dart
fvm flutter test
fvm flutter analyze
```

**方案 B：如果 openai_dart 5.0.0 的 Dart SDK 约束有问题**

openai_dart 5.0.0 要求 Dart >=3.9.0，当前 Flutter 3.29.2 对应 Dart 3.7.2。

我已经下载了 openai_dart 5.0.0 包到 `/tmp/claude-501/openai_dart_pkg/`，并将其 SDK 约束从 `>=3.9.0` 改为 `>=3.7.0`。`pubspec.yaml` 中已配置为 path 依赖。

如果 `fvm flutter pub get` 报 SDK 版本不兼容，有两个选项：
1. **升级 Flutter** 到 3.35.x（对应 Dart 3.9.x），然后改回 `openai_dart: ^5.0.0`（去掉 path 依赖和 dependency_overrides）
2. **保持当前 Flutter**，用我修改过的本地包（path 依赖方式）

## DeepSeek 400 Bug 根因

`SessionContextProjector` 将 planner 文本输出和 tool_use 输出投影为**两条独立的 assistant 消息**。DeepSeek 严格校验 tool_calls 后必须紧跟 tool 消息，不允许多条 assistant 消息间隔。

SDK adapter 的 `SdkMessageConverter` 中已实现合并逻辑：相邻的 assistant text + assistant toolUse 会被合并为单条 `ChatMessage.assistant(content: ..., toolCalls: [...])`。

## 相关设计文档

- Spec: `docs/superpowers/specs/2026-05-21-openai-dart-sdk-integration-design.md`
- Plan: `docs/superpowers/plans/2026-05-21-openai-dart-sdk-integration-plan.md`

## 注意事项

- `pubspec.yaml` 当前使用 path 依赖和 dependency_overrides，正式发布前需改回 hosted 依赖
- `.playwright-mcp/` 目录下有下载的包文件（openai_dart-5.0.0.tar.gz, web_socket.tar.gz），可清理
- 切换机制已实现：设置页可通过 `llm.chat_completions_adapter` 键值在 `sdk`/`legacy` 间切换
