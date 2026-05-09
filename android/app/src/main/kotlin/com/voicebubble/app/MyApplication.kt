package com.voicebubble.app

import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.app.FlutterApplication
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugins.GeneratedPluginRegistrant

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

            val engine = FlutterEngine(this)
            DebugLog.log(this, "App", "FlutterEngine constructed")

            // CRITICAL: the FlutterEngine constructor's reflective
            // auto-registration of plugins is unreliable on engines
            // created outside of FlutterActivity. Without this explicit
            // call, flutter_overlay_window's MethodCallHandler doesn't
            // attach to this engine, and any `showOverlay` invocation
            // comes back as `notImplemented`. This was THE bug — every
            // bubble tap fired but the plugin never received it.
            GeneratedPluginRegistrant.registerWith(engine)
            DebugLog.log(
                this,
                "App",
                "GeneratedPluginRegistrant.registerWith called → plugins attached"
            )

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
