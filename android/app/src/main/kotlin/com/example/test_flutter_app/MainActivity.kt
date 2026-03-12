package com.example.ai_chat

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "xunfei_speech"
    }

    private var speechRecognizer: XunfeiSpeechRecognizer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    val appId = call.argument<String>("appId")
                    speechRecognizer = XunfeiSpeechRecognizer(this, appId ?: "", flutterEngine)
                    result.success(speechRecognizer?.initialize())
                }
                "startListening" -> {
                    speechRecognizer?.startListening()
                    result.success(null)
                }
                "stopListening" -> {
                    speechRecognizer?.stopListening()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
