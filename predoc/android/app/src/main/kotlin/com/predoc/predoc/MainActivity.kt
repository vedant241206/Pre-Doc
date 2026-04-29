package com.predoc.predoc

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar

class MainActivity : FlutterActivity() {

    private val CHANNEL       = "predoc/usage_stats"
    private val AUDIO_CHANNEL = "predoc/continuous_audio"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Usage-stats channel (Day 7 — unchanged) ──────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isUsageStatsGranted" -> {
                        result.success(isUsageStatsGranted())
                    }
                    "getTodayScreenTime" -> {
                        if (!isUsageStatsGranted()) {
                            result.success(-1)
                        } else {
                            result.success(getTodayScreenTimeMinutes())
                        }
                    }
                    "getNightUsage" -> {
                        if (!isUsageStatsGranted()) {
                            result.success(-1)
                        } else {
                            result.success(getNightUsageMinutes())
                        }
                    }
                    "getLast7DaysNightUsage" -> {
                        if (!isUsageStatsGranted()) {
                            result.success(listOf<Int>())
                        } else {
                            result.success(getLast7DaysNightUsage())
                        }
                    }
                    "openUsageSettings" -> {
                        try {
                            val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Continuous audio foreground-service channel (Day 8) ──────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startForeground" -> {
                        try {
                            val intent = Intent(
                                this,
                                ContinuousAudioForegroundService::class.java
                            )
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("START_FAILED", e.message, null)
                        }
                    }
                    "stopForeground" -> {
                        try {
                            val intent = Intent(
                                this,
                                ContinuousAudioForegroundService::class.java
                            )
                            stopService(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("STOP_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ── Check if PACKAGE_USAGE_STATS is granted ──────────────────────
    private fun isUsageStatsGranted(): Boolean {
        return try {
            val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    packageName
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    packageName
                )
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            false
        }
    }

    // ── Total screen time today (minutes) ────────────────────────────
    private fun getTodayScreenTimeMinutes(): Int {
        return try {
            val usageStatsManager =
                getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager

            val cal = Calendar.getInstance()
            cal.set(Calendar.HOUR_OF_DAY, 0)
            cal.set(Calendar.MINUTE, 0)
            cal.set(Calendar.SECOND, 0)
            cal.set(Calendar.MILLISECOND, 0)
            val startOfDay = cal.timeInMillis
            val now = System.currentTimeMillis()

            val stats = usageStatsManager.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY, startOfDay, now
            )

            val totalMs = stats?.sumOf { it.totalTimeInForeground } ?: 0L
            (totalMs / 1000 / 60).toInt()
        } catch (e: Exception) {
            0
        }
    }

    // ── Night usage today (22:00–05:00) in minutes ───────────────────
    private fun getNightUsageMinutes(): Int {
        return try {
            val usageStatsManager =
                getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager

            val now = System.currentTimeMillis()
            val cal = Calendar.getInstance()

            // Night window: yesterday 22:00 → today 05:00
            // We query last 8 hours to capture late-night usage generously
            val eightHoursAgo = now - 8 * 60 * 60 * 1000L

            // Build today's 22:00 start
            cal.set(Calendar.HOUR_OF_DAY, 22)
            cal.set(Calendar.MINUTE, 0)
            cal.set(Calendar.SECOND, 0)
            cal.set(Calendar.MILLISECOND, 0)
            val todayNightStart = cal.timeInMillis

            // Night window start: use whichever is earlier (yesterday 22:00 or 8h ago)
            val nightStart = if (todayNightStart > now) {
                // It's before 22:00 today — use yesterday 22:00
                todayNightStart - 24 * 60 * 60 * 1000L
            } else {
                todayNightStart
            }

            // Night window end: today 05:00
            cal.set(Calendar.HOUR_OF_DAY, 5)
            val todayMorningEnd = cal.timeInMillis

            val windowStart = nightStart
            val windowEnd = minOf(now, todayMorningEnd + 24 * 60 * 60 * 1000L)

            val stats = usageStatsManager.queryUsageStats(
                UsageStatsManager.INTERVAL_BEST, windowStart, windowEnd
            )

            val totalMs = stats?.sumOf { it.totalTimeInForeground } ?: 0L
            (totalMs / 1000 / 60).toInt()
        } catch (e: Exception) {
            0
        }
    }

    // ── Last 7 days night usage (list of 7 ints, oldest first) ───────
    private fun getLast7DaysNightUsage(): List<Int> {
        val result = mutableListOf<Int>()
        try {
            val usageStatsManager =
                getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val cal = Calendar.getInstance()

            for (i in 6 downTo 0) {
                // Night window for day (i days ago): 22:00 of that day → 05:00 next day
                val dayAgo = Calendar.getInstance()
                dayAgo.add(Calendar.DAY_OF_YEAR, -i)
                dayAgo.set(Calendar.HOUR_OF_DAY, 22)
                dayAgo.set(Calendar.MINUTE, 0)
                dayAgo.set(Calendar.SECOND, 0)
                dayAgo.set(Calendar.MILLISECOND, 0)
                val nightStart = dayAgo.timeInMillis

                val morningEnd = Calendar.getInstance()
                morningEnd.add(Calendar.DAY_OF_YEAR, -i + 1)
                morningEnd.set(Calendar.HOUR_OF_DAY, 5)
                morningEnd.set(Calendar.MINUTE, 0)
                morningEnd.set(Calendar.SECOND, 0)
                morningEnd.set(Calendar.MILLISECOND, 0)
                val nightEnd = minOf(morningEnd.timeInMillis, System.currentTimeMillis())

                if (nightStart >= nightEnd) {
                    result.add(0)
                    continue
                }

                val stats = usageStatsManager.queryUsageStats(
                    UsageStatsManager.INTERVAL_BEST, nightStart, nightEnd
                )
                val totalMs = stats?.sumOf { it.totalTimeInForeground } ?: 0L
                result.add((totalMs / 1000 / 60).toInt())
            }
        } catch (e: Exception) {
            repeat(7) { result.add(0) }
        }
        return result
    }
}
