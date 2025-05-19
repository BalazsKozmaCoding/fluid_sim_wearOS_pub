# Wear OS Porting Summary & Testing Reference

This document summarizes the key modifications and implementations made to port the FLIP fluid simulation application to Wear OS. It serves as a reference for testing and troubleshooting.

## 1. Android Project Configuration
*   **File:** [`android/app/src/main/AndroidManifest.xml`](android/app/src/main/AndroidManifest.xml)
    *   Added `<uses-feature android:name="android.hardware.type.watch" />`
    *   Added `<meta-data android:name="com.google.android.wearable.standalone" android:value="true" />`
    *   Added `<uses-permission android:name="android.permission.WAKE_LOCK" />`
*   **File:** [`android/app/build.gradle`](android/app/build.gradle)
    *   Reviewed `minSdkVersion`: Confirmed as `flutter.minSdkVersion`.
    *   Reviewed NDK/CMake: Confirmed ABI compatibility for Wear OS (e.g., `armeabi-v7a`, `arm64-v8a` are expected to be built).

## 2. UI/UX Adaptations
*   **File:** [`lib/simulation_screen.dart`](lib/simulation_screen.dart)
    *   Removed user-configurable settings panel and its trigger button from the AppBar.
    *   Retained "Info" dialog button in AppBar.
    *   Wrapped main UI in `SafeArea` for better compatibility with round/notched screens.
    *   Adjusted AppBar title size for better fit.
    *   Repositioned Floating Action Buttons (Start/Stop, Reset) with increased bottom padding for better accessibility on Wear OS.
*   **File:** [`lib/particle_renderer.dart`](lib/particle_renderer.dart)
    *   Implemented uniform scaling and centering of the simulation rendering. This ensures the circular simulation boundary is displayed correctly and fully visible on various Wear OS screen sizes and shapes.

## 3. Input System Integration
*   **Touch Input:**
    *   **File:** [`lib/simulation_screen.dart`](lib/simulation_screen.dart)
    *   Existing `GestureDetector` for obstacle control (`onPanStart`, `onPanUpdate`, `onPanEnd`) was reviewed and deemed suitable for Wear OS. Coordinate mapping (`_toSimCoords`) should be correct.
*   **Accelerometer Input:**
    *   **File:** [`lib/simulation_screen.dart`](lib/simulation_screen.dart)
    *   Existing `SensorService` integration for gravity via accelerometer was reviewed and deemed suitable.
*   **Rotary Input (Bezel/Crown):**
    *   **File:** [`android/app/src/main/kotlin/com/example/water_slosher_250428/MainActivity.kt`](android/app/src/main/kotlin/com/example/water_slosher_250428/MainActivity.kt)
        *   Overridden `onGenericMotionEvent` to detect rotary scroll events.
        *   Sends scroll delta via a `MethodChannel` named "com.example.water_slosher/bezel".
    *   **File:** [`lib/bezel_channel.dart`](lib/bezel_channel.dart) (New file)
        *   Manages the Dart side of the "com.example.water_slosher/bezel" `MethodChannel`.
        *   Listens for rotary events from native code and exposes them (e.g., via a Stream).
    *   **File:** [`lib/simulation_screen.dart`](lib/simulation_screen.dart)
        *   Integrates `BezelChannelService`.
        *   Uses rotary input to adjust `simOptions.obstacleRadius` (between 0.05 and 0.3).
        *   Calls `_updateSimulationOptions()` to apply changes.

## 4. Simulation Core & Parameter Handling
*   **File:** [`lib/simulation_screen.dart`](lib/simulation_screen.dart) (specifically `_resetToDefaults` or similar)
    *   Default `SimOptions` adjusted for Wear OS:
        *   `particleCount` reduced to `300`.
        *   `pressureIters` (number of pressure iterations) reduced to `30`.
    *   Other default parameters were reviewed and maintained.
*   **File:** [`lib/flip_fluid_simulation.dart`](lib/flip_fluid_simulation.dart)
    *   Core simulation logic remains unchanged as per requirements.
    *   Integration with `SimulationScreen` and data flow to `ParticleRenderer` verified.

## 5. Key Files for Testing Focus
*   [`lib/simulation_screen.dart`](lib/simulation_screen.dart): Overall UI, FABs, touch input, accelerometer integration, rotary input integration, default parameter initialization.
*   [`lib/particle_renderer.dart`](lib/particle_renderer.dart): Correct rendering within screen boundaries, especially on round screens.
*   [`lib/bezel_channel.dart`](lib/bezel_channel.dart) & [`android/app/src/main/kotlin/com/example/water_slosher_250428/MainActivity.kt`](android/app/src/main/kotlin/com/example/water_slosher_250428/MainActivity.kt): Rotary input functionality.
*   [`android/app/src/main/AndroidManifest.xml`](android/app/src/main/AndroidManifest.xml): Correct Wear OS declaration.

## 6. Documentation for Future Enhancements
*   Ideas for future simulation improvements should be logged in [`docs/simulation_enhancement_ideas.md`](docs/simulation_enhancement_ideas.md).