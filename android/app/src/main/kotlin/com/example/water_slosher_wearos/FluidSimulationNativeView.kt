package com.example.water_slosher_wearos

import android.content.Context
import android.graphics.Rect
import android.os.Build
import android.view.MotionEvent
import android.view.View
// import android.view.ViewParent // parent property is used directly
import io.flutter.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformViewFactory

class FluidSimulationNativeViewFactory(private val messenger: BinaryMessenger) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context?, viewId: Int, args: Any?): PlatformView {
        val creationParams = args as? Map<String?, Any?>
        return FluidSimulationNativeView(context!!, messenger, viewId, creationParams)
    }
}

// Constants for MethodChannel communication
private const val UPDATE_OBSTACLE_METHOD = "updateObstacle"
private const val SET_NATIVE_TOUCH_MODE_METHOD = "setNativeTouchMode"

class FluidSimulationNativeView(
    private val context: Context,
    private val messenger: BinaryMessenger,
    private val viewId: Int,
    private val creationParams: Map<String?, Any?>?
) : PlatformView, View(context), MethodChannel.MethodCallHandler {

    private lateinit var methodChannel: MethodChannel
    private var simWorldWidth: Double = 1.0 // Default value
    private var simWorldHeight: Double = 1.0 // Default value
    private var isNativeTouchEnabled: Boolean = false
    private var isDragging: Boolean = false
    private var isNewDrag: Boolean = true // To indicate the start of a new drag sequence

    private val TAG = "FluidSimNativeView"

    init {
        val channelName = "com.example.water_slosher_wearos/fluidSimulationNativeViewChannel_$viewId"
        methodChannel = MethodChannel(messenger, channelName)
        methodChannel.setMethodCallHandler(this)

        creationParams?.let {
            simWorldWidth = it["simWorldWidth"] as? Double ?: 1.0
            simWorldHeight = it["simWorldHeight"] as? Double ?: 1.0
            Log.d(TAG, "Initialized with simWorldWidth: $simWorldWidth, simWorldHeight: $simWorldHeight. View ID: $viewId")
        }
    }

    override fun getView(): View {
        return this
    }

    override fun dispose() {
        methodChannel.setMethodCallHandler(null)
        Log.d(TAG, "View $viewId disposed, method channel handler cleared.")
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        Log.d(TAG, "onMethodCall for view $viewId: ${call.method}")
        when (call.method) {
            SET_NATIVE_TOUCH_MODE_METHOD -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                isNativeTouchEnabled = enabled
                Log.d(TAG, "setNativeTouchMode for view $viewId called: $isNativeTouchEnabled")
                updateSystemGestureExclusionRects()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (!isNativeTouchEnabled) {
            Log.d(TAG, "View $viewId: Native touch disabled, not handling event: ${MotionEvent.actionToString(event.action)}")
            return super.onTouchEvent(event)
        }

        // Check if view is laid out
        if (width == 0 || height == 0) {
            Log.w(TAG, "View $viewId: onTouchEvent called before layout (width/height is 0). Ignoring event.")
            return false // Or super.onTouchEvent(event) if preferred
        }

        val viewX = event.x
        val viewY = event.y

        val simX = (viewX / width.toFloat()).coerceIn(0.0f, 1.0f)
        val simY = (viewY / height.toFloat()).coerceIn(0.0f, 1.0f)

        val obstacleData = mutableMapOf<String, Any>()

        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                Log.d(TAG, "View $viewId: ACTION_DOWN at ($viewX, $viewY) -> sim ($simX, $simY)")
                parent?.requestDisallowInterceptTouchEvent(true)
                isDragging = true
                isNewDrag = true
                obstacleData["simX"] = simX.toDouble()
                obstacleData["simY"] = simY.toDouble()
                obstacleData["isDragging"] = true
                obstacleData["isNewDrag"] = true
                methodChannel.invokeMethod(UPDATE_OBSTACLE_METHOD, obstacleData)
                isNewDrag = false
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                if (isDragging) {
                    Log.d(TAG, "View $viewId: ACTION_MOVE at ($viewX, $viewY) -> sim ($simX, $simY)")
                    obstacleData["simX"] = simX.toDouble()
                    obstacleData["simY"] = simY.toDouble()
                    obstacleData["isDragging"] = true
                    obstacleData["isNewDrag"] = false
                    methodChannel.invokeMethod(UPDATE_OBSTACLE_METHOD, obstacleData)
                    return true
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                val actionType = if (event.action == MotionEvent.ACTION_UP) "ACTION_UP" else "ACTION_CANCEL"
                Log.d(TAG, "View $viewId: $actionType at ($viewX, $viewY) -> sim ($simX, $simY)")
                parent?.requestDisallowInterceptTouchEvent(false)
                if (isDragging) {
                    isDragging = false
                    obstacleData["simX"] = simX.toDouble()
                    obstacleData["simY"] = simY.toDouble()
                    obstacleData["isDragging"] = false
                    obstacleData["isNewDrag"] = false
                    methodChannel.invokeMethod(UPDATE_OBSTACLE_METHOD, obstacleData)
                }
                isNewDrag = true
                return true
            }
        }
        return super.onTouchEvent(event)
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        Log.d(TAG, "View $viewId: onLayout called. changed: $changed, LTRB: ($left,$top,$right,$bottom), WxH: ($width x $height)")
        if (width > 0 && height > 0) { // Ensure view is actually laid out
            updateSystemGestureExclusionRects()
        }
    }

    private fun updateSystemGestureExclusionRects() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            if (isNativeTouchEnabled && width > 0 && height > 0) {
                val exclusionRect = Rect(0, 0, width, height)
                systemGestureExclusionRects = listOf(exclusionRect)
                Log.d(TAG, "View $viewId: System gesture exclusion rect set: $exclusionRect")
            } else {
                systemGestureExclusionRects = emptyList()
                Log.d(TAG, "View $viewId: System gesture exclusion rects cleared (isNativeTouchEnabled: $isNativeTouchEnabled, width: $width, height: $height).")
            }
        } else {
            Log.d(TAG, "View $viewId: System gesture exclusion rects not supported on API ${Build.VERSION.SDK_INT}.")
        }
    }
}