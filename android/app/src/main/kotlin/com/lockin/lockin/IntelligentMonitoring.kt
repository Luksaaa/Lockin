package com.lockin.lockin

import android.app.usage.UsageStatsManager
import android.content.Context

class IntelligentMonitoring(private val context: Context) {
    private val usageStatsManager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager

    fun getUsageTime(packageName: String): Long {
        val endTime = System.currentTimeMillis()
        val startTime = endTime - Constants.USAGE_WINDOW_MS
        val stats = usageStatsManager.queryAndAggregateUsageStats(startTime, endTime)
        return stats[packageName]?.totalTimeInForeground ?: 0L
    }

    fun isOverLimit(packageName: String): Boolean {
        return getUsageTime(packageName) > Constants.USAGE_LIMIT_MS
    }
}
