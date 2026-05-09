package com.voicebubble.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "voicebubble/overlay"
    private val TAG = "MainActivity"

    // MethodChannel used ONLY to send messages TO Flutter
    private var methodChannel: MethodChannel? = null

    /**
     * Receiver that listens for bubble clicks from OverlayService.
     * When the bubble is tapped, OverlayService broadcasts "SHOW_FLUTTER_OVERLAY".
     */
    private val overlayReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "SHOW_FLUTTER_OVERLAY") {
                Log.d(TAG, "📨 Received SHOW_FLUTTER_OVERLAY broadcast")
                showFlutterOverlay()
            }
        }
    }

    /**
     * Flutter engine setup.
     * We register OverlayPlugin (which handles showOverlay/hideOverlay).
     * We ONLY create a MethodChannel to send *outgoing* messages ("triggerOverlay").
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Register native plugin that handles overlay service start/stop
        flutterEngine.plugins.add(OverlayPlugin())

        // Create a MethodChannel used ONLY for sending messages to Flutter
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )

        Log.d(TAG, "MainActivity configured. MethodChannel ready for 'triggerOverlay'.")
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Register broadcast receiver for bubble tap
        val filter = IntentFilter("SHOW_FLUTTER_OVERLAY")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(overlayReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(overlayReceiver, filter)
        }

        Log.d(TAG, "MainActivity created — overlayReceiver registered.")
        
        // Handle intent to show overlay
        handleIntent(intent)
    }
    
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }
    
    private fun handleIntent(intent: Intent?) {
        if (intent?.action == "SHOW_OVERLAY_POPUP") {
            Log.d(TAG, "📲 SHOW_OVERLAY_POPUP action received")
            DebugLog.log(this, "Bridge", "MainActivity got SHOW_OVERLAY_POPUP (fallback path)")
            showFlutterOverlay()

            // Move MainActivity to background so user stays in current app
            moveTaskToBack(true)
            Log.d(TAG, "✅ Overlay triggered, MainActivity moved to background")
            DebugLog.log(this, "Bridge", "MainActivity.moveTaskToBack(true) called")
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            unregisterReceiver(overlayReceiver)
        } catch (e: Exception) {
            Log.e(TAG, "Error unregistering overlayReceiver", e)
        }
    }

    /**
     * Show the Flutter overlay window (half-screen popup)
     */
    private fun showFlutterOverlay() {
        Log.d(TAG, "⚡ Showing Flutter overlay window...")

        try {
            // Use method channel to tell Flutter to show the overlay
            if (methodChannel != null) {
                methodChannel!!.invokeMethod("showOverlayWindow", null)
                Log.d(TAG, "✅ Method call sent to Flutter to show overlay")
            } else {
                Log.e(TAG, "❌ MethodChannel is null")
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error showing Flutter overlay window", e)
            e.printStackTrace()
        }
    }
}
