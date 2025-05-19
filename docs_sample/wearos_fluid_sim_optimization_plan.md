**Goal:** Improve performance and reduce periodic slowdowns by minimizing Dart FFI overhead, optimizing rendering, moving computations to native code, and providing options to manage thermal throttling.

**Summary of Bottlenecks:**

1.  **FFI Call Overhead:** Excessive time spent in Dart wrappers (`_transferVelocitiesFFI`, `pushParticlesApart`), likely due to redundant data copying between Dart and Native memory before/after *every* native call.
2.  **Rendering (`ParticleRenderer.paint`):** Inefficient particle and grid drawing using per-color maps and list conversions within the paint method.
3.  **Dart Computations:** Significant time spent in Dart functions iterating over particles/cells (`updateParticleColors`, `updateParticleDensity`, `handleParticleCollisions`).
4.  **Object Hashing/Primitives:** High cost associated with `Object.hash` and basic Dart operations, indicating potential overhead from object creation/use in loops or collections.
5.  **Potential Thermal Throttling:** The periodic slowdown suggests the CPU is overheating due to sustained load (especially with OpenMP).

**Detailed Modification Steps:**

---

**Phase 1: Optimize Dart FFI Data Handling**

*   **Goal:** Reduce redundant memory copies between Dart and Native buffers. Leverage the fact that native functions modify data via pointers directly in the allocated native memory.
*   **File:** `lib//flip_fluid_simulation.dart`

1.  **Remove Redundant Copy Calls:** Modify the Dart wrapper functions (`pushParticlesApart`, `solveIncompressibility`, `transferVelocities`) to *only* copy data when absolutely necessary. Often, no copy is needed if the native function reads data that hasn't changed since the last native write *to the same native buffer*.
    *   **Modify `pushParticlesApart`:**
        *   *Before* calling `_ffi.pushParticlesApart`: Copy `particlePos`, `firstCellParticle`, `cellParticleIds` TO native buffers. These are input.
        *   *After* calling `_ffi.pushParticlesApart`: Copy `particlePos` FROM native buffer. This is output.
        *   **REMOVE** the existing wrapper function `pushParticlesApart` and replace its *content* inside `_stepOnce` (or wherever it's called) with the direct copy-call-copy pattern described above. (See example below for `transferVelocities`).
    *   **Modify `solveIncompressibility`:**
        *   *Before* calling `_ffi.solveIncompressibility`: Copy `u`, `v`, `p` (initial guess), `s`, `cellType`, `particleDensity` TO native buffers.
        *   *After* calling `_ffi.solveIncompressibility`: Copy `u`, `v`, `p` FROM native buffers.
        *   **REMOVE** the existing wrapper function `solveIncompressibility` and replace its *content* inside `_stepOnce` with the direct copy-call-copy pattern.
    *   **Modify `transferVelocities`:** This requires careful handling based on `toGrid`.
        *   *If `toGrid == true` (P->G):*
            *   *Before*: Copy `u` (read for prevU), `v` (read for prevV), `s`, `particlePos`, `particleVel` TO native.
            *   *After*: Copy `u`, `v`, `du`, `dv`, `prevU`, `prevV`, `cellType` FROM native.
        *   *If `toGrid == false` (G->P):*
            *   *Before*: Copy `u`, `v`, `prevU`, `prevV`, `cellType`, `particlePos`, `particleVel` (read for FLIP) TO native.
            *   *After*: Copy `particleVel` FROM native.
        *   **REMOVE** the existing wrapper function `transferVelocities` and replace its *content* inside `_stepOnce` with the direct copy-call-copy pattern, including the `if (toGrid)` logic for copies.

    *Example applying this pattern to `transferVelocities` inside `_stepOnce`*:*
    ```dart
    // Inside _stepOnce method...

    // --- Replace transferVelocities(toGrid: true, ...) call ---
    try {
      // Copy necessary inputs TO native for P->G
      _nativeUPtr.asTypedList(u.length).setAll(0, u); // Needed by C++ to write prevU
      _nativeVPtr.asTypedList(v.length).setAll(0, v); // Needed by C++ to write prevV
      _nativeSPtr.asTypedList(s.length).setAll(0, s);
      _nativeParticlePosPtr.asTypedList(particlePos.length).setAll(0, particlePos);
      _nativeParticleVelPtr.asTypedList(particleVel.length).setAll(0, particleVel);
      // Note: du, dv, prevU, prevV, cellType are outputs, no need to copy TO native

      // Call FFI function
      _ffi.transferVelocities(
          true, flipR, // toGrid = true
          _nativeUPtr, _nativeVPtr, _nativeDuPtr, _nativeDvPtr,
          _nativePrevUPtr, _nativePrevVPtr,
          _nativeCellTypePtr,
          _nativeSPtr,
          _nativeParticlePosPtr,
          _nativeParticleVelPtr,
          fNumX, fNumY, h, fInvSpacing,
          numParticles
      );

      // Copy necessary outputs FROM native after P->G
      u.setAll(0, _nativeUPtr.asTypedList(u.length));
      v.setAll(0, _nativeVPtr.asTypedList(v.length));
      du.setAll(0, _nativeDuPtr.asTypedList(du.length));
      dv.setAll(0, _nativeDvPtr.asTypedList(dv.length));
      prevU.setAll(0, _nativePrevUPtr.asTypedList(prevU.length));
      prevV.setAll(0, _nativePrevVPtr.asTypedList(prevV.length));
      cellType.setAll(0, _nativeCellTypePtr.asTypedList(cellType.length));

    } catch (e) { print("Error during FFI call/copy for transferVelocities(toGrid=true): $e"); }
    // --- End replacement ---

    updateParticleDensity(); // Keep this for now

    // --- Replace solveIncompressibility(...) call ---
    try {
        // Copy necessary inputs TO native for solveIncompressibility
        // u, v were just copied back from native, but p needs copy TO
        _nativePPtr.asTypedList(p.length).setAll(0, p);
        // s and cellType might have been updated by setObstacle - copy TO
        _nativeSPtr.asTypedList(s.length).setAll(0, s);
        _nativeCellTypePtr.asTypedList(cellType.length).setAll(0, cellType);
        // particleDensity was just calculated in Dart - copy TO
        _nativeParticleDensityPtr.asTypedList(particleDensity.length).setAll(0, particleDensity);
        // prevU, prevV were just copied back - C++ reads these from native buffer, no copy needed.

        _ffi.solveIncompressibility(
            _nativeUPtr, _nativeVPtr, _nativePPtr, _nativeSPtr, _nativeCellTypePtr,
            _nativeParticleDensityPtr, fNumX, fNumY, pIters, h, dt, density, oRelax,
            particleRestDensity, compDrift, sceneCircleCenterX, sceneCircleCenterY,
            sceneCircleRadius, this.isObstacleActive, this.obstacleX, this.obstacleY,
            this.obstacleRadius, this.obstacleVelX, this.obstacleVelY);

       // Copy necessary outputs FROM native after solveIncompressibility
       u.setAll(0, _nativeUPtr.asTypedList(u.length));
       v.setAll(0, _nativeVPtr.asTypedList(v.length));
       p.setAll(0, _nativePPtr.asTypedList(p.length));

    } catch (e) { print("Error during FFI call/copy for solveIncompressibility: $e"); }
    // --- End replacement ---


    // --- Replace transferVelocities(toGrid: false, ...) call ---
     try {
        // Copy necessary inputs TO native for G->P
        // u, v, p were just copied back from native.
        // prevU, prevV are already in native buffers from P->G write.
        // cellType is already in native buffer from P->G write.
        // s is already in native buffer.
        // particlePos might have changed from Dart collision handling - copy TO
        _nativeParticlePosPtr.asTypedList(particlePos.length).setAll(0, particlePos);
        // particleVel might have changed from Dart collision handling - copy TO
        _nativeParticleVelPtr.asTypedList(particleVel.length).setAll(0, particleVel);

        // Call FFI function
        _ffi.transferVelocities(
            false, flipR, // toGrid = false
            _nativeUPtr, _nativeVPtr, _nativeDuPtr, _nativeDvPtr, // du/dv not used but need placeholder? Check C++ signature
            _nativePrevUPtr, _nativePrevVPtr,
            _nativeCellTypePtr,
            _nativeSPtr, // s not used but need placeholder? Check C++ signature
            _nativeParticlePosPtr,
            _nativeParticleVelPtr,
            fNumX, fNumY, h, fInvSpacing,
            numParticles
        );

        // Copy necessary outputs FROM native after G->P
        particleVel.setAll(0, _nativeParticleVelPtr.asTypedList(particleVel.length));

    } catch (e) { print("Error during FFI call/copy for transferVelocities(toGrid=false): $e"); }
    // --- End replacement ---

    // Apply the same pattern for pushParticlesApart call within _stepOnce

    // --- START pushParticlesApart replacement ---
    if (sepParts) {
      try {
        // Copy necessary inputs TO native for pushParticlesApart
        // particlePos might have changed from integration/collisions
        _nativeParticlePosPtr.asTypedList(particlePos.length).setAll(0, particlePos);
        // firstCellParticle and cellParticleIds were just computed in Dart wrapper
        _nativeFirstCellParticlePtr.asTypedList(firstCellParticle.length).setAll(0, firstCellParticle);
        _nativeCellParticleIdsPtr.asTypedList(cellParticleIds.length).setAll(0, cellParticleIds);

        _ffi.pushParticlesApart(
            _nativeParticlePosPtr, _nativeFirstCellParticlePtr, _nativeCellParticleIdsPtr,
            numParticles, pNumX, pNumY, pInvSpacing, partIters, particleRadius, minDist2 // Assume minDist2 calculated locally
        );

        // Copy necessary outputs FROM native after pushParticlesApart
        particlePos.setAll(0, _nativeParticlePosPtr.asTypedList(particlePos.length));

      } catch (e) { print("Error during FFI call/copy for pushParticlesApart: $e"); }
    }
    // --- END pushParticlesApart replacement ---

    // ... rest of _stepOnce ...
    ```
2.  **Remove Helper Methods:** Delete the now-unused helper methods: `_copyDataToNativeForSolveIncompressibility`, `_copyDataFromNativeForSolveIncompressibility`, `_solveIncompressibilityFFI`, `_copyDataToNativeForTransferVelocities`, `_copyDataFromNativeForTransferVelocities`, `_transferVelocitiesFFI`, and the original `pushParticlesApart` wrapper method.

---

**Phase 2: Optimize Rendering**

*   **Goal:** Use `drawRawPoints` efficiently without intermediate maps or per-color buffer creation.
*   **File:** `lib//particle_renderer.dart`

1.  **Modify `paint` Method:** Replace the particle drawing logic.
    *   **Remove:** Delete the `Map<Color, List<Offset>> particlePointsByColor`.
    *   **Create Buffers:** Inside `paint`, *before* the particle loop, create `Float32List` for positions and `Int32List` for colors *once*.
    *   **Populate Buffers:** Iterate through particles (`for int i = 0...`), calculate screen coordinates `sx`, `sy`, populate the `positionBuffer[i*2]`, `positionBuffer[i*2+1]`, and calculate the ARGB `int colorValue` to populate `colorBuffer[i]`.
    *   **Draw Once:** After the loop, create a single `Paint` object (you can set strokeWidth here). Call `canvas.drawRawPoints` *once* with `PointMode.points`, the `positionBuffer`, the `paint` object, and the `colorBuffer`.

    *Example modification*:*
    ```dart
    // Inside paint method...

    // --- START Particle Rendering Replacement ---
    if (simOptions.showParticles) {
      final int particleCount = sim.numParticles;
      if (particleCount > 0) {
        // Create buffers ONCE per paint call
        final Float32List positionBuffer = Float32List(particleCount * 2);
        final Int32List colorBuffer = Int32List(particleCount);

        // Create Paint object ONCE
        final particlePaint = Paint()
          ..strokeCap = StrokeCap.round // Keep round for particles
          ..strokeWidth = (sim.particleRadius * 2.0) * scale; // Point size

        // Populate buffers
        for (int i = 0; i < particleCount; i++) {
          final double px = sim.particlePos[2 * i];
          final double py = sim.particlePos[2 * i + 1];
          final int colorIndex = 3 * i;

          // Apply transform (ensure this matches your coordinate system)
          final double sx = offsetX + px * scale;
          final double sy = offsetY + (simHeight - py) * scale; // Y-flip

          // Populate position buffer
          positionBuffer[i * 2] = sx;
          positionBuffer[i * 2 + 1] = sy;

          // Populate color buffer (ARGB format)
          final int r = (sim.particleColor[colorIndex] * 255).round();
          final int g = (sim.particleColor[colorIndex + 1] * 255).round();
          final int b = (sim.particleColor[colorIndex + 2] * 255).round();
          colorBuffer[i] = (255 << 24) | (r << 16) | (g << 8) | b; // Alpha=255 (Opaque)
        }

        // Draw all particles at once using raw points and per-vertex colors
        canvas.drawRawPoints(
          PointMode.points,
          positionBuffer,
          particlePaint, // Base paint (color ignored when colors list provided)
          colors: colorBuffer, // Provide the color buffer
        );
      }
    }
    // --- END Particle Rendering Replacement ---

    // Grid drawing optimization (similar pattern can be applied if needed)
    // ... (keep existing grid drawing or optimize similarly) ...
    ```

---

**Phase 3: Move Dart Logic to Native C++**

*   **Goal:** Eliminate expensive Dart loops and object handling for per-particle/cell calculations.
*   **Files:** `lib//flip_fluid_simulation.dart`, `simulation_native.cpp` (or your C++ filename), `CMakeLists.txt`

1.  **Define New Native Functions:** In C++, create functions for the logic currently in Dart's `updateParticleDensity`, `updateParticleColors`, and `handleParticleCollisions`.
    *   **`updateParticleProperties_native` (Example):**
        ```c++
        // In simulation_native.cpp (or your .cpp file)
        extern "C" __attribute__((visibility("default"))) __attribute__((used))
        void updateParticleProperties_native(
            // Inputs
            int numParticles,
            float particleRestDensity, // Read
            float invH, // Read
            int fNumX, int fNumY, // Read
            float h, // Read
            const float* particlePos, // Read
            const int32_t* cellType, // Read (needed for density calc?)
            // Outputs (modified in place via pointers)
            float* particleDensityGrid, // Written (density accumulation)
            float* particleColor // Written (color update)
        ) {
            const int n = fNumY;
            const int fNumCells = fNumX * fNumY;
            const float hh = h;
            const float h2 = 0.5f * h;
            const float decay = 0.01f; // Match Dart value

            // 1. Update Particle Density (Logic from Dart's updateParticleDensity)
            // Zero the density grid first
            // Use OpenMP if safe (memset might be faster for large grids)
            #pragma omp parallel for schedule(static) // Check safety if density is read later
            for(int i = 0; i < fNumCells; ++i) {
                 particleDensityGrid[i] = 0.0f;
            }

            // Accumulate density (keep serial - accumulation race)
            for (int i = 0; i < numParticles; i++) {
                float x = particlePos[2 * i];
                float y = particlePos[2 * i + 1];
                // Clamp position (ensure clamp_cpp is available or reimplement)
                x = clamp_cpp(x, hh, (fNumX - 1) * hh);
                y = clamp_cpp(y, hh, (fNumY - 1) * hh);
                x -= h2; // Offset for cell center interpolation
                y -= h2;

                const int x0 = static_cast<int>(floorf(x * invH));
                const int y0 = static_cast<int>(floorf(y * invH));
                const float tx = (x - static_cast<float>(x0) * hh) * invH;
                const float ty = (y - static_cast<float>(y0) * hh) * invH;

                // Ensure indices are safe before calculating weights/indices
                if (x0 < 0 || x0 >= fNumX - 1 || y0 < 0 || y0 >= fNumY - 1) continue;

                const int x1 = x0 + 1; // No min needed due to loop bounds/clamping check
                const int y1 = y0 + 1;
                const float sx = 1.0f - tx;
                const float sy = 1.0f - ty;

                // Indices of the 4 cells
                int idx0 = x0 * n + y0; int idx1 = x1 * n + y0;
                int idx2 = x1 * n + y1; int idx3 = x0 * n + y1;

                // Accumulate density (check bounds before writing)
                // Requires atomic updates if parallelized
                if(idx0 >= 0 && idx0 < fNumCells) particleDensityGrid[idx0] += sx * sy;
                if(idx1 >= 0 && idx1 < fNumCells) particleDensityGrid[idx1] += tx * sy;
                if(idx2 >= 0 && idx2 < fNumCells) particleDensityGrid[idx2] += tx * ty;
                if(idx3 >= 0 && idx3 < fNumCells) particleDensityGrid[idx3] += sx * ty;
            }

            // 2. Update Particle Colors (Logic from Dart's updateParticleColors)
            // This loop is independent per particle - safe for OpenMP
            #pragma omp parallel for schedule(static)
            for (int i = 0; i < numParticles; ++i) {
                int baseColorIdx = 3 * i;
                // Apply decay
                particleColor[baseColorIdx + 0] = clamp_cpp(particleColor[baseColorIdx + 0] - decay, 0.0f, 1.0f);
                particleColor[baseColorIdx + 1] = clamp_cpp(particleColor[baseColorIdx + 1] - decay, 0.0f, 1.0f);
                particleColor[baseColorIdx + 2] = clamp_cpp(particleColor[baseColorIdx + 2] + decay, 0.0f, 1.0f);

                // Apply density highlight
                if (particleRestDensity > 1e-9f) { // Avoid division by zero
                    // Safely get grid index for particle position
                     int xi = static_cast<int>(clamp_cpp(floorf(particlePos[2*i] * invH), 0.0f, static_cast<float>(fNumX - 1)));
                     int yi = static_cast<int>(clamp_cpp(floorf(particlePos[2*i+1] * invH), 0.0f, static_cast<float>(fNumY - 1)));
                     int cellIdx = xi * n + yi;

                     if (cellIdx >= 0 && cellIdx < fNumCells) {
                         float relDensity = particleDensityGrid[cellIdx] / particleRestDensity;
                         if (relDensity < 0.7f) {
                             const float s_highlight = 0.8f;
                             particleColor[baseColorIdx + 0] = s_highlight;
                             particleColor[baseColorIdx + 1] = s_highlight;
                             particleColor[baseColorIdx + 2] = 1.0f;
                         }
                     }
                }
            }
        }
        ```
    *   **`handleCollisions_native`:** Create a similar native function taking particle positions, velocities, obstacle parameters, scene parameters, and modifying positions/velocities in place. The logic will mirror `handleParticleCollisions` in Dart. This is independent per particle and safe for OpenMP.

2.  **Update FFI Bindings:** In `flip_fluid_simulation.dart`, add `typedef`s and `lookup` calls for the new native functions.
    ```dart
    // --- Add near other typedefs ---
    typedef UpdateParticlePropertiesNative = Void Function(
        Int32 numParticles, Float particleRestDensity, Float invH,
        Int32 fNumX, Int32 fNumY, Float h,
        Pointer<Float> particlePos, Pointer<Int32> cellType,
        Pointer<Float> particleDensityGrid, Pointer<Float> particleColor
    );
    typedef UpdateParticlePropertiesDart = void Function(
        int numParticles, double particleRestDensity, double invH,
        int fNumX, int fNumY, double h,
        Pointer<Float> particlePos, Pointer<Int32> cellType,
        Pointer<Float> particleDensityGrid, Pointer<Float> particleColor
    );
    // Add typedefs for handleCollisions_native...

    // --- Inside _SimulationFFI._internal() ---
    late final UpdateParticlePropertiesDart updateParticleProperties;
    // late final HandleCollisionsDart handleCollisions; // For collision function
     _SimulationFFI._internal() {
        // ... existing lookups ...
        updateParticleProperties = _dylib
            .lookup<NativeFunction<UpdateParticlePropertiesNative>>(
                'updateParticleProperties_native')
            .asFunction<UpdateParticlePropertiesDart>(isLeaf: true);
        // Add lookup for handleCollisions_native...
     }

    // --- Add native buffer pointers ---
    // Add near other pointer declarations
    late final Pointer<Float> _nativeParticleColorPtr; // Add this if not present

    // --- Allocate in constructor ---
     FlipFluidSimulation(...) {
        // ... existing allocations ...
        _nativeParticleColorPtr = ffi.calloc<Float>(particleColor.length);
        // Check for null pointer...
     }

     // --- Free in dispose ---
     void dispose() {
        // ... existing frees ...
        ffi.calloc.free(_nativeParticleColorPtr);
     }
    ```

3.  **Call New Native Functions:** In Dart's `_stepOnce` method:
    *   **Remove calls** to the original Dart methods `updateParticleDensity()` and `updateParticleColors()`.
    *   **Add a call** to the new `_updateParticlePropertiesFFI` wrapper method (which you'll create). This wrapper should copy necessary inputs (particlePos, cellType, particleColor) TO native, call `_ffi.updateParticleProperties`, and copy outputs (particleDensityGrid, particleColor) FROM native. Place this call *after* `transferVelocities(toGrid: true, ...)` because that's when `cellType` is updated.
    *   **Replace the call** to Dart's `handleParticleCollisions()` with a call to the new native collision function wrapper (copy pos/vel TO, call, copy pos/vel FROM).

4.  **Recompile:** Update `CMakeLists.txt` if needed (e.g., if you add new `.cpp` files, though modifying the existing one is fine). Run `flutter clean` and `flutter run`.

---

**Phase 4: Address Thermal Throttling / Periodic Slowdown**

*   **Goal:** Stabilize performance if periodic slowdowns persist after the above optimizations.
*   **File:** `simulation_native.cpp` (or your C++ filename)

1.  **Limit OpenMP Threads:** If slowdowns continue, explicitly limit the number of threads used by OpenMP. Add this line at the beginning of functions that use OpenMP pragmas (`solveIncompressibility_native`, `transferVelocities_native`, `updateParticleProperties_native`, `handleCollisions_native`).
    ```c++
    // At the start of the function...
    omp_set_num_threads(2); // Limit to 2 threads for Watch 6 (dual-core A55)
                            // Experiment with 1 if 2 still throttles.
    ```
    *Start with 2 threads. If it still throttles, try 1.*

---

**Implementation Notes:**

*   **Native `clamp_cpp`:** Ensure the `clamp_cpp` helper function exists and is accessible within your C++ file if you use the provided native code snippets.
*   **Build System:** Remember to update `CMakeLists.txt` correctly (library name, source files) and ensure OpenMP flags are active.
*   **Testing:** Test thoroughly after each phase to ensure correctness and measure performance improvements. Use the Flutter profiler again.

This detailed plan provides a structured approach to tackle the identified bottlenecks systematically. Start with Phase 1, as the FFI overhead seems most significant according to the profiler's self-time metric for the wrappers.