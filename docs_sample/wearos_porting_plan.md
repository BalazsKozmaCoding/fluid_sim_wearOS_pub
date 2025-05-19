# Wear OS Porting Plan

This document outlines the plan for porting the water slosher application to Wear OS.

## Current Status

- [ ] Assess compatibility of existing Flutter code with Wear OS.
- [ ] Identify necessary UI/UX adjustments for a small circular screen.
- [ ] Research Wear OS specific features and APIs.

## Next Steps

- [ ] Create a new Wear OS project or add Wear OS support to the existing project.
- [ ] Adapt the UI to the Wear OS form factor.
- [ ] Implement sensor data handling for Wear OS.
- [ ] Test on Wear OS emulator and physical devices.


Okay, let's assess the work involved in porting this Flutter application to Wear OS.

# Assessment: Porting Water Slosher Simulation to Wear OS (by Gemini Pro)

**Executive Summary:**

Porting the "Water Slosher" Flutter application to Wear OS is **feasible**, but presents **significant challenges**, primarily due to **performance constraints** on wearable devices and the need for substantial **UI/UX redesign** for the small, round screen format. The core Dart simulation logic and sensor integration are largely platform-agnostic, but rendering performance and adapting interactions (touch, physics boundaries) to the watch face require considerable effort. Expect a non-trivial amount of work, moving beyond simple code reuse to involve architectural adjustments and platform-specific considerations.

**Detailed Breakdown by Component:**

1.  **Core Simulation Logic (`flip_fluid_simulation.dart`):**
    *   **Portability:** High. The physics simulation is written in pure Dart using standard math and typed lists. It contains no direct platform dependencies.
    *   **Required Changes:** Minimal to none for the logic itself.
    *   **Challenges/Considerations:**
        *   **Performance:** This is the *biggest* concern. Wear OS devices have significantly less CPU power and RAM than phones. The simulation, especially the pressure solver and particle separation loops, might be too slow for an acceptable frame rate even with the recent optimizations, necessitating:
            *   Drastically lower default particle counts.
            *   Reduced grid resolution (larger `spacing`).
            *   Fewer solver iterations (`numPressureIters`, `numParticleIters`).
        *   **Round Boundaries:** The physics simulation currently assumes rectangular walls. The `handleParticleCollisions` function needs modification to implement *round* boundary conditions that match the watch face. This involves changing the wall collision checks from simple `x < minX`, `x > maxX`, etc., to distance-from-center checks.

2.  **Rendering (`particle_renderer.dart`):**
    *   **Portability:** Medium. `CustomPaint` works on Wear OS, but its performance characteristics are critical.
    *   **Required Changes:**
        *   **Performance:** The current CPU-bound `canvas.drawPoints` loop will be a major bottleneck. For acceptable performance with more than a handful of particles, transitioning to GPU-accelerated rendering (`dart:ui.Vertices`, `dart:ui.FragmentProgram`) is likely **essential**.
        *   **Round Adaptation:** The renderer needs to visually account for the round display. While Flutter clips automatically, you might want to adjust the drawing area or scaling (`scaleX`, `scaleY`) to neatly fit within the circle. The drawing of the *grid* (if enabled) would also need adapting to look sensible on a round display.
    *   **Challenges/Considerations:** Implementing GPU rendering is a significant task requiring knowledge of shaders and lower-level graphics APIs. Ensuring the visual representation matches the new round physics boundaries.

3.  **UI Shell & Layout (`simulation_screen.dart`):**
    *   **Portability:** Low. The current phone-centric layout (AppBar simulation, bottom FABs, large canvas area) is unsuitable for Wear OS.
    *   **Required Changes:** Complete redesign following Wear OS design principles. This involves:
        *   Using a Wear OS-specific scaffold or navigation structure (e.g., potentially `PageView` for different views/settings).
        *   Adapting or replacing widgets with wearable-friendly alternatives (e.g., smaller buttons, curved layouts if desired). Libraries like `flutter_wear` (if maintained/suitable) or custom implementations might be needed.
        *   Managing state within a potentially different widget structure.
    *   **Challenges/Considerations:** Designing an intuitive UI for simulation control and visualization on a tiny screen. Ensuring information density is appropriate.

4.  **Touch Input (`GestureDetector`, `_toSimCoords`):**
    *   **Portability:** Medium. `GestureDetector` itself works.
    *   **Required Changes:**
        *   The `_toSimCoords` mapping needs adjustment if the simulation area is mapped to the inscribed circle rather than the full square bounding box of the screen size.
        *   The logic in `onPanEnd` (calling `sim.initializeGrid`) needs to be coordinated with the new round boundary conditions – it should reset the *interior* grid cells, not just based on rectangular walls.
    *   **Challenges/Considerations:** Touch interaction precision on a small screen. Deciding how the obstacle interaction should behave near the round edges.

5.  **Sensor Input (`sensor_service.dart`, Accelerometer Handling):**
    *   **Portability:** High. `sensors_plus` package supports Android, including Wear OS.
    *   **Required Changes:**
        *   Ensure the `AndroidManifest.xml` for the Wear OS target correctly declares sensor permissions (`android.permission.BODY_SENSORS`).
        *   Test and potentially adjust the axis mapping (`gravityX = event.x * 9.81`, etc.) as the orientation and typical movement of a watch differ from a phone.
    *   **Challenges/Considerations:** Background sensor usage and battery impact on wearables. Ensuring reliable sensor readings.

6.  **Configuration/Settings (Modal Sheet):**
    *   **Portability:** Very Low. Modal bottom sheets are not a standard Wear OS pattern.
    *   **Required Changes:** Complete replacement with a Wear OS-appropriate mechanism. Options include:
        *   A dedicated settings screen (navigated via swipe, long-press, or button).
        *   Using rotary input (if the device has it) to adjust parameters.
        *   Simplifying the available settings drastically to only the most essential ones (e.g., Particle Count toggle, Show Grid toggle).
    *   **Challenges/Considerations:** Designing a discoverable and usable settings interface on the watch.

7.  **Build & Platform Configuration:**
    *   **Portability:** N/A - This is platform setup.
    *   **Required Changes:** Creating a new Wear OS application target, configuring the specific `AndroidManifest.xml` (`uses-feature android.hardware.type.watch`, permissions), handling dependencies, potentially managing different build flavors.
    *   **Challenges/Considerations:** Standard Flutter setup for a new platform target.

**Overall Effort Estimation:**

*   **Core Simulation Logic Adaptation (Round Boundary):** Medium
*   **Rendering Performance Overhaul (GPU):** High / Very High (if unfamiliar with shaders)
*   **UI/UX Redesign:** High
*   **Touch Input Adaptation:** Low / Medium
*   **Sensor Integration:** Low
*   **Settings Redesign:** Medium
*   **Build Configuration:** Low / Medium

**Total Effort:** **Significant.** This is not a simple recompile. The core performance bottlenecks and the required UI/UX overhaul for the wearable form factor constitute the bulk of the work. Adapting the physics and rendering to the round display is also non-trivial.

**Recommendations:**

1.  **Prioritize Performance:** Address the rendering bottleneck early. Profile on a target Wear OS device (or emulator) to confirm `CustomPaint` limitations. Plan for GPU rendering if > ~100-200 particles are desired.
2.  **Simplify Aggressively:** Start with the absolute minimum viable features. Drastically reduce particle count, grid resolution, and settings initially.
3.  **Design for Wear OS:** Don't try to shrink the phone UI. Redesign from scratch using Wear OS guidelines.
4.  **Tackle Roundness:** Implement the round physics boundaries in `handleParticleCollisions` and adapt rendering coordinates accordingly.
5.  **Iterate:** Get a basic version running (low particle count, simple UI, basic touch/sensor) and then incrementally improve performance, UI, and features.