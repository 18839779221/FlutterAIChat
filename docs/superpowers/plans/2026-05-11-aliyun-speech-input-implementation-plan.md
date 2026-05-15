# 阿里云实时语音输入 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为聊天输入框实现“按住说话、实时转写、松手回填”的阿里云实时语音输入第一版，并清理旧语音方案残留。

**Architecture:** 语音输入按 `VoiceInputController -> SpeechToTextService -> AliyunRealtimeAsrClient -> AudioCaptureService` 分层，配置统一从 `config/local_defaults.json` 的 `speechInput` 节点读取。UI 只消费受控状态与草稿文本，不直接处理 WebSocket 协议或音频帧。实现顺序先从配置模型与旧残留清理开始，再做服务层与 Android 真机 PoC，最后接入 `ChatInput`。

**Tech Stack:** Flutter 3.29.2（优先 `fvm flutter`）, Riverpod, current local defaults loading pipeline, WebSocket client, microphone permission handling, Android real-device validation, `flutter_test`

---

## 涉及文件与职责

### 需要新增

- `lib/models/speech/speech_input_config.dart`
  - `speechInput` 本地配置模型，承载 provider、endpoint、apiKey、sampleRate、languageHints 等字段

- `lib/models/speech/speech_input_state.dart`
  - 语音输入运行时状态模型，承载 phase、draftText、errorMessage、hasPermission 等字段

- `lib/services/speech/speech_to_text_service.dart`
  - 统一语音识别抽象接口

- `lib/services/speech/aliyun_realtime_asr_client.dart`
  - 阿里实时语音识别 WebSocket 客户端与协议解析

- `lib/services/speech/aliyun_speech_to_text_service.dart`
  - `SpeechToTextService` 的阿里实现

- `lib/services/audio/audio_capture_service.dart`
  - 底层录音采集抽象

- `lib/controllers/voice_input_controller.dart`
  - 录音权限、录音会话、草稿态、final 回填协同控制器

- `test/models/speech/speech_input_config_test.dart`
  - `speechInput` 配置解析与校验测试

- `test/controllers/voice_input_controller_test.dart`
  - 状态机、partial/final 合并、错误态测试

- `test/services/speech/aliyun_speech_to_text_service_test.dart`
  - 阿里服务层的 partial/final/error 解析测试

### 需要修改

- `config/local_defaults.json`
  - 增加 `speechInput` 示例配置

- `lib/repositories/llm_local_defaults.dart`
  - 扩展本地默认配置加载链路，解析 `speechInput`

- `lib/repositories/app_settings_repository.dart`
  - 若存在本地默认配置落地或投影逻辑，补齐 `speechInput` 读取/透传

- `lib/providers/chat_dependency_providers.dart`
  - 注入 `SpeechInputConfig`、`SpeechToTextService`、`AudioCaptureService`、`VoiceInputController`

- `lib/widgets/chat_input.dart`
  - 新增按住说话按钮、语音草稿态展示、最终文本回填接入

- `android/app/src/main/AndroidManifest.xml`
  - 重审并保留新方案需要的麦克风权限

- `ios/Runner/Info.plist`
  - 重审并更新新方案的麦克风 / 语音识别权限文案

- `pubspec.yaml`
  - 按实际实现引入录音或权限相关依赖

- `test/widgets/chat_input_test.dart`
  - 补充语音按钮显隐、按住态、配置缺失态测试

- `README.md`
  - 若第一版实现落地，补充语音输入能力与 `speechInput` 配置说明

- `AGENTS.md`
  - 若实现过程中形成新的明确约束，再决定是否补充

### 可能需要删除或清理

- 历史语音输入残留文案、无效设置项、旧 provider/SDK 命名
- 旧语音相关测试桩或未使用依赖

---

## 前置说明

- 所有 Flutter 命令优先使用 `fvm flutter`。
- 当前工作区已有用户改动，实施时禁止回退无关文件。
- 第一期以 Android 真机 PoC 为主，iOS 只完成配置与编译层准备。
- `apiKey` 通过 `local_defaults.json` 注入仅视为开发 / 测试方案，不做生产安全承诺。
- 本计划中的示例代码是实现轮廓，实际开工时应优先遵循仓库既有命名与 provider 组织方式。

---

## Task 1：建立 `speechInput` 配置模型与解析测试

**Files:**
- Create: `lib/models/speech/speech_input_config.dart`
- Modify: `lib/repositories/llm_local_defaults.dart`
- Test: `test/models/speech/speech_input_config_test.dart`

- [ ] **Step 1: 写失败测试，定义 `speechInput` 解析行为**

创建 `test/models/speech/speech_input_config_test.dart`，覆盖：

- 完整 `speechInput` JSON 可解析为强类型模型
- `enabled=false` 时模型仍可读取，但上层应视为禁用
- 缺失 `provider` / `endpoint` / `apiKey` 时解析结果为 `null` 或标记为无效
- `languageHints` 缺失时默认 `['zh', 'en']`
- `sampleRate` 缺失时默认 `16000`

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
fvm flutter test test/models/speech/speech_input_config_test.dart
```

Expected:

- FAIL，提示 `SpeechInputConfig` 或解析逻辑未定义

- [ ] **Step 3: 新建 `SpeechInputConfig` 模型**

建议最小实现：

```dart
class SpeechInputConfig {
  final bool enabled;
  final String provider;
  final String endpoint;
  final String apiKey;
  final int sampleRate;
  final List<String> languageHints;

  const SpeechInputConfig({
    required this.enabled,
    required this.provider,
    required this.endpoint,
    required this.apiKey,
    required this.sampleRate,
    required this.languageHints,
  });

  bool get isValid =>
      enabled &&
      provider.trim().isNotEmpty &&
      endpoint.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty;

  factory SpeechInputConfig.fromJson(Map<String, dynamic> json) {
    final languageHints = (json['languageHints'] as List<dynamic>?)
            ?.whereType<String>()
            .where((item) => item.trim().isNotEmpty)
            .toList(growable: false) ??
        const <String>['zh', 'en'];
    return SpeechInputConfig(
      enabled: json['enabled'] as bool? ?? false,
      provider: (json['provider'] as String? ?? '').trim(),
      endpoint: (json['endpoint'] as String? ?? '').trim(),
      apiKey: (json['apiKey'] as String? ?? '').trim(),
      sampleRate: json['sampleRate'] as int? ?? 16000,
      languageHints: languageHints,
    );
  }
}
```

- [ ] **Step 4: 在 `llm_local_defaults.dart` 中接入 `speechInput` 解析**

要求：

- 在当前本地默认配置模型中新增 `speechInput` 字段
- 解析失败时不要让整个 defaults 加载崩溃
- 保持与现有 `additionalConfig` / provider defaults 并存

- [ ] **Step 5: 重新运行测试确认通过**

Run:

```bash
fvm flutter test test/models/speech/speech_input_config_test.dart
```

Expected:

- PASS

- [ ] **Step 6: 运行 analyze**

Run:

```bash
fvm flutter analyze lib/models/speech/speech_input_config.dart lib/repositories/llm_local_defaults.dart test/models/speech/speech_input_config_test.dart
```

Expected:

- `No issues found!`

- [ ] **Step 7: 提交**

```bash
git add lib/models/speech/speech_input_config.dart lib/repositories/llm_local_defaults.dart test/models/speech/speech_input_config_test.dart
git commit -m "feat: add speech input config model"
```

---

## Task 2：把 `speechInput` 接入 local defaults 示例与依赖注入

**Files:**
- Modify: `config/local_defaults.json`
- Modify: `lib/providers/chat_dependency_providers.dart`
- Modify: `lib/repositories/app_settings_repository.dart`
- Test: `test/pages/settings_page_tool_settings_test.dart`

- [ ] **Step 8: 写失败测试，明确配置缺失与存在时的运行行为**

补充或新增测试，覆盖：

- 当 `speechInput` 缺失时，依赖 provider 返回 `null` 或禁用态
- 当 `speechInput.enabled=true` 且配置完整时，provider 可产出有效配置

- [ ] **Step 9: 运行测试确认失败**

Run:

```bash
fvm flutter test test/pages/settings_page_tool_settings_test.dart
```

Expected:

- FAIL，当前 provider 链路无法暴露 `speechInput`

- [ ] **Step 10: 在 `config/local_defaults.json` 中加入示例配置块**

示例：

```json
"speechInput": {
  "enabled": false,
  "provider": "aliyun",
  "endpoint": "wss://your-endpoint",
  "apiKey": "",
  "sampleRate": 16000,
  "languageHints": ["zh", "en"]
}
```

要求：

- 默认保持禁用，避免开发者未填密钥时误触发
- 示例字段完整，便于复制修改

- [ ] **Step 11: 在依赖 provider 中暴露 `SpeechInputConfig`**

要求：

- 延续当前 provider 组织方式
- 单独提供 `speechInputConfigProvider`
- 不把语音配置硬塞到现有聊天主 provider 中

- [ ] **Step 12: 重新运行测试确认通过**

Run:

```bash
fvm flutter test test/pages/settings_page_tool_settings_test.dart
```

Expected:

- PASS

- [ ] **Step 13: 运行 analyze**

Run:

```bash
fvm flutter analyze lib/providers/chat_dependency_providers.dart lib/repositories/app_settings_repository.dart
```

Expected:

- `No issues found!`

- [ ] **Step 14: 提交**

```bash
git add config/local_defaults.json lib/providers/chat_dependency_providers.dart lib/repositories/app_settings_repository.dart
git commit -m "feat: wire speech input config providers"
```

---

## Task 3：清理旧语音输入残留并建立平台权限基线

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `ios/Runner/Info.plist`
- Modify: `pubspec.yaml`
- Test: `fvm flutter analyze`

- [ ] **Step 15: 排查旧语音残留并形成变更清单**

Run:

```bash
rg -n -i "voice|speech|stt|asr|xfyun|xunfei|讯飞|科大讯飞|speech_to_text|record_audio|microphone" lib android ios pubspec.yaml pubspec.lock
```

Expected:

- 得到当前剩余残留位置，确认没有隐藏原生 SDK 入口

- [ ] **Step 16: 更新 Android / iOS 权限文案**

要求：

- Android 保留新方案需要的 `RECORD_AUDIO`
- iOS 权限文案改成面向“按住说话转文字”的表述
- 删除任何明显指向旧讯飞或旧失败方案的文字

- [ ] **Step 17: 清理未使用的旧语音依赖或注释**

要求：

- `pubspec.yaml` 不保留旧语音 SDK 依赖
- 原生工程中无历史 provider 专属注释或无效配置

- [ ] **Step 18: 运行 analyze 作为基线校验**

Run:

```bash
fvm flutter analyze
```

Expected:

- `No issues found!`

- [ ] **Step 19: 提交**

```bash
git add android/app/src/main/AndroidManifest.xml ios/Runner/Info.plist pubspec.yaml
git commit -m "chore: clean up legacy speech input remnants"
```

---

## Task 4：建立 `SpeechToTextService` 抽象与服务层测试桩

**Files:**
- Create: `lib/services/speech/speech_to_text_service.dart`
- Create: `lib/models/speech/speech_input_state.dart`
- Test: `test/services/speech/aliyun_speech_to_text_service_test.dart`

- [ ] **Step 20: 写失败测试，定义 partial/final/error 流接口**

测试覆盖：

- `startSession()` 后可接受音频帧
- 服务层可发出 partial 结果
- `finishSession()` 后可发出 final 结果
- error 事件会进入错误流

- [ ] **Step 21: 运行测试确认失败**

Run:

```bash
fvm flutter test test/services/speech/aliyun_speech_to_text_service_test.dart
```

Expected:

- FAIL，接口与实现均不存在

- [ ] **Step 22: 新建抽象接口与状态模型**

建议接口：

```dart
abstract class SpeechToTextService {
  Stream<String> get partialResults;
  Stream<String> get finalResults;
  Stream<Object> get errors;

  Future<void> startSession();
  Future<void> sendAudioFrame(Uint8List frame);
  Future<void> finishSession();
  Future<void> close();
}
```

`SpeechInputState` 建议包含：

- `phase`
- `draftText`
- `errorMessage`
- `isConfigured`
- `hasPermission`

- [ ] **Step 23: 重新运行测试，确认仍是实现缺失类失败**

Run:

```bash
fvm flutter test test/services/speech/aliyun_speech_to_text_service_test.dart
```

Expected:

- FAIL，但已对准阿里实现缺口

- [ ] **Step 24: 运行 analyze**

Run:

```bash
fvm flutter analyze lib/services/speech/speech_to_text_service.dart lib/models/speech/speech_input_state.dart
```

Expected:

- `No issues found!`

- [ ] **Step 25: 提交**

```bash
git add lib/services/speech/speech_to_text_service.dart lib/models/speech/speech_input_state.dart
git commit -m "feat: add speech to text service abstractions"
```

---

## Task 5：实现阿里实时 ASR 客户端协议解析

**Files:**
- Create: `lib/services/speech/aliyun_realtime_asr_client.dart`
- Create: `lib/services/speech/aliyun_speech_to_text_service.dart`
- Test: `test/services/speech/aliyun_speech_to_text_service_test.dart`

- [ ] **Step 26: 写失败测试，覆盖阿里事件解析**

建议覆盖：

- partial 消息解析为 `partialResults`
- final 消息解析为 `finalResults`
- 错误消息解析为 `errors`
- `finishSession()` 会发送结束信号并关闭会话

- [ ] **Step 27: 运行测试确认失败**

Run:

```bash
fvm flutter test test/services/speech/aliyun_speech_to_text_service_test.dart
```

Expected:

- FAIL

- [ ] **Step 28: 实现 `AliyunRealtimeAsrClient`**

要求：

- 封装 WebSocket 建连、消息发送、消息监听
- 提供受控的 `connect/send/finish/dispose`
- 协议解析与上游结果分发分开组织
- 对外暴露 narrow API，不把原始动态 JSON 直接交给 UI

- [ ] **Step 29: 实现 `AliyunSpeechToTextService`**

要求：

- 用 `AliyunRealtimeAsrClient` 驱动 partial/final/error stream
- 在未启动 session 时拒绝发送音频帧
- `close()` 要可重复调用且安全

- [ ] **Step 30: 重新运行测试确认通过**

Run:

```bash
fvm flutter test test/services/speech/aliyun_speech_to_text_service_test.dart
```

Expected:

- PASS

- [ ] **Step 31: 运行 analyze**

Run:

```bash
fvm flutter analyze lib/services/speech/aliyun_realtime_asr_client.dart lib/services/speech/aliyun_speech_to_text_service.dart test/services/speech/aliyun_speech_to_text_service_test.dart
```

Expected:

- `No issues found!`

- [ ] **Step 32: 提交**

```bash
git add lib/services/speech/aliyun_realtime_asr_client.dart lib/services/speech/aliyun_speech_to_text_service.dart test/services/speech/aliyun_speech_to_text_service_test.dart
git commit -m "feat: add aliyun realtime speech client"
```

---

## Task 6：实现录音采集抽象与 Android PoC 连通

**Files:**
- Create: `lib/services/audio/audio_capture_service.dart`
- Modify: `pubspec.yaml`
- Test: `fvm flutter analyze`

- [ ] **Step 33: 选定录音依赖并补充 `pubspec.yaml`**

要求：

- 选择一个能稳定输出实时 PCM 帧的 Flutter 录音依赖
- 不引入带整套 STT 能力的黑盒插件

- [ ] **Step 34: 实现 `AudioCaptureService` 抽象**

建议接口：

```dart
abstract class AudioCaptureService {
  Stream<Uint8List> get audioFrames;

  Future<bool> requestPermission();
  Future<void> start({required int sampleRate});
  Future<void> stop();
  Future<void> dispose();
}
```

- [ ] **Step 35: 做最小 Android 真机 PoC**

要求：

- 真机上能开始录音并稳定收到音频帧
- 暂时允许用简单日志验证帧流，不要求 UI 全接通

- [ ] **Step 36: 运行 analyze**

Run:

```bash
fvm flutter analyze
```

Expected:

- `No issues found!`

- [ ] **Step 37: 提交**

```bash
git add pubspec.yaml lib/services/audio/audio_capture_service.dart
git commit -m "feat: add audio capture service for speech input"
```

---

## Task 7：实现 `VoiceInputController` 状态机与文本合并策略

**Files:**
- Create: `lib/controllers/voice_input_controller.dart`
- Test: `test/controllers/voice_input_controller_test.dart`
- Modify: `lib/providers/chat_dependency_providers.dart`

- [ ] **Step 38: 写失败测试，定义状态机与 composer 合并行为**

覆盖场景：

- `pressStart()` 在未配置时进入错误或 no-op
- 权限拒绝时进入 `error`
- partial 结果更新 `draftText`，但不直接写 composer
- `releaseStop()` 收到 final 后把文本合并回输入框
- 原有 composer 非空时，final 结果采用追加而非覆盖

- [ ] **Step 39: 运行测试确认失败**

Run:

```bash
fvm flutter test test/controllers/voice_input_controller_test.dart
```

Expected:

- FAIL

- [ ] **Step 40: 实现 `VoiceInputController`**

要求：

- 注入 `SpeechToTextService`、`AudioCaptureService`、`TextEditingController`
- 用不可变状态对象驱动 UI
- partial / final / error 订阅要在 `dispose` 中清理
- 文本合并策略不要直接覆盖用户已有输入

- [ ] **Step 41: 在 provider 中注入控制器**

要求：

- 保持现有 Riverpod 风格
- 不把控制器逻辑塞回 `ChatController`

- [ ] **Step 42: 重新运行测试确认通过**

Run:

```bash
fvm flutter test test/controllers/voice_input_controller_test.dart
```

Expected:

- PASS

- [ ] **Step 43: 运行 analyze**

Run:

```bash
fvm flutter analyze lib/controllers/voice_input_controller.dart lib/providers/chat_dependency_providers.dart test/controllers/voice_input_controller_test.dart
```

Expected:

- `No issues found!`

- [ ] **Step 44: 提交**

```bash
git add lib/controllers/voice_input_controller.dart lib/providers/chat_dependency_providers.dart test/controllers/voice_input_controller_test.dart
git commit -m "feat: add voice input controller"
```

---

## Task 8：把语音输入接入 `ChatInput` UI

**Files:**
- Modify: `lib/widgets/chat_input.dart`
- Modify: `test/widgets/chat_input_test.dart`

- [ ] **Step 45: 写失败测试，定义麦克风按钮与草稿态呈现**

覆盖场景：

- `speechInput` 未配置或禁用时，不显示麦克风按钮
- 配置存在时，显示麦克风按钮
- 进入 listening 状态时显示草稿文本或录音态提示
- 松手后 final 文本写入输入框

- [ ] **Step 46: 运行测试确认失败**

Run:

```bash
fvm flutter test test/widgets/chat_input_test.dart
```

Expected:

- FAIL

- [ ] **Step 47: 在 `ChatInput` 中接入语音按钮与按住交互**

要求：

- 使用 `GestureDetector` 或等效方案处理 `onLongPressStart` / `onLongPressEnd`
- 不破坏现有发送按钮、slash suggestions、context usage indicator
- 录音态文案保持克制，不新增解释型大段文本

- [ ] **Step 48: 接入草稿显示**

要求：

- 语音草稿单独显示，不频繁改写 `TextEditingController`
- 结束后由控制器统一回填最终文本

- [ ] **Step 49: 重新运行测试确认通过**

Run:

```bash
fvm flutter test test/widgets/chat_input_test.dart
```

Expected:

- PASS

- [ ] **Step 50: 运行 analyze**

Run:

```bash
fvm flutter analyze lib/widgets/chat_input.dart test/widgets/chat_input_test.dart
```

Expected:

- `No issues found!`

- [ ] **Step 51: 提交**

```bash
git add lib/widgets/chat_input.dart test/widgets/chat_input_test.dart
git commit -m "feat: add push to talk chat input UI"
```

---

## Task 9：做 Android 真机联调与最小端到端验证

**Files:**
- Modify: implementation files from Tasks 5-8 as needed
- Optional Test: add narrow regression tests if defects are fixed

- [ ] **Step 52: 安装依赖并确保工程可构建**

Run:

```bash
fvm flutter pub get
```

Expected:

- 依赖解析成功

- [ ] **Step 53: 在 Android 真机上运行调试版本**

Run:

```bash
fvm flutter run
```

Expected:

- App 在连接设备上正常启动

- [ ] **Step 54: 手动验证按住说话链路**

验证项：

- 首次请求麦克风权限
- 按住录音时能持续收到 partial text
- 松手后 final text 回填输入框
- 失败时 UI 可恢复，不锁死输入区

- [ ] **Step 55: 修复联调中发现的问题并补最小回归测试**

要求：

- 每修一个确定性 bug，优先补对应单测 / widget 测试
- 不把真机联调问题直接留在备注里

- [ ] **Step 56: 重新运行目标测试集**

Run:

```bash
fvm flutter test test/models/speech/speech_input_config_test.dart test/controllers/voice_input_controller_test.dart test/services/speech/aliyun_speech_to_text_service_test.dart test/widgets/chat_input_test.dart
```

Expected:

- PASS

- [ ] **Step 57: 运行全量 analyze**

Run:

```bash
fvm flutter analyze
```

Expected:

- `No issues found!`

- [ ] **Step 58: 提交**

```bash
git add .
git commit -m "feat: wire aliyun speech input end to end"
```

---

## Task 10：文档回写与收尾验证

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`（仅在新增明确长期约束时）
- Modify: `docs/superpowers/specs/2026-05-11-aliyun-speech-input-design.md`（若实现偏离设计）

- [ ] **Step 59: 更新 README 语音输入说明**

要求：

- 说明第一版能力边界
- 说明 `speechInput` 的 local defaults 配置方式
- 明确当前主要验证平台是 Android

- [ ] **Step 60: 若实现过程中形成新约束，更新 AGENTS**

仅在以下情况更新：

- 新增了明确长期维护规则
- 或配置 / 测试流程被项目采用为新约定

- [ ] **Step 61: 运行最终验证**

Run:

```bash
fvm flutter test
fvm flutter analyze
```

Expected:

- 测试与 analyze 全绿

- [ ] **Step 62: 最终提交**

```bash
git add README.md AGENTS.md docs/superpowers/specs/2026-05-11-aliyun-speech-input-design.md
git commit -m "docs: document aliyun speech input rollout"
```

---

## 执行备注

- 本计划默认按照 TDD 推进：先写失败测试，再做最小实现，再回归。
- 如果阿里实时协议在客户端直连阶段暴露出不可接受的鉴权限制，先记录为明确阻塞，不要偷偷切到其他 provider。
- 如果录音依赖无法稳定输出 16k PCM 帧，应优先替换录音实现，而不是修改 UI 目标。
- 第一阶段以“能稳定在 Android 真机上完成按住说话链路”为完成标准，不把范围扩大到语音消息或自动发送。
