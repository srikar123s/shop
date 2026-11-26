package com.example.shop

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.graphics.Color
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import kotlin.math.abs

data class ParsedTimeSlot(val hour: Int, val minute: Int)

data class NativeNotifConfig(
    val enabled: Boolean = true,
    val pendingEnabled: Boolean = true,
    val pendingMode: String = "scheduled",
    val pendingTimes: List<ParsedTimeSlot> = listOf(
        ParsedTimeSlot(10, 0),
        ParsedTimeSlot(14, 0),
        ParsedTimeSlot(19, 0),
    ),
    val procureEnabled: Boolean = true,
    val procureTimes: List<ParsedTimeSlot> = listOf(
        ParsedTimeSlot(9, 30),
        ParsedTimeSlot(17, 30),
    ),
    val dailyReportEnabled: Boolean = true,
    val dailyReportTime: ParsedTimeSlot = ParsedTimeSlot(21, 0),
    val priceCautionEnabled: Boolean = true,
    val priceCautionDays: Int = 30,
)

data class ShopDbMetrics(
    val dbAvailable: Boolean = false,
    val pendingCount: Int = 0,
    val oldPendingCount: Int = 0,
    val toProcureCount: Int = 0,
    val completedTodayCount: Int = 0,
    val totalTodaySales: Double = 0.0,
    val totalTodayCollected: Double = 0.0,
    val stalePriceCount: Int = 0,
)

object ShopNotificationConfig {
    private const val TAG = "ShopNotifEngine"
    const val CHANNEL_ID = "shop_alerts_high_priority_v1"
    const val LEGACY_CHANNEL_ID = "shop_order_reminders"
    private const val CHANNEL_NAME = "Shop Urgent Alerts & Reminders"
    private const val CHANNEL_DESC =
        "Important business reminders, order updates, and counter notifications"

    private const val PREF_CONFIG = "shop_bg_notif_config"
    private const val KEY_CONFIG_JSON = "config_json"
    private const val PREF_DEDUPE = "shop_bg_notif_dedupe"
    private const val KEY_INITIAL_PAYLOAD = "pending_launch_payload"
    private const val DB_NAME = "hardware_shop.db"

    const val NOTIF_ID_PENDING = 101
    const val NOTIF_ID_PROCURE = 102
    const val NOTIF_ID_OVERDUE = 103
    const val NOTIF_ID_STALE = 104
    const val NOTIF_ID_DAILY_REPORT = 105
    const val NOTIF_ID_TEST = 999

    const val EXTRA_PAYLOAD = "notif_payload"

    fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val mgr = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return

        val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val audioAttrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        val primary = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = CHANNEL_DESC
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 250, 150, 250)
            enableLights(true)
            lightColor = Color.parseColor("#0F766E")
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setSound(soundUri, audioAttrs)
        }
        mgr.createNotificationChannel(primary)

        // Legacy fallback channel so any external/server push targeting it also displays cleanly.
        val legacy = NotificationChannel(
            LEGACY_CHANNEL_ID,
            "Shop Order & Cloud Reminders",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = CHANNEL_DESC
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 250, 150, 250)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setSound(soundUri, audioAttrs)
        }
        mgr.createNotificationChannel(legacy)
    }

    fun saveConfigJson(context: Context, jsonStr: String) {
        context.getSharedPreferences(PREF_CONFIG, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_CONFIG_JSON, jsonStr)
            .commit()
    }

    fun loadConfig(context: Context): NativeNotifConfig {
        val raw = context.getSharedPreferences(PREF_CONFIG, Context.MODE_PRIVATE)
            .getString(KEY_CONFIG_JSON, null)
            ?: return NativeNotifConfig()

        return try {
            val obj = JSONObject(raw)
            val pendingTimes = parseTimeArray(obj.optJSONArray("pending_times"))
                .ifEmpty {
                    listOf(
                        ParsedTimeSlot(10, 0),
                        ParsedTimeSlot(14, 0),
                        ParsedTimeSlot(19, 0),
                    )
                }
            val procureTimes = parseTimeArray(obj.optJSONArray("procure_times"))
                .ifEmpty {
                    listOf(
                        ParsedTimeSlot(9, 30),
                        ParsedTimeSlot(17, 30),
                    )
                }
            val reportTime = parseTimeString(obj.optString("daily_report_time", "21:00"))
                ?: ParsedTimeSlot(21, 0)

            NativeNotifConfig(
                enabled = obj.optBoolean("enabled", true),
                pendingEnabled = obj.optBoolean("pending_enabled", true),
                pendingMode = obj.optString("pending_mode", "scheduled"),
                pendingTimes = pendingTimes,
                procureEnabled = obj.optBoolean("procure_enabled", true),
                procureTimes = procureTimes,
                dailyReportEnabled = obj.optBoolean("daily_report_enabled", true),
                dailyReportTime = reportTime,
                priceCautionEnabled = obj.optBoolean("price_caution_enabled", true),
                priceCautionDays = obj.optInt("price_caution_days", 30),
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error parsing native config JSON: $e")
            NativeNotifConfig()
        }
    }

    private fun parseTimeArray(arr: JSONArray?): List<ParsedTimeSlot> {
        if (arr == null) return emptyList()
        val out = mutableListOf<ParsedTimeSlot>()
        for (i in 0 until arr.length()) {
            val item = arr.optString(i, "")
            parseTimeString(item)?.let { out.add(it) }
        }
        return out
    }

    private fun parseTimeString(raw: String): ParsedTimeSlot? {
        val parts = raw.trim().split(":")
        if (parts.size < 2) return null
        val h = parts[0].toIntOrNull() ?: return null
        val m = parts[1].toIntOrNull() ?: return null
        if (h !in 0..23 || m !in 0..59) return null
        return ParsedTimeSlot(h, m)
    }

    fun markDedupeSlot(context: Context, key: String, slotValue: String) {
        context.getSharedPreferences(PREF_DEDUPE, Context.MODE_PRIVATE)
            .edit()
            .putString(key, slotValue)
            .apply()
    }

    fun isDedupeSlotAlreadyNotified(context: Context, key: String, slotValue: String): Boolean {
        val prev = context.getSharedPreferences(PREF_DEDUPE, Context.MODE_PRIVATE)
            .getString(key, null)
        return prev == slotValue
    }

    fun savePendingLaunchPayload(context: Context, payload: String?) {
        if (payload.isNullOrBlank()) return
        context.getSharedPreferences(PREF_CONFIG, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_INITIAL_PAYLOAD, payload)
            .apply()
    }

    fun consumePendingLaunchPayload(context: Context): String? {
        val prefs = context.getSharedPreferences(PREF_CONFIG, Context.MODE_PRIVATE)
        val payload = prefs.getString(KEY_INITIAL_PAYLOAD, null)
        if (payload != null) {
            prefs.edit().remove(KEY_INITIAL_PAYLOAD).apply()
        }
        return payload
    }

    fun queryShopMetrics(context: Context, priceCautionDays: Int): ShopDbMetrics {
        val dbFile: File = context.getDatabasePath(DB_NAME)
        if (!dbFile.exists()) {
            return ShopDbMetrics(dbAvailable = false)
        }

        var db: SQLiteDatabase? = null
        return try {
            db = SQLiteDatabase.openDatabase(
                dbFile.absolutePath,
                null,
                SQLiteDatabase.OPEN_READONLY or SQLiteDatabase.NO_LOCALIZED_COLLATORS,
            )

            var pendingCount = 0
            var oldPendingCount = 0
            val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US)
            val threeDaysAgoMillis = System.currentTimeMillis() - (3L * 24L * 60L * 60L * 1000L)

            db.rawQuery(
                """
                SELECT o.id, o.created_at
                FROM orders o
                WHERE UPPER(o.status) NOT IN ('COMPLETED', 'CLOSED')
                  AND EXISTS (
                    SELECT 1 FROM order_items oi
                    WHERE oi.order_id = o.id
                      AND LOWER(oi.status) != 'given'
                      AND (oi.quantity_ordered - oi.quantity_given) > 0
                  )
                """.trimIndent(),
                null,
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    pendingCount++
                    val createdRaw = cursor.getString(1)
                    if (!createdRaw.isNullOrBlank()) {
                        try {
                            val clean = createdRaw.take(19)
                            val parsed = isoFormat.parse(clean)
                            if (parsed != null && parsed.time < threeDaysAgoMillis) {
                                oldPendingCount++
                            }
                        } catch (_: Exception) {
                        }
                    }
                }
            }

            var toProcureCount = 0
            db.rawQuery(
                """
                SELECT COUNT(oi.id) as cnt
                FROM order_items oi
                JOIN orders o ON oi.order_id = o.id
                WHERE LOWER(oi.procurement_status) = 'toprocure'
                  AND (oi.quantity_ordered - oi.quantity_given) > 0
                """.trimIndent(),
                null,
            ).use { cursor ->
                if (cursor.moveToFirst()) {
                    toProcureCount = cursor.getInt(0)
                }
            }

            val todayIso = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
            var completedCount = 0
            var totalSales = 0.0
            db.rawQuery(
                """
                SELECT COUNT(*) as cnt, COALESCE(SUM(estimate_total), 0.0) as total_sales
                FROM orders
                WHERE date(created_at) = ? AND LOWER(status) IN ('completed', 'closed')
                """.trimIndent(),
                arrayOf(todayIso),
            ).use { cursor ->
                if (cursor.moveToFirst()) {
                    completedCount = cursor.getInt(0)
                    totalSales = cursor.getDouble(1)
                }
            }

            var totalCollected = 0.0
            try {
                db.rawQuery(
                    """
                    SELECT COALESCE(SUM(amount), 0.0) as total_collected
                    FROM customer_payments
                    WHERE date(created_at) = ?
                    """.trimIndent(),
                    arrayOf(todayIso),
                ).use { cursor ->
                    if (cursor.moveToFirst()) {
                        totalCollected = cursor.getDouble(0)
                    }
                }
            } catch (_: Exception) {
            }

            var stalePriceCount = 0
            val cutoffCal = Calendar.getInstance().apply {
                add(Calendar.DAY_OF_YEAR, -priceCautionDays)
            }
            val cutoffIso = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US)
                .format(cutoffCal.time)
            try {
                db.rawQuery(
                    """
                    SELECT COUNT(*) as cnt FROM products
                    WHERE is_active = 1
                      AND (
                        COALESCE(price_updated_at, created_at) < ?
                        OR (price_updated_at IS NULL AND created_at IS NULL)
                      )
                    """.trimIndent(),
                    arrayOf(cutoffIso),
                ).use { cursor ->
                    if (cursor.moveToFirst()) {
                        stalePriceCount = cursor.getInt(0)
                    }
                }
            } catch (_: Exception) {
            }

            ShopDbMetrics(
                dbAvailable = true,
                pendingCount = pendingCount,
                oldPendingCount = oldPendingCount,
                toProcureCount = toProcureCount,
                completedTodayCount = completedCount,
                totalTodaySales = totalSales,
                totalTodayCollected = totalCollected,
                stalePriceCount = stalePriceCount,
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error reading shop SQLite metrics: $e")
            ShopDbMetrics(dbAvailable = false)
        } finally {
            try {
                db?.close()
            } catch (_: Exception) {
            }
        }
    }

    fun evaluateAndNotify(
        context: Context,
        triggerType: String,
        slotHour: Int = -1,
        slotMinute: Int = -1,
        slotTag: String? = null,
    ) {
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val wakeLock = try {
            powerManager?.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "${context.packageName}:ShopNotifWakeLock",
            )?.apply {
                acquire(10_000L)
            }
        } catch (_: Exception) {
            null
        }

        try {
            ensureChannels(context)
            val cfg = loadConfig(context)
            val metrics = queryShopMetrics(context, cfg.priceCautionDays)

            if (triggerType == "test") {
                val dbSummary = if (metrics.dbAvailable) {
                    "Live DB check: ${metrics.pendingCount} pending order(s), ${metrics.toProcureCount} procurement item(s)."
                } else {
                    "Background engine verified ready for closed-app reminders."
                }
                showNativeNotification(
                    context = context,
                    id = NOTIF_ID_TEST,
                    title = "⏰ Closed-App Alarm Test SUCCESS!",
                    body = "Background alarm fired even with app closed! $dbSummary",
                    colorHex = "#0F766E",
                    payload = "pending_orders",
                )
                return
            }

            if (!cfg.enabled) return

            val nowCal = Calendar.getInstance()
            val nowHour = nowCal.get(Calendar.HOUR_OF_DAY)
            val nowMinute = nowCal.get(Calendar.MINUTE)
            val dayPrefix =
                "${nowCal.get(Calendar.YEAR)}-${nowCal.get(Calendar.MONTH) + 1}-${nowCal.get(Calendar.DAY_OF_MONTH)}"

            // Overdue alert whenever old orders (>3 days) exist
            if (metrics.oldPendingCount > 0 &&
                (triggerType == "pending" || triggerType == "morning_checks" || triggerType == "periodic_watchdog")
            ) {
                val overdueSlot = "$dayPrefix-overdue-$nowHour"
                if (!isDedupeSlotAlreadyNotified(context, "notif_overdue", overdueSlot)) {
                    showNativeNotification(
                        context = context,
                        id = NOTIF_ID_OVERDUE,
                        title = "⚠️ URGENT: ${metrics.oldPendingCount} Order(s) >3 Days Old!",
                        body = "${metrics.pendingCount} total orders pending. ${metrics.oldPendingCount} order(s) taken over 3 days ago are still not closed! Tap to review.",
                        colorHex = "#DC2626",
                        payload = "pending_orders",
                    )
                    markDedupeSlot(context, "notif_overdue", overdueSlot)
                }
            }

            // 1. Pending orders check
            if (cfg.pendingEnabled && metrics.pendingCount > 0) {
                val shouldCheckPending = when (triggerType) {
                    "pending" -> true
                    "periodic_watchdog" -> isWithinScheduledSlotWindow(
                        mode = cfg.pendingMode,
                        times = cfg.pendingTimes,
                        nowHour = nowHour,
                        nowMinute = nowMinute,
                    ) != null
                    else -> false
                }

                if (shouldCheckPending) {
                    val slotKey = buildPendingSlotKey(
                        dayPrefix = dayPrefix,
                        mode = cfg.pendingMode,
                        times = cfg.pendingTimes,
                        slotHour = slotHour,
                        slotMinute = slotMinute,
                        nowHour = nowHour,
                        nowMinute = nowMinute,
                        slotTag = slotTag,
                    )
                    val dedupePrefKey = "notif_pending_$slotKey"
                    if (slotKey != null && !isDedupeSlotAlreadyNotified(context, dedupePrefKey, slotKey)) {
                        var title = "📋 ${metrics.pendingCount} Pending Counter Orders"
                        var body =
                            "You have ${metrics.pendingCount} unclosed customer order(s). Tap here to review and finalize."
                        if (nowHour <= 10) {
                            title = "🌅 Morning Status: ${metrics.pendingCount} Open Orders"
                        } else if (nowHour >= 20) {
                            title = "🌙 Closing Reminder: ${metrics.pendingCount} Unclosed Bills"
                            body =
                                "Day-end closing! Close counter orders to update daily sales & khata balances."
                        }
                        showNativeNotification(
                            context = context,
                            id = NOTIF_ID_PENDING,
                            title = title,
                            body = body,
                            colorHex = "#0F766E",
                            payload = "pending_orders",
                        )
                        markDedupeSlot(context, dedupePrefKey, slotKey)
                    }
                }
            }

            // 2. Procurement list check
            if (cfg.procureEnabled && metrics.toProcureCount > 0) {
                val matchedSlot = when (triggerType) {
                    "procure" -> if (slotHour >= 0 && slotMinute >= 0) {
                        "$dayPrefix-procure-$slotHour:$slotMinute"
                    } else {
                        "$dayPrefix-procure-$nowHour:$nowMinute"
                    }
                    "periodic_watchdog" -> findMatchingTimeSlot(
                        times = cfg.procureTimes,
                        nowHour = nowHour,
                        nowMinute = nowMinute,
                        prefix = "$dayPrefix-procure",
                    )
                    else -> null
                }
                if (matchedSlot != null) {
                    val dedupePrefKey = "notif_procure_$matchedSlot"
                    if (!isDedupeSlotAlreadyNotified(context, dedupePrefKey, matchedSlot)) {
                        showNativeNotification(
                            context = context,
                            id = NOTIF_ID_PROCURE,
                            title = "📦 Procurement: ${metrics.toProcureCount} Item(s) Short / Needed",
                            body = "Items are short or out of stock for customer orders. Tap to view procurement list.",
                            colorHex = "#E11D48",
                            payload = "procurement",
                        )
                        markDedupeSlot(context, dedupePrefKey, matchedSlot)
                    }
                }
            }

            // 3. Daily business summary report
            if (cfg.dailyReportEnabled) {
                val shouldCheckReport = when (triggerType) {
                    "daily_report" -> true
                    "periodic_watchdog" -> isTimeNear(
                        nowHour = nowHour,
                        nowMinute = nowMinute,
                        targetHour = cfg.dailyReportTime.hour,
                        targetMinute = cfg.dailyReportTime.minute,
                        windowMinutes = 20,
                    )
                    else -> false
                }
                if (shouldCheckReport) {
                    val reportSlot = "$dayPrefix-daily-report"
                    if (!isDedupeSlotAlreadyNotified(context, "notif_report", reportSlot)) {
                        val salesRounded = metrics.totalTodaySales.toLong()
                        val collectedRounded = metrics.totalTodayCollected.toLong()
                        showNativeNotification(
                            context = context,
                            id = NOTIF_ID_DAILY_REPORT,
                            title = "📊 Daily Shop Report: ₹$salesRounded Sales",
                            body = "Completed ${metrics.completedTodayCount} orders today. Collected: ₹$collectedRounded. Open pending orders: ${metrics.pendingCount}. Tap for details.",
                            colorHex = "#0F766E",
                            payload = "daily_report",
                        )
                        markDedupeSlot(context, "notif_report", reportSlot)
                    }
                }
            }

            // 4. Market price caution check (morning / watchdog before noon)
            if (cfg.priceCautionEnabled && metrics.stalePriceCount > 0 &&
                (triggerType == "morning_checks" || (triggerType == "periodic_watchdog" && nowHour in 8..11))
            ) {
                val cautionSlot = "$dayPrefix-price-caution"
                if (!isDedupeSlotAlreadyNotified(context, "notif_price_caution", cautionSlot)) {
                    showNativeNotification(
                        context = context,
                        id = NOTIF_ID_STALE,
                        title = "🏷️ Market Price Check: ${metrics.stalePriceCount} Product(s) Outdated",
                        body = "${metrics.stalePriceCount} item rate(s) have not been updated for >${cfg.priceCautionDays} days. Market rates may have changed. Tap to review.",
                        colorHex = "#D97706",
                        payload = "stale_prices",
                    )
                    markDedupeSlot(context, "notif_price_caution", cautionSlot)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in evaluateAndNotify ($triggerType): $e")
        } finally {
            try {
                if (wakeLock?.isHeld == true) {
                    wakeLock.release()
                }
            } catch (_: Exception) {
            }
        }
    }

    private fun buildPendingSlotKey(
        dayPrefix: String,
        mode: String,
        times: List<ParsedTimeSlot>,
        slotHour: Int,
        slotMinute: Int,
        nowHour: Int,
        nowMinute: Int,
        slotTag: String?,
    ): String? {
        if (!slotTag.isNullOrBlank()) {
            return "$dayPrefix-$slotTag"
        }
        if (mode == "hourly") {
            val h = if (slotHour >= 0) slotHour else nowHour
            return if (h in 7..21) "$dayPrefix-pending-hourly-$h" else null
        }
        if (mode == "two_hours" || mode == "every2hours") {
            val h = if (slotHour >= 0) slotHour else nowHour
            return if (h in 8..20 && h % 2 == 0) "$dayPrefix-pending-2hr-$h" else null
        }
        if (slotHour >= 0 && slotMinute >= 0) {
            return "$dayPrefix-pending-$slotHour:$slotMinute"
        }
        return findMatchingTimeSlot(times, nowHour, nowMinute, "$dayPrefix-pending")
    }

    private fun isWithinScheduledSlotWindow(
        mode: String,
        times: List<ParsedTimeSlot>,
        nowHour: Int,
        nowMinute: Int,
    ): String? {
        if (mode == "hourly") {
            if (nowHour in 7..21 && nowMinute <= 20) {
                return "pending-hourly-$nowHour"
            }
            return null
        }
        if (mode == "two_hours" || mode == "every2hours") {
            if (nowHour in 8..20 && nowHour % 2 == 0 && nowMinute <= 20) {
                return "pending-2hr-$nowHour"
            }
            return null
        }
        return findMatchingTimeSlot(times, nowHour, nowMinute, "pending")
    }

    private fun findMatchingTimeSlot(
        times: List<ParsedTimeSlot>,
        nowHour: Int,
        nowMinute: Int,
        prefix: String,
    ): String? {
        for (t in times) {
            if (isTimeNear(nowHour, nowMinute, t.hour, t.minute, 20)) {
                return "$prefix-${t.hour}:${t.minute}"
            }
        }
        return null
    }

    private fun isTimeNear(
        nowHour: Int,
        nowMinute: Int,
        targetHour: Int,
        targetMinute: Int,
        windowMinutes: Int,
    ): Boolean {
        val nowTotal = nowHour * 60 + nowMinute
        val targetTotal = targetHour * 60 + targetMinute
        val diff = abs(nowTotal - targetTotal)
        return diff <= windowMinutes && nowTotal >= targetTotal - 1
    }

    fun showNativeNotification(
        context: Context,
        id: Int,
        title: String,
        body: String,
        colorHex: String,
        payload: String,
    ) {
        val mgrCompat = NotificationManagerCompat.from(context)
        if (!mgrCompat.areNotificationsEnabled()) {
            Log.w(TAG, "Notifications blocked by system settings; skipping #$id")
            return
        }

        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_PAYLOAD, payload)
        }
        val contentPendingIntent = PendingIntent.getActivity(
            context,
            id,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val smallIconRes = context.applicationInfo.icon
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(smallIconRes)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setAutoCancel(true)
            .setContentIntent(contentPendingIntent)

        try {
            builder.color = Color.parseColor(colorHex)
        } catch (_: Exception) {
        }

        try {
            mgrCompat.notify(id, builder.build())
            Log.d(TAG, "Displayed native notification #$id: $title")
        } catch (se: SecurityException) {
            Log.e(TAG, "Missing POST_NOTIFICATIONS runtime permission for #$id: $se")
        } catch (e: Exception) {
            Log.e(TAG, "Failed showing notification #$id: $e")
        }
    }
}
