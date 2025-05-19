# Flutter Wear OS Input Integration Guide

This document provides **precise, step-by-step instructions** for a Code‑Modifying LLM (CM‑LLM) to integrate hardware input support into a Flutter Wear OS application. It covers three independent input types:

1. **Rotary Bezel** (sections 2–3)
2. **Raw Touch** (sections 2.e, 5.e)
3. **Accelerometer** (sections 4–5.b–5.d)

Each section explains **what** change is needed and **why** it’s required, references authoritative sources for validation, and gives **unambiguous** file paths and code blocks. A human reader can follow the “What” and “Why” explanations, while the CM‑LLM executes each modification exactly.

---

## 1. Configure AndroidManifest.xml for Standalone Wear OS

**What:** Make your Wear OS app installable on a watch by itself, without a paired phone.

**Why:** Wear OS requires a `<meta-data>` tag in `AndroidManifest.xml` to mark an app as **standalone**. Without it, Google Play may treat it as requiring a phone companion ([Android Developers](https://developer.android.com/training/wearables/packaging?utm_source=chatgpt.com)).

**File:** `android/app/src/main/AndroidManifest.xml`

> **Instruction:** Inside the top-level `<application>` element, immediately before `</application>`, insert **only**:

```xml
    <!-- enable standalone Wear OS installation -->
    <meta-data
        android:name="com.google.android.wearable.standalone"
        android:value="true" />
```

---

## 2. Modify MainActivity.kt for Rotary (Bezel) & Touch Input

**What:** Extend the Android host activity to listen for bezel rotation and touch, then forward events to Flutter via an `EventChannel`.

**Why:** Flutter by default doesn’t handle hardware rotary or raw touch on Wear OS. We register a custom channel so Dart code can react to bezel turns and taps ([Dart packages](https://pub.dev/packages/wearable_rotary?utm_source=chatgpt.com)).

**File:** `android/app/src/main/kotlin/com/example/bouncing_shape_wearos/MainActivity.kt`

> **Note:** Adjust the package path (`com/example/...`) to match the `package` declaration in your file.

### a) Add or verify imports at the top

```kotlin
import android.os.Bundle
import android.view.InputDevice
import android.view.MotionEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
```

### b) Declare bezel channel properties inside the `MainActivity` class, before any methods

```kotlin
private val BEZEL_CHANNEL = "bezel_rotation"
private var bezelEventSink: EventChannel.EventSink? = null
```

### c) Configure the `EventChannel` in `configureFlutterEngine`

> **Instruction:** Replace or insert the entire `configureFlutterEngine` override so it matches **exactly**:

```kotlin
override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    EventChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        BEZEL_CHANNEL
    ).setStreamHandler(
        object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                bezelEventSink = events
            }
            override fun onCancel(arguments: Any?) {
                bezelEventSink = null
            }
        }
    )
}
```

### d) Handle bezel rotation via `onGenericMotionEvent`

> **Why:** Rotary crowns/bezel send `ACTION_SCROLL` from `SOURCE_ROTARY_ENCODER`. We invert the sign so **clockwise → positive**.

```kotlin
override fun onGenericMotionEvent(event: MotionEvent?): Boolean {
    if (event?.action == MotionEvent.ACTION_SCROLL &&
        event.isFromSource(InputDevice.SOURCE_ROTARY_ENCODER)) {
        val rotationDelta = -event.getAxisValue(MotionEvent.AXIS_SCROLL)
        bezelEventSink?.success(rotationDelta.toDouble())
        return true
    }
    return super.onGenericMotionEvent(event)
}
```

### e) Forward raw touch events via `dispatchTouchEvent`

> **Why:** Ensures Flutter’s gesture recognizers (e.g. `GestureDetector`) receive screen taps and pans.

```kotlin
override fun dispatchTouchEvent(event: MotionEvent?): Boolean {
    if (event != null) {
        super.dispatchTouchEvent(event)
        return true
    }
    return super.dispatchTouchEvent(event)
}
```

---

## 3. Create Dart Bezel Channel (`lib/bezel_channel.dart`)

**What:** A Dart wrapper exposing a broadcast `Stream<double>` of bezel rotations.

**Why:** Cleanly abstracts the platform channel so UI code can subscribe to rotation changes.

**File to create:** `lib/bezel_channel.dart`

```dart
import 'dart:async';
import 'package:flutter/services.dart';

class BezelChannel {
  static const _channel = EventChannel('bezel_rotation');
  static Stream<double>? _rotationStream;

  /// Emits bezel rotation: positive = clockwise turns.
  static Stream<double> rotationStream() {
    _rotationStream ??= _channel
        .receiveBroadcastStream()
        .map((event) => event as double);
    return _rotationStream!;
  }
}
```

> *After creating this file, a human operator must run `flutter pub get` to register the platform channel.*

---

## 4. Add Accelerometer Plugin in `pubspec.yaml`

**What:** Include `sensors_plus` to read accelerometer data for physics interactions.

**Why:** Flutter’s core SDK doesn’t bundle advanced sensor APIs; `sensors_plus` is the official plugin ([DhiWise – AI App Builder for Everyone](https://www.dhiwise.com/post/implementing-flutter-sensors-plus-package?utm_source=chatgpt.com)).

**File:** `pubspec.yaml`

> **Instruction:** Under the existing `dependencies:` key, insert (two-space indent):

```yaml
  sensors_plus: ^2.0.0   # for accelerometer input
```

> *Then run `flutter pub get` manually.*

---

## 5. Update Dart UI Code (`lib/ball_simulator.dart`)

**What:** Hook accelerometer events and add touch‐drag handling around the physics simulation.

**Why:** Allow users to tilt the watch to move balls and drag by touch.

**File:** `lib/ball_simulator.dart`

### a) Import the plugin

```dart
import 'package:sensors_plus/sensors_plus.dart';
```

### b) Declare a subscription inside `_BallSimulatorState`

```dart
StreamSubscription<AccelerometerEvent>? _accelSub;
```

### c) Replace or insert the `initState` method exactly

```dart
@override
void initState() {
  super.initState();
  _accelSub = accelerometerEvents.listen((evt) {
    setState(() {
      _physics.applyAcceleration(evt.x, evt.y);
    });
  });
}
```

### d) Replace or insert the `dispose` method exactly

```dart
@override
void dispose() {
  _accelSub?.cancel();
  super.dispose();
}
```

### e) Wrap your `CustomPaint` in `GestureDetector`

> **Instruction:** In the `build` method, locate the line with `CustomPaint(/* ... */)` and **replace** it with:

```dart
GestureDetector(
  onPanDown:   (details) => _startDrag(details.localPosition),
  onPanUpdate: (details) => _updateDrag(details.localPosition),
  onPanEnd:    (_)       => _endDrag(),
  child: CustomPaint(/* ... draws balls ... */),
)
```

---

## 6. Update Project-Level Gradle Files

**What:** Ensure the Android Gradle plugin and Kotlin plugin are declared so the project can compile Kotlin code in your modifications.

**Why:** Without the proper `buildscript` or `plugins` blocks, your Wear OS integrations fail to compile.

### 6.1 Groovy Syntax (`android/build.gradle`)

> **File:** `android/build.gradle`

1. **Insert** at the very top (before any existing lines):

   ```groovy
   buildscript {
       ext.kotlin_version = '1.8.21'
       repositories {
           google()
           mavenCentral()
       }
       dependencies {
           classpath "com.android.tools.build:gradle:7.4.2"
           classpath "org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlin_version"
       }
   }
   ```

2. **Ensure** the `allprojects { repositories { … } }` block reads:

   ```groovy
   allprojects {
       repositories {
           google()
           mavenCentral()
       }
   }
   ```

> **Sensibility note:**
> Current Flutter 3.29 projects often use a `plugins { … }` block in `settings.gradle.kts` instead.
> If your project already uses the **Kotlin DSL** plugin mechanism, you **must** adjust **settings.gradle.kts** rather than add a `buildscript` block here ([Code With Andrea](https://codewithandrea.com/articles/flutter-android-gradle-kts/?utm_source=chatgpt.com)).

### 6.2 Kotlin Script Syntax (`android/build.gradle.kts`)

> **File:** `android/build.gradle.kts`

1. **Insert** at the very top:

   ```kotlin
   buildscript {
       extra["kotlin_version"] = "1.8.21"
       repositories {
           google()
           mavenCentral()
       }
       dependencies {
           classpath("com.android.tools.build:gradle:7.4.2")
           classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:${extra["kotlin_version"]}")
       }
   }
   ```

2. **Ensure** the `allprojects { repositories { … } }` block reads:

   ```kotlin
   allprojects {
       repositories {
           google()
           mavenCentral()
       }
   }
   ```

> **Sensibility note:**
> New Flutter 3.29 Kotlin-DSL templates generated via `flutter create` often declare plugins in `settings.gradle.kts` instead.
> Consult your `settings.gradle.kts`—if you see a `pluginManagement { ... }` or `plugins { ... }` block handling `com.android.tools.build`, **do not** add this `buildscript` block; instead adapt the existing plugin DSL ([Code With Andrea](https://codewithandrea.com/articles/flutter-android-gradle-kts/?utm_source=chatgpt.com)).

---

### Final Remarks

* Each section is **atomic** and explicit for a CM-LLM to apply.

* After all modifications, a human operator should execute:

  ```bash
  cd android && ./gradlew clean assembleDebug
  flutter pub get
  flutter run
  ```

* **Sensibility Check:** If your project’s Gradle setup deviates (e.g., newer Kotlin-DSL in `settings.gradle.kts`), update **only** the plugin declarations there rather than via `buildscript`.

---

### Summary of Instructions

**What to Change:**

* **Manifest:** Add standalone Wear OS meta-data.
* **MainActivity.kt:** Register an `EventChannel`, handle bezel rotation via `onGenericMotionEvent`, and forward touch via `dispatchTouchEvent`.
* **Dart BezelChannel:** Create `lib/bezel_channel.dart` with a `Stream<double>` API for bezel events.
* **Accelerometer Integration:** Add `sensors_plus` dependency and wire accelerometer events in `ball_simulator.dart` (initState, dispose, subscription).
* **Touch Integration:** Wrap `CustomPaint` in a `GestureDetector` for drag/tap.
* **Gradle Files:** Add appropriate `buildscript`/plugins blocks for Groovy or Kotlin DSL.

**Concept:**
Implement a **platform channel** between Android and Flutter that handles Wear OS–specific inputs (rotary bezel, raw touch) and sensor-based accelerometer data to enable responsive, hardware-integrated UI controls on Wear OS devices.
Implement a **platform channel** between Android and Flutter that handles Wear OS–specific inputs (rotary bezel and touch/accelerometer) to enable responsive, hardware-integrated UI controls on Wear OS devices.
