**Project Context:** Continuing the "Water Slosher" Flutter project. You previously generated an initial structural code skeleton including placeholder classes like `FlipFluidSimulation` (likely in `lib/simulation/flip_fluid.dart`), `ParticleRenderer`, etc., based on **the attached HTML file containing the JavaScript FLIP implementation**. The skeleton sets up the basic app structure, UI, and timer loop calling a placeholder simulation function.

**Current Goal:** Implement the core FLIP simulation logic within the provided `FlipFluidSimulation` class accurately, replacing the placeholder logic.

**Request:** Please provide the complete implementation for the `FlipFluidSimulation` Dart class. This implementation MUST:

1.  **Accurately Port Logic:** Translate the *entire* simulation algorithm and logic contained within the `FlipFluid` class (and its associated methods) from **the attached HTML implementation file** into Dart.
2.  **Implement Key Methods:** Ensure all core simulation methods found in the JavaScript reference are implemented correctly in Dart within the `FlipFluidSimulation` class. This includes, but is not limited to:
    *   Constructor (`FlipFluid(...)` or appropriate initialization logic)
    *   `integrateParticles(...)`
    *   `pushParticlesApart(...)` (including any spatial hashing logic)
    *   `handleParticleCollisions(...)` (obstacle and boundary logic)
    *   `updateParticleDensity(...)`
    *   `transferVelocities(...)` (`toGrid=true` and `toGrid=false`)
    *   `solveIncompressibility(...)`
    *   `updateParticleColors(...)` / `updateCellColors(...)` (if applicable)
    *   The main `simulate(...)` method orchestrating these steps.
    *   Necessary helper functions (e.g., `clamp`).
3.  **Use Correct Data Structures:** Utilize `Float32List`, `Int32List`, etc., for the internal simulation data arrays (particle positions/velocities, grid velocities/types, etc.) as defined in the skeleton and consistent with the JS reference.
4.  **Encapsulate State:** The class should properly manage all necessary simulation state (particle data, grid data, parameters, obstacle state).
5.  **Provide Complete Class Code:** Output the *entire*, updated `FlipFluidSimulation` Dart class file content, ready to replace the placeholder file generated in the previous step.

**Integration Points (Context Only):**
*   Assume the `simulate()` method implemented here will be called by the `Ticker`/`Timer` established in the skeleton.
*   Assume public getters or the class instance will provide necessary state (like particle positions, obstacle data) to the rendering and input handling components from the skeleton. (Do *not* implement these interactions in this response).

**Constraints & Emphasis:**
*   Focus *only* on the accurate implementation of the `FlipFluidSimulation` class logic based *strictly* on the **attached HTML reference**.
*   Do not implement rendering, detailed input handling, or UI logic in this response.
*   The output must be the complete, runnable Dart code for the `FlipFluidSimulation` class itself.

**Goal:** After incorporating this response, the simulation core within the skeleton should be functionally complete and algorithmically accurate according to the JavaScript reference, ready for its state to be rendered and interacted with by the other skeleton components.