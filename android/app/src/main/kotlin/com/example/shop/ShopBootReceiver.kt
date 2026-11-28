package com.example.shop

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import java.util.concurrent.Executors

class ShopBootReceiver : BroadcastReceiver() {
    companion object {
        private val backgroundExecutor = Executors.newSingleThreadExecutor()
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        Log.d("ShopBootReceiver", "Rescheduling native shop alarms for action: $action")
        val pendingResult = goAsync()
        val appContext = context.applicationContext
        backgroundExecutor.execute {
            try {
                ShopNotificationConfig.ensureChannels(appContext)
                ShopAlarmScheduler.rescheduleAll(appContext)
            } catch (e: Exception) {
                Log.e("ShopBootReceiver", "Error rescheduling alarms on boot: $e")
            } finally {
                pendingResult.finish()
            }
        }
    }
}
