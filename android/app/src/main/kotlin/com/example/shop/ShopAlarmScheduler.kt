package com.example.shop

import android.app.AlarmManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import java.util.Calendar

object ShopAlarmScheduler {
    private const val TAG = "ShopAlarmScheduler"
    private const val PREF_SCHEDULED = "shop_bg_scheduled_ids"
    private const val KEY_IDS = "active_request_codes"
    private const val BASE_REQUEST_CODE = 5000
    private const val TEST_REQUEST_CODE = 5999
    private const val PERIODIC_JOB_ID = 7001

    const val EXTRA_TYPE = "alarm_trigger_type"
    const val EXTRA_HOUR = "alarm_hour"
    const val EXTRA_MINUTE = "alarm_minute"
    const val EXTRA_SLOT_TAG = "alarm_slot_tag"
    const val EXTRA_REQUEST_CODE = "alarm_request_code"
    const val EXTRA_REPEAT_DAILY = "alarm_repeat_daily"

    fun canScheduleExactAlarms(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val am = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return false
        return try {
            am.canScheduleExactAlarms()
        } catch (_: Exception) {
            false
        }
    }

    fun getActiveAlarmCount(context: Context): Int {
        val prefs = context.getSharedPreferences(PREF_SCHEDULED, Context.MODE_PRIVATE)
        val raw = prefs.getStringSet(KEY_IDS, emptySet()) ?: emptySet()
        return raw.size
    }

    fun isPeriodicJobScheduled(context: Context): Boolean {
        val scheduler = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as? JobScheduler
            ?: return false
        return scheduler.allPendingJobs.any { it.id == PERIODIC_JOB_ID }
    }

    fun cancelAllAlarms(context: Context) {
        cancelScheduledAlarmsOnly(context)

        try {
            val scheduler =
                context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as? JobScheduler
            scheduler?.cancel(PERIODIC_JOB_ID)
        } catch (e: Exception) {
            Log.e(TAG, "Error cancelling periodic job: $e")
        }
    }

    private fun cancelScheduledAlarmsOnly(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
        val prefs = context.getSharedPreferences(PREF_SCHEDULED, Context.MODE_PRIVATE)
        val existingIds = prefs.getStringSet(KEY_IDS, emptySet()) ?: emptySet()
        if (am != null) {
            for (codeStr in existingIds) {
                val code = codeStr.toIntOrNull() ?: continue
                cancelSingleAlarm(context, am, code)
            }
            // Extra safety sweep in case previous run left unmanaged codes
            for (code in BASE_REQUEST_CODE..(BASE_REQUEST_CODE + 80)) {
                cancelSingleAlarm(context, am, code)
            }
        }
        prefs.edit().remove(KEY_IDS).commit()
    }

    private fun cancelSingleAlarm(context: Context, am: AlarmManager, requestCode: Int) {
        val intent = Intent(context, ShopNotificationReceiver::class.java)
        val existing = PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        )
        if (existing != null) {
            am.cancel(existing)
            existing.cancel()
        }
    }

    fun rescheduleAll(context: Context) {
        ShopNotificationConfig.ensureChannels(context)
        val cfg = ShopNotificationConfig.loadConfig(context)
        if (!cfg.enabled) {
            cancelAllAlarms(context)
            Log.d(TAG, "Master notifications disabled; all native alarms cancelled.")
            return
        }
        cancelScheduledAlarmsOnly(context)

        val registeredCodes = mutableSetOf<String>()
        var nextCode = BASE_REQUEST_CODE

        // 1. Pending Orders Alarms
        if (cfg.pendingEnabled) {
            when (cfg.pendingMode) {
                "hourly" -> {
                    for (h in 7..21) {
                        val code = nextCode++
                        scheduleDailySlot(
                            context = context,
                            requestCode = code,
                            triggerType = "pending",
                            hour = h,
                            minute = 0,
                            slotTag = "pending-hourly-$h",
                        )
                        registeredCodes.add(code.toString())
                    }
                }
                "two_hours", "every2hours" -> {
                    for (h in 8..20 step 2) {
                        val code = nextCode++
                        scheduleDailySlot(
                            context = context,
                            requestCode = code,
                            triggerType = "pending",
                            hour = h,
                            minute = 0,
                            slotTag = "pending-2hr-$h",
                        )
                        registeredCodes.add(code.toString())
                    }
                }
                else -> {
                    for (t in cfg.pendingTimes) {
                        val code = nextCode++
                        scheduleDailySlot(
                            context = context,
                            requestCode = code,
                            triggerType = "pending",
                            hour = t.hour,
                            minute = t.minute,
                            slotTag = "pending-${t.hour}:${t.minute}",
                        )
                        registeredCodes.add(code.toString())
                    }
                }
            }
        }

        // 2. Procurement List Alarms
        if (cfg.procureEnabled) {
            for (t in cfg.procureTimes) {
                val code = nextCode++
                scheduleDailySlot(
                    context = context,
                    requestCode = code,
                    triggerType = "procure",
                    hour = t.hour,
                    minute = t.minute,
                    slotTag = "procure-${t.hour}:${t.minute}",
                )
                registeredCodes.add(code.toString())
            }
        }

        // 3. Daily Business Summary Report Alarm
        if (cfg.dailyReportEnabled) {
            val code = nextCode++
            scheduleDailySlot(
                context = context,
                requestCode = code,
                triggerType = "daily_report",
                hour = cfg.dailyReportTime.hour,
                minute = cfg.dailyReportTime.minute,
                slotTag = "daily-report",
            )
            registeredCodes.add(code.toString())
        }

        // 4. Morning Overdue & Market Price Caution Check (09:00 AM daily)
        val morningCode = nextCode++
        scheduleDailySlot(
            context = context,
            requestCode = morningCode,
            triggerType = "morning_checks",
            hour = 9,
            minute = 0,
            slotTag = "morning-checks",
        )
        registeredCodes.add(morningCode.toString())

        context.getSharedPreferences(PREF_SCHEDULED, Context.MODE_PRIVATE)
            .edit()
            .putStringSet(KEY_IDS, registeredCodes)
            .commit()

        ensurePeriodicJobScheduled(context)
        Log.d(TAG, "Scheduled ${registeredCodes.size} exact native alarms + periodic JobScheduler watchdog.")
    }

    fun scheduleDailySlot(
        context: Context,
        requestCode: Int,
        triggerType: String,
        hour: Int,
        minute: Int,
        slotTag: String?,
        forceNextDay: Boolean = false,
    ) {
        val now = Calendar.getInstance()
        val target = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        if (forceNextDay || !target.after(now)) {
            target.add(Calendar.DAY_OF_YEAR, 1)
        }

        scheduleAtMillis(
            context = context,
            requestCode = requestCode,
            triggerAtMillis = target.timeInMillis,
            triggerType = triggerType,
            hour = hour,
            minute = minute,
            slotTag = slotTag,
            repeatDaily = true,
        )
    }

    fun scheduleTestAlarm(context: Context, delaySeconds: Int = 30) {
        ShopNotificationConfig.ensureChannels(context)
        val triggerAtMillis = System.currentTimeMillis() + (delaySeconds * 1000L)
        scheduleAtMillis(
            context = context,
            requestCode = TEST_REQUEST_CODE,
            triggerAtMillis = triggerAtMillis,
            triggerType = "test",
            hour = -1,
            minute = -1,
            slotTag = "test_alarm",
            repeatDaily = false,
        )
    }

    private fun scheduleAtMillis(
        context: Context,
        requestCode: Int,
        triggerAtMillis: Long,
        triggerType: String,
        hour: Int,
        minute: Int,
        slotTag: String?,
        repeatDaily: Boolean,
    ) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val intent = Intent(context, ShopNotificationReceiver::class.java).apply {
            putExtra(EXTRA_TYPE, triggerType)
            putExtra(EXTRA_HOUR, hour)
            putExtra(EXTRA_MINUTE, minute)
            putExtra(EXTRA_SLOT_TAG, slotTag ?: "")
            putExtra(EXTRA_REQUEST_CODE, requestCode)
            putExtra(EXTRA_REPEAT_DAILY, repeatDaily)
        }
        val pi = PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val canExact = canScheduleExactAlarms(context)
        if (canExact) {
            try {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pi)
                return
            } catch (se: SecurityException) {
                Log.w(TAG, "setExactAndAllowWhileIdle denied ($se); falling back to setAndAllowWhileIdle")
            } catch (e: Exception) {
                Log.w(TAG, "setExactAndAllowWhileIdle failed ($e); falling back to setAndAllowWhileIdle")
            }
        }

        // Safe fallback when exact alarm permission was explicitly denied by user
        try {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pi)
        } catch (e: Exception) {
            Log.e(TAG, "All AlarmManager schedule modes failed for #$requestCode: $e")
        }
    }

    fun ensurePeriodicJobScheduled(context: Context) {
        val cfg = ShopNotificationConfig.loadConfig(context)
        if (!cfg.enabled) return
        val scheduler = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as? JobScheduler
            ?: return

        // Always keep one persisted 15-minute safety watchdog JobScheduler job active
        val job = JobInfo.Builder(
            PERIODIC_JOB_ID,
            ComponentName(context, ShopPeriodicJobService::class.java),
        )
            .setPeriodic(15L * 60L * 1000L)
            .setPersisted(true)
            .build()

        try {
            scheduler.schedule(job)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to schedule periodic watchdog job: $e")
        }
    }
}
