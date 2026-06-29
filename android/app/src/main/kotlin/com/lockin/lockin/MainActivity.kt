package com.lockin.lockin

import android.Manifest
import android.app.AppOpsManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.os.Build
import android.os.Bundle
import android.os.Process
import android.os.SystemClock
import android.provider.Settings
import android.util.Base64
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.edit
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {
    private lateinit var intelligentMonitoring: IntelligentMonitoring

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        intelligentMonitoring = IntelligentMonitoring(this)
        createNotificationChannel()

        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (!prefs.contains(KEY_BLOCKED_PACKAGES)) {
            prefs.edit { putStringSet(KEY_BLOCKED_PACKAGES, emptySet()) }
        }
        if (!prefs.contains(KEY_USAGE_LIMIT_MS)) {
            prefs.edit { putLong(KEY_USAGE_LIMIT_MS, Constants.DEFAULT_USAGE_LIMIT_MS) }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getState" -> result.success(getState())
                "getInstalledApps" -> result.success(getInstalledApps())
                "toggleBlockedApp" -> toggleBlockedApp(call, result)
                "toggleBlocking" -> toggleBlocking(result)
                "setUsageLimit" -> setUsageLimit(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun getState(): Map<String, Any> {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val blockedPackages = prefs.getStringSet(KEY_BLOCKED_PACKAGES, emptySet()) ?: emptySet()
        val usageByPackage = blockedPackages.associateWith { packageName ->
            try {
                intelligentMonitoring.getUsageTime(packageName)
            } catch (_: Exception) {
                0L
            }
        }

        return mapOf(
            "isBlockingActive" to prefs.getBoolean(KEY_BLOCKING_ACTIVE, false),
            "blockedPackages" to blockedPackages.toList(),
            "usageByPackage" to usageByPackage,
            "usageLimitMs" to prefs.getLong(KEY_USAGE_LIMIT_MS, Constants.DEFAULT_USAGE_LIMIT_MS),
            "usageWindowMs" to Constants.USAGE_WINDOW_MS,
            "unlockText" to getUnlockText(prefs.getLong(KEY_ACTIVATION_ELAPSED, 0L)),
            "permissions" to mapOf(
                "usageAccess" to isUsageAccessGranted(),
                "accessibility" to isAccessibilityServiceEnabled(),
                "deviceAdmin" to isAdminActive()
            )
        )
    }

    private fun getInstalledApps(): List<Map<String, String>> {
        return packageManager.getInstalledApplications(PackageManager.GET_META_DATA)
            .filter { it.flags and ApplicationInfo.FLAG_SYSTEM == 0 }
            .sortedBy { packageManager.getApplicationLabel(it).toString().lowercase() }
            .map { app ->
                mapOf(
                    "packageName" to app.packageName,
                    "label" to packageManager.getApplicationLabel(app).toString(),
                    "icon" to encodeIcon(app.packageName)
                )
            }
    }

    private fun toggleBlockedApp(call: MethodCall, result: MethodChannel.Result) {
        val packageName = call.argument<String>("packageName")
        if (packageName.isNullOrBlank()) {
            result.error("bad_package", "Nedostaje package name.", null)
            return
        }

        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val isBlockingActive = prefs.getBoolean(KEY_BLOCKING_ACTIVE, false)
        val blockedPackages = (prefs.getStringSet(KEY_BLOCKED_PACKAGES, emptySet()) ?: emptySet()).toMutableSet()
        val isSelected = blockedPackages.contains(packageName)

        if (isBlockingActive && isSelected) {
            result.success(mapOf("message" to "Nije moguce ukloniti dok je blokiranje aktivno."))
            return
        }

        if (isSelected) {
            blockedPackages.remove(packageName)
        } else {
            blockedPackages.add(packageName)
        }

        prefs.edit { putStringSet(KEY_BLOCKED_PACKAGES, blockedPackages) }
        result.success(mapOf("message" to ""))
    }

    private fun setUsageLimit(call: MethodCall, result: MethodChannel.Result) {
        val minutes = call.argument<Int>("minutes")
        if (minutes == null || minutes !in 5..240) {
            result.error("bad_limit", "Limit mora biti izmedu 5 i 240 minuta.", null)
            return
        }

        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (prefs.getBoolean(KEY_BLOCKING_ACTIVE, false)) {
            result.success(mapOf("message" to "Limit mozes promijeniti kada blokiranje nije aktivno."))
            return
        }

        prefs.edit { putLong(KEY_USAGE_LIMIT_MS, minutes * 60 * 1000L) }
        result.success(mapOf("message" to ""))
    }

    private fun toggleBlocking(result: MethodChannel.Result) {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val isBlockingActive = prefs.getBoolean(KEY_BLOCKING_ACTIVE, false)

        if (!isBlockingActive) {
            when {
                !isAdminActive() -> {
                    requestDeviceAdmin()
                    result.success(mapOf("message" to "Ukljuci Device Admin dozvolu za Lockin."))
                    return
                }
                !isUsageAccessGranted() -> {
                    startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                    result.success(mapOf("message" to "Ukljuci Usage Access dozvolu za Lockin."))
                    return
                }
                !isAccessibilityServiceEnabled() -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(mapOf("message" to "Ukljuci Lockin u postavkama Pristupacnosti."))
                    return
                }
            }

            requestNotificationPermissionIfNeeded()
            prefs.edit {
                putBoolean(KEY_BLOCKING_ACTIVE, true)
                putLong(KEY_ACTIVATION_ELAPSED, SystemClock.elapsedRealtime())
            }
            startBlockService()
            result.success(mapOf("message" to "Blokiranje aktivirano."))
        } else {
            val activationElapsed = prefs.getLong(KEY_ACTIVATION_ELAPSED, 0L)
            val elapsed = (SystemClock.elapsedRealtime() - activationElapsed).coerceAtLeast(0L)
            if (elapsed < Constants.USAGE_WINDOW_MS) {
                result.success(mapOf("message" to "Limit jos nije istekao."))
                return
            }

            prefs.edit { putBoolean(KEY_BLOCKING_ACTIVE, false) }
            stopService(Intent(this, BlockForegroundService::class.java))
            result.success(mapOf("message" to "Blokiranje ugaseno."))
        }
    }

    private fun encodeIcon(packageName: String): String {
        return try {
            val drawable = packageManager.getApplicationIcon(packageName)
            val bitmap = if (drawable is BitmapDrawable) {
                drawable.bitmap
            } else {
                val width = drawable.intrinsicWidth.takeIf { it > 0 } ?: 96
                val height = drawable.intrinsicHeight.takeIf { it > 0 } ?: 96
                Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also {
                    val canvas = Canvas(it)
                    drawable.setBounds(0, 0, canvas.width, canvas.height)
                    drawable.draw(canvas)
                }
            }
            val output = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
            Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP)
        } catch (_: Exception) {
            ""
        }
    }

    private fun getUnlockText(activationElapsed: Long): String {
        if (activationElapsed <= 0L) return ""
        val elapsed = (SystemClock.elapsedRealtime() - activationElapsed).coerceAtLeast(0L)
        val remaining = Constants.USAGE_WINDOW_MS - elapsed
        if (remaining <= 0L) return ""
        val hours = TimeUnit.MILLISECONDS.toHours(remaining)
        val minutes = TimeUnit.MILLISECONDS.toMinutes(remaining) % 60
        return String.format("%02dh %02dm", hours, minutes)
    }

    private fun isUsageAccessGranted(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        val expectedComponentName = ComponentName(this, IGAccessibilityService::class.java).flattenToString()
        val enabledServices = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
        return enabledServices?.split(":")?.contains(expectedComponentName) == true
    }

    private fun isAdminActive(): Boolean {
        val dpm = getSystemService(DevicePolicyManager::class.java)
        return dpm.isAdminActive(ComponentName(this, MyDeviceAdminReceiver::class.java))
    }

    private fun requestDeviceAdmin() {
        val componentName = ComponentName(this, MyDeviceAdminReceiver::class.java)
        val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
            putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, componentName)
            putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, "Potrebno za zastitu aktivnog blokiranja.")
        }
        startActivity(intent)
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 44)
        }
    }

    private fun startBlockService() {
        try {
            ContextCompat.startForegroundService(this, Intent(this, BlockForegroundService::class.java))
        } catch (error: Exception) {
            Toast.makeText(this, error.message ?: "Ne mogu pokrenuti servis.", Toast.LENGTH_SHORT).show()
        }
    }

    private fun createNotificationChannel() {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(Constants.CHANNEL_ID, "Lockin Service", NotificationManager.IMPORTANCE_LOW)
        )
    }

    companion object {
        private const val CHANNEL = "lockin/app_blocker"
        const val PREFS_NAME = "ig_prefs"
        const val KEY_BLOCKED_PACKAGES = "blocked_packages"
        const val KEY_BLOCKING_ACTIVE = "is_blocking_active"
        const val KEY_ACTIVATION_ELAPSED = "block_activation_elapsed"
        const val KEY_USAGE_LIMIT_MS = "usage_limit_ms"
    }
}
