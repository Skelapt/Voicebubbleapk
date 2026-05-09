package com.voicebubble.app

import android.util.Log
import flutter.overlay.window.flutter_overlay_window.FlutterOverlayWindowPlugin
import io.flutter.FlutterInjector
import io.flutter.app.FlutterApplication
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Custom Application that pre-warms a cached background Flutter engine.
 *
 * This engine runs the lightweight `bgEngineMain` Dart entry point —
 * just enough to keep the isolate alive with all pubspec plugins
 * auto-registered. It exists so the bubble's [OverlayService] can
 * invoke `showOverlay` on the `flutter_overlay_window` plugin's method
 * channel **directly from the bubble's onClick handler**, with no
 * Activity ever being summoned to foreground. That's what kills the
 * "MainActivity flashes for a frame when you tap the bubble" bug.
 *
 * The engine lives for the lifetime of the process. Memory cost is
 * acceptable (~20–30 MB) — same order as a notification listener
 * service or a music app's playback engine.
 */
class MyApplication : FlutterApplication() {

    companion object {
        private const val TAG = "MyApplication"
        const val BG_ENGINE_ID = "voicebubble_bg_engine"
    }

    override fun onCreate() {
        super.onCreate()
        DebugLog.log(this, "App", "MyApplication.onCreate — process started")
        try {
            // Make sure Flutter's native libraries are loaded before we
            // try to spin up an engine. FlutterLoader is the modern
            // replacement for the deprecated FlutterMain.
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(this)
            loader.ensureInitializationComplete(this, null)
            DebugLog.log(this, "App", "FlutterLoader init complete")

            // Disable the implicit reflective plugin registration —
            // GeneratedPluginRegistrant.registerWith() pulls in EVERY
            // pubspec plugin, and at least one of them
            // (super_native_extensions) throws NoClassDefFoundError on
            // engines created outside of a FlutterActivity, which
            // nukes the whole engine warm-up. Build the engine without
            // auto-registration so we control exactly which plugins
            // attach.
            val engine = FlutterEngine(
                /* context = */ this,
                /* dartVmArgs = */ null,
                /* automaticallyRegisterPlugins = */ false
            )
            DebugLog.log(this, "App", "FlutterEngine constructed (no auto-register)")

            // The bg engine only needs flutter_overlay_window's plugin
            // attached — that's the only channel
            // (`x-slayer/overlay_channel`) we invoke from native code
            // when the bubble is tapped. Registering it explicitly
            // avoids the noise + side effects of all the other
            // plugins (Firebase, IAP, ML Kit, Hive, etc.) that have
            // no business running on a background engine.
            try {
                engine.plugins.add(FlutterOverlayWindowPlugin())
                DebugLog.log(
                    this,
                    "App",
                    "FlutterOverlayWindowPlugin attached to bg engine"
                )
            } catch (e: Throwable) {
                DebugLog.log(
                    this,
                    "App",
                    "FlutterOverlayWindowPlugin attach FAILED: ${e.javaClass.simpleName} ${e.message}"
                )
            }

            val entrypoint = DartExecutor.DartEntrypoint(
                loader.findAppBundlePath(),
                "bgEngineMain"
            )
            engine.dartExecutor.executeDartEntrypoint(entrypoint)
            FlutterEngineCache.getInstance().put(BG_ENGINE_ID, engine)
            Log.d(TAG, "Background Flutter engine warmed up (id=$BG_ENGINE_ID)")
            DebugLog.log(
                this,
                "App",
                "BG engine warm + cached as '$BG_ENGINE_ID'"
            )
        } catch (e: Throwable) {
            Log.e(TAG, "Failed to warm background engine", e)
            DebugLog.log(
                this,
                "App",
                "BG engine warm-up FAILED: ${e.javaClass.simpleName} ${e.message}"
            )
        }
    }
}
