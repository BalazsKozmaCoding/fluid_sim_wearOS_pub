
# Flutter for Wear OS: Input Handling Guide

This document summarizes learnings and provides guidance for implementing common Wear OS inputs (touch, accelerometer, rotary bezel) in Flutter applications, based on the "Pentagon Interaction" project.

## 1. Touch Input (Dragging Objects)

### Conceptual Overview
-   Describe how touch input was used for dragging an object on the screen.
-   Mention the general approach (e.g., detecting pan gestures, updating object position).

### Technical Implementation
-   **Flutter Widget:** `GestureDetector` (specifically `onPanStart`, `onPanUpdate`, `onPanEnd`).
-   **State Management:** How the object's position was stored and updated (e.g., `Offset` in a `StatefulWidget`).
-   **Rendering:** How the object was re-rendered at the new position (e.g., using `Positioned` within a `Stack`, or `Transform.translate`).
-   **Hit Testing:** Briefly mention the approach used for determining if the touch was on the object (e.g., bounding circle/box).
-   Refer to relevant sections of [`lib/main.dart`](lib/main.dart:1) from the "Pentagon Interaction" project as an example.

### LLM Instructions for Touch Input
```
When implementing touch-based dragging of a UI element in Flutter for Wear OS:
1. Wrap the target widget (or its interactive area) with a `GestureDetector`.
2. Implement `onPanStart` to record the initial touch point and confirm the drag should begin (e.g., check if the touch is within the object's bounds).
3. Implement `onPanUpdate` to calculate the new position of the element based on `details.delta` and update the state variable holding the element's position.
4. Implement `onPanEnd` for any cleanup if necessary.
5. Ensure the widget displaying the element re-renders when its position state changes (e.g., by calling `setState`).
6. For hit testing, a simple bounding box or bounding circle check against the touch coordinates is often sufficient for Wear OS.
```

## 2. Accelerometer Input (Motion-based Interaction)

### Conceptual Overview
-   Describe how accelerometer data was used to make an object slide based on watch tilt.
-   Mention the general approach (e.g., listening to sensor events, mapping sensor data to screen movement).

### Technical Implementation
-   **Package:** `sensors_plus` (mention adding it to [`pubspec.yaml`](pubspec.yaml:0)).
-   **Event Stream:** Listening to `accelerometerEvents`.
-   **Data Processing:** How accelerometer data (X, Y values) was mapped to changes in the object's on-screen position.
-   **Sensitivity/Filtering:** Briefly discuss considerations for movement sensitivity or data smoothing (if any insights were gained, otherwise state it's an area for tuning).
-   **State Management:** Updating the object's position state based on processed sensor data.
-   **Screen Boundaries:** How the object was kept within screen limits.
-   Refer to relevant sections of [`lib/main.dart`](lib/main.dart:1) as an example.

### LLM Instructions for Accelerometer Input
```
When implementing accelerometer-based movement for a UI element in Flutter for Wear OS:
1. Add the `sensors_plus` package to your `pubspec.yaml`.
2. Subscribe to the `accelerometerEvents` stream in your `StatefulWidget`'s `initState`. Remember to cancel the subscription in `dispose`.
3. In the event handler, process the `AccelerometerEvent` data (typically `event.x` and `event.y` for 2D screen movement, adjusting for watch orientation).
4. Apply a sensitivity factor to the sensor readings to control the speed/responsiveness of the movement.
5. Update the state variable holding the element's position based on the processed sensor data (e.g., `newPosition = currentPosition + Offset(processedX, processedY)`).
6. Implement logic to keep the element within the screen boundaries.
7. Ensure the widget re-renders when its position state changes.
8. Note: Accelerometer data can be noisy; consider simple filtering or averaging if needed, though often direct mapping with a sensitivity factor is a good start.
```

## 3. Rotary Bezel Input (Rotational Control)

### Conceptual Overview
-   Describe how rotary bezel input was used to control an object's property (e.g., size).
-   Highlight the challenges and the successful approach.

### Technical Implementation & Learnings
-   **Initial Attempt (and common pitfall):** Briefly mention the experience with the `wearable_rotary` package (or similar direct Flutter packages) and why it might not have worked out-of-the-box in this project (e.g., "In this project, the `wearable_rotary` package did not function as expected, necessitating a custom solution.").
-   **Successful Approach: Custom Platform Channel**
    -   **Rationale:** Explain why a platform channel was chosen (e.g., direct access to native OS events for reliability, as suggested by external documentation like [`lib/flutter_wearos_rotary_touch_input.md`](lib/flutter_wearos_rotary_touch_input.md:1)).
    -   **Native Side (Android/Kotlin):**
        -   File: [`MainActivity.kt`](android/app/src/main/kotlin/com/example/wearos_accel_touch_bezel_study/MainActivity.kt:1).
        -   Key Android API: Overriding `onGenericMotionEvent` in the `FlutterActivity` (or `Activity`) to capture `MotionEvent.ACTION_SCROLL`.
        -   Extracting scroll delta: `event.getAxisValue(MotionEvent.AXIS_SCROLL)`.
        -   Sending data to Flutter: Using `MethodChannel.invokeMethod`.
    -   **Dart Side (Flutter):**
        -   File: [`lib/bezel_channel.dart`](lib/bezel_channel.dart:1) (or wherever the channel was defined).
        -   Defining the `MethodChannel`.
        -   Setting up a `setMethodCallHandler` (if native calls Dart) or listening to `invokeMethod` calls from native. In this project, native invoked Dart. (Correction: Dart invokes native to set up, native sends events back via the channel). The `MainActivity.kt` sends events, and Dart listens.
        -   File: [`lib/main.dart`](lib/main.dart:1) (how the channel was used to update state).
-   **State Management:** How the controlled property (e.g., size) was updated based on bezel events.

### LLM Instructions for Rotary Bezel Input (Platform Channel Method)
```
Implementing rotary bezel input in Flutter for Wear OS can be challenging with direct Flutter packages. A robust method involves a custom platform channel:

**1. Native Android (Kotlin) Side (e.g., in `MainActivity.kt`):**
   a. Define a `MethodChannel` in your `FlutterActivity`'s `configureFlutterEngine`.
      ```kotlin
      import io.flutter.embedding.android.FlutterActivity
      import io.flutter.embedding.engine.FlutterEngine
      import io.flutter.plugin.common.MethodChannel
      import android.view.MotionEvent

      class MainActivity: FlutterActivity() {
          private val CHANNEL = "com.example.wearos_accel_touch_bezel_study/bezel" // Use your app's unique channel name
          private var channel: MethodChannel? = null

          override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
              super.configureFlutterEngine(flutterEngine)
              channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
          }

          override fun onGenericMotionEvent(event: MotionEvent?): Boolean {
              if (event?.action == MotionEvent.ACTION_SCROLL && event.isFromSource(android.view.InputDevice.SOURCE_ROTARY_ENCODER)) {
                  val delta = event.getAxisValue(MotionEvent.AXIS_SCROLL)
                  // Send delta to Flutter (positive for clockwise, negative for counter-clockwise)
                  // Note: The sign might depend on the device or OS version. Test and adjust.
                  // A common convention is that a negative delta from AXIS_SCROLL means clockwise rotation.
                  channel?.invokeMethod("onBezelScroll", mapOf("delta" to delta))
                  return true
              }
              return super.onGenericMotionEvent(event)
          }
      }
      ```
   b. Override `onGenericMotionEvent` in your `MainActivity.kt`.
   c. Check for `MotionEvent.ACTION_SCROLL` and `event.isFromSource(android.view.InputDevice.SOURCE_ROTARY_ENCODER)`.
   d. Get the scroll delta using `event.getAxisValue(MotionEvent.AXIS_SCROLL)`.
   e. Use the `MethodChannel` to `invokeMethod` (e.g., "onBezelScroll") sending the delta to Flutter.

**2. Flutter (Dart) Side:**
   a. Create a Dart file (e.g., `bezel_channel.dart`) to manage the channel.
      ```dart
      import 'package:flutter/services.dart';
      import 'dart:async'; // Added for StreamController

      class BezelChannel {
        static const MethodChannel _channel =
            MethodChannel('com.example.wearos_accel_touch_bezel_study/bezel'); // Must match native

        static Stream<double> get bezelEvents {
          // It's better to use an EventChannel for continuous streams from native to Dart.
          // However, if native frequently calls invokeMethod, you can set up a handler
          // on the Dart side to process these calls and feed them into a StreamController.
          // For simplicity with invokeMethod from native:
          final controller = StreamController<double>.broadcast();
          _channel.setMethodCallHandler((call) async {
            if (call.method == 'onBezelScroll') {
              final double delta = call.arguments['delta'];
              controller.add(delta);
            }
          });
          return controller.stream;
        }
      }
      ```
   b. In your main UI widget (`StatefulWidget` in `lib/main.dart`):
      - Import your bezel channel.
      - Listen to the `bezelEvents` stream in `initState`.
      - Process the delta (e.g., adjust size state). Remember to handle the sign of the delta appropriately (e.g., negative delta might mean clockwise).
      - Cancel the stream subscription in `dispose`.

**Important Considerations:**
- The sign of the delta from `AXIS_SCROLL` can vary. Test thoroughly. A common convention is that a negative delta indicates clockwise rotation.
- For continuous events like rotary input, an `EventChannel` is often more semantically correct than repeated `invokeMethod` calls from native to Dart, but the `invokeMethod` approach shown works.
- Ensure the channel name is unique and matches exactly between native and Dart.
```
---