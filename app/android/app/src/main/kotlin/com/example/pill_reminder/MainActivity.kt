package com.example.pill_reminder

import android.annotation.SuppressLint
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Adds one small channel, "pill_reminder/background", so the Dart side can
 * check and fix Android's battery saving for this app. Phones such as realme,
 * OPPO and Xiaomi hold back alarms of apps that are "optimised", so dose
 * reminders would only appear when the app is opened again.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pill_reminder/background")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isIgnoringBatteryOptimizations" -> {
                        val power = getSystemService(POWER_SERVICE) as PowerManager
                        result.success(power.isIgnoringBatteryOptimizations(packageName))
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        result.success(requestIgnoreBatteryOptimizations())
                    }
                    "openAppSettings" -> {
                        result.success(open(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:$packageName"))))
                    }
                    "manufacturer" -> result.success(Build.MANUFACTURER)
                    else -> result.notImplemented()
                }
            }
    }

    /** Shows Android's "Let app always run in background?" dialog. */
    @SuppressLint("BatteryLife") // a medication reminder is exactly what this exemption is for
    private fun requestIgnoreBatteryOptimizations(): Boolean {
        val ask = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            Uri.parse("package:$packageName"))
        // Some phones hide that dialog; the full list of apps is the fallback.
        return open(ask) || open(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
    }

    private fun open(intent: Intent): Boolean = try {
        startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: Exception) {
        false
    }
}
