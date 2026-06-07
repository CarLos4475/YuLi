package com.carlos.yuli.yuli

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

class IconSwapScheduler(private val context: Context) {
    companion object {
        const val ACTION_BOUNDARY = "yuli.action.ICON_SWAP"
        const val ACTION_LIFECYCLE = "yuli.action.ICON_LIFECYCLE_SWAP"
        private const val REQ_BOUNDARY = 1001
        private const val REQ_LIFECYCLE = 1002
    }

    fun scheduleBoundaryAt(triggerAtMs: Long) =
        scheduleAt(triggerAtMs, ACTION_BOUNDARY, REQ_BOUNDARY)

    fun cancelBoundary() = cancel(ACTION_BOUNDARY, REQ_BOUNDARY)

    fun scheduleLifecycleAt(triggerAtMs: Long) =
        scheduleAt(triggerAtMs, ACTION_LIFECYCLE, REQ_LIFECYCLE)

    fun cancelLifecycle() = cancel(ACTION_LIFECYCLE, REQ_LIFECYCLE)

    private fun scheduleAt(triggerAtMs: Long, action: String, requestCode: Int) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = pendingIntent(action, requestCode)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (am.canScheduleExactAlarms()) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
            } else {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
            }
        } else {
            am.setExact(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
        }
    }

    private fun cancel(action: String, requestCode: Int) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(pendingIntent(action, requestCode))
    }

    private fun pendingIntent(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(context, IconSwapReceiver::class.java).apply {
            this.action = action
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getBroadcast(context, requestCode, intent, flags)
    }
}
