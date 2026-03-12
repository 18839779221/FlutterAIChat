# 讯飞 SparkChain 语音集成说明

## 1. 下载 SparkChain SDK

访问 https://www.xfyun.cn/doc/asr/voicedictation/SparkChain-Android-SDK.html
- 下载 SparkChain Android SDK
- 解压后将 `SparkChain.aar` 文件放入 `android/app/libs/` 目录

## 2. 获取应用信息

- 登录讯飞开放平台 https://console.xfyun.cn/
- 创建应用获取 AppID、APIKey、APISecret
- 在 `android/app/src/main/kotlin/com/example/test_flutter_app/XunfeiSpeechRecognizer.kt` 中替换：
  - 第 20 行：`YOUR_API_KEY`
  - 第 21 行：`YOUR_API_SECRET`
- 在 `lib/services/speech/xunfei_speech_service.dart` 中替换：
  - 第 14 行：`请替换为你的讯飞AppID`

## 3. 配置权限

已在 `AndroidManifest.xml` 中添加必要权限（录音、网络、存储等）

## 4. 切换到讯飞语音

在 `lib/providers/speech_providers.dart` 中修改：

```dart
final speechServiceProvider = Provider<SpeechService>((ref) {
  return XunfeiSpeechService(); // 使用讯飞
  // return SpeechToTextService(); // 使用系统语音
});
```

## 5. 测试

```bash
fvm flutter run
```

点击麦克风按钮即可使用讯飞语音识别。

## 注意事项

- SparkChain SDK 支持 Android 5.0 及以上版本
- 需要 armv7 或 armv8 架构
- 确保 `android/app/libs/` 目录存在且有读写权限

