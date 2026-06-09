package com.carlos.yuli.yuli

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val notificationsChannelName = "yuli/notifications"
    private val launcherIconChannelName = "yuli/launcher_icon"
    private val launcherAliases = mapOf(
        "icon1" to ".LauncherIcon1",
        "icon2" to ".LauncherIcon2",
        "icon3" to ".LauncherIcon3",
    )
    private val prefsName = "yuli_launcher_prefs"
    private val kAutoMode = "auto_mode"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (isAutoMode()) {
            scheduleNextSwap(nextSwapAtMs())
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, notificationsChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "openNotificationSettings") {
                    val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                        putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(intent)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, launcherIconChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "current" -> result.success(currentLauncherIcon())
                    "set" -> {
                        val iconId = call.arguments as? String
                        if (iconId == null || !launcherAliases.containsKey(iconId)) {
                            result.error("invalid_icon", "Icono no valido", null)
                            return@setMethodCallHandler
                        }
                        setLauncherIcon(iconId)
                        result.success(null)
                    }
                    "scheduleNextSwap" -> {
                        val triggerAtMs = (call.arguments as? Number)?.toLong()
                        if (triggerAtMs == null) {
                            result.error("invalid_args", "triggerAtMs requerido", null)
                            return@setMethodCallHandler
                        }
                        scheduleNextSwap(triggerAtMs)
                        result.success(null)
                    }
                    "cancelSchedule" -> {
                        cancelSwapSchedule()
                        result.success(null)
                    }
                    "scheduleLifecycleSwap" -> {
                        val delayMs = (call.arguments as? Number)?.toLong() ?: 30_000L
                        scheduleLifecycleSwap(delayMs)
                        result.success(null)
                    }
                    "cancelLifecycleSwap" -> {
                        cancelLifecycleSwap()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun currentLauncherIcon(): String {
        launcherAliases.forEach { (iconId, aliasName) ->
            val state = packageManager.getComponentEnabledSetting(componentNameFor(aliasName))
            val enabled = when (state) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
                PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> iconId == "icon1"
                else -> false
            }
            if (enabled) return iconId
        }
        return "icon1"
    }

    private fun setLauncherIcon(iconId: String) {
        val activeAlias = launcherAliases.getValue(iconId)
        setAliasEnabled(activeAlias, true)
        launcherAliases.values
            .filter { it != activeAlias }
            .forEach { setAliasEnabled(it, false) }
    }

    private fun setAliasEnabled(aliasName: String, enabled: Boolean) {
        val state = if (enabled) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        } else {
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        }
        packageManager.setComponentEnabledSetting(
            componentNameFor(aliasName),
            state,
            PackageManager.DONT_KILL_APP,
        )
    }

    private fun componentNameFor(aliasName: String): ComponentName {
        return ComponentName(this, "$packageName$aliasName")
    }

    private fun swapPrefs(): SharedPreferences =
        getSharedPreferences(prefsName, Context.MODE_PRIVATE)

    private fun isAutoMode(): Boolean = swapPrefs().getBoolean(kAutoMode, true)

    private fun nextSwapAtMs(): Long {
        val cal = java.util.Calendar.getInstance()
        val nowMs = cal.timeInMillis
        val today = java.util.Calendar.getInstance().apply {
            set(java.util.Calendar.HOUR_OF_DAY, 0)
            set(java.util.Calendar.MINUTE, 0)
            set(java.util.Calendar.SECOND, 0)
            set(java.util.Calendar.MILLISECOND, 0)
        }
        val candidates = intArrayOf(0, 4, 8, 12, 16, 20)
        for (h in candidates) {
            val c = today.clone() as java.util.Calendar
            c.set(java.util.Calendar.HOUR_OF_DAY, h)
            if (c.timeInMillis > nowMs) return c.timeInMillis
        }
        val tomorrow = (today.clone() as java.util.Calendar).apply {
            add(java.util.Calendar.DAY_OF_YEAR, 1)
        }
        tomorrow.set(java.util.Calendar.HOUR_OF_DAY, 0)
        return tomorrow.timeInMillis
    }

    private fun scheduleNextSwap(triggerAtMs: Long) {
        IconSwapScheduler(this).scheduleBoundaryAt(triggerAtMs)
    }

    private fun cancelSwapSchedule() {
        IconSwapScheduler(this).cancelBoundary()
    }

    private fun scheduleLifecycleSwap(delayMs: Long) {
        val triggerAtMs = System.currentTimeMillis() + delayMs
        IconSwapScheduler(this).scheduleLifecycleAt(triggerAtMs)
    }

    private fun cancelLifecycleSwap() {
        IconSwapScheduler(this).cancelLifecycle()
    }
}
