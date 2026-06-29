package com.lockin.lockin

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class IGAccessibilityService : AccessibilityService() {
    private lateinit var intelligentMonitoring: IntelligentMonitoring

    override fun onCreate() {
        super.onCreate()
        intelligentMonitoring = IntelligentMonitoring(this)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        val eventPackageName = event.packageName?.toString() ?: return

        if (eventPackageName == "com.android.settings" || eventPackageName.contains("packageinstaller")) {
            val rootNode = rootInActiveWindow ?: return
            val nodes = rootNode.findAccessibilityNodeInfosByText("Lockin")
            if (nodes.isNotEmpty()) {
                val allText = getAllText(rootNode).lowercase()
                val dangerousKeywords = listOf(
                    "uninstall",
                    "deinstall",
                    "ukloni",
                    "obrisi",
                    "izbrisi",
                    "force stop",
                    "prisilno zaustavi",
                    "clear data",
                    "ocisti podatke",
                    "pohrana",
                    "deactivate",
                    "deaktiviraj",
                    "admin",
                    "administrator"
                )
                if (dangerousKeywords.any { allText.contains(it) }) {
                    performGlobalAction(GLOBAL_ACTION_HOME)
                    return
                }
            }
        }

        val prefs = getSharedPreferences(MainActivity.PREFS_NAME, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(MainActivity.KEY_BLOCKING_ACTIVE, false)) return

        if (eventPackageName != packageName &&
            eventPackageName != "com.android.settings" &&
            !eventPackageName.contains("launcher")
        ) {
            val blockedPackages = prefs.getStringSet(MainActivity.KEY_BLOCKED_PACKAGES, emptySet()) ?: emptySet()
            if (blockedPackages.contains(eventPackageName) && intelligentMonitoring.isOverLimit(eventPackageName)) {
                val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_HOME)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(homeIntent)
                performGlobalAction(GLOBAL_ACTION_HOME)
            }
        }
    }

    private fun getAllText(node: AccessibilityNodeInfo?): String {
        if (node == null) return ""
        val text = StringBuilder()
        node.text?.let { text.append(it).append(" ") }
        for (index in 0 until node.childCount) {
            text.append(getAllText(node.getChild(index)))
        }
        return text.toString()
    }

    override fun onInterrupt() = Unit
}
