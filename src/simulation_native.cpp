#include <cmath>      // For sqrtf, fmaxf, fminf
#include <cstdint>    // For int32_t
#include <algorithm>  // For std::max, std::min
#include <vector>     // Required for pushParticlesApart temporary data if needed

#include <arm_neon.h> // Include NEON intrinsics header
#include <omp.h>      // Include OpenMP header

// Define constants matching Dart code for clarity (optional but good practice)
const int FLUID_CELL_CPP = 0; // Renamed to avoid conflict if FLUID_CELL is a macro
const int AIR_CELL_CPP = 1;
const int SOLID_CELL_CPP = 2;

// Helper function to check if a cell is part of the static circular wall (Unchanged)
bool isCellStaticWall_native(int ix, int iy, int fNumX_cells, int fNumY_cells, float h_grid,
                             float cCenterX, float cCenterY, float cRadius) {
    if (ix < 0 || ix >= fNumX_cells || iy < 0 || iy >= fNumY_cells) {
        return true;
    }
    float cell_center_x = (static_cast<float>(ix) + 0.5f) * h_grid;
    float cell_center_y = (static_cast<float>(iy) + 0.5f) * h_grid;
    float dx = cell_center_x - cCenterX;
    float dy = cell_center_y - cCenterY;
    return (dx * dx + dy * dy) > (cRadius * cRadius);
}

// Helper function to check if a cell is part of the draggable obstacle (Unchanged)
bool isCellDraggable_native(int ix, int iy, int fNumX_cells, int fNumY_cells, float h_grid,
                            bool obsActive, float obsX, float obsY, float obsRadius) {
    if (!obsActive) {
        return false;
    }
    if (ix < 0 || ix >= fNumX_cells || iy < 0 || iy >= fNumY_cells) {
        return false;
    }
    float cell_center_x = (static_cast<float>(ix) + 0.5f) * h_grid;
    float cell_center_y = (static_cast<float>(iy) + 0.5f) * h_grid;
    float dx = cell_center_x - obsX;
    float dy = cell_center_y - obsY;
    return (dx * dx + dy * dy) < (obsRadius * obsRadius);
}


// Use extern "C" to prevent C++ name mangling for FFI compatibility
extern "C" {

    // Removed __attribute__ for broader compatibility
    void solveIncompressibility_native(
        float* u, float* v, float* p, const float* s, const int32_t* cellType,
        const float* particleDensity,
        int fNumX, int fNumY, int numIters,
        float h, float dt, float density, float overRelaxation,
        float particleRestDensity, bool compensateDrift,
        // --- Boundary Parameters ---
        float circleCenterX, float circleCenterY, float circleRadius,
        bool isObstacleActive,
        float obstacleX, float obstacleY, float obstacleRadiusCpp,
        float obstacleVelX, float obstacleVelY
    )
    {
        omp_set_num_threads(2); // Limit threads for thermal management (Phase 4)
        const float cp = density * h / dt;
        const int n = fNumY; // Stride

        // --- Core pressure loop (Keep serial - Gauss-Seidel like structure is sensitive to parallelization) ---
        for (int iter = 0; iter < numIters; ++iter) {
            for (int i = 1; i < fNumX - 1; ++i) { // Iterate over interior cells
                for (int j = 1; j < fNumY - 1; ++j) {
                    const int idx = i * n + j;
                    if (cellType[idx] != FLUID_CELL_CPP) continue;

                    const int left   = (i - 1) * n + j;
                    const int right  = (i + 1) * n + j;
                    const int bottom = i * n + (j - 1);
                    const int top    = i * n + (j + 1);

                    // Use s values from neighboring cells (as per _vectorized logic)
                    const float sx0_from_code = s[left];
                    const float sx1_from_code = s[right];
                    const float sy0_from_code = s[bottom];
                    const float sy1_from_code = s[top];
                    const float sumS = sx0_from_code + sx1_from_code + sy0_from_code + sy1_from_code;
                    if (sumS < 1e-9f) continue;

                    float div = (u[right] - u[idx]) + (v[top] - v[idx]);

                    if (particleRestDensity > 0.0f && compensateDrift) {
                        const float comp = particleDensity[idx] - particleRestDensity;
                        if (comp > 0.0f) { div -= comp; }
                    }

                    float pressure_update = -div / sumS * overRelaxation;
                    p[idx] += cp * pressure_update;

                    // Apply velocity updates (matching _vectorized)
                    u[idx]    -= sx0_from_code * pressure_update;
                    u[right]  += sx1_from_code * pressure_update;
                    v[idx]    -= sy0_from_code * pressure_update;
                    v[top]    += sy1_from_code * pressure_update;
                }
            }
        } // --- End core pressure loop ---

        // --- Boundary Condition Enforcement (Vectorized NEON + OpenMP) ---
        const float circleRadiusSq = circleRadius * circleRadius;
        const float obstacleRadiusSq = obstacleRadiusCpp * obstacleRadiusCpp;
        const float32x4_t zero_f32x4 = vdupq_n_f32(0.0f);
        const int32x4_t fNumX_cells_vec = vdupq_n_s32(fNumX);
        const int32x4_t fNumY_cells_vec = vdupq_n_s32(fNumY);
        const float32x4_t h_grid_vec = vdupq_n_f32(h);
        const float32x4_t half_vec = vdupq_n_f32(0.5f);
        const int32x4_t const_zero_s32x4 = vdupq_n_s32(0);
        const int32_t inc4_arr_local[4] = { 0, 1, 2, 3 }; // Local copy for vld1q if needed

        // Enforce U-velocities (Parallelize outer loop)
        #pragma omp parallel for schedule(static)
        for (int i_face = 0; i_face < fNumX; ++i_face) {
            const float32x4_t obstacleVelX_vec = vdupq_n_f32(obstacleVelX);
            const int32x4_t j_inc_vec = vld1q_s32(inc4_arr_local); // {0, 1, 2, 3}

            int j_row = 0;
            // Vectorized part
            for (; j_row <= fNumY - 4; j_row += 4) {
                int u_idx_base = i_face * n + j_row;
                float32x4_t u_val_vec = vld1q_f32(&u[u_idx_base]);
                float32x4_t final_u_val_vec = u_val_vec;

                int32x4_t j_row_base_vec = vdupq_n_s32(j_row);
                int32x4_t j_row_vec = vaddq_s32(j_row_base_vec, j_inc_vec); // {j, j+1, j+2, j+3}

                uint32x4_t overall_static_mask = vdupq_n_u32(0);
                uint32x4_t overall_draggable_mask = vdupq_n_u32(0);

                // Check adjacent cells (left: i_face-1, right: i_face)
                for (int side = 0; side < 2; ++side) {
                    int ix = (side == 0) ? (i_face - 1) : i_face;
                    int32x4_t ix_vec = vdupq_n_s32(ix);

                    // Static check
                    uint32x4_t static_domain_mask = vorrq_u32(vorrq_u32(vcltq_s32(ix_vec, const_zero_s32x4), vcgeq_s32(ix_vec, fNumX_cells_vec)), vorrq_u32(vcltq_s32(j_row_vec, const_zero_s32x4), vcgeq_s32(j_row_vec, fNumY_cells_vec)));
                    float32x4_t cell_center_x_vec = vmulq_f32(vaddq_f32(vcvtq_f32_s32(ix_vec), half_vec), h_grid_vec);
                    float32x4_t cell_center_y_vec = vmulq_f32(vaddq_f32(vcvtq_f32_s32(j_row_vec), half_vec), h_grid_vec);
                    float32x4_t dx_static_vec = vsubq_f32(cell_center_x_vec, vdupq_n_f32(circleCenterX));
                    float32x4_t dy_static_vec = vsubq_f32(cell_center_y_vec, vdupq_n_f32(circleCenterY));
                    float32x4_t dist_sq_static_vec = vmlaq_f32(vmulq_f32(dx_static_vec, dx_static_vec), dy_static_vec, dy_static_vec);
                    uint32x4_t static_radius_mask = vcgtq_f32(dist_sq_static_vec, vdupq_n_f32(circleRadiusSq));
                    uint32x4_t cell_is_static = vorrq_u32(static_domain_mask, static_radius_mask);
                    overall_static_mask = vorrq_u32(overall_static_mask, cell_is_static);

                    // Draggable check
                    uint32x4_t cell_is_draggable = vdupq_n_u32(0);
                    if (isObstacleActive) {
                        uint32x4_t draggable_domain_mask = static_domain_mask; // Reuse domain check
                        float32x4_t dx_drag_vec = vsubq_f32(cell_center_x_vec, vdupq_n_f32(obstacleX));
                        float32x4_t dy_drag_vec = vsubq_f32(cell_center_y_vec, vdupq_n_f32(obstacleY));
                        float32x4_t dist_sq_drag_vec = vmlaq_f32(vmulq_f32(dx_drag_vec, dx_drag_vec), dy_drag_vec, dy_drag_vec);
                        uint32x4_t draggable_radius_mask = vcltq_f32(dist_sq_drag_vec, vdupq_n_f32(obstacleRadiusSq));
                        cell_is_draggable = vandq_u32(vmvnq_u32(draggable_domain_mask), draggable_radius_mask); // NOT outside domain AND inside radius
                        overall_draggable_mask = vorrq_u32(overall_draggable_mask, cell_is_draggable);
                    }
                }
                // Apply conditions
                uint32x4_t not_static_mask = vmvnq_u32(overall_static_mask);
                uint32x4_t not_static_and_draggable_mask = vandq_u32(not_static_mask, overall_draggable_mask);
                final_u_val_vec = vbslq_f32(overall_static_mask, zero_f32x4, final_u_val_vec); // If static, set 0
                final_u_val_vec = vbslq_f32(not_static_and_draggable_mask, obstacleVelX_vec, final_u_val_vec); // If not static and draggable, set obsVel

                vst1q_f32(&u[u_idx_base], final_u_val_vec);
            }
            // Scalar remainder loop
            for (; j_row < fNumY; ++j_row) {
                int u_idx = i_face * n + j_row;
                bool adj_left_cell_static  = isCellStaticWall_native(i_face - 1, j_row, fNumX, fNumY, h, circleCenterX, circleCenterY, circleRadius);
                bool adj_right_cell_static = isCellStaticWall_native(i_face, j_row,     fNumX, fNumY, h, circleCenterX, circleCenterY, circleRadius);
                bool adj_left_cell_draggable  = isCellDraggable_native(i_face - 1, j_row, fNumX, fNumY, h, isObstacleActive, obstacleX, obstacleY, obstacleRadiusCpp);
                bool adj_right_cell_draggable = isCellDraggable_native(i_face, j_row,     fNumX, fNumY, h, isObstacleActive, obstacleX, obstacleY, obstacleRadiusCpp);

                if (adj_left_cell_static || adj_right_cell_static) { u[u_idx] = 0.0f; }
                else if (adj_left_cell_draggable || adj_right_cell_draggable) { u[u_idx] = obstacleVelX; }
            }
        } // End parallel U enforcement

        // Enforce V-velocities (Parallelize outer loop)
        #pragma omp parallel for schedule(static)
        for (int i_col = 0; i_col < fNumX; ++i_col) {
            const float32x4_t obstacleVelY_vec = vdupq_n_f32(obstacleVelY);
            const int32x4_t const_one_s32x4 = vdupq_n_s32(1);
            const int32x4_t j_inc_vec = vld1q_s32(inc4_arr_local); // {0, 1, 2, 3}

            int j_face = 0;
            // Vectorized part
            for (; j_face <= fNumY - 4; j_face += 4) {
                int v_idx_base = i_col * n + j_face;
                float32x4_t v_val_vec = vld1q_f32(&v[v_idx_base]);
                float32x4_t final_v_val_vec = v_val_vec;

                int32x4_t j_face_base_vec = vdupq_n_s32(j_face);
                int32x4_t j_face_vec = vaddq_s32(j_face_base_vec, j_inc_vec); // {j, j+1, j+2, j+3}

                uint32x4_t overall_static_mask = vdupq_n_u32(0);
                uint32x4_t overall_draggable_mask = vdupq_n_u32(0);
                int32x4_t ix_vec = vdupq_n_s32(i_col);

                // Check adjacent cells (bottom: j_face-1, top: j_face)
                for (int side = 0; side < 2; ++side) {
                    int32x4_t iy_vec = (side == 0) ? vsubq_s32(j_face_vec, const_one_s32x4) : j_face_vec;

                    // Static check
                    uint32x4_t static_domain_mask = vorrq_u32(vorrq_u32(vcltq_s32(ix_vec, const_zero_s32x4), vcgeq_s32(ix_vec, fNumX_cells_vec)), vorrq_u32(vcltq_s32(iy_vec, const_zero_s32x4), vcgeq_s32(iy_vec, fNumY_cells_vec)));
                    float32x4_t cell_center_x_vec = vmulq_f32(vaddq_f32(vcvtq_f32_s32(ix_vec), half_vec), h_grid_vec);
                    float32x4_t cell_center_y_vec = vmulq_f32(vaddq_f32(vcvtq_f32_s32(iy_vec), half_vec), h_grid_vec);
                    float32x4_t dx_static_vec = vsubq_f32(cell_center_x_vec, vdupq_n_f32(circleCenterX));
                    float32x4_t dy_static_vec = vsubq_f32(cell_center_y_vec, vdupq_n_f32(circleCenterY));
                    float32x4_t dist_sq_static_vec = vmlaq_f32(vmulq_f32(dx_static_vec, dx_static_vec), dy_static_vec, dy_static_vec);
                    uint32x4_t static_radius_mask = vcgtq_f32(dist_sq_static_vec, vdupq_n_f32(circleRadiusSq));
                    uint32x4_t cell_is_static = vorrq_u32(static_domain_mask, static_radius_mask);
                    overall_static_mask = vorrq_u32(overall_static_mask, cell_is_static);

                    // Draggable check
                    uint32x4_t cell_is_draggable = vdupq_n_u32(0);
                    if (isObstacleActive) {
                        uint32x4_t draggable_domain_mask = static_domain_mask;
                        float32x4_t dx_drag_vec = vsubq_f32(cell_center_x_vec, vdupq_n_f32(obstacleX));
                        float32x4_t dy_drag_vec = vsubq_f32(cell_center_y_vec, vdupq_n_f32(obstacleY));
                        float32x4_t dist_sq_drag_vec = vmlaq_f32(vmulq_f32(dx_drag_vec, dx_drag_vec), dy_drag_vec, dy_drag_vec);
                        uint32x4_t draggable_radius_mask = vcltq_f32(dist_sq_drag_vec, vdupq_n_f32(obstacleRadiusSq));
                        cell_is_draggable = vandq_u32(vmvnq_u32(draggable_domain_mask), draggable_radius_mask);
                        overall_draggable_mask = vorrq_u32(overall_draggable_mask, cell_is_draggable);
                    }
                }
                // Apply conditions
                uint32x4_t not_static_mask = vmvnq_u32(overall_static_mask);
                uint32x4_t not_static_and_draggable_mask = vandq_u32(not_static_mask, overall_draggable_mask);
                final_v_val_vec = vbslq_f32(overall_static_mask, zero_f32x4, final_v_val_vec);
                final_v_val_vec = vbslq_f32(not_static_and_draggable_mask, obstacleVelY_vec, final_v_val_vec);

                vst1q_f32(&v[v_idx_base], final_v_val_vec);
            }
            // Scalar remainder loop
            for (; j_face < fNumY; ++j_face) {
                int v_idx = i_col * n + j_face;
                bool adj_bottom_cell_static = isCellStaticWall_native(i_col, j_face - 1, fNumX, fNumY, h, circleCenterX, circleCenterY, circleRadius);
                bool adj_top_cell_static    = isCellStaticWall_native(i_col, j_face,     fNumX, fNumY, h, circleCenterX, circleCenterY, circleRadius);
                bool adj_bottom_cell_draggable = isCellDraggable_native(i_col, j_face - 1, fNumX, fNumY, h, isObstacleActive, obstacleX, obstacleY, obstacleRadiusCpp);
                bool adj_top_cell_draggable    = isCellDraggable_native(i_col, j_face,     fNumX, fNumY, h, isObstacleActive, obstacleX, obstacleY, obstacleRadiusCpp);

                if (adj_bottom_cell_static || adj_top_cell_static) { v[v_idx] = 0.0f; }
                else if (adj_bottom_cell_draggable || adj_top_cell_draggable) { v[v_idx] = obstacleVelY; }
            }
        } // End parallel V enforcement
    } // End solveIncompressibility_native


    // Removed __attribute__ for broader compatibility
    void pushParticlesApart_native(
        float* particlePos, // Removed particleColor_param
        const int32_t* firstCellParticle, const int32_t* cellParticleIds,
        int numParticles, int pNumX, int pNumY,
        float pInvSpacing, int numIters,
        float particleRadius, float minDist2 // Removed enableDynamicColoring
        )
    {
        const float minDist = 2.0f * particleRadius;
        const int pn = pNumY; // Stride for particle grid
        // const float colorDiffusionCoeff = 0.001f; // Removed

        // Keep serial - parallelizing this naively causes race conditions
        for (int iter = 0; iter < numIters; ++iter) {
            for (int ii = 0; ii < numParticles; ++ii) {
                const int pIdx = 2 * ii;
                // const int pColorIdx = 3 * ii; // Removed
                // Load particle i's position (needed fresh if modified in inner loop)
                float p_pos_scalar_arr[2];
                p_pos_scalar_arr[0] = particlePos[pIdx];
                p_pos_scalar_arr[1] = particlePos[pIdx + 1];
                const float px = p_pos_scalar_arr[0]; // Keep scalar copy for grid calc
                const float py = p_pos_scalar_arr[1];
                // float32x2_t p_pos_vec = vld1_f32(p_pos_scalar_arr); // Vector version - kept scalar for now

                // Particle grid calculation (scalar)
                const int pxi = static_cast<int>(fmaxf(0.0f, fminf(static_cast<float>(pNumX - 1), floorf(px * pInvSpacing))));
                const int pyi = static_cast<int>(fmaxf(0.0f, fminf(static_cast<float>(pNumY - 1), floorf(py * pInvSpacing))));
                const int x0 = std::max(0, pxi - 1);
                const int x1 = std::min(pNumX - 1, pxi + 1);
                const int y0 = std::max(0, pyi - 1);
                const int y1 = std::min(pNumY - 1, pyi + 1);

                // Iterate neighbor cells
                for (int cx = x0; cx <= x1; ++cx) {
                    for (int cy = y0; cy <= y1; ++cy) {
                        const int cellIndex = cx * pn + cy;
                        // Bounds check for firstCellParticle array access
                        if (cellIndex < 0 || cellIndex + 1 > (pNumX * pNumY)) continue;

                        const int cellStart = firstCellParticle[cellIndex];
                        const int cellEnd   = firstCellParticle[cellIndex + 1];

                        // Basic validation for indices
                        if (cellStart < 0 || cellEnd < cellStart || cellEnd > numParticles) continue;

                        // Iterate particles in neighbor cell
                        for (int k_loop_idx = cellStart; k_loop_idx < cellEnd; ++k_loop_idx) { // Renamed k to k_loop_idx
                            if (k_loop_idx < 0 || k_loop_idx >= numParticles) continue;

                            const int jj = cellParticleIds[k_loop_idx];
                            if (jj == ii) continue;
                            if (jj < 0 || jj >= numParticles) continue;

                            const int qIdx = 2 * jj;
                            // const int qColorIdx = 3 * jj; // Removed

                            // --- Interaction (Scalar for dist2 and position update) ---
                            float p_curr_x = particlePos[pIdx + 0];
                            float p_curr_y = particlePos[pIdx + 1];
                            float q_curr_x = particlePos[qIdx + 0];
                            float q_curr_y = particlePos[qIdx + 1];

                            float dx_scalar = q_curr_x - p_curr_x;
                            float dy_scalar = q_curr_y - p_curr_y;
                            float dist2 = dx_scalar * dx_scalar + dy_scalar * dy_scalar;

                            if (dist2 > minDist2 || dist2 < 1e-12f) continue;

                            const float d = sqrtf(dist2);
                            const float s_factor = (d > 1e-9f) ? (0.5f * (minDist - d) / d) : 0.0f;
                            
                            float offset_x = dx_scalar * s_factor;
                            float offset_y = dy_scalar * s_factor;

                            particlePos[pIdx + 0] = p_curr_x - offset_x;
                            particlePos[pIdx + 1] = p_curr_y - offset_y;
                            particlePos[qIdx + 0] = q_curr_x + offset_x;
                            particlePos[qIdx + 1] = q_curr_y + offset_y;

                            // --- Color Diffusion (Scalar) ---
                            // Removed from here
                        }
                    }
                }
            }
        }
    } // End pushParticlesApart_native

    // Forward declaration for clamp_cpp
    inline float clamp_cpp(float val, float min_val, float max_val);

    // __attribute__((visibility("default"))) __attribute__((used)) // Removed for broader compatibility
    void diffuseParticleColors_native(
        const float* particlePos, // Read-only for this function
        float* particleColor_param, // Read & Written
        const int32_t* firstCellParticle,
        const int32_t* cellParticleIds,
        int numParticles,
        int pNumX, int pNumY,
        float pInvSpacing,
        float particleRadius, // For minDist calculation
        bool enableDynamicColoring,
        float colorDiffusionCoeff_param
    ) {
        if (!enableDynamicColoring || numParticles == 0) {
            return;
        }
        omp_set_num_threads(2); // Consistent with other particle loops

        const float minDist = 2.0f * particleRadius;
        const float minDist2 = minDist * minDist;
        const int pn = pNumY; // Stride for particle grid

        // This loop structure is similar to pushParticlesApart_native for finding neighbors
        // It's kept serial as color diffusion between a pair (i,j) modifies both i's and j's colors,
        // creating potential race conditions if parallelized naively without atomic operations or complex coloring schemes.
        for (int ii = 0; ii < numParticles; ++ii) {
            const int pIdx = 2 * ii; // Position index
            const int pColorIdx = 4 * ii; // Color index (RGBA)

            const float px = particlePos[pIdx];
            const float py = particlePos[pIdx + 1];

            const int pxi = static_cast<int>(fmaxf(0.0f, fminf(static_cast<float>(pNumX - 1), floorf(px * pInvSpacing))));
            const int pyi = static_cast<int>(fmaxf(0.0f, fminf(static_cast<float>(pNumY - 1), floorf(py * pInvSpacing))));
            const int x0 = std::max(0, pxi - 1);
            const int x1 = std::min(pNumX - 1, pxi + 1);
            const int y0 = std::max(0, pyi - 1);
            const int y1 = std::min(pNumY - 1, pyi + 1);

            for (int cx = x0; cx <= x1; ++cx) {
                for (int cy = y0; cy <= y1; ++cy) {
                    const int cellIndex = cx * pn + cy;
                    if (cellIndex < 0 || cellIndex + 1 > (pNumX * pNumY)) continue;

                    const int cellStart = firstCellParticle[cellIndex];
                    const int cellEnd   = firstCellParticle[cellIndex + 1];
                    if (cellStart < 0 || cellEnd < cellStart || cellEnd > numParticles) continue;

                    for (int k_loop_idx = cellStart; k_loop_idx < cellEnd; ++k_loop_idx) {
                        if (k_loop_idx < 0 || k_loop_idx >= numParticles) continue;
                        const int jj = cellParticleIds[k_loop_idx];
                        if (jj == ii) continue;
                        if (jj < 0 || jj >= numParticles) continue;

                        const int qIdx = 2 * jj; // Position index for neighbor
                        const int qColorIdx = 4 * jj; // Color index for neighbor (RGBA)

                        float p_curr_x = particlePos[pIdx + 0];
                        float p_curr_y = particlePos[pIdx + 1];
                        float q_curr_x = particlePos[qIdx + 0];
                        float q_curr_y = particlePos[qIdx + 1];

                        float dx_scalar = q_curr_x - p_curr_x;
                        float dy_scalar = q_curr_y - p_curr_y;
                        float dist2 = dx_scalar * dx_scalar + dy_scalar * dy_scalar;

                        // Only diffuse colors if particles are close enough (same threshold as push apart)
                        if (dist2 < minDist2 && dist2 > 1e-12f) { // Note: Using < minDist2 here
                            // Load current colors for particle ii and jj
                            float32x4_t pColor_vec = vld1q_f32(&particleColor_param[pColorIdx]);
                            float32x4_t qColor_vec = vld1q_f32(&particleColor_param[qColorIdx]);

                            // Calculate average color
                            float32x4_t avg_color_vec = vmulq_n_f32(vaddq_f32(pColor_vec, qColor_vec), 0.5f);

                            // Apply diffusion: new_color = old_color + (avg_color - old_color) * coeff
                            // p_new = p_old + (avg - p_old) * coeff  => vmlaq_n_f32(p_old, vsubq_f32(avg, p_old), coeff)
                            pColor_vec = vmlaq_n_f32(pColor_vec, vsubq_f32(avg_color_vec, pColor_vec), colorDiffusionCoeff_param);
                            qColor_vec = vmlaq_n_f32(qColor_vec, vsubq_f32(avg_color_vec, qColor_vec), colorDiffusionCoeff_param);
                            
                            // Clamp colors to [0,1] after diffusion
                            const float32x4_t zero_vec = vdupq_n_f32(0.0f);
                            const float32x4_t one_vec = vdupq_n_f32(1.0f);

                            pColor_vec = vmaxq_f32(zero_vec, vminq_f32(pColor_vec, one_vec));
                            qColor_vec = vmaxq_f32(zero_vec, vminq_f32(qColor_vec, one_vec));

                            // Store updated colors
                            vst1q_f32(&particleColor_param[pColorIdx], pColor_vec);
                            vst1q_f32(&particleColor_param[qColorIdx], qColor_vec);
                        }
                    }
                }
            }
        }
    } // End diffuseParticleColors_native

    // Helper clamp function (Unchanged)
    inline float clamp_cpp(float val, float min_val, float max_val) {
        return fmaxf(min_val, fminf(val, max_val));
    }

    // Removed __attribute__ for broader compatibility
    void transferVelocities_native(
        bool toGrid, float flipRatio,
        // Grid data
        float* u, float* v, float* du, float* dv,
        float* prevU, float* prevV,
        int32_t* cellType, // Written in P->G, read in G->P
        const float* s,    // Read only
        // Particle data
        const float* particlePos, // Read only
        float* particleVel,       // Written in G->P, read in P->G
        // Grid parameters
        int fNumX, int fNumY, float h, float invH,
        // Particle parameters
        int numParticles
    ) {
        omp_set_num_threads(2); // Limit threads for thermal management (Phase 4)
        const int n = fNumY; // Stride
        const int fNumCells = fNumX * fNumY;
        const float hh = h; // Alias for clarity
        const float h2 = 0.5f * hh;

        if (toGrid) {
            // --- P->G Transfer ---

            // 1. Backup grid velocities and clear current/delta velocities (Vectorized + OpenMP)
            const float32x4_t zero_vec = vdupq_n_f32(0.0f);
            #pragma omp parallel for schedule(static)
            for (int i = 0; i <= fNumCells - 4; i += 4) {
                float32x4_t u_vec = vld1q_f32(&u[i]);
                float32x4_t v_vec = vld1q_f32(&v[i]);
                vst1q_f32(&prevU[i], u_vec);
                vst1q_f32(&prevV[i], v_vec);
                vst1q_f32(&du[i], zero_vec);
                vst1q_f32(&dv[i], zero_vec);
                vst1q_f32(&u[i], zero_vec);
                vst1q_f32(&v[i], zero_vec);
            }
            // Scalar remainder (can be parallel too, less impact)
            #pragma omp parallel for schedule(static)
            for (int i = fNumCells - (fNumCells % 4); i < fNumCells; ++i) {
                prevU[i] = u[i]; prevV[i] = v[i];
                du[i] = 0.0f; dv[i] = 0.0f;
                u[i] = 0.0f; v[i] = 0.0f;
            }

            // 2. Initialize cell types (Solid based on s, rest Air) (OpenMP)
            #pragma omp parallel for schedule(static)
            for (int i = 0; i < fNumCells; ++i) {
                cellType[i] = (s[i] == 0.0f ? SOLID_CELL_CPP : AIR_CELL_CPP);
            }

            // 3. Mark cells containing particles as Fluid (Keep serial - potential races on cellType write)
            for (int i = 0; i < numParticles; ++i) {
                const float px = particlePos[2 * i];
                const float py = particlePos[2 * i + 1];
                const int xi = static_cast<int>(clamp_cpp(floorf(px * invH), 0.0f, static_cast<float>(fNumX - 1)));
                const int yi = static_cast<int>(clamp_cpp(floorf(py * invH), 0.0f, static_cast<float>(fNumY - 1)));
                const int c = xi * n + yi;
                if (c >= 0 && c < fNumCells && cellType[c] == AIR_CELL_CPP) {
                    cellType[c] = FLUID_CELL_CPP;
                }
            }

            // 4. Transfer particle velocities to grid (Keep serial - accumulation race condition)
            for (int comp = 0; comp < 2; ++comp) {
                // (Logic identical to _vectorized - scalar interpolation per particle)
                const float dx_offset = (comp == 0 ? 0.0f : h2);
                const float dy_offset = (comp == 0 ? h2 : 0.0f);
                float* f_arr = (comp == 0 ? u : v);
                float* df_arr = (comp == 0 ? du : dv);
                const float clamp_max_x_val = static_cast<float>(fNumX - 1) * hh;
                const float clamp_max_y_val = static_cast<float>(fNumY - 1) * hh;
                const float grid_max_idx_f_x_val = static_cast<float>(fNumX - 2);
                const float grid_max_idx_f_y_val = static_cast<float>(fNumY - 2);

                for (int i = 0; i < numParticles; ++i) {
                    float val_px_orig = particlePos[2 * i];
                    float val_py_orig = particlePos[2 * i + 1];
                    float px_clamped = fmaxf(hh, fminf(val_px_orig, clamp_max_x_val));
                    float py_clamped = fmaxf(hh, fminf(val_py_orig, clamp_max_y_val));
                    float fx = (px_clamped - dx_offset) * invH;
                    float fy = (py_clamped - dy_offset) * invH;
                    const int x0 = static_cast<int>(fminf(floorf(fx), grid_max_idx_f_x_val));
                    const int y0 = static_cast<int>(fminf(floorf(fy), grid_max_idx_f_y_val));
                    float tx = fx - static_cast<float>(x0);
                    float ty = fy - static_cast<float>(y0);
                    float sx = 1.0f - tx; float sy = 1.0f - ty;
                    const float w0 = sx * sy, w1 = tx * sy, w2 = tx * ty, w3 = sx * ty;
                    const int x1 = x0 + 1; const int y1 = y0 + 1;
                    const int n0 = x0 * n + y0, n1 = x1 * n + y0, n2 = x1 * n + y1, n3 = x0 * n + y1;
                    const float pv = particleVel[2 * i + comp];
                    if (n0 >= 0 && n0 < fNumCells) { f_arr[n0] += pv * w0; df_arr[n0] += w0; }
                    if (n1 >= 0 && n1 < fNumCells) { f_arr[n1] += pv * w1; df_arr[n1] += w1; }
                    if (n2 >= 0 && n2 < fNumCells) { f_arr[n2] += pv * w2; df_arr[n2] += w2; }
                    if (n3 >= 0 && n3 < fNumCells) { f_arr[n3] += pv * w3; df_arr[n3] += w3; }
                }
            }

            // 5. Normalize grid velocities (Vectorized + OpenMP)
            const float32x4_t epsilon_vec = vdupq_n_f32(1e-9f);
            #pragma omp parallel for schedule(static)
            for (int i = 0; i <= fNumCells - 4; i += 4) {
                float32x4_t u_vec = vld1q_f32(&u[i]); float32x4_t v_vec = vld1q_f32(&v[i]);
                float32x4_t du_vec = vld1q_f32(&du[i]); float32x4_t dv_vec = vld1q_f32(&dv[i]);
                uint32x4_t u_mask = vcgtq_f32(du_vec, epsilon_vec);
                float32x4_t u_divisor = vbslq_f32(u_mask, du_vec, vdupq_n_f32(1.0f));
                float32x4_t u_inv_divisor_est = vrecpeq_f32(u_divisor);
                float32x4_t u_inv_divisor_refined = vmulq_f32(vrecpsq_f32(u_divisor, u_inv_divisor_est), u_inv_divisor_est);
                float32x4_t u_div_result = vmulq_f32(u_vec, u_inv_divisor_refined);
                float32x4_t u_result = vbslq_f32(u_mask, u_div_result, zero_vec);
                uint32x4_t v_mask = vcgtq_f32(dv_vec, epsilon_vec);
                float32x4_t v_divisor = vbslq_f32(v_mask, dv_vec, vdupq_n_f32(1.0f));
                float32x4_t v_inv_divisor_est = vrecpeq_f32(v_divisor);
                float32x4_t v_inv_divisor_refined = vmulq_f32(vrecpsq_f32(v_divisor, v_inv_divisor_est), v_inv_divisor_est);
                float32x4_t v_div_result = vmulq_f32(v_vec, v_inv_divisor_refined);
                float32x4_t v_result = vbslq_f32(v_mask, v_div_result, zero_vec);
                vst1q_f32(&u[i], u_result); vst1q_f32(&v[i], v_result);
            }
            // Scalar remainder (can be parallel)
            #pragma omp parallel for schedule(static)
            for (int i = fNumCells - (fNumCells % 4); i < fNumCells; ++i) {
                u[i] = (du[i] > 1e-9f) ? (u[i] / du[i]) : 0.0f;
                v[i] = (dv[i] > 1e-9f) ? (v[i] / dv[i]) : 0.0f;
            }

            // 6. Restore solid cell velocities (using prevU/prevV) (OpenMP)
            #pragma omp parallel for collapse(2) schedule(static)
            for (int i = 0; i < fNumX; i++) {
                for (int j = 0; j < fNumY; j++) {
                    const int idx = i * n + j;
                    if (idx < 0 || idx >= fNumCells) continue;
                    const bool solidCurrent = (cellType[idx] == SOLID_CELL_CPP);
                    const int leftCellIdx = (i > 0) ? (i - 1) * n + j : -1;
                    bool solidLeft = (i > 0 && leftCellIdx >= 0 && leftCellIdx < fNumCells && cellType[leftCellIdx] == SOLID_CELL_CPP);
                    if (solidCurrent || solidLeft) { if (idx < fNumCells) u[idx] = prevU[idx]; }
                    const int bottomCellIdx = (j > 0) ? i * n + (j - 1) : -1;
                    bool solidBottom = (j > 0 && bottomCellIdx >= 0 && bottomCellIdx < fNumCells && cellType[bottomCellIdx] == SOLID_CELL_CPP);
                    if (solidCurrent || solidBottom) { if (idx < fNumCells) v[idx] = prevV[idx]; }
                }
            }

        } else {
            // --- G->P Transfer (Keep serial - potential races on particleVel write) ---
            const int n_stride = n; // For lambda capture

             // Define validity check lambda (logic from previous fix)
            auto isValidVelocitySample =
                [&](int sample_idx, int component) -> bool {
                if (sample_idx < 0 || sample_idx >= fNumCells) return false;
                int neighbor_idx_offset = (component == 0) ? n_stride : 1;
                int neighbor_idx = sample_idx - neighbor_idx_offset;
                bool sample_cell_ok = (cellType[sample_idx] != AIR_CELL_CPP);
                bool neighbor_cell_ok = (neighbor_idx >= 0 && neighbor_idx < fNumCells && cellType[neighbor_idx] != AIR_CELL_CPP);
                return sample_cell_ok || neighbor_cell_ok;
            };

            for (int comp = 0; comp < 2; ++comp) {
                 // (Logic identical to _vectorized / previous fix - scalar interpolation per particle)
                const float dx_offset = (comp == 0 ? 0.0f : h2);
                const float dy_offset = (comp == 0 ? h2 : 0.0f);
                const float* f_arr = (comp == 0) ? u : v;
                const float* prevF_arr = (comp == 0) ? prevU : prevV;
                const float clamp_max_x_val = static_cast<float>(fNumX - 1) * hh;
                const float clamp_max_y_val = static_cast<float>(fNumY - 1) * hh;
                const float grid_max_idx_f_x_val = static_cast<float>(fNumX - 2);
                const float grid_max_idx_f_y_val = static_cast<float>(fNumY - 2);

                for (int i = 0; i < numParticles; ++i) {
                    float px_orig = particlePos[2*i]; float py_orig = particlePos[2*i+1];
                    float px_clamped = fmaxf(hh, fminf(px_orig, clamp_max_x_val));
                    float py_clamped = fmaxf(hh, fminf(py_orig, clamp_max_y_val));
                    float fx = (px_clamped - dx_offset) * invH;
                    float fy = (py_clamped - dy_offset) * invH;
                    const int x0 = static_cast<int>(fminf(floorf(fx), grid_max_idx_f_x_val));
                    const int y0 = static_cast<int>(fminf(floorf(fy), grid_max_idx_f_y_val));
                    float tx = fx - static_cast<float>(x0); float ty = fy - static_cast<float>(y0);
                    float sx = 1.0f - tx; float sy = 1.0f - ty;
                    const int x1 = x0 + 1; const int y1 = y0 + 1;
                    const float w0 = sx * sy, w1 = tx * sy, w2 = tx * ty, w3 = sx * ty;
                    const int n0 = x0 * n + y0, n1 = x1 * n + y0, n2 = x1 * n + y1, n3 = x0 * n + y1;

                    float v0ok = 0.0f, v1ok = 0.0f, v2ok = 0.0f, v3ok = 0.0f;
                     // Use validity check lambda
                    if (n0 >= 0 && n0 < fNumCells) v0ok = isValidVelocitySample(n0, comp) ? 1.0f : 0.0f;
                    if (n1 >= 0 && n1 < fNumCells) v1ok = isValidVelocitySample(n1, comp) ? 1.0f : 0.0f;
                    if (n2 >= 0 && n2 < fNumCells) v2ok = isValidVelocitySample(n2, comp) ? 1.0f : 0.0f;
                    if (n3 >= 0 && n3 < fNumCells) v3ok = isValidVelocitySample(n3, comp) ? 1.0f : 0.0f;

                    const float sumW = v0ok * w0 + v1ok * w1 + v2ok * w2 + v3ok * w3;

                    if (sumW > 1e-9f) {
                         // Safely access arrays only if index is valid (although lambda should prevent invalid indices)
                        const float f0 = (n0 >= 0 && n0 < fNumCells) ? f_arr[n0] : 0.0f;
                        const float f1 = (n1 >= 0 && n1 < fNumCells) ? f_arr[n1] : 0.0f;
                        const float f2 = (n2 >= 0 && n2 < fNumCells) ? f_arr[n2] : 0.0f;
                        const float f3 = (n3 >= 0 && n3 < fNumCells) ? f_arr[n3] : 0.0f;
                        const float pf0 = (n0 >= 0 && n0 < fNumCells) ? prevF_arr[n0] : 0.0f;
                        const float pf1 = (n1 >= 0 && n1 < fNumCells) ? prevF_arr[n1] : 0.0f;
                        const float pf2 = (n2 >= 0 && n2 < fNumCells) ? prevF_arr[n2] : 0.0f;
                        const float pf3 = (n3 >= 0 && n3 < fNumCells) ? prevF_arr[n3] : 0.0f;

                        const float picV = (v0ok * w0 * f0 + v1ok * w1 * f1 + v2ok * w2 * f2 + v3ok * w3 * f3) / sumW;
                        const float corr = (v0ok * w0 * (f0 - pf0) + v1ok * w1 * (f1 - pf1) +
                                            v2ok * w2 * (f2 - pf2) + v3ok * w3 * (f3 - pf3)) / sumW;
                        const float flipV = particleVel[2 * i + comp] + corr;
                        particleVel[2 * i + comp] = (1.0f - flipRatio) * picV + flipRatio * flipV;
                    }
                }
            }
        }
    } // End transferVelocities_native

    // __attribute__((visibility("default"))) __attribute__((used)) // Removed for broader compatibility
    void updateParticleDensityGrid_native( // Renamed from updateParticleProperties_native
        // Inputs
        int numParticles,
        float particleRestDensity_param,
        float invH_param,
        int fNumX_param, int fNumY_param,
        float h_param,
        const float* particlePos_param,
        // const int32_t* cellType_param, // Was unused, removed
        // Outputs (modified in place via pointers)
        float* particleDensityGrid_param
        // float* particleColor_param, // REMOVED
        // bool enableDynamicColoring // REMOVED
    ) {
        omp_set_num_threads(2); // Limit threads for thermal management (Phase 4)
        const int n_stride = fNumY_param; // Stride for grid
        const int fNumCells_param = fNumX_param * fNumY_param;
        const float hh_param = h_param; // Alias for clarity
        const float h2_param = 0.5f * hh_param;
        
        // 1. Update Particle Density (Logic from Dart's updateParticleDensity)
        // Zero the density grid first
        #pragma omp parallel for schedule(static)
        for(int i = 0; i < fNumCells_param; ++i) {
             particleDensityGrid_param[i] = 0.0f;
        }

        // Accumulate density (keep serial - accumulation race)
        for (int i = 0; i < numParticles; i++) {
            float x = particlePos_param[2 * i];
            float y = particlePos_param[2 * i + 1];
            
            x = clamp_cpp(x, hh_param, (fNumX_param - 1) * hh_param);
            y = clamp_cpp(y, hh_param, (fNumY_param - 1) * hh_param);
            x -= h2_param;
            y -= h2_param;

            const int x0 = static_cast<int>(floorf(x * invH_param));
            const int y0 = static_cast<int>(floorf(y * invH_param));
            const float tx = (x - static_cast<float>(x0) * hh_param) * invH_param;
            const float ty = (y - static_cast<float>(y0) * hh_param) * invH_param;

            // Ensure indices are safe before calculating weights/indices
            if (x0 < 0 || x0 >= fNumX_param - 1 || y0 < 0 || y0 >= fNumY_param - 1) continue;

            const int x1 = x0 + 1;
            const int y1 = y0 + 1;
            const float sx = 1.0f - tx;
            const float sy = 1.0f - ty;

            int idx0 = x0 * n_stride + y0; int idx1 = x1 * n_stride + y0;
            int idx2 = x1 * n_stride + y1; int idx3 = x0 * n_stride + y1;

            if(idx0 >= 0 && idx0 < fNumCells_param) particleDensityGrid_param[idx0] += sx * sy;
            if(idx1 >= 0 && idx1 < fNumCells_param) particleDensityGrid_param[idx1] += tx * sy;
            if(idx2 >= 0 && idx2 < fNumCells_param) particleDensityGrid_param[idx2] += tx * ty;
            if(idx3 >= 0 && idx3 < fNumCells_param) particleDensityGrid_param[idx3] += sx * ty;
        }
        // Color update logic removed from this function
    } // End updateParticleDensityGrid_native

    // New function for dynamic particle color updates
    void updateDynamicParticleColors_native(
        int numParticles,
        float particleRestDensity_param,
        float invH_param,
        int fNumX_param, int fNumY_param,
        float h_param,
        const float* particlePos_param, // For cell index calculation
        const float* particleDensityGrid_param, // Read-only, needed for relDensity
        float* particleColor_param // Read & Written
    ) {
        omp_set_num_threads(2); // Consistent threading
        const int n_stride = fNumY_param;
        const int fNumCells_param = fNumX_param * fNumY_param;

        // Logic from JS updateParticleColors / former part of updateParticleProperties_native
        const float color_fade_s = 0.01f;
        const float low_density_threshold = 0.7f;
        const float low_density_highlight_s = 0.8f;

        #pragma omp parallel for schedule(static)
        for (int i = 0; i < numParticles; ++i) {
            int baseColorIdx = 4 * i; // Changed for RGBA

            // Load current color
            float32x4_t color_vec = vld1q_f32(&particleColor_param[baseColorIdx]);

            // Apply fading/shifting using NEON
            // R fades down, G fades down, B fades up, A is preserved
            float32x4_t fade_adjustments = vdupq_n_f32(0.0f); // Initialize all lanes to 0.0f
            fade_adjustments = vsetq_lane_f32(color_fade_s, fade_adjustments, 0);    // Set lane 0 (for R adjustment)
            fade_adjustments = vsetq_lane_f32(color_fade_s, fade_adjustments, 1);    // Set lane 1 (for G adjustment)
            fade_adjustments = vsetq_lane_f32(-color_fade_s, fade_adjustments, 2);   // Set lane 2 (for B adjustment)
                                                                                    // Lane 3 remains 0.0f (for A, no change in adjustment)
            color_vec = vsubq_f32(color_vec, fade_adjustments);

            // Clamp all components to [0.0, 1.0] using NEON
            const float32x4_t zero_vec = vdupq_n_f32(0.0f);
            const float32x4_t one_vec = vdupq_n_f32(1.0f);
            color_vec = vmaxq_f32(zero_vec, vminq_f32(color_vec, one_vec));
            
            // Store faded and clamped color (will be overwritten if density reset occurs)
            vst1q_f32(&particleColor_param[baseColorIdx], color_vec);

            // Apply density-based reset
            if (particleRestDensity_param > 1e-9f) { // Ensure rest_density is valid
                int xi = static_cast<int>(clamp_cpp(floorf(particlePos_param[2*i] * invH_param), 0.0f, static_cast<float>(fNumX_param - 1)));
                int yi = static_cast<int>(clamp_cpp(floorf(particlePos_param[2*i+1] * invH_param), 0.0f, static_cast<float>(fNumY_param - 1)));
                int cellIdx = xi * n_stride + yi;

                if (cellIdx >= 0 && cellIdx < fNumCells_param) {
                    float relDensity = particleDensityGrid_param[cellIdx] / particleRestDensity_param;
                    if (relDensity < low_density_threshold) {
                        // Set to highlight color {low_density_highlight_s, low_density_highlight_s, 1.0f, 1.0f} (RGBA)
                        float32x4_t highlight_color_vec = vdupq_n_f32(0.0f); // Initialize all lanes
                        highlight_color_vec = vsetq_lane_f32(low_density_highlight_s, highlight_color_vec, 0);
                        highlight_color_vec = vsetq_lane_f32(low_density_highlight_s, highlight_color_vec, 1);
                        highlight_color_vec = vsetq_lane_f32(1.0f, highlight_color_vec, 2);
                        highlight_color_vec = vsetq_lane_f32(1.0f, highlight_color_vec, 3); // Alpha to 1.0f for highlight
                        vst1q_f32(&particleColor_param[baseColorIdx], highlight_color_vec);
                    }
                }
            }
        }
    } // End updateDynamicParticleColors_native


    // __attribute__((visibility("default"))) __attribute__((used)) // Removed for broader compatibility
    void handleCollisions_native(
        // Inputs / Outputs (modified in place)
        float* particlePos_param,     // Read & Written
        float* particleVel_param,     // Read & Written
        // Inputs
        int numParticles,
        float particleRadius_param,
        // Obstacle parameters
        bool isObstacleActive_param,
        float obstacleX_param,
        float obstacleY_param,
        float obstacleRadius_param,
        float obstacleVelX_param,
        float obstacleVelY_param,
        // Scene boundary parameters
        float sceneCircleCenterX_param,
        float sceneCircleCenterY_param,
        float sceneCircleRadius_param
    ) {
        omp_set_num_threads(2); // Limit threads for thermal management (Phase 4)
        const float r = particleRadius_param;
        const float obsInteractRadius = obstacleRadius_param + r;
        const float obsInteractRadiusSq = obsInteractRadius * obsInteractRadius;
        const float wallCollisionRadius = sceneCircleRadius_param - r;

        #pragma omp parallel for schedule(static)
        for (int i = 0; i < numParticles; i++) {
            const int pIdx = 2 * i;
            float px = particlePos_param[pIdx];
            float py = particlePos_param[pIdx + 1];
            float pvx = particleVel_param[pIdx];
            float pvy = particleVel_param[pIdx + 1];

            if (isObstacleActive_param) {
                const float dxObs = px - obstacleX_param;
                const float dyObs = py - obstacleY_param;
                const float d2Obs = dxObs * dxObs + dyObs * dyObs;
                if (d2Obs < obsInteractRadiusSq && d2Obs > 1e-12f) {
                    const float dObs = sqrtf(d2Obs);
                    const float overlapObs = obsInteractRadius - dObs;
                    const float pushFactor = 1.0f; // Match Dart
                    px += (dxObs / dObs) * overlapObs * pushFactor;
                    py += (dyObs / dObs) * overlapObs * pushFactor;
                    pvx = obstacleVelX_param;
                    pvy = obstacleVelY_param;
                }
            }

            const float dxWall = px - sceneCircleCenterX_param;
            const float dyWall = py - sceneCircleCenterY_param;
            const float distSqToWallCenter = dxWall * dxWall + dyWall * dyWall;
            if (distSqToWallCenter > wallCollisionRadius * wallCollisionRadius && distSqToWallCenter > 1e-12f) {
                const float distToWallCenter = sqrtf(distSqToWallCenter);
                const float overlapWall = distToWallCenter - wallCollisionRadius;
                px -= (dxWall / distToWallCenter) * overlapWall;
                py -= (dyWall / distToWallCenter) * overlapWall;
                pvx = 0.0f;
                pvy = 0.0f;
            }
            particlePos_param[pIdx] = px;
            particlePos_param[pIdx + 1] = py;
            particleVel_param[pIdx] = pvx;
            particleVel_param[pIdx + 1] = pvy;
        }
    } // End handleCollisions_native

} // extern "C"