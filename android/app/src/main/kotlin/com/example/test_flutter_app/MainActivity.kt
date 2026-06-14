package com.example.ai_chat

import android.content.ContentValues
import android.content.ActivityNotFoundException
import android.content.Intent
import android.provider.AlarmClock
import android.provider.CalendarContract
import android.provider.MediaStore
import android.util.Log
import java.io.File
import java.io.FileInputStream
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            HOST_TOOLS_CHANNEL
        ).setMethodCallHandler { call, result ->
            if (call.method != "launchHostIntent") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val payload = call.arguments as? Map<*, *>
            val action = payload?.get("action") as? String
            val arguments = payload?.get("arguments") as? Map<*, *> ?: emptyMap<String, Any?>()
            Log.i(
                HOST_TOOLS_LOG_TAG,
                "launchHostIntent action=$action arguments=$arguments"
            )

            val launchResult = when (action) {
                "create_reminder" -> launchReminderIntent(arguments)
                "create_calendar_event" -> launchCalendarEventIntent(arguments)
                "save_image_to_gallery" -> saveImageToGallery(arguments)
                else -> mapOf(
                    "status" to "failed",
                    "message" to "unsupported_action"
                )
            }

            result.success(launchResult)
        }
    }

    private fun launchReminderIntent(arguments: Map<*, *>): Map<String, String> {
        val title = arguments["title"] as? String
            ?: return mapOf("status" to "failed", "message" to "missing_title")
        val hour = (arguments["hour"] as? Number)?.toInt()
            ?: return mapOf("status" to "failed", "message" to "missing_hour")
        val minutes = (arguments["minutes"] as? Number)?.toInt()
            ?: return mapOf("status" to "failed", "message" to "missing_minutes")

        val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
            putExtra(AlarmClock.EXTRA_MESSAGE, title)
            putExtra(AlarmClock.EXTRA_HOUR, hour)
            putExtra(AlarmClock.EXTRA_MINUTES, minutes)
            putExtra(AlarmClock.EXTRA_SKIP_UI, false)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        val alarmLaunchResult = launchIntent(intent)
        if (alarmLaunchResult["status"] == "launched") {
            return alarmLaunchResult
        }

        val dueAt = arguments["dueAt"] as? String
        val fallbackBeginTimeMillis = dueAt?.let(::parseIsoToMillis)
        if (fallbackBeginTimeMillis == null) {
            return alarmLaunchResult
        }

        val fallbackIntent = Intent(Intent.ACTION_INSERT).apply {
            data = CalendarContract.Events.CONTENT_URI
            putExtra(CalendarContract.Events.TITLE, title)
            putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, fallbackBeginTimeMillis)
            putExtra(
                CalendarContract.EXTRA_EVENT_END_TIME,
                fallbackBeginTimeMillis + REMINDER_FALLBACK_DURATION_MILLIS
            )
            (arguments["note"] as? String)?.let {
                putExtra(
                    CalendarContract.Events.DESCRIPTION,
                    "Reminder fallback\n$it"
                )
            }
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        val fallbackResult = launchIntent(fallbackIntent)
        if (fallbackResult["status"] == "launched") {
            return mapOf(
                "status" to "launched",
                "message" to "calendar_fallback_launched"
            )
        }

        return fallbackResult
    }

    private fun launchCalendarEventIntent(arguments: Map<*, *>): Map<String, String> {
        val title = arguments["title"] as? String
            ?: return mapOf("status" to "failed", "message" to "missing_title")
        val beginTimeMillis = (arguments["beginTimeMillis"] as? Number)?.toLong()
            ?: return mapOf("status" to "failed", "message" to "missing_begin_time")
        val endTimeMillis = (arguments["endTimeMillis"] as? Number)?.toLong()
            ?: return mapOf("status" to "failed", "message" to "missing_end_time")

        val intent = Intent(Intent.ACTION_INSERT).apply {
            data = CalendarContract.Events.CONTENT_URI
            putExtra(CalendarContract.Events.TITLE, title)
            putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, beginTimeMillis)
            putExtra(CalendarContract.EXTRA_EVENT_END_TIME, endTimeMillis)
            (arguments["location"] as? String)?.let {
                putExtra(CalendarContract.Events.EVENT_LOCATION, it)
            }
            (arguments["notes"] as? String)?.let {
                putExtra(CalendarContract.Events.DESCRIPTION, it)
            }
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        return launchIntent(intent)
    }

    private fun saveImageToGallery(arguments: Map<*, *>): Map<String, String> {
        val sourcePath = arguments["sourcePath"] as? String
            ?: return mapOf("status" to "failed", "message" to "missing_source_path")
        val fileName = arguments["fileName"] as? String
            ?: return mapOf("status" to "failed", "message" to "missing_file_name")
        val mimeType = arguments["mimeType"] as? String ?: "image/png"

        val sourceFile = File(sourcePath)
        if (!sourceFile.exists()) {
            return mapOf("status" to "failed", "message" to "source_file_missing")
        }

        return try {
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
                put(MediaStore.Images.Media.MIME_TYPE, mimeType)
            }

            val resolver = applicationContext.contentResolver
            val collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            val targetUri = resolver.insert(collection, values)
                ?: return mapOf("status" to "failed", "message" to "insert_failed")

            resolver.openOutputStream(targetUri)?.use { outputStream ->
                FileInputStream(sourceFile).use { inputStream ->
                    inputStream.copyTo(outputStream)
                }
            } ?: return mapOf("status" to "failed", "message" to "open_output_stream_failed")

            Log.i(
                HOST_TOOLS_LOG_TAG,
                "saveImageToGallery success source=$sourcePath target=$targetUri"
            )
            mapOf(
                "status" to "launched",
                "message" to "image_saved"
            )
        } catch (error: Exception) {
            Log.e(HOST_TOOLS_LOG_TAG, "saveImageToGallery failed source=$sourcePath", error)
            mapOf(
                "status" to "failed",
                "message" to (error.message ?: "gallery_save_failed")
            )
        }
    }

    private fun launchIntent(intent: Intent): Map<String, String> {
        return try {
            val resolved = intent.resolveActivity(packageManager)
            Log.i(
                HOST_TOOLS_LOG_TAG,
                "launchIntent action=${intent.action} resolved=${resolved?.flattenToShortString()} extras=${intent.extras}"
            )
            if (resolved == null) {
                return mapOf(
                    "status" to "unavailable",
                    "message" to "activity_not_resolved"
                )
            }
            startActivity(intent)
            Log.i(HOST_TOOLS_LOG_TAG, "launchIntent success action=${intent.action}")
            mapOf(
                "status" to "launched",
                "message" to "intent_launched"
            )
        } catch (error: ActivityNotFoundException) {
            Log.e(HOST_TOOLS_LOG_TAG, "launchIntent activity not found action=${intent.action}", error)
            mapOf(
                "status" to "unavailable",
                "message" to "activity_not_found"
            )
        } catch (error: Exception) {
            Log.e(HOST_TOOLS_LOG_TAG, "launchIntent failed action=${intent.action}", error)
            mapOf(
                "status" to "failed",
                "message" to (error.message ?: "intent_failed")
            )
        }
    }

    companion object {
        private const val HOST_TOOLS_CHANNEL = "ai_chat/host_tools"
        private const val HOST_TOOLS_LOG_TAG = "AIChatHostTools"
        private const val REMINDER_FALLBACK_DURATION_MILLIS = 30 * 60 * 1000L
    }
}

private fun parseIsoToMillis(rawValue: String): Long? {
    return try {
        java.time.OffsetDateTime.parse(rawValue).toInstant().toEpochMilli()
    } catch (_: Exception) {
        null
    }
}
