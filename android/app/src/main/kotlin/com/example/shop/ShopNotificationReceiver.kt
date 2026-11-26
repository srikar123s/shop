package com.example.shop

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class ShopNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val triggerType = intent.getStringExtra(ShopAlarmScheduler.EXTRA_TYPE) ?: "pending"
        val hour = intent.getIntExtra(ShopAlarmScheduler.EXTRA_HOUR, -1)
        val minute = intent.getIntExtra(ShopAlarmScheduler.EXTRA_MINUTE, -1)
        val slotTag = intent.getStringExtra(ShopAlarmScheduler.EXTRA_SLOT_TAG)
        val requestCode = intent.getIntExtra(ShopAlarmScheduler.EXTRA_REQUEST_CODE, -1)
        val repeatDaily = intent.getBooleanExtra(ShopAlarmScheduler.EXTRA_REPEAT_DAILY, false)

        Log.d(
            "ShopNotificationRcv",
            "Alarm fired: type=$triggerType, hour=$hour, minute=$minute, repeatDaily=$repeatDaily",
        )

        ShopNotificationConfig.evaluateAndNotify(
            context = context,
            triggerType = triggerType,
            slotHour = hour,
            slotMinute = minute,
            slotTag = if (slotTag.isNullOrBlank()) null else slotTag,
        )

        if (repeatDaily && requestCode >= 0 && hour >= 0 && minute >= 0) {
            ShopAlarmScheduler.scheduleDailySlot(
                context = context,
                requestCode = requestCode,
                triggerType = triggerType,
                hour = hour,
                minute = minute,
                slotTag = if (slotTag.isNullOrBlank()) null else slotTag,
                forceNextDay = true,
            )
        }
    }
}
