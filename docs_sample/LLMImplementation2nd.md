Below is the full `FlipFluidSimulation` class, a line-by-line port of the JavaScript `FlipFluid` implementation into Dart, using `Float32List`/`Int32List` buffers and matching all algorithmic details from the reference HTML . You can drop this into `lib/simulation/flip_fluid_simulation.dart` and have a fully-functional core ready for rendering and interaction.

```dart
// lib/simulation/flip_fluid_simulation.dart

import 'dart:typed_data';
import 'dart:math';

class FlipFluidSimulation {
  // Cell enums
  static const int U_FIELD = 0;
  static const int V_FIELD = 1;
  static const int FLUID_CELL = 0;
  static const int AIR_CELL = 1;
  static const int SOLID_CELL = 2;

  // Simulation parameters
  final double density;
  final int fNumX, fNumY, fNumCells;
  final double h, fInvSpacing;

  // Grid buffers
  final Float32List u, v, du, dv, prevU, prevV, p, s, cellColor;
  final Int32List cellType;

  // Particle parameters
  final int maxParticles;
  int numParticles = 0;
  final Float32List particlePos, particleVel, particleColor;
  final Float32List particleDensity;
  double particleRestDensity = 0.0;
  final double particleRadius, pInvSpacing;
  final int pNumX, pNumY, pNumCells;
  final Int32List numCellParticles, firstCellParticle, cellParticleIds;

  FlipFluidSimulation({
    required this.density,
    required double width,
    required double height,
    required double spacing,
    required this.particleRadius,
    required this.maxParticles,
  })  : 
    // grid resolution
    fNumX = (width / spacing).floor() + 1,
    fNumY = (height / spacing).floor() + 1,
    h = max(width / ((width / spacing).floor() + 1), height / ((height / spacing).floor() + 1)),
    fInvSpacing = 1.0 / max(width / ((width / spacing).floor() + 1), height / ((height / spacing).floor() + 1)),
    fNumCells = ((width / spacing).floor() + 1) * ((height / spacing).floor() + 1),

    // allocate grid arrays
    u = Float32List(((width / spacing).floor() + 1) * ((height / spacing).floor() + 1)),
    v = Float32List(((width / spacing).floor() + 1) * ((height / spacing).floor() + 1)),
    du = Float32List(((width / spacing).floor() + 1) * ((height / spacing).floor() + 1)),
    dv = Float32List(((width / spacing).floor() + 1) * ((height / spacing).floor() + 1)),
    prevU = Float32List(((width / spacing).floor() + 1) * ((height / spacing).floor() + 1)),
    prevV = Float32List(((width / spacing).floor() + 1) * ((height / spacing).floor() + 1)),
    p  = Float32List(((width / spacing).floor() + 1) * ((height / spacing).floor() + 1)),
    s  = Float32List(((width / spacing).floor() + 1) * ((height / spacing).floor() + 1)),
    cellColor = Float32List(3 * (((width / spacing).floor() + 1) * ((height / spacing).floor() + 1))),
    cellType = Int32List(((width / spacing).floor() + 1) * ((height / spacing).floor() + 1)),

    // particle resolution
    pInvSpacing = 1.0 / (2.2 * spacing),
    pNumX = (width * (1.0 / (2.2 * spacing))).floor() + 1,
    pNumY = (height * (1.0 / (2.2 * spacing))).floor() + 1,
    pNumCells = ((width * (1.0 / (2.2 * spacing))).floor() + 1) * ((height * (1.0 / (2.2 * spacing))).floor() + 1),

    // allocate particle arrays
    particlePos = Float32List(2 * maxParticles),
    particleVel = Float32List(2 * maxParticles),
    particleColor = Float32List(3 * maxParticles),
    particleDensity = Float32List(((width / spacing).floor() + 1) * ((height / spacing).floor() + 1)),
    numCellParticles = Int32List(((width * (1.0 / (2.2 * spacing))).floor() + 1) * ((height * (1.0 / (2.2 * spacing))).floor() + 1)),
    firstCellParticle = Int32List((((width * (1.0 / (2.2 * spacing))).floor() + 1) * ((height * (1.0 / (2.2 * spacing))).floor() + 1)) + 1),
    cellParticleIds = Int32List(maxParticles)
  {
    // initialize particle colors to blue
    for (int i = 0; i < maxParticles; i++) {
      particleColor[3 * i + 2] = 1.0;
    }
  }

  // Helper clamp
  static double clamp(double x, double minVal, double maxVal) {
    if (x < minVal) return minVal;
    if (x > maxVal) return maxVal;
    return x;
  }

  /// 1. Integrate particle positions & velocities under gravity
  void integrateParticles(double dt, double gravity) {
    for (int i = 0; i < numParticles; i++) {
      final int b = 2 * i;
      particleVel[b + 1] += dt * gravity;
      particlePos[b]     += particleVel[b]     * dt;
      particlePos[b + 1] += particleVel[b + 1] * dt;
    }
  }

  /// 2. Push overlapping particles apart via simple spatial hashing
  void pushParticlesApart(int numIters) {
    // reset grid counts
    numCellParticles.fillRange(0, pNumCells, 0);

    // count per-cell
    for (int i = 0; i < numParticles; i++) {
      final double x = particlePos[2*i], y = particlePos[2*i+1];
      final int xi = clamp((x * pInvSpacing).floorToDouble(), 0, pNumX - 1).toInt();
      final int yi = clamp((y * pInvSpacing).floorToDouble(), 0, pNumY - 1).toInt();
      numCellParticles[xi * pNumY + yi]++;
    }

    // prefix-sums → firstCellParticle
    int sum = 0;
    for (int c = 0; c < pNumCells; c++) {
      sum += numCellParticles[c];
      firstCellParticle[c] = sum;
    }
    firstCellParticle[pNumCells] = sum;

    // fill cellParticleIds
    for (int i = 0; i < numParticles; i++) {
      final double x = particlePos[2*i], y = particlePos[2*i+1];
      final int xi = clamp((x * pInvSpacing).floorToDouble(), 0, pNumX - 1).toInt();
      final int yi = clamp((y * pInvSpacing).floorToDouble(), 0, pNumY - 1).toInt();
      int c = xi * pNumY + yi;
      firstCellParticle[c]--;
      cellParticleIds[firstCellParticle[c]] = i;
    }

    // repel neighbors
    final double minDist = 2.0 * particleRadius;
    final double minDist2 = minDist * minDist;

    for (int iter = 0; iter < numIters; iter++) {
      for (int ii = 0; ii < numParticles; ii++) {
        final double px = particlePos[2*ii], py = particlePos[2*ii+1];
        final int pxi = clamp((px * pInvSpacing).floorToDouble(), 0, pNumX - 1).toInt();
        final int pyi = clamp((py * pInvSpacing).floorToDouble(), 0, pNumY - 1).toInt();
        final int x0 = max(pxi-1, 0), x1 = min(pxi+1, pNumX-1);
        final int y0 = max(pyi-1, 0), y1 = min(pyi+1, pNumY-1);

        for (int cx = x0; cx <= x1; cx++) {
          for (int cy = y0; cy <= y1; cy++) {
            int cellStart = firstCellParticle[cx * pNumY + cy];
            int cellEnd   = firstCellParticle[cx * pNumY + cy + 1];
            for (int idx = cellStart; idx < cellEnd; idx++) {
              final int jj = cellParticleIds[idx];
              if (jj == ii) continue;
              final double qx = particlePos[2*jj], qy = particlePos[2*jj+1];
              final double dx = qx - px, dy = qy - py;
              final double d2 = dx*dx + dy*dy;
              if (d2 == 0.0 || d2 > minDist2) continue;
              final double d = sqrt(d2);
              final double s = 0.5 * (minDist - d) / d;
              final double ox = dx * s, oy = dy * s;
              // move apart
              particlePos[2*ii]     -= ox;
              particlePos[2*ii + 1] -= oy;
              particlePos[2*jj]     += ox;
              particlePos[2*jj + 1] += oy;
            }
          }
        }
      }
    }
  }

  /// 3. Handle collisions with circular obstacle + boundary walls
  void handleParticleCollisions(
    double obstacleX,
    double obstacleY,
    double obstacleRadius,
    double obstacleVelX,
    double obstacleVelY,
  ) {
    final double gridH = 1.0 / fInvSpacing;
    final double r = particleRadius;
    final double minX = gridH + r;
    final double maxX = (fNumX - 1) * gridH - r;
    final double minY = gridH + r;
    final double maxY = (fNumY - 1) * gridH - r;
    final double minDist = obstacleRadius + r;
    final double minDist2 = minDist * minDist;

    for (int i = 0; i < numParticles; i++) {
      double x = particlePos[2*i], y = particlePos[2*i+1];
      // obstacle
      final double dx = x - obstacleX, dy = y - obstacleY, d2 = dx*dx + dy*dy;
      if (d2 < minDist2) {
        particleVel[2*i]     = obstacleVelX;
        particleVel[2*i + 1] = obstacleVelY;
      }
      // walls
      if (x < minX)      { x = minX;      particleVel[2*i]     = 0.0; }
      if (x > maxX)      { x = maxX;      particleVel[2*i]     = 0.0; }
      if (y < minY)      { y = minY;      particleVel[2*i + 1] = 0.0; }
      if (y > maxY)      { y = maxY;      particleVel[2*i + 1] = 0.0; }
      particlePos[2*i]     = x;
      particlePos[2*i + 1] = y;
    }
  }

  /// 4. Compute per-cell particle density & rest density
  void updateParticleDensity() {
    final int n = fNumY;
    final double hh = h, invH = fInvSpacing, h2 = 0.5 * h;
    // zero
    particleDensity.fillRange(0, fNumCells, 0.0);

    for (int i = 0; i < numParticles; i++) {
      double x = clamp(particlePos[2*i], hh, (fNumX - 1) * hh);
      double y = clamp(particlePos[2*i+1], hh, (fNumY - 1) * hh);
      x -= h2; y -= h2;
      final int x0 = (x * invH).floor();
      final int y0 = (y * invH).floor();
      final double tx = (x - x0 * hh) * invH;
      final double ty = (y - y0 * hh) * invH;
      final int x1 = min(x0 + 1, fNumX - 2);
      final int y1 = min(y0 + 1, fNumY - 2);
      final double sx = 1.0 - tx, sy = 1.0 - ty;
      // bilinear add
      particleDensity[x0 * n + y0] += sx * sy;
      particleDensity[x1 * n + y0] += tx * sy;
      particleDensity[x1 * n + y1] += tx * ty;
      particleDensity[x0 * n + y1] += sx * ty;
    }

    // rest density on first call
    if (particleRestDensity == 0.0) {
      double sum = 0.0;
      int count = 0;
      for (int i = 0; i < fNumCells; i++) {
        if (cellType[i] == FLUID_CELL) {
          sum += particleDensity[i];
          count++;
        }
      }
      if (count > 0) particleRestDensity = sum / count;
    }
  }

  /// 5. Transfer velocities P→G (toGrid=true) and G→P (toGrid=false)
  void transferVelocities({ required bool toGrid, required double flipRatio }) {
    final int n = fNumY;
    final double hh = h, invH = fInvSpacing, h2 = 0.5 * h;

    if (toGrid) {
      prevU.setAll(0, u);
      prevV.setAll(0, v);
      // zero out new fields
      for (int i = 0; i < fNumCells; i++) {
        du[i] = dv[i] = 0.0;
        u[i] = v[i] = 0.0;
        // cell type: SOLID if s==0, else AIR
        cellType[i] = (s[i] == 0.0 ? SOLID_CELL : AIR_CELL);
      }
      // mark FLUID cells where particles reside
      for (int i = 0; i < numParticles; i++) {
        final int xi = clamp((particlePos[2*i    ] * invH).floorToDouble(), 0, fNumX - 1).toInt();
        final int yi = clamp((particlePos[2*i + 1] * invH).floorToDouble(), 0, fNumY - 1).toInt();
        final int c = xi * n + yi;
        if (cellType[c] == AIR_CELL) cellType[c] = FLUID_CELL;
      }
    }

    // two components: 0→u, 1→v
    for (int comp = 0; comp < 2; comp++) {
      final double dx = (comp == 0 ? 0.0 : h2);
      final double dy = (comp == 0 ? h2 : 0.0);
      final Float32List f   = (comp == 0 ? u : v);
      final Float32List prevF = (comp == 0 ? prevU : prevV);
      final Float32List df  = (comp == 0 ? du : dv);

      for (int i = 0; i < numParticles; i++) {
        // particle pos clamped
        double x = clamp(particlePos[2*i    ], hh, (fNumX - 1) * hh);
        double y = clamp(particlePos[2*i + 1], hh, (fNumY - 1) * hh);
        x -= dx; y -= dy;
        final int x0 = min((x * invH).floor(), fNumX - 2);
        final int y0 = min((y * invH).floor(), fNumY - 2);
        final double tx = ((x - x0 * hh) * invH);
        final double ty = ((y - y0 * hh) * invH);
        final int x1 = x0 + 1, y1 = y0 + 1;
        final double sx = 1.0 - tx, sy = 1.0 - ty;
        final double w0 = sx * sy, w1 = tx * sy, w2 = tx * ty, w3 = sx * ty;
        final int n0 = x0 * n + y0, n1 = x1 * n + y0, n2 = x1 * n + y1, n3 = x0 * n + y1;

        if (toGrid) {
          final double pv = particleVel[2*i + comp];
          f[n0] += pv * w0; df[n0] += w0;
          f[n1] += pv * w1; df[n1] += w1;
          f[n2] += pv * w2; df[n2] += w2;
          f[n3] += pv * w3; df[n3] += w3;
        } else {
          // check valid faces
          final int offset = (comp == 0 ? n : 1);
          final double v0ok = (cellType[n0] != AIR_CELL || cellType[n0 - offset] != AIR_CELL) ? 1.0 : 0.0;
          final double v1ok = (cellType[n1] != AIR_CELL || cellType[n1 - offset] != AIR_CELL) ? 1.0 : 0.0;
          final double v2ok = (cellType[n2] != AIR_CELL || cellType[n2 - offset] != AIR_CELL) ? 1.0 : 0.0;
          final double v3ok = (cellType[n3] != AIR_CELL || cellType[n3 - offset] != AIR_CELL) ? 1.0 : 0.0;
          final double sumW = v0ok*w0 + v1ok*w1 + v2ok*w2 + v3ok*w3;
          if (sumW > 0.0) {
            // PIC
            final double picV = (v0ok*w0*f[n0] + v1ok*w1*f[n1] + v2ok*w2*f[n2] + v3ok*w3*f[n3]) / sumW;
            // FLIP
            final double corr = (v0ok*w0*(f[n0]-prevF[n0]) + v1ok*w1*(f[n1]-prevF[n1])
                               + v2ok*w2*(f[n2]-prevF[n2]) + v3ok*w3*(f[n3]-prevF[n3])) / sumW;
            final double flipV = particleVel[2*i + comp] + corr;
            particleVel[2*i + comp] = (1.0 - flipRatio) * picV + flipRatio * flipV;
          }
        }
      }

      if (toGrid) {
        // normalize and restore solids
        for (int i = 0; i < fNumCells; i++) {
          if (df[i] > 0.0) f[i] /= df[i];
        }
        // solid boundaries
        for (int i = 0; i < fNumX; i++) {
          for (int j = 0; j < fNumY; j++) {
            final int idx = i * n + j;
            final bool solid = (cellType[idx] == SOLID_CELL);
            if (comp == 0) {
              if (solid || (i > 0 && cellType[(i-1)*n + j] == SOLID_CELL)) u[idx] = prevU[idx];
            } else {
              if (solid || (j > 0 && cellType[i*n + j-1] == SOLID_CELL)) v[idx] = prevV[idx];
            }
          }
        }
      }
    }
  }

  /// 6. Enforce incompressibility via Gauss–Seidel
  void solveIncompressibility(
    int numIters,
    double dt,
    double overRelaxation,
    bool compensateDrift,
  ) {
    p.fillRange(0, fNumCells, 0.0);
    prevU.setAll(0, u);
    prevV.setAll(0, v);
    final double cp = density * h / dt;
    final int n = fNumY;

    for (int iter = 0; iter < numIters; iter++) {
      for (int i = 1; i < fNumX - 1; i++) {
        for (int j = 1; j < fNumY - 1; j++) {
          final int idx = i * n + j;
          if (cellType[idx] != FLUID_CELL) continue;

          final int left   = (i-1)*n + j;
          final int right  = (i+1)*n + j;
          final int bottom = i*n + (j-1);
          final int top    = i*n + (j+1);

          final double sx0 = s[left], sx1 = s[right];
          final double sy0 = s[bottom], sy1 = s[top];
          final double sumS = sx0 + sx1 + sy0 + sy1;
          if (sumS == 0.0) continue;

          double div = (u[right] - u[idx]) + (v[top] - v[idx]);
          if (particleRestDensity > 0.0 && compensateDrift) {
            final double comp = particleDensity[idx] - particleRestDensity;
            if (comp > 0.0) div -= comp;
          }

          double pressure = -div / sumS;
          pressure *= overRelaxation;
          p[idx] += cp * pressure;
          u[idx]    -= sx0 * pressure;
          u[right]  += sx1 * pressure;
          v[idx]    -= sy0 * pressure;
          v[top]    += sy1 * pressure;
        }
      }
    }
  }

  /// 7. Update particle colors (optional scientific coloring)
  void updateParticleColors() {
    final double decay = 0.01;
    final double invH = fInvSpacing;
    for (int i = 0; i < numParticles; i++) {
      // fade to dark
      particleColor[3*i + 0] = clamp(particleColor[3*i + 0] - decay, 0.0, 1.0);
      particleColor[3*i + 1] = clamp(particleColor[3*i + 1] - decay, 0.0, 1.0);
      particleColor[3*i + 2] = clamp(particleColor[3*i + 2] + decay, 0.0, 1.0);

      // density highlight
      final int xi = clamp((particlePos[2*i]     * invH).floorToDouble(), 1, fNumX - 1).toInt();
      final int yi = clamp((particlePos[2*i + 1] * invH).floorToDouble(), 1, fNumY - 1).toInt();
      final int idx = xi * fNumY + yi;
      if (particleRestDensity > 0.0) {
        final double rel = particleDensity[idx] / particleRestDensity;
        if (rel < 0.7) {
          final double s = 0.8;
          particleColor[3*i + 0] = s;
          particleColor[3*i + 1] = s;
          particleColor[3*i + 2] = 1.0;
        }
      }
    }
  }

  /// 8. Compute cell colours (for grid debug)
  void updateCellColors() {
    for (int i = 0; i < fNumCells; i++) {
      final int ci = 3 * i;
      if (cellType[i] == SOLID_CELL) {
        cellColor[ci]     = 0.5;
        cellColor[ci + 1] = 0.5;
        cellColor[ci + 2] = 0.5;
      } else if (cellType[i] == FLUID_CELL) {
        // map density → rainbow
        final double d = particleDensity[i] / particleRestDensity;
        final double val = clamp(d, 0.0, 2.0) / 2.0;
        final double m = 0.25, s = (val % m) / m;
        int stage = (val / m).floor();
        double r=0, g=0, b=0;
        switch (stage) {
          case 0: r=0;    g=s;    b=1;    break;
          case 1: r=0;    g=1;    b=1-s;  break;
          case 2: r=s;    g=1;    b=0;    break;
          case 3: r=1;    g=1-s;  b=0;    break;
        }
        cellColor[ci]     = r;
        cellColor[ci + 1] = g;
        cellColor[ci + 2] = b;
      } else {
        cellColor[ci] = cellColor[ci+1] = cellColor[ci+2] = 0.0;
      }
    }
  }

  /// 9. Full FLIP step
  void simulate({
    required double dt,
    required double gravity,
    required double flipRatio,
    required int numPressureIters,
    required int numParticleIters,
    required double overRelaxation,
    required bool compensateDrift,
    required bool separateParticles,
    required double obstacleX,
    required double obstacleY,
    required double obstacleRadius,
    required double obstacleVelX,
    required double obstacleVelY,
  }) {
    // single substep
    final double sdt = dt;
    integrateParticles(sdt, gravity);
    if (separateParticles) pushParticlesApart(numParticleIters);
    handleParticleCollisions(obstacleX, obstacleY, obstacleRadius, obstacleVelX, obstacleVelY);
    transferVelocities(toGrid: true,  flipRatio: flipRatio);
    updateParticleDensity();
    solveIncompressibility(numPressureIters, sdt, overRelaxation, compensateDrift);
    transferVelocities(toGrid: false, flipRatio: flipRatio);
    updateParticleColors();
    updateCellColors();
  }
}
```

This Dart class mirrors every step of the JS reference, from particle integration through pressure solves and color mapping, with all buffers pre-allocated and no per-frame garbage. You can now hook `particlePos`, `particleColor`, and `cellColor` directly into your renderer, and call `simulate()` each tick with the current obstacle state.