# 阿里云实时语音输入设计

- 日期：2026-05-11
- 作者：协作（用户 + Codex）
- 相关文件：`lib/widgets/chat_input.dart`、`config/local_defaults.json`、`lib/repositories/llm_local_defaults.dart`、`android/app/src/main/AndroidManifest.xml`、`ios/Runner/Info.plist`

## 1. 背景与目标

当前 App 缺少语音输入能力，用户无法以“按住说话”的方式快速把口述内容转成聊天输入。项目历史上曾尝试接入语音输入，但当前仓库中只剩少量平台权限与可能的原生配置残留，没有形成一套可维护、可扩展的正式方案。

本次设计聚焦一个最小但完整的第一版：

- 按住开始说话；
- 说话过程中实时显示转写草稿；
- 松手结束识别；
- 最终文字回填到现有输入框；
- 用户自行决定是否发送；
- 不引入自建后端；
- 通过 `config/local_defaults.json` 按不同运行实例注入鉴权配置；
- 首个 provider 固定为阿里云实时语音识别。

本次设计既要建立新方案，也要清理旧失败方案留下的 UI / 平台 / 配置痕迹，避免双轨并存。

## 2. 方案比较与选择

围绕“语音输入”目标，讨论过三类路线：

### 2.1 系统语音识别 / 通用 Flutter 插件

代表方案：系统 `SpeechRecognizer`、`speech_to_text` 一类 Flutter 插件。

优点：

- 接入快；
- 初期代码量小；
- 不需要额外云服务账号。

缺点：

- 行为依赖平台系统能力，跨平台一致性弱；
- 中文实时结果、长时稳定性、状态细节控制能力有限；
- 难以与未来多 provider 配置体系统一。

结论：不作为本次正式方案。

### 2.2 云端传统实时 ASR 服务

代表方案：阿里云 `Paraformer-realtime-v2`、火山引擎流式识别等。

优点：

- 天然适合“按住说话、边说边出字”的流式输入；
- 中文支持成熟；
- 识别结果、错误码、partial/final 语义比系统识别更可控；
- 后续可替换为第二 provider，而不改动 UI 交互模型。

缺点：

- 客户端要承担录音、音频帧编码、WebSocket 会话管理；
- 不走自建后端时，鉴权安全性只适合开发 / 内部测试场景。

结论：作为本次正式方案。

### 2.3 大模型语音 API

代表方案：实时语音模型、语音对话 API。

优点：

- 未来可扩展到完整语音助手；
- 可能统一转写与后续理解链路。

缺点：

- 接入复杂度与成本普遍高于“只做语音输入”；
- 对当前 App 的第一版目标属于过度设计；
- 不利于快速验证输入体验。

结论：当前阶段不采用。

### 2.4 最终选择

第一版采用 **阿里云 `Paraformer-realtime-v2` 直连方案**：

- 产品形态：`按住说话 + 实时出字 + 松手结束`
- 架构边界：`纯客户端直连阿里 + local defaults 注入鉴权配置`
- 目标定位：`开发 / 测试可用方案`

火山引擎保留为后续第二 provider 候选，但本次不进入实现范围。

## 3. 非目标

第一版明确不包含：

- 自动发送转写结果；
- 语音消息、音频文件持久化、消息气泡播放；
- TTS、语音播报、语音助手模式；
- 自建鉴权后端、临时令牌服务、服务端代理转发；
- 多 provider 切换 UI；
- 保留或兼容旧讯飞 / 旧 STT 路径的运行时 fallback；
- 为 Web/Desktop 同步交付完整语音输入能力。

## 4. 现状梳理

当前仓库中的语音相关现状如下：

- `pubspec.yaml` 中已无明显语音识别 Flutter 依赖；
- `lib/widgets/chat_input.dart` 当前是纯文本输入，没有现成麦克风按钮；
- Android Manifest 仍保留 `RECORD_AUDIO`；
- iOS `Info.plist` 仍保留麦克风与语音识别权限文案；
- 未搜索到当前仍在使用的讯飞 SDK / `speech_to_text` Flutter 代码入口；
- 因此“旧失败方案”的主要残留大概率集中在平台权限声明、可能的原生工程配置以及少量命名 / 文案层面的历史痕迹。

这意味着本次工作不应尝试“修旧方案”，而应清理残留后建立一套新的、边界清晰的语音输入模块。

## 5. 产品交互设计

### 5.1 第一版交互

用户交互固定为：

1. 用户在聊天输入区按住麦克风按钮；
2. App 请求权限（若尚未授权）并开始录音；
3. 录音期间实时展示语音转写草稿；
4. 用户松手后结束录音并等待最终结果；
5. 最终文字合并回现有输入框；
6. 用户可继续编辑或手动发送。

### 5.2 明确约束

- 不自动发送；
- 不覆盖用户原本已经输入的文字；
- partial text 仅作为临时草稿态存在；
- final text 写回输入框时才进入正式 composer 文本；
- 识别失败时不破坏当前输入框已有内容。

### 5.3 UI 呈现建议

主入口位于 `ChatInput`：

- 在现有输入区新增一个麦克风按钮；
- 按住态使用明显但克制的运行视觉反馈；
- 录音时显示“实时转写草稿”，但不把 partial text 直接反复写入 `TextEditingController`；
- 松手后将最终文本一次性并入 composer。

建议保留现有发送按钮语义，不把麦克风与发送逻辑混合为一个动态主按钮。

## 6. 架构设计

### 6.1 总体分层

本次语音输入能力拆为四层：

1. `VoiceInputController`
2. `SpeechToTextService`
3. `AliyunRealtimeAsrClient`
4. `AudioCaptureService`

目标是让 UI 只关心交互状态，provider / SDK 细节收敛在下层，不把阿里协议直接暴露到页面组件。

### 6.2 `VoiceInputController`

职责：

- 管理语音输入状态机；
- 协调权限、录音、识别和最终文本回填；
- 对 UI 暴露简单操作接口；
- 维护语音草稿文本与错误态。

建议状态：

- `idle`
- `requestingPermission`
- `connecting`
- `listening`
- `finalizing`
- `error`

建议对外能力：

- `pressStart()`
- `releaseStop()`
- `cancel()`
- `draftText`
- `errorMessage`
- `isListening`

### 6.3 `SpeechToTextService`

职责：

- 抽象具体语音识别 provider；
- 为上层提供统一的流式语音输入接口；
- 隐藏 WebSocket 协议细节。

第一版只实现一个 provider：

- `AliyunSpeechToTextService`

建议接口能力：

- `startSession()`
- `sendAudioFrame(Uint8List frame)`
- `finishSession()`
- `close()`
- `partialResults`
- `finalResults`
- `errors`

此层不直接接触 Flutter 页面，不持有 `TextEditingController`。

### 6.4 `AliyunRealtimeAsrClient`

职责：

- 负责阿里云 WebSocket 会话建立；
- 组装鉴权参数与请求头；
- 发送音频帧；
- 解析 partial / final 识别结果；
- 管理断开、超时、错误码与结束信号。

这一层只理解阿里实时识别协议，不负责 UI 与交互状态。

### 6.5 `AudioCaptureService`

职责：

- 请求和校验麦克风权限；
- 采集音频流；
- 将音频统一转换为阿里所需格式；
- 以稳定帧率向上层输出音频块。

第一版约束：

- 优先适配 Android 真机；
- 音频格式统一为 `16k / mono / PCM`；
- 不引入多套录音格式动态协商逻辑。

## 7. 配置设计

### 7.1 配置来源

语音输入配置统一从 `config/local_defaults.json` 注入，保持与当前项目本地运行配置方式一致。

本次不新增独立配置文件，不把语音输入配置塞入现有 LLM provider 配置项内部。

### 7.2 建议配置块

建议新增独立配置节点：

```json
{
  "speechInput": {
    "enabled": true,
    "provider": "aliyun",
    "endpoint": "wss://...",
    "apiKey": "...",
    "sampleRate": 16000,
    "languageHints": ["zh", "en"]
  }
}
```

字段含义：

- `enabled`：当前实例是否启用语音输入；
- `provider`：第一版固定为 `aliyun`；
- `endpoint`：阿里实时语音识别 WebSocket 地址；
- `apiKey`：开发 / 测试环境下直接注入客户端；
- `sampleRate`：默认 16000；
- `languageHints`：语言提示，默认中英。

如阿里官方接入还需要额外字段，应继续扩展该节点，而不是把细节散落到页面层。

### 7.3 配置缺失行为

当 `speechInput` 缺失、禁用或不完整时：

- 默认不展示麦克风按钮，或展示禁用态；
- 不抛出阻断式启动异常；
- 在设置/调试视图中可提示当前实例未配置语音输入。

## 8. 数据流设计

单次语音输入的数据流如下：

1. `ChatInput` 捕获按下动作；
2. `VoiceInputController.pressStart()` 被调用；
3. `AudioCaptureService` 请求权限并开始产出音频帧；
4. `SpeechToTextService` 建立阿里实时识别会话；
5. `AudioCaptureService` 连续输出 PCM 帧给 `SpeechToTextService`；
6. 阿里返回 partial result；
7. `VoiceInputController` 更新 `draftText`；
8. 用户松手后触发 `releaseStop()`；
9. 服务层结束音频发送并等待 final result；
10. `VoiceInputController` 把 final text 合并回 composer；
11. UI 退出录音态。

## 9. 输入框文本合并策略

这是第一版的关键细节，必须明确：

- partial result 不直接写回 `TextEditingController`；
- 现有手输文本和语音草稿必须分层维护；
- final result 到达后，才一次性并入 composer。

建议维护两段运行态文本：

- `baseComposerText`：用户原始手输内容；
- `voiceDraftText`：语音识别实时草稿。

回填时的建议行为：

- 若 `baseComposerText` 为空：直接写入 final text；
- 若 `baseComposerText` 非空：按空格或换行规则追加；
- 不在 partial 阶段改变光标位置；
- 不在 final 阶段覆盖用户刚刚手动修改过的内容，必要时以“追加”优先。

## 10. 平台与依赖策略

### 10.1 平台优先级

按项目约定，第一阶段优先 Android 真机验证。  
iOS 在 Android 路径跑通后补齐。

### 10.2 权限策略

最终需要保留的权限：

- Android：麦克风权限；
- iOS：麦克风权限与语音识别权限说明。

但在正式接入新方案前，应重新审查当前残留权限文案，确保文案与新方案一致，而不是继续沿用旧失败方案的表述。

### 10.3 依赖策略

优先引入一个职责明确的录音依赖来提供底层音频流采集。  
语音识别协议层建议自行封装，不直接把 provider-specific SDK 大面积扩散到 UI 层。

## 11. 旧方案残留清理

本次必须显式清理旧失败方案痕迹，不保留兼容路径。

### 11.1 平台权限与配置

排查并清理：

- `android/app/src/main/AndroidManifest.xml`
- `ios/Runner/Info.plist`
- Android Gradle / native sources 中可能残留的历史语音 SDK 配置
- iOS Pod / 原生工程中可能残留的历史语音 SDK 配置

### 11.2 Flutter 侧 UI / 状态残留

排查并清理：

- 输入区旧语音按钮或占位代码；
- 设置页中与旧语音功能相关的开关、文案或未完成状态；
- 旧方案命名（如讯飞、旧 STT）在 provider / controller / service 中的残留引用；
- 不再使用的测试桩或 mock。

### 11.3 配置层残留

排查并清理：

- `pubspec.yaml` / `pubspec.lock` 中旧语音依赖；
- Android / iOS 构建配置中的历史 SDK 接入痕迹；
- 与旧 provider 强耦合的配置字段。

清理原则：

- 不保留讯飞兼容层；
- 不保留“旧方案失败时 fallback 到新方案”的双轨逻辑；
- 直接迁移到新的 `speechInput` 配置模型。

## 12. 测试与验证计划

### 12.1 PoC 最小验证目标

第一阶段只验证五件事：

1. App 能正确读取 `speechInput` 配置；
2. Android 真机能请求并获得麦克风权限；
3. Flutter 能稳定采集实时音频帧；
4. 阿里 WebSocket 能返回 partial result；
5. 松手后 final text 能稳定写回输入框。

### 12.2 自动化测试

建议覆盖：

- `speechInput` 配置解析测试；
- `VoiceInputController` 状态机测试；
- final text 合并策略测试；
- 配置缺失时 UI 禁用 / 隐藏语音按钮测试；
- 阿里协议解析的服务层单元测试。

第一版不强求完整端到端自动化，但应至少补上状态机与配置层测试。

### 12.3 手动验证

按项目约定，优先 Android 真机：

- 按住录音；
- partial text 实时更新；
- 松手结束；
- final text 回填；
- 连续多次短句输入；
- 中途取消与权限拒绝；
- 弱网 / 识别失败时 UI 恢复正常。

## 13. 风险与限制

### 13.1 鉴权安全性

将 `apiKey` 通过 local defaults 注入客户端，只适合开发 / 测试与内部使用。  
该方案不能视为生产安全方案。

### 13.2 实时音频格式匹配

Flutter 录音流的输出格式若与阿里接口要求不完全一致，可能导致无结果、乱码或延迟异常。  
因此音频采集与帧格式对齐是第一阶段的核心技术风险。

### 13.3 输入框并发编辑

如果用户在录音过程中同时手动编辑输入框，partial / final 结果与手输内容之间可能出现竞争。  
第一版必须通过“草稿分层、final 再合并”的方式避免光标抖动和文本覆盖。

### 13.4 平台差异

Android 与 iOS 的录音会话、权限时机、后台行为不同。  
第一版先以 Android 作为主验证平台，不承诺一次性解决全部平台差异。

## 14. 交付物

第一阶段交付物包括：

- `speechInput` 配置模型与读取链路；
- `VoiceInputController`；
- `SpeechToTextService` 与阿里实现；
- `AliyunRealtimeAsrClient`；
- `AudioCaptureService`；
- `ChatInput` 麦克风按钮与草稿态 UI；
- 旧语音残留清理；
- 配置层 / 状态机 / 基础 UI 测试。

## 15. 推荐实施顺序

1. 清点并删除旧语音方案残留；
2. 为 `local_defaults.json` 扩展 `speechInput` 配置模型；
3. 实现 `VoiceInputController` 与 `SpeechToTextService` 抽象；
4. 接入阿里 WebSocket 实时识别客户端；
5. 接入录音能力并打通 Android 真机 PoC；
6. 把语音草稿态接入 `ChatInput`；
7. 补充自动化测试与手动回归；
8. 再评估是否需要接入火山作为第二 provider。

## 16. 最终结论

在不引入自建后端、继续沿用 `local_defaults.json` 注入运行时配置的前提下，  
**“阿里云 `Paraformer-realtime-v2` + 按住说话实时转写 + 松手回填输入框”** 是当前最合适的第一版语音输入方案。

它在产品形态、开发成本、月度免费额度和后续可扩展性之间取得了合理平衡，也与当前项目的配置体系和 Flutter 架构边界兼容。
