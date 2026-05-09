package com.voicebubble.app

// IMPORTANT POLICY COMPLIANCE:
// This service ONLY shows a floating bubble overlay using TYPE_APPLICATION_OVERLAY.
// It does NOT use Accessibility APIs.
// It does NOT read screen content from other apps.
// It does NOT automatically insert text into other apps.
// It does NOT simulate user input or clicks.
// 
// User interaction flow:
// 1. User manually taps the floating bubble
// 2. App opens to record voice
// 3. User manually copies/shares the rewritten text
//
// This implementation complies with Google Play Store policies by:
// - Using ONLY SYSTEM_ALERT_WINDOW permission for the overlay
// - Using ONLY RECORD_AUDIO permission for voice recording
// - NOT requesting or using any Accessibility permissions
// - NOT reading or modifying content from other applications
// - Requiring explicit user interaction for all actions

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import android.content.BroadcastReceiver
import android.content.IntentFilter

class OverlayService : Service() {
    
    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var isOverlayVisible = false
    
    companion object {
        private const val TAG = "OverlayService"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "VoiceBubbleOverlay"
        
        fun start(context: Context) {
            try {
                val intent = Intent(context, OverlayService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                Log.d(TAG, "OverlayService start requested")
            } catch (e: Exception) {
                Log.e(TAG, "Error starting OverlayService", e)
            }
        }
        
        fun stop(context: Context) {
            try {
                val intent = Intent(context, OverlayService::class.java)
                context.stopService(intent)
                Log.d(TAG, "OverlayService stop requested")
            } catch (e: Exception) {
                Log.e(TAG, "Error stopping OverlayService", e)
            }
        }
    }
    
    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "OverlayService onCreate")
        
        try {
            // Create notification channel
            createNotificationChannel()
            
            // Start foreground service FIRST before creating overlay
            val notification = createNotification()
            startForeground(NOTIFICATION_ID, notification)
            Log.d(TAG, "Foreground service started")
            
            // Initialize window manager
            windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
            
            // Create and show overlay
            createOverlay()
        } catch (e: Exception) {
            Log.e(TAG, "Error in onCreate", e)
            stopSelf()
        }
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Voice Bubble",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Keeps the floating bubble active so you can quickly record and rewrite messages"
                    setShowBadge(false)
                }
                
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.createNotificationChannel(channel)
                Log.d(TAG, "Notification channel created")
            } catch (e: Exception) {
                Log.e(TAG, "Error creating notification channel", e)
            }
        }
    }
    
    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE
        )
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Voice Bubble Active")
            .setContentText("Floating bubble ready for quick voice recording")
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
    
    private fun createOverlay() {
        try {
            Log.d(TAG, "Creating overlay view...")
            
            // Create overlay view
            overlayView = createBubbleView()
            
            // Set up window parameters
            val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }
            
            val params = WindowManager.LayoutParams(
                dpToPx(36), // Fixed width: 36dp - slightly smaller than original 40dp
                dpToPx(36), // Fixed height: 36dp - perfect sweet spot!
                layoutType,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
                PixelFormat.TRANSLUCENT
            )
            
            // Position on LEFT side of screen, vertically centered
            params.gravity = Gravity.START or Gravity.CENTER_VERTICAL
            params.x = 0
            params.y = 0
            
            // Add view to window manager
            windowManager?.addView(overlayView, params)
            isOverlayVisible = true
            Log.d(TAG, "Overlay view added to window manager")
            
            // Set up touch listener for dragging
            setupDragListener(params)
        } catch (e: Exception) {
            Log.e(TAG, "Error creating overlay", e)
            // If overlay creation fails, stop the service
            stopSelf()
        }
    }
    
    private fun createBubbleView(): View {
        Log.d(TAG, "Creating bubble view...")
        
        // Create container - PERFECT SIZE bubble (36dp - slightly smaller than original 40dp)
        val container = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                dpToPx(36),
                dpToPx(36)
            )
        }
        
        try {
            // Just the logo — fills the entire bubble, no padding, no background
            val iconView = ImageView(this).apply {
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
                setImageResource(R.drawable.logo)
                scaleType = ImageView.ScaleType.FIT_CENTER
            }
            container.addView(iconView)
            
            // Set click listener — short tap pops the Flutter recording
            // overlay over whatever app the user is currently in. The
            // long-press path is wired up in setupDragListener (it uses
            // the same MainActivity intent but writes a flag first so
            // the overlay opens straight into preset selection).
            container.setOnClickListener {
                showRecordingOverlay(showPresets = false)
            }
            
            Log.d(TAG, "Bubble view created successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Error creating bubble view components", e)
        }
        
        return container
    }
    
    private fun dpToPx(dp: Int): Int {
        return (dp * resources.displayMetrics.density).toInt()
    }

    /**
     * Open MainActivity with the action that pops the Flutter recording
     * overlay. Optionally writes a SharedPreference flag the overlay
     * isolate reads on init so it can start in preset-selection mode
     * (driven by long-press on the bubble).
     */
    private fun showRecordingOverlay(showPresets: Boolean) {
        try {
            // Write into the same backing file the Dart `shared_preferences`
            // plugin reads from on Android (file name `FlutterSharedPreferences`,
            // keys prefixed with `flutter.`). The overlay isolate reads
            // `show_presets_on_open` on init to decide its initial phase.
            getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .edit()
                .putBoolean("flutter.show_presets_on_open", showPresets)
                .apply()

            val intent = Intent(this, MainActivity::class.java).apply {
                action = "SHOW_OVERLAY_POPUP"
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
            }
            startActivity(intent)
            Log.d(TAG, "Recording overlay requested (showPresets=$showPresets)")
        } catch (e: Exception) {
            Log.e(TAG, "Error showing recording overlay", e)
        }
    }

    private fun setupDragListener(params: WindowManager.LayoutParams) {
        var initialX = 0
        var initialY = 0
        var initialTouchX = 0f
        var initialTouchY = 0f
        var isMoved = false
        var longPressFired = false

        val handler = Handler(Looper.getMainLooper())
        val longPressRunnable = Runnable {
            if (!isMoved) {
                longPressFired = true
                Log.d(TAG, "Bubble long-press → preset fan")
                // Subtle haptic via the view itself so the user feels
                // the long-press register before the overlay paints.
                overlayView?.performHapticFeedback(
                    android.view.HapticFeedbackConstants.LONG_PRESS
                )
                showRecordingOverlay(showPresets = true)
            }
        }

        overlayView?.setOnTouchListener { view, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x
                    initialY = params.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    isMoved = false
                    longPressFired = false
                    handler.postDelayed(longPressRunnable, 400)
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val deltaX = Math.abs(event.rawX - initialTouchX)
                    val deltaY = Math.abs(event.rawY - initialTouchY)

                    if (deltaX > 10 || deltaY > 10) {
                        if (!isMoved) {
                            // First time we cross the drag threshold —
                            // cancel any pending long-press so we don't
                            // open the preset fan after a drag.
                            handler.removeCallbacks(longPressRunnable)
                        }
                        isMoved = true
                        params.x = initialX + (event.rawX - initialTouchX).toInt()
                        params.y = initialY + (event.rawY - initialTouchY).toInt()
                        try {
                            windowManager?.updateViewLayout(overlayView, params)
                        } catch (e: Exception) {
                            Log.e(TAG, "Error updating view layout", e)
                        }
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    handler.removeCallbacks(longPressRunnable)
                    if (!isMoved && !longPressFired) {
                        // Plain tap — let the click listener fire.
                        view.performClick()
                    }
                    false
                }
                MotionEvent.ACTION_CANCEL -> {
                    handler.removeCallbacks(longPressRunnable)
                    false
                }
                else -> false
            }
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "OverlayService onDestroy")
        
        // Remove overlay view
        try {
            if (overlayView != null && isOverlayVisible) {
                windowManager?.removeView(overlayView)
                overlayView = null
                isOverlayVisible = false
                Log.d(TAG, "Overlay view removed")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error removing overlay view", e)
        }
    }
    
    override fun onBind(intent: Intent?): IBinder? {
        return null
    }
}
