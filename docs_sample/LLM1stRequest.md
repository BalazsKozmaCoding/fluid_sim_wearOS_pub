**Project Context:** I need to develop a Flutter application called "Water Slosher". The core task is porting a 2D FLIP fluid simulation from an existing JavaScript implementation (detailed in **the attached HTML file containing the JavaScript FLIP implementation**) to Flutter, initially for mobile, then Wear OS. **The attached PDF document providing theoretical background on the FLIP method** offers conceptual background. Key features include accelerometer-based gravity, touch-based obstacle interaction (similar to the mouse interaction in the HTML demo), and particle rendering.

**Request:** Please provide a comprehensive, single-response project starter pack to minimize back-and-forth communication. I need the following components included in your response:

1.  **Brief Technical Analysis:**
    *   Identify the main technical challenges (e.g., simulation performance, rendering performance, touch input handling, cross-platform adaptation).
    *   Suggest initial technology choices for simulation core (Dart Typed Lists vs. potential FFI) and rendering (CustomPaint vs. SkSL), briefly justifying them.

2.  **High-Level Project Plan:**
    *   Outline the main phases (e.g., Mobile Core Sim, Mobile Render, Mobile Interaction [Gravity & Touch], Wear OS Adapt, Polish).
    *   List key steps/tasks within each phase.

3.  **Proposed File Structure:**
    *   Show a recommended directory structure within the `lib` folder (e.g., `lib/simulation`, `lib/rendering`, `lib/ui`, `lib/sensors`, `lib/input`, `lib/common`).

4.  **Core Class Structure:**
    *   Define the main Dart classes needed and their responsibilities (e.g., `SimulationController` (state management), `FlipFluidSimulation` (holds logic ported from JS), `ParticleRenderer` (CustomPainter), `SensorService` (accelerometer handling), `TouchInputHandler` (manages obstacle dragging), main App/Screen Widgets). Include basic method signatures if possible.

5.  **Algorithm Implementation Snippet (Dart):**
    *   Provide a small, illustrative Dart code snippet demonstrating how a specific part of the JS algorithm from **the attached HTML implementation file** (e.g., the `integrateParticles` function OR the particle-to-grid transfer logic) would be translated accurately using `Float32List`. This snippet serves as a proof-of-concept for the required translation accuracy.

6.  **Initial Structural Code Skeleton:**
    *   Provide basic, copy-pasteable Flutter code for:
        *   `main.dart`
        *   A main application widget (`MyApp`).
        *   A primary screen widget (`SimulationScreen`) that includes:
            *   Placeholders for simulation state (including obstacle position).
            *   A basic `GestureDetector` wrapping the `CustomPaint` area for touch input.
            *   A basic `CustomPaint` area for future rendering (including drawing the obstacle).
            *   Placeholder buttons for Start/Reset.
            *   Basic integration of a `Ticker` or `Timer` to drive the simulation loop.
        *   Placeholder class files for the core structures outlined in point 4 (e.g., `flip_fluid.dart`, `renderer.dart`, `input_handler.dart`).
    *   *Goal:* This skeleton MUST compile and run, showing the basic app structure. Crucially, the core logic *within* the simulation loop, rendering methods, and input handlers in this skeleton will be **placeholders**, ready to be filled in later based on the accurate algorithm.

**Constraints & Emphasis:**
*   The *ultimate goal* is algorithmic accuracy based on **the attached HTML implementation reference**. This goal should guide the structure provided.
*   Focus on performance optimization from the start in planning and structure.
*   Implement touch interaction for the obstacle accurately *in the final product* (placeholders are acceptable in the initial skeleton).
*   Ensure the structure facilitates future Wear OS adaptation.
*   Provide all the above within this single response.