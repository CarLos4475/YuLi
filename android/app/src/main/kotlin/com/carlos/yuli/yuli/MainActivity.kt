package com.carlos.yuli.yuli

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
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
}
