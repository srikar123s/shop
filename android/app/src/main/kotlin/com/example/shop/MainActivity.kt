package com.example.shop

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL_NAME = "com.example.shop/background_notifications"
    }

    private var methodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        capturePayloadFromIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val payload = intent.getStringExtra(ShopNotificationConfig.EXTRA_PAYLOAD)
        if (!payload.isNullOrBlank()) {
            if (methodChannel != null) {
                methodChannel?.invokeMethod("onNotificationTap", payload)
            } else {
                ShopNotificationConfig.savePendingLaunchPayload(applicationContext, payload)
            }
        }
    }

    private fun capturePayloadFromIntent(intent: Intent?) {
        val payload = intent?.getStringExtra(ShopNotificationConfig.EXTRA_PAYLOAD)
        if (!payload.isNullOrBlank()) {
            ShopNotificationConfig.savePendingLaunchPayload(applicationContext, payload)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ShopNotificationConfig.ensureChannels(applicationContext)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "saveAndScheduleAlarms" -> {
                    val jsonConfig = call.argument<String>("config")
                    if (jsonConfig.isNullOrBlank()) {
                        result.error("INVALID_ARG", "Missing config JSON", null)
                        return@setMethodCallHandler
                    }
                    ShopNotificationConfig.saveConfigJson(applicationContext, jsonConfig)
                    ShopAlarmScheduler.rescheduleAll(applicationContext)
                    result.success(ShopAlarmScheduler.getActiveAlarmCount(applicationContext))
                }
                "cancelAllNativeAlarms" -> {
                    ShopAlarmScheduler.cancelAllAlarms(applicationContext)
                    result.success(true)
                }
                "scheduleTestAlarm" -> {
                    val seconds = call.argument<Int>("delaySeconds") ?: 30
                    ShopAlarmScheduler.scheduleTestAlarm(applicationContext, seconds)
                    result.success(true)
                }
                "syncDedupeSlot" -> {
                    val key = call.argument<String>("key")
                    val slot = call.argument<String>("slot")
                    if (!key.isNullOrBlank() && !slot.isNullOrBlank()) {
                        ShopNotificationConfig.markDedupeSlot(applicationContext, key, slot)
                    }
                    result.success(true)
                }
                "getInitialPayload" -> {
                    result.success(ShopNotificationConfig.consumePendingLaunchPayload(applicationContext))
                }
                "getNotificationDiagnostics" -> {
                    val notifEnabled =
                        NotificationManagerCompat.from(applicationContext).areNotificationsEnabled()
                    val exactAlarmsAllowed =
                        ShopAlarmScheduler.canScheduleExactAlarms(applicationContext)
                    val ignoringBattery = isIgnoringBatteryOptimizations()
                    val activeAlarms = ShopAlarmScheduler.getActiveAlarmCount(applicationContext)
                    val periodicJob = ShopAlarmScheduler.isPeriodicJobScheduled(applicationContext)
                    val dbExists = getDatabasePath("hardware_shop.db").exists()
                    result.success(
                        mapOf(
                            "notificationsEnabled" to notifEnabled,
                            "exactAlarmsAllowed" to exactAlarmsAllowed,
                            "ignoringBatteryOptimizations" to ignoringBattery,
                            "activeNativeAlarmsCount" to activeAlarms,
                            "periodicJobScheduled" to periodicJob,
                            "dbExists" to dbExists,
                            "manufacturer" to (Build.MANUFACTURER ?: ""),
                            "sdkInt" to Build.VERSION.SDK_INT,
                        ),
                    )
                }
                "requestIgnoreBatteryOptimizations" -> {
                    result.success(openBatteryOptimizationDialog())
                }
                "openExactAlarmSettings" -> {
                    result.success(openExactAlarmSettings())
                }
                "openNotificationSettings" -> {
                    result.success(openNotificationSettings())
                }
                "openAutostartSettings" -> {
                    result.success(openAutostartOrAppInfo())
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return true
        return try {
            pm.isIgnoringBatteryOptimizations(packageName)
        } catch (_: Exception) {
            true
        }
    }

    private fun openBatteryOptimizationDialog(): Boolean {
        return try {
            if (!isIgnoringBatteryOptimizations()) {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                }
                if (canResolve(intent)) {
                    startActivity(intent)
                    return true
                }
            }
            val listIntent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            if (canResolve(listIntent)) {
                startActivity(listIntent)
                return true
            }
            openAppDetailsSettings()
        } catch (_: Exception) {
            openAppDetailsSettings()
        }
    }

    private fun openExactAlarmSettings(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                    data = Uri.parse("package:$packageName")
                }
                if (canResolve(intent)) {
                    startActivity(intent)
                    return true
                }
            } catch (_: Exception) {
            }
        }
        return openAppDetailsSettings()
    }

    private fun openNotificationSettings(): Boolean {
        return try {
            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                }
            } else {
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:$packageName")
                }
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            openAppDetailsSettings()
        }
    }

    private fun openAutostartOrAppInfo(): Boolean {
        val oemCandidates = listOf(
            ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"),
            ComponentName("com.letv.android.letvsafe", "com.letv.android.letvsafe.AutobootManageActivity"),
            ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
            ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.optimize.process.ProtectActivity"),
            ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity"),
            ComponentName("com.coloros.safecenter", "com.coloros.safecenter.startupapp.StartupAppListActivity"),
            ComponentName("com.oppo.safe", "com.oppo.safe.permission.startup.StartupAppListActivity"),
            ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"),
            ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager"),
            ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"),
            ComponentName("com.samsung.android.lool", "com.samsung.android.sm.ui.battery.BatteryActivity"),
            ComponentName("com.samsung.android.lool", "com.samsung.android.sm.battery.ui.BatteryActivity"),
            ComponentName("com.asus.mobilemanager", "com.asus.mobilemanager.entry.FunctionActivity"),
            ComponentName("com.oneplus.security", "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity"),
        )
        for (component in oemCandidates) {
            try {
                val intent = Intent().apply {
                    setComponent(component)
                }
                if (canResolve(intent)) {
                    startActivity(intent)
                    return true
                }
            } catch (_: Exception) {
            }
        }
        return openAppDetailsSettings()
    }

    private fun openAppDetailsSettings(): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun canResolve(intent: Intent): Boolean {
        val matches = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            packageManager.queryIntentActivities(intent, 0)
        }
        return matches.isNotEmpty()
    }
}
