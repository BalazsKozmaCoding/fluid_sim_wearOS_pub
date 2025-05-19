package com.example.water_slosher_wearos

import android.content.Context
import android.os.Build
import android.os.Bundle // Added for onCreate
import android.os.PowerManager
import android.view.View
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.core.view.WindowInsetsCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.Log
import android.view.MotionEvent
import android.view.InputDevice // Added for SOURCE_ROTARY_ENCODER
import android.view.WindowManager // Added for keeping screen on
import android.os.HardwarePropertiesManager // Added for temperature

class MainActivity: FlutterActivity() {
    private val BEZEL_CHANNEL_NAME = "com.example.water_slosher/bezel" // Unique channel name
    private val TEMPERATURE_CHANNEL_NAME = "com.example.water_slosher/temperature"
    private var bezelChannel: MethodChannel? = null
    private var temperatureChannel: MethodChannel? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val TAG = "MainActivity" // Consolidated TAG

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Keep the screen on
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        Log.d(TAG, "onCreate: FLAG_KEEP_SCREEN_ON added.")
        // Acquire a partial wake lock to keep the CPU running
        // Note: FLAG_KEEP_SCREEN_ON is usually preferred for keeping screen on.
        // This wake lock is more about ensuring the app itself doesn't get killed quickly.
        // For Wear OS, screen timeout is managed by system settings, but FLAG_KEEP_SCREEN_ON
        // tells the system this specific window wants to stay on.
        // The 45 seconds requirement is better handled by FLAG_KEEP_SCREEN_ON
        // and ensuring the app is in the foreground.
        // If more aggressive wake lock is needed:
        // val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        // wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "WaterSlosher::MyWakelockTag")
        // wakeLock?.acquire(45 * 1000L) // 45 seconds
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d(TAG, "Configuring Flutter Engine.")
        // Bezel Channel
        bezelChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BEZEL_CHANNEL_NAME)
        // The bezel channel in this version of MainActivity only sends from native to Flutter (onGenericMotionEvent)
        // So, no setMethodCallHandler is strictly needed here unless Flutter needs to call native via this channel.
        // For consistency with previous versions or future use, one could be added:
        bezelChannel?.setMethodCallHandler { call, result ->
            Log.d(TAG, "Bezel channel call received from Flutter: ${call.method}")
            result.notImplemented()
        }
        Log.d(TAG, "Bezel MethodChannel established ($BEZEL_CHANNEL_NAME).")


        // Temperature Channel
        temperatureChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TEMPERATURE_CHANNEL_NAME)
        temperatureChannel?.setMethodCallHandler { call, result ->
            if (call.method == "getDeviceTemperature") {
                Log.d(TAG, "Temperature channel call received: ${call.method}")
                val temperature = getCpuTemperature()
                if (temperature != null) {
                    result.success(temperature)
                } else {
                    result.error("UNAVAILABLE", "CPU temperature not available.", null)
                }
            } else {
                result.notImplemented()
            }
        }
        Log.d(TAG, "Temperature MethodChannel established ($TEMPERATURE_CHANNEL_NAME).")

        // Register Native View Factory
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "com.example.water_slosher_wearos/fluidSimulationNativeView", // Ensure this matches the viewType in Dart
                FluidSimulationNativeViewFactory(flutterEngine.dartExecutor.binaryMessenger)
            )
        Log.d(TAG, "FluidSimulationNativeViewFactory registered.")
    }

    private fun getCpuTemperature(): Float? {
        // HardwarePropertiesManager is API 24+
        // N_MR1 is API 25. getDeviceTemperatures itself was added in API 24.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                val hpm = context.getSystemService(Context.HARDWARE_PROPERTIES_SERVICE) as HardwarePropertiesManager
                // DEVICE_TEMPERATURE_CPU = 0
                // TEMPERATURE_CURRENT = 1
                val temps = hpm.getDeviceTemperatures(HardwarePropertiesManager.DEVICE_TEMPERATURE_CPU, HardwarePropertiesManager.TEMPERATURE_CURRENT)
                
                if (temps.isNotEmpty()) {
                    Log.d(TAG, "CPU Temperatures: ${temps.joinToString()}")
                    // Return the first reported CPU temperature.
                    // Some devices might report multiple, or it might be an average.
                    return temps[0]
                } else {
                    Log.d(TAG, "No CPU temperatures reported by HardwarePropertiesManager.")
                    return null
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error getting CPU temperature: ${e.message}", e)
                return null
            }
        } else {
            Log.w(TAG, "HardwarePropertiesManager not available on this API level (${Build.VERSION.SDK_INT}). CPU temp unavailable.")
            return null
        }
    }

    override fun onGenericMotionEvent(event: MotionEvent?): Boolean {
        if (event?.action == MotionEvent.ACTION_SCROLL && event.isFromSource(InputDevice.SOURCE_ROTARY_ENCODER)) {
            val delta = event.getAxisValue(MotionEvent.AXIS_SCROLL)
            // Log.d(TAG, "Rotary scroll delta: $delta") // Log only if needed for debugging
            bezelChannel?.invokeMethod("onBezelScroll", mapOf("delta" to delta))
            return true
        }
        return super.onGenericMotionEvent(event)
    }

    private fun setImmersiveMode() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            WindowCompat.setDecorFitsSystemWindows(window, false)
            val controller = WindowInsetsControllerCompat(window, window.decorView)
            controller.hide(WindowInsetsCompat.Type.systemBars())
            controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            Log.d(TAG, "Immersive mode set for Android R+")
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_FULLSCREEN
            )
            Log.d(TAG, "Immersive mode set for pre-Android R")
        }
    }

    override fun onPostResume() {
        super.onPostResume()
        setImmersiveMode()
    }

    override fun onDestroy() {
        Log.d(TAG, "MainActivity onDestroy called.")
        // Release the wake lock if it was acquired
        // if (wakeLock?.isHeld == true) {
        //     wakeLock?.release()
        // }
        // Remove the flag to allow screen to turn off
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        
        bezelChannel?.setMethodCallHandler(null)
        bezelChannel = null
        temperatureChannel?.setMethodCallHandler(null)
        temperatureChannel = null
        Log.d(TAG, "Channels cleaned up.")
        super.onDestroy()
    }
}
