# Wear OS Slosh O'Clock Performance Improvement Plan

Based on profiling data and code analysis, this plan outlines steps to improve the performance and smoothness of the Slosh O'Clock simulation on Wear OS (specifically tested on Galaxy Watch 6).

## Analysis Summary

1.  **Rendering Bottleneck (Primary):** The profiling data (`_NativeCanvas._drawPoints`, `Paint.color=`, `ParticleRenderer.paint`, `RenderCustomPaint._paintWithPainter`) and the code in `lib/particle_renderer.dart` strongly indicate that the biggest performance hit comes from how particles and grid cells are drawn. Calling `canvas.drawPoints` individually for potentially thousands of points and changing `paint.color` for each one is highly inefficient.
2.  **Native Computation & FFI (Secondary):**
    *   The FFI call `_transferVelocitiesFFI` (9.09% self-time) is significant. This includes both the C++ execution time and the overhead of copying data (`u`, `v`, `particlePos`, `particleVel`, etc.) between Dart and native memory.
    *   The native C++ code (`src/simulation_native.cpp`) is standard C++ without explicit SIMD (NEON) vectorization, which could accelerate loops on the watch's ARM processor.
    *   The simulation parameters in `assets/config.json` show a high workload: `particleCount: 3500` and `pressureIters: 30`. This directly impacts the time spent in native code and FFI calls.
3.  **Dart Simulation Logic (Tertiary):** Functions like `pushParticlesApart`, `updateParticleDensity`, etc., contribute but are less dominant than rendering and native computation.
4.  **Threading:** The simulation currently runs entirely on the main Dart thread, potentially causing UI jank (lack of smoothness) during heavy computation frames.

## Proposed Improvement Plan

```mermaid
graph TD
    A[Performance Problem: Slow/Janky Simulation on Watch] --> B{Identify Bottlenecks};
    B --> C[Rendering: Individual drawPoints Calls];
    B --> D[Native/FFI: Computation Load & Data Copying];
    B --> E[Dart Logic: Minor Contribution];
    B --> F[Threading: Simulation on Main Thread];

    C --> G[Optimize Rendering (High Priority)];
    G --> G1[Option 1: Use `canvas.drawRawPoints` for Batching];
    G --> G2[Option 2: Use `canvas.drawVertices` (More Complex)];
    G --> G3[Reduce Render Load (Toggle Grid/Particles)];

    D --> H[Optimize Native/FFI (Medium Priority)];
    H --> H1[Vectorize C++ Code (NEON)];
    H --> H2[Tune Parameters (particleCount, pressureIters)];
    H --> H3[Analyze FFI Data Copying (Minor Gain Likely)];

    E --> I[Optimize Dart Logic (Low Priority)];
    I --> I1[Review Loops (e.g., handleParticleCollisions)];

    F --> J[Improve Responsiveness (Concurrency)];
    J --> J1[Run Simulation in Dart Isolate];

    G1 --> K[Implement Solution];
    G2 --> K;
    G3 --> K;
    H1 --> K;
    H2 --> K;
    H3 --> K;
    I1 --> K;
    J1 --> K;

    subgraph Legend
        direction LR
        L1[High Priority]:::high;
        L2[Medium Priority]:::medium;
        L3[Low Priority]:::low;
    end
    classDef high fill:#f9d,stroke:#f66,stroke-width:2px;
    classDef medium fill:#fce,stroke:#f99,stroke-width:2px;
    classDef low fill:#eee,stroke:#999,stroke-width:1px;

    class G,G1,G2,G3 high;
    class H,H1,H2,H3 medium;
    class I,I1 low;
    class J,J1 medium;
```

## Plan Details & Implementation Notes

1.  **Optimize Rendering (Highest Priority):**
    *   **Target File:** `lib/particle_renderer.dart` (`ParticleRenderer.paint` method).
    *   **Action:** Replace the loops calling `canvas.drawPoints` individually.
    *   **Recommended Approach (`canvas.drawRawPoints`):**
        *   Create two `Float32List` buffers within `ParticleRenderer`: one for particle positions (`particlePointsBuffer`) and one for grid cell positions (`gridPointsBuffer`). Resize them dynamically if `maxParticles` or grid dimensions change.
        *   Create two `Int32List` buffers for colors: `particleColorsBuffer` and `gridColorsBuffer`.
        *   In `paint`, iterate through `sim.particlePos` and `sim.particleColor`, populating the `particlePointsBuffer` (with `x, y` interleaved) and `particleColorsBuffer` (with ARGB integer values). Do the same for grid cells. Keep track of the actual number of points added.
        *   Use `canvas.drawRawPoints(PointMode.points, particlePointsBuffer.sublist(0, numParticles * 2), paint)` and potentially `canvas.drawRawPoints` with the color buffer if supported directly, or group points by color and make fewer `drawRawPoints` calls, updating the `paint.color` only between groups. *Initial research suggests `drawRawPoints` might not directly support per-point colors; `drawVertices` is the standard way.*
    *   **Alternative Approach (`canvas.drawVertices`):**
        *   This is the more robust way to handle per-point colors and potentially render particles as small quads instead of points for better size control.
        *   Requires creating `Vertices` objects. You'll need `Float32List` for positions (`x, y` interleaved) and `Int32List` for colors (ARGB).
        *   In `paint`, populate these lists similarly to the `drawRawPoints` approach.
        *   Create the `Vertices` object: `final vertices = Vertices(VertexMode.points, positionsList, colors: colorsList);`
        *   Draw in one call: `canvas.drawVertices(vertices, BlendMode.srcOver, paint);` (The base paint here might just define stroke width/cap if colors are in `Vertices`).
    *   **Configuration:** Ensure `showGrid` and `showParticles` in `assets/config.json` can be toggled easily for testing performance impact.

2.  **Optimize Native/FFI (Medium Priority):**
    *   **Target File:** `src/simulation_native.cpp`
    *   **Action (Vectorization):** Identify performance-critical loops (e.g., inner loops in `solveIncompressibility_native`, `pushParticlesApart_native`, `transferVelocities_native`). Rewrite them using NEON intrinsics (available via `<arm_neon.h>`). This requires understanding NEON data types (`float32x4_t`, etc.) and operations (`vaddq_f32`, `vmulq_f32`, etc.). Focus on floating-point arithmetic and memory access patterns. Ensure proper handling of loop boundaries not divisible by the vector size (4 for floats).
    *   **Action (Parameter Tuning):** Experiment with lower values for `pressureIters` and `particleCount` in `assets/config.json`. Profile the app after changes to find the best trade-off. Reducing `particleCount` significantly reduces work in *both* simulation and rendering.

3.  **Improve Responsiveness (Concurrency - Medium Priority):**
    *   **Target Files:** `lib/simulation_screen.dart`, `lib/flip_fluid_simulation.dart`.
    *   **Action:**
        *   Create a new Dart file for the Isolate function (e.g., `lib/simulation_isolate.dart`).
        *   Define a top-level function that takes a `SendPort` and simulation parameters. This function will contain the main simulation loop (`_stepOnce`).
        *   In `simulation_screen.dart`, use `Isolate.spawn()` to start the simulation isolate.
        *   Set up `ReceivePort` in the main isolate (`simulation_screen`) to receive results (e.g., updated `particlePos`, `particleColor`) from the simulation isolate.
        *   Set up `SendPort` communication to send commands (e.g., new parameters, obstacle updates, pause/resume) to the simulation isolate.
        *   Modify `FlipFluidSimulation` to handle being run in an isolate (it might not need many changes if it's mostly self-contained). Be mindful of data copying between isolates – only send necessary data. FFI calls *can* be made from isolates.

4.  **Optimize Dart Logic (Low Priority):**
    *   **Target Files:** `lib/flip_fluid_simulation.dart`.
    *   **Action:** Review loops in methods like `handleParticleCollisions`, `updateParticleDensity`, `updateParticleColors`, `updateCellColors`. Look for opportunities to reduce object allocations, use more efficient data structures if applicable, or simplify calculations (e.g., using squared distances where possible, which is already done in some places).

This detailed plan should provide a good starting point for the implementation phase.

# Additional suggestions for c++ parallelization of transferVelocitiesNative() from ChatGPT

```c++
// ==========================================
// Optimizing transferVelocitiesToGrid()
// For Flutter / Wear OS / C++ FFI
// ==========================================

// GOAL: Optimize the particle-to-grid velocity transfer step
// for a fluid simulation running on constrained hardware
// (e.g. Galaxy Watch) using:
// - SIMD (NEON)
// - FFI (from Dart/Flutter)
// - C++ performance idioms

//------------------------------------------
// 1. NAIVE REFERENCE VERSION (Dart or C++)
//------------------------------------------
// Each particle transfers its velocity to 4 surrounding grid nodes

void transferVelocitiesToGridNaive(
  const float* particle_pos,   // [num_particles * 2]
  const float* particle_vel,   // [num_particles * 2]
  float* grid_vel,             // [grid_w * grid_h * 2]
  float* grid_weight,          // [grid_w * grid_h]
  int32_t num_particles,
  int32_t grid_w,
  int32_t grid_h
) {
  for (int32_t p = 0; p < num_particles; ++p) {
    float x = particle_pos[2 * p];
    float y = particle_pos[2 * p + 1];
    float vx = particle_vel[2 * p];
    float vy = particle_vel[2 * p + 1];

    int i0 = (int)x;
    int j0 = (int)y;
    float fx = x - i0, fy = y - j0;

    float w00 = (1 - fx) * (1 - fy);
    float w10 = fx * (1 - fy);
    float w01 = (1 - fx) * fy;
    float w11 = fx * fy;

    const int dx[4] = {0, 1, 0, 1};
    const int dy[4] = {0, 0, 1, 1};
    const float w[4] = {w00, w10, w01, w11};

    for (int k = 0; k < 4; ++k) {
      int i = i0 + dx[k];
      int j = j0 + dy[k];
      if (i < 0 || i >= grid_w || j < 0 || j >= grid_h) continue;

      int idx = j * grid_w + i;
      int vi = idx * 2;
      float wk = w[k];

      grid_vel[vi]     += vx * wk;
      grid_vel[vi + 1] += vy * wk;
      grid_weight[idx] += wk;
    }
  }
}

//------------------------------------------
// 2. SIMD HINTS FOR AUTO-VECTORIZATION
//------------------------------------------
// Ensure compiler can auto-vectorize:
// - Enable with -O3 -ffast-math -funroll-loops -march=armv8-a+simd
// - Avoid pointer aliasing/confusing control flow

// For example, use flat arrays, avoid nested loops with complex indexing
// And keep code structure like above (simple predictable loop)

//------------------------------------------
// 3. EXPLICIT NEON SIMD (manual)
//------------------------------------------
// Optional: write NEON code explicitly for even better control

#include <arm_neon.h>

extern "C" void transferVelocitiesToGridSIMD(...) {
  // inside loop:
  float32x2_t vel = vld1_f32(&particle_vel[2 * p]);
  float32x2_t wvec = vdup_n_f32(w[k]);
  float32x2_t scaled = vmul_f32(vel, wvec);
  float32x2_t grid = vld1_f32(&grid_vel[vi]);
  vst1_f32(&grid_vel[vi], vadd_f32(grid, scaled));
  grid_weight[idx] += w[k];
}

//------------------------------------------
// 4. FFI INTEGRATION WITH FLUTTER
//------------------------------------------
// Dart: bind and call native version using FFI
// Dart-side code allocates Float32List and uses calloc for pointers

// void callTransferFFI(...) { ... } // See previous full example

//------------------------------------------
// 5. VALIDATION + BENCHMARKING
//------------------------------------------
// Use Stopwatch (Dart) or perf tools to time
// Compare Dart vs FFI vs SIMD FFI
// Disassemble .so to confirm NEON: look for fmla, ld1, st1, etc.
// Add -Rpass=loop-vectorize to Clang for vectorization logs

//===============================
// Summary
//===============================
// ✅ Use flat arrays, reuse buffers
// ✅ Auto-vectorize via compiler flags
// ✅ Optional: explicit NEON intrinsics
// ✅ Call via FFI using Dart Float32List
// ✅ Benchmark with Stopwatch + disassembly

// Results: expect 2x–5x+ speedup over Dart on ARM CPUs
```