package com.predoc.predoc

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/**
 * ContinuousAudioForegroundService
 *
 * A minimal Android foreground service whose sole purpose is to:
 *   1. Keep the app alive in the background (foreground service rules)
 *   2. Display a persistent notification so the user is always aware
 *      that the microphone is in use.
 *
 * The actual mic recording and YAMNet inference run on the Flutter/Dart side
 * via the `record` plugin — this service only provides the Android lifecycle
 * anchor and the required notification.
 *
 * SAFETY:
 *   • Notification is ALWAYS visible while service is running.
 *   • Service stops itself when Flutter calls stopForeground() via the channel.
 *   • No audio data is processed or stored here.
 */
class ContinuousAudioForegroundService : Service() {

    companion object {
        const val CHANNEL_ID   = "predoc_live_monitoring"
        const val NOTIF_ID     = 1001
        const val ACTION_STOP  = "predoc.action.STOP_MONITORING"
    }

    private var wakeLock: PowerManager.WakeLock? = null

    // ── onCreate ─────────────────────────────────────────────
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIF_ID, buildNotification())
        acquireWakeLock()
    }

    // ── onStartCommand ───────────────────────────────────────
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        // Recreate notification so it's always fresh
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIF_ID, buildNotification())
        return START_STICKY   // restart automatically if killed
    }

    // ── onDestroy ────────────────────────────────────────────
    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ── Notification ─────────────────────────────────────────

    private fun buildNotification(): Notification {
        // Tapping the notification brings the app to the foreground
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?.apply { flags = Intent.FLAG_ACTIVITY_SINGLE_TOP }

        val contentPendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // "Stop" action in the notification shade
        val stopIntent = Intent(this, ContinuousAudioForegroundService::class.java)
            .apply { action = ACTION_STOP }
        val stopPending = PendingIntent.getService(
            this, 1, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("Predoc – Live Health Monitoring")
            .setContentText("Predoc is actively monitoring your health (audio)")
            .setSubText("All data stays on your device")
            .setOngoing(true)          // non-dismissible
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setContentIntent(contentPendingIntent)
            .addAction(
                android.R.drawable.ic_media_pause,
                "Stop Monitoring",
                stopPending
            )
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Live Health Monitoring",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shown while Predoc actively monitors health audio signals."
                setShowBadge(false)
                setSound(null, null)
                enableLights(false)
                enableVibration(false)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    // ── Wake lock (keeps CPU alive for mic + inference) ──────

    private fun acquireWakeLock() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "predoc:ContinuousAudio"
        ).also {
            it.acquire(4 * 60 * 60 * 1000L) // max 4 hours safety cap
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }
}
