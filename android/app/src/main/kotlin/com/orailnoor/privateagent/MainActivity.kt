package com.orailnoor.privateagent

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.graphics.PixelFormat
import android.graphics.Color
import android.view.Gravity
import android.view.WindowManager
import android.view.View
import android.widget.Button
import android.net.Uri
import android.media.AudioRecord
import android.media.AudioFormat
import android.media.MediaRecorder
import android.media.AudioTrack
import android.media.AudioAttributes
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.privateagent/accessibility"
    private val EVENT_CHANNEL = "com.privateagent/accessibility_events"
    private var eventSink: EventChannel.EventSink? = null
    private var overlayView: View? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    AgentAccessibilityService.eventListener = { eventMap ->
                        runOnUiThread {
                            eventSink?.success(eventMap)
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    AgentAccessibilityService.eventListener = null
                }
            }
        )

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_STREAM_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    audioEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    audioEventSink = null
                }
            }
        )

        registerAccessibilityChannel(flutterEngine, this)
    }

    companion object {
        private val AUDIO_STREAM_CHANNEL = "com.privateagent/audio_stream"
        private var audioEventSink: EventChannel.EventSink? = null
        private var audioRecord: AudioRecord? = null
        @Volatile private var isRecording = false

        // Persistent PCM player used for live voice responses (and Kokoro TTS clips).
        private val pcmQueue = LinkedBlockingQueue<ByteArray>()
        private var pcmPlayerThread: Thread? = null
        private var pcmAudioTrack: AudioTrack? = null
        @Volatile private var isPcmPlayerActive = false
        @Volatile private var currentPcmSampleRate = 24000

        fun registerAccessibilityChannel(flutterEngine: FlutterEngine, context: android.content.Context) {
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.privateagent/accessibility")
                .setMethodCallHandler { call, result ->
                    android.util.Log.d("MobileUseKotlin", "Received method call: ${call.method}")
                    when (call.method) {
                        "ping" -> result.success(true)

                        "logToNative" -> {
                            val msg = call.argument<String>("message") ?: ""
                            android.util.Log.d("MobileUseDart", msg)
                            result.success(true)
                        }

                        "isServiceRunning" -> {
                            result.success(AgentAccessibilityService.isRunning())
                        }

                        "checkOverlayPermission" -> {
                            result.success(Settings.canDrawOverlays(context))
                        }

                        "requestOverlayPermission" -> {
                            val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${context.packageName}"))
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            context.startActivity(intent)
                            result.success(true)
                        }

                        "showMacroOverlay" -> {
                            result.error("NOT_SUPPORTED", "Macro overlay not supported from background", null)
                        }

                        "hideMacroOverlay" -> {
                            result.success(true)
                        }

                        "openAccessibilitySettings" -> {
                            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            context.startActivity(intent)
                            result.success(true)
                        }

                        "dumpScreen" -> {
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                val nodes = service.dumpScreen()
                                result.success(nodes)
                            }
                        }

                        "takeScreenshot" -> {
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                                    service.takeScreenshot { base64 ->
                                        if (base64 != null) {
                                            result.success(base64)
                                        } else {
                                            result.error("SCREENSHOT_FAILED", "Failed to capture screenshot", null)
                                        }
                                    }
                                } else {
                                    result.error("UNSUPPORTED_VERSION", "Screenshot requires Android 11 (API 30) or higher", null)
                                }
                            }
                        }

                        "clickByText" -> {
                            val text = call.argument<String>("text") ?: ""
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                result.success(service.clickByText(text))
                            }
                        }

                        "clickAt" -> {
                            val x = call.argument<Double>("x")?.toFloat() ?: 0f
                            val y = call.argument<Double>("y")?.toFloat() ?: 0f
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                result.success(service.clickAtCoordinates(x, y))
                            }
                        }

                        "typeText" -> {
                            val text = call.argument<String>("text") ?: ""
                            val hint = call.argument<String>("fieldHint")
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                result.success(service.typeText(text, hint))
                            }
                        }

                        "pressEnter" -> {
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                result.success(service.pressEnter())
                            }
                        }

                        "scroll" -> {
                            val direction = call.argument<String>("direction") ?: "down"
                            val target = call.argument<String>("target")
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                result.success(service.scroll(direction, target))
                            }
                        }

                        "showToast" -> {
                            val message = call.argument<String>("message") ?: ""
                            android.widget.Toast.makeText(context, message, android.widget.Toast.LENGTH_SHORT).show()
                            result.success(true)
                        }

                        "swipe" -> {
                            val startX = call.argument<Double>("startX")?.toFloat() ?: 0f
                            val startY = call.argument<Double>("startY")?.toFloat() ?: 0f
                            val endX = call.argument<Double>("endX")?.toFloat() ?: 0f
                            val endY = call.argument<Double>("endY")?.toFloat() ?: 0f
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                result.success(service.swipe(startX, startY, endX, endY))
                            }
                        }

                        "pressBack" -> {
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                result.success(service.pressBack())
                            }
                        }

                        "pressHome" -> {
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                result.success(service.pressHome())
                            }
                        }

                        "openNotifications" -> {
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                result.success(service.openNotifications())
                            }
                        }

                        "getCurrentPackage" -> {
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                result.success(service.getCurrentPackage())
                            }
                        }

                        "startRecording" -> {
                            val sampleRate = call.argument<Int>("sampleRate") ?: 16000
                            try {
                                val bufferSize = AudioRecord.getMinBufferSize(
                                    sampleRate,
                                    AudioFormat.CHANNEL_IN_MONO,
                                    AudioFormat.ENCODING_PCM_16BIT
                                )
                                audioRecord = AudioRecord(
                                    MediaRecorder.AudioSource.MIC,
                                    sampleRate,
                                    AudioFormat.CHANNEL_IN_MONO,
                                    AudioFormat.ENCODING_PCM_16BIT,
                                    bufferSize * 2
                                )
                                audioRecord?.startRecording()
                                isRecording = true
                                val buf = ByteArray(bufferSize)
                                Thread {
                                    android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_URGENT_AUDIO)
                                    while (isRecording) {
                                        val read = audioRecord?.read(buf, 0, buf.size) ?: -1
                                        if (read > 0) {
                                            val chunk = java.util.Arrays.copyOf(buf, read)
                                            val b64 = android.util.Base64.encodeToString(chunk, android.util.Base64.NO_WRAP)
                                            audioEventSink?.success(b64)
                                        }
                                    }
                                }.start()
                                result.success(true)
                            } catch (e: Exception) {
                                android.util.Log.e("MobileUseAgent", "startRecording error: ${e.message}")
                                result.error("RECORD_ERROR", e.message, null)
                            }
                        }

                        "stopRecording" -> {
                            isRecording = false
                            try {
                                audioRecord?.stop()
                            } catch (_: Exception) {}
                            audioRecord?.release()
                            audioRecord = null
                            result.success(true)
                        }

                        "playPcmAudio" -> {
                            val base64Data = call.argument<String>("data") ?: ""
                            try {
                                val pcmBytes = android.util.Base64.decode(base64Data, android.util.Base64.DEFAULT)
                                val sampleRate = call.argument<Int>("sampleRate") ?: 24000
                                playPcmChunk(pcmBytes, sampleRate)
                                result.success(true)
                            } catch (e: Exception) {
                                android.util.Log.e("MobileUseAgent", "playPcmAudio error: ${e.message}")
                                result.error("AUDIO_ERROR", e.message, null)
                            }
                        }

                        "stopPcmAudio" -> {
                            stopPcmPlayer()
                            result.success(true)
                        }

                        else -> result.notImplemented()
                    }
                }
        }

        private fun playPcmChunk(chunk: ByteArray, sampleRate: Int) {
            if (pcmAudioTrack == null || currentPcmSampleRate != sampleRate) {
                stopPcmPlayer()
                currentPcmSampleRate = sampleRate
                val bufferSize = AudioTrack.getMinBufferSize(
                    sampleRate,
                    AudioFormat.CHANNEL_OUT_MONO,
                    AudioFormat.ENCODING_PCM_16BIT
                )
                pcmAudioTrack = AudioTrack(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build(),
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(sampleRate)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build(),
                    bufferSize.coerceAtLeast(4096),
                    AudioTrack.MODE_STREAM,
                    0
                )
                pcmAudioTrack?.play()
                startPcmPlayerThread()
            }
            pcmQueue.offer(chunk)
        }

        private fun startPcmPlayerThread() {
            if (pcmPlayerThread?.isAlive == true) return
            isPcmPlayerActive = true
            pcmPlayerThread = Thread {
                android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_URGENT_AUDIO)
                while (isPcmPlayerActive) {
                    try {
                        val chunk = pcmQueue.poll(50, TimeUnit.MILLISECONDS)
                        if (chunk != null) {
                            pcmAudioTrack?.write(chunk, 0, chunk.size)
                        }
                    } catch (e: Exception) {
                        android.util.Log.e("MobileUseAgent", "PCM player thread error: ${e.message}")
                    }
                }
            }.apply { start() }
        }

        private fun stopPcmPlayer() {
            isPcmPlayerActive = false
            pcmQueue.clear()
            pcmPlayerThread?.interrupt()
            pcmPlayerThread = null
            pcmAudioTrack?.apply {
                try { stop() } catch (_: Exception) {}
                flush()
                release()
            }
            pcmAudioTrack = null
        }
    }
}

class BackgroundEngineReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: android.content.Context, intent: android.content.Intent) {
        val engine = io.flutter.embedding.engine.FlutterEngineCache
            .getInstance()
            .get("myCachedEngine")
        if (engine == null) {
            android.util.Log.e("MobileUse Agent", "Background engine myCachedEngine was not found")
            return
        }

        android.util.Log.d(
            "MobileUse Agent",
            "Registering accessibility channel on myCachedEngine " +
                "(engine=${System.identityHashCode(engine)}, " +
                "dartExecuting=${engine.dartExecutor.isExecutingDart})"
        )
        MainActivity.registerAccessibilityChannel(engine, context.applicationContext)
    }
}
