package com.f.s.f_stopwatch

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 建立 Dart ⇆ 原生 的双向通道，并转发悬浮窗按钮事件到 Dart。
 */
object OverlayController {
    private const val METHOD = "com.f_stopwatch/overlay"
    private const val EVENT = "com.f_stopwatch/overlay/buttons"

    private var eventSink: EventChannel.EventSink? = null

    fun configure(engine: FlutterEngine, ctx: Context) {
        val messenger = engine.dartExecutor.binaryMessenger

        MethodChannel(messenger, METHOD).setMethodCallHandler { call, result ->
            handleMethodCall(call, result, ctx)
        }

        EventChannel(messenger, EVENT).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                eventSink = sink
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    /** 悬浮窗按钮点击 → 推送给 Dart。 */
    fun emitButton(action: String) {
        eventSink?.success(action)
    }

    private fun handleMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
        ctx: Context
    ) {
        when (call.method) {
            "startForeground" -> {
                if (Settings.canDrawOverlays(ctx)) {
                    OverlayService.start(ctx)
                    result.success(true)
                } else {
                    result.success(false)
                }
            }

            "stopForeground" -> {
                OverlayService.stop(ctx)
                result.success(null)
            }

            "updateTotal" -> {
                OverlayService.updateTotal(call.arguments as? String ?: "")
                result.success(null)
            }

            "updateSecondary" -> {
                OverlayService.updateSecondary(call.arguments as? String ?: "")
                result.success(null)
            }

            "updateRunning" -> {
                OverlayService.updateRunning(call.arguments as? Boolean ?: true)
                result.success(null)
            }

            "updateConfig" -> {
                val m = call.arguments as? Map<*, *>
                val fontColor = (m?.get("fontColor") as? Number)?.toInt() ?: -0x1
                val sizeScaleOffset = (m?.get("sizeScale") as? Number)?.toFloat() ?: 1f
                val bgAlpha = (m?.get("bgAlpha") as? Number)?.toInt() ?: 200
                OverlayService.updateConfig(fontColor, sizeScaleOffset, bgAlpha)
                result.success(null)
            }

            "resetPosition" -> {
                OverlayService.resetPosition()
                result.success(null)
            }

            "updateLaps" -> {
                val raw = call.arguments as? List<*> ?: emptyList<Any>()
                OverlayService.updateLaps(raw.map { it.toString() })
                result.success(null)
            }

            "isOverlayActive" -> result.success(OverlayService.isAlive())

            "hasOverlayPermission" -> result.success(Settings.canDrawOverlays(ctx))

            "requestOverlayPermission" -> {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:${ctx.packageName}")
                )
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                ctx.startActivity(intent)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }
}