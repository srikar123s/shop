package com.example.shop

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class ShopBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        Log.d("ShopBootReceiver", "Rescheduling native shop alarms for action: $action")
        ShopNotificationConfig.ensureChannels(context)
        ShopAlarmScheduler.rescheduleAll(context)
    }
}
