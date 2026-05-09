package com.voicebubble.app

import android.util.Log
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
        try {
            // Make sure Flutter's native libraries are loaded before we
            // try to spin up an engine. FlutterLoader is the modern
            // replacement for the deprecated FlutterMain.
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(this)
            loader.ensureInitializationComplete(this, null)

            val engine = FlutterEngine(this)
            val entrypoint = DartExecutor.DartEntrypoint(
                loader.findAppBundlePath(),
                "bgEngineMain"
            )
            engine.dartExecutor.executeDartEntrypoint(entrypoint)
            FlutterEngineCache.getInstance().put(BG_ENGINE_ID, engine)
            Log.d(TAG, "Background Flutter engine warmed up (id=$BG_ENGINE_ID)")
        } catch (e: Throwable) {
            // Never crash app start over this. The bubble overlay flow
            // gracefully falls back to the Activity-bridge path.
            Log.e(TAG, "Failed to warm background engine", e)
        }
    }
}
