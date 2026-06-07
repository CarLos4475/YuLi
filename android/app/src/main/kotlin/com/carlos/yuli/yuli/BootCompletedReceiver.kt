package com.carlos.yuli.yuli

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import java.util.Calendar

class BootCompletedReceiver : BroadcastReceiver() {
    private val prefsName = "yuli_launcher_prefs"
    private val kAutoMode = "auto_mode"

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != Intent.ACTION_MY_PACKAGE_REPLACED &&
            intent.action != "android.intent.action.QUICKBOOT_POWERON"
        ) return

        val prefs: SharedPreferences = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(kAutoMode, true)) return

        val cal = Calendar.getInstance()
        val nowMs = cal.timeInMillis
        val today = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val candidates = intArrayOf(6, 12, 18)
        var nextMs: Long = -1
        for (h in candidates) {
            val c = today.clone() as Calendar
            c.set(Calendar.HOUR_OF_DAY, h)
            if (c.timeInMillis > nowMs) {
                nextMs = c.timeInMillis
                break
            }
        }
        if (nextMs < 0) {
            val tomorrow = (today.clone() as Calendar).apply {
                add(Calendar.DAY_OF_YEAR, 1)
            }
            tomorrow.set(Calendar.HOUR_OF_DAY, 6)
            nextMs = tomorrow.timeInMillis
        }
        IconSwapScheduler(context).scheduleBoundaryAt(nextMs)
    }
}
