package com.voicebubble.app

import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class OverlayPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    
    private lateinit var overlayChannel: MethodChannel
    private var context: Context? = null
    private var activity: Activity? = null
    
    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        overlayChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "voicebubble/overlay")
        overlayChannel.setMethodCallHandler(this)
        
        context = flutterPluginBinding.applicationContext
    }
    
    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            // Overlay permission methods
            "checkPermission" -> {
                result.success(checkOverlayPermission())
            }
            "requestPermission" -> {
                requestOverlayPermission()
                result.success(null)
            }
            "showOverlay" -> {
                if (checkOverlayPermission()) {
                    context?.let { ctx ->
                        OverlayService.start(ctx)
                        // Save state for boot persistence
                        BootReceiver.setOverlayEnabled(ctx, true)
                        result.success(true)
                    } ?: result.success(false)
                } else {
                    result.success(false)
                }
            }
            "hideOverlay" -> {
                context?.let { ctx ->
                    OverlayService.stop(ctx)
                    // Save state for boot persistence
                    BootReceiver.setOverlayEnabled(ctx, false)
                    result.success(true)
                } ?: result.success(false)
            }
            "isActive" -> {
                result.success(isOverlayServiceRunning())
            }

            // Accessibility (text-injection) methods
            "isAccessibilityEnabled" -> {
                val ctx = context
                result.success(ctx != null && VoiceBubbleA11yService.isEnabled(ctx))
            }
            "openAccessibilitySettings" -> {
                context?.let { VoiceBubbleA11yService.openSettings(it) }
                result.success(null)
            }
            "injectText" -> {
                val text = call.argument<String>("text")
                if (text.isNullOrEmpty()) {
                    result.success(false)
                    return
                }
                val service = VoiceBubbleA11yService.getInstance()
                if (service == null) {
                    result.success(false)
                    return
                }
                result.success(service.setFocusedFieldText(text))
            }
            "getFocusedAppPackage" -> {
                result.success(VoiceBubbleA11yService.lastFocusedPackage)
            }

            else -> {
                result.notImplemented()
            }
        }
    }
    
    private fun checkOverlayPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(context)
        } else {
            true
        }
    }
    
    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:${context?.packageName}")
                )
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

                // Try activity first, fallback to context
                if (activity != null) {
                    activity?.startActivity(intent)
                } else {
                    context?.startActivity(intent)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }
    
    private fun isOverlayServiceRunning(): Boolean {
        val ctx = context ?: return false
        val manager = ctx.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        @Suppress("DEPRECATION")
        for (service in manager.getRunningServices(Int.MAX_VALUE)) {
            if (OverlayService::class.java.name == service.service.className) {
                return true
            }
        }
        return false
    }
    
    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        overlayChannel.setMethodCallHandler(null)
        context = null
    }
    
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }
    
    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }
    
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }
    
    override fun onDetachedFromActivity() {
        activity = null
    }
}
