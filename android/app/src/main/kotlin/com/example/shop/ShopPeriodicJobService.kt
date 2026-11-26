package com.example.shop

import android.app.job.JobParameters
import android.app.job.JobService
import android.util.Log
import java.util.concurrent.Executors

class ShopPeriodicJobService : JobService() {
    private val executor = Executors.newSingleThreadExecutor()

    override fun onStartJob(params: JobParameters?): Boolean {
        executor.execute {
            try {
                Log.d("ShopPeriodicJobService", "Running periodic closed-app notification check")
                ShopNotificationConfig.ensureChannels(applicationContext)
                ShopNotificationConfig.evaluateAndNotify(
                    context = applicationContext,
                    triggerType = "periodic_watchdog",
                )
            } catch (e: Exception) {
                Log.e("ShopPeriodicJobService", "Periodic check error: $e")
            } finally {
                jobFinished(params, false)
            }
        }
        return true
    }

    override fun onStopJob(params: JobParameters?): Boolean {
        return true
    }
}
