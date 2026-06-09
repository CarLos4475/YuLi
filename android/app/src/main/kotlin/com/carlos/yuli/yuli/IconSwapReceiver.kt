package com.carlos.yuli.yuli

import android.app.ActivityManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager

class IconSwapReceiver : BroadcastReceiver() {
    private val prefsName = "yuli_launcher_prefs"
    private val kAutoMode = "auto_mode"
    private val kManualOverride = "manual_override"
    private val launcherAliases = mapOf(
        "icon1" to ".LauncherIcon1",
        "icon2" to ".LauncherIcon2",
        "icon3" to ".LauncherIcon3",
    )
    private val deferIfForegroundMs = 5 * 60 * 1000L

    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        try {
            val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            if (isMainProcessForeground(context)) {
                IconSwapScheduler(context).scheduleBoundaryAt(
                    System.currentTimeMillis() + deferIfForegroundMs
                )
                return
            }
            val current = currentLauncherIcon(context)
            val target = targetIconId(prefs)
            if (current != target) {
                applyIcon(context, target)
            }
            if (prefs.getBoolean(kAutoMode, true)) {
                rescheduleNext(context)
            }
        } finally {
            pending.finish()
        }
    }

    @Suppress("DEPRECATION")
    private fun isMainProcessForeground(context: Context): Boolean {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val mainProcessName = context.packageName
        val procs = am.getRunningAppProcesses() ?: return false
        return procs.any { proc ->
            proc.processName == mainProcessName &&
                (proc.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND ||
                    proc.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND_SERVICE ||
                    proc.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_VISIBLE)
        }
    }

    private fun currentLauncherIcon(context: Context): String {
        launcherAliases.forEach { (iconId, aliasName) ->
            val state = context.packageManager.getComponentEnabledSetting(
                ComponentName(context, "${context.packageName}$aliasName")
            )
            val enabled = when (state) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
                PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> iconId == "icon1"
                else -> false
            }
            if (enabled) return iconId
        }
        return "icon1"
    }

    private fun targetIconId(prefs: SharedPreferences): String {
        if (!prefs.getBoolean(kAutoMode, true)) {
            return prefs.getString(kManualOverride, null) ?: "icon1"
        }
        val manual = prefs.getString(kManualOverride, null)
        if (manual != null) return manual
        val cal = java.util.Calendar.getInstance()
        val bucket = (cal.get(java.util.Calendar.HOUR_OF_DAY) / 4) % 3
        return when (bucket) {
            0 -> "icon1"
            1 -> "icon2"
            else -> "icon3"
        }
    }

    private fun applyIcon(context: Context, iconId: String) {
        val activeAlias = launcherAliases.getValue(iconId)
        setAliasEnabled(context, activeAlias, true)
        launcherAliases.values
            .filter { it != activeAlias }
            .forEach { setAliasEnabled(context, it, false) }
    }

    private fun setAliasEnabled(context: Context, aliasName: String, enabled: Boolean) {
        val state = if (enabled) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        } else {
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        }
        context.packageManager.setComponentEnabledSetting(
            ComponentName(context, "${context.packageName}$aliasName"),
            state,
            PackageManager.DONT_KILL_APP,
        )
    }

    private fun rescheduleNext(context: Context) {
        val cal = java.util.Calendar.getInstance()
        val nowMs = cal.timeInMillis
        val today = java.util.Calendar.getInstance().apply {
            set(java.util.Calendar.HOUR_OF_DAY, 0)
            set(java.util.Calendar.MINUTE, 0)
            set(java.util.Calendar.SECOND, 0)
            set(java.util.Calendar.MILLISECOND, 0)
        }
        val candidates = intArrayOf(0, 4, 8, 12, 16, 20)
        var nextMs: Long = -1
        for (h in candidates) {
            val c = today.clone() as java.util.Calendar
            c.set(java.util.Calendar.HOUR_OF_DAY, h)
            if (c.timeInMillis > nowMs) {
                nextMs = c.timeInMillis
                break
            }
        }
        if (nextMs < 0) {
            val tomorrow = (today.clone() as java.util.Calendar).apply {
                add(java.util.Calendar.DAY_OF_YEAR, 1)
            }
            tomorrow.set(java.util.Calendar.HOUR_OF_DAY, 0)
            nextMs = tomorrow.timeInMillis
        }
        IconSwapScheduler(context).scheduleBoundaryAt(nextMs)
    }
}

