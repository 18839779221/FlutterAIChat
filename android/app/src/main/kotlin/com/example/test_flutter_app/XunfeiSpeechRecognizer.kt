package com.example.ai_chat

import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.iflytek.sparkchain.core.SparkChain
import com.iflytek.sparkchain.core.SparkChainConfig
import com.iflytek.sparkchain.core.asr.ASR
import com.iflytek.sparkchain.core.asr.AsrCallbacks
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread

class XunfeiSpeechRecognizer(
    private val context: Context,
    private val appId: String,
    private val flutterEngine: FlutterEngine
) {
    companion object {
        private const val TAG = "XunfeiSpeech"
        private const val CHANNEL_NAME = "xunfei_speech"
    }

    private val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var asr: ASR? = null
    private var audioRecord: AudioRecord? = null
    private var isRecording = false

    private val sampleRate = 16000
    private val channelConfig = AudioFormat.CHANNEL_IN_MONO
    private val audioFormat = AudioFormat.ENCODING_PCM_16BIT

    fun initialize(): Boolean {
        return try {
            Log.d(TAG, "Initializing SparkChain SDK...")
            // TODO: Move credentials to secure storage or environment variables
            // These should NOT be hardcoded in source code
            val config = SparkChainConfig.builder()
                .appID("8509c381")
                .apiKey("3194c81a8bac534cef9a8343570ce92d")
                .apiSecret("OTBmZTU5NTBhMjdkM2M2NzhmYThjYjJl")

            val ret = SparkChain.getInst().init(context, config)
            Log.d(TAG, "SparkChain init result: $ret")

            if (ret == 0) {
                asr = ASR()
                asr?.language("zh_cn")
                asr?.domain("iat")
                asr?.accent("mandarin")
                Log.d(TAG, "ASR configured successfully")
                true
            } else {
                Log.e(TAG, "SparkChain init failed with code: $ret")
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Initialize error: ${e.message}", e)
            false
        }
    }

    fun startListening() {
        Log.d(TAG, "Starting listening...")
        asr?.registerCallbacks(object : AsrCallbacks {
            override fun onResult(result: ASR.ASRResult?, userData: Any?) {
                Log.d(TAG, "onResult: ${result?.bestMatchText}")
                result?.let {
                    mainHandler.post {
                        channel.invokeMethod("onResult", it.bestMatchText)
                    }
                }
            }

            override fun onError(error: ASR.ASRError?, userData: Any?) {
                Log.e(TAG, "onError: code=${error?.code}, msg=${error?.errMsg}")
                stopListening()
                mainHandler.post {
                    channel.invokeMethod("onError", null)
                }
            }
        })

        val startRet = asr?.start(null)
        Log.d(TAG, "ASR start result: $startRet")

        startRecording()
    }

    private fun startRecording() {
        val bufferSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)
        audioRecord = AudioRecord(MediaRecorder.AudioSource.MIC, sampleRate, channelConfig, audioFormat, bufferSize)

        audioRecord?.startRecording()
        isRecording = true

        thread {
            val buffer = ByteArray(bufferSize)
            while (isRecording) {
                val read = audioRecord?.read(buffer, 0, buffer.size) ?: 0
                if (read > 0) {
                    asr?.write(buffer)
                }
            }
        }
    }

    fun stopListening() {
        Log.d(TAG, "Stopping listening...")
        isRecording = false
        audioRecord?.stop()
        audioRecord?.release()
        audioRecord = null
        asr?.stop(true)
    }
}
