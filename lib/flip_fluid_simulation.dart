// lib/simulation/flip_fluid_simulation.dart

import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:ffi/ffi.dart' as ffiMemory; // Changed alias
import 'dart:developer' as devLog; // Changed alias

// --- FFI Bindings Setup ---
typedef SolveIncompressibilityNative = Void Function(
    Pointer<Float> u,
    Pointer<Float> v,
    Pointer<Float> p,
    Pointer<Float> s,
    Pointer<Int32> cellType,
    Pointer<Float> particleDensity,
    Int32 fNumX,
    Int32 fNumY,
    Int32 numIters,
    Float h,
    Float dt,
    Float density,
    Float overRelaxation,
    Float particleRestDensity,
    Bool compensateDrift,
    Float circleCenterX,
    Float circleCenterY,
    Float circleRadius,
    Bool isObstacleActive,
    Float obstacleX,
    Float obstacleY,
    Float obstacleRadius,
    Float obstacleVelX,
    Float obstacleVelY);

typedef PushParticlesApartNative = Void Function(
    Pointer<Float> particlePos,
    Pointer<Int32> firstCellParticle,
    Pointer<Int32> cellParticleIds,
    Int32 numParticles,
    Int32 pNumX,
    Int32 pNumY,
    Float pInvSpacing,
    Int32 numIters,
    Float particleRadius,
    Float minDist2);

typedef SolveIncompressibilityDart = void Function(
    Pointer<Float> u,
    Pointer<Float> v,
    Pointer<Float> p,
    Pointer<Float> s,
    Pointer<Int32> cellType,
    Pointer<Float> particleDensity,
    int fNumX,
    int fNumY,
    int numIters,
    double h,
    double dt,
    double density,
    double overRelaxation,
    double particleRestDensity,
    bool compensateDrift,
    double circleCenterX,
    double circleCenterY,
    double circleRadius,
    bool isObstacleActive,
    double obstacleX,
    double obstacleY,
    double obstacleRadius,
    double obstacleVelX,
    double obstacleVelY);

typedef PushParticlesApartDart = void Function(
    Pointer<Float> particlePos,
    Pointer<Int32> firstCellParticle,
    Pointer<Int32> cellParticleIds,
    int numParticles,
    int pNumX,
    int pNumY,
    double pInvSpacing,
    int numIters,
    double particleRadius,
    double minDist2);

typedef TransferVelocitiesNative = Void Function(
    Bool toGrid, Float flipRatio,
    Pointer<Float> u, Pointer<Float> v, Pointer<Float> du, Pointer<Float> dv,
    Pointer<Float> prevU, Pointer<Float> prevV,
    Pointer<Int32> cellType,
    Pointer<Float> s,
    Pointer<Float> particlePos,
    Pointer<Float> particleVel,
    Int32 fNumX, Int32 fNumY, Float h, Float invH,
    Int32 numParticles
);

typedef TransferVelocitiesDart = void Function(
    bool toGrid, double flipRatio,
    Pointer<Float> u, Pointer<Float> v, Pointer<Float> du, Pointer<Float> dv,
    Pointer<Float> prevU, Pointer<Float> prevV,
    Pointer<Int32> cellType,
    Pointer<Float> s,
    Pointer<Float> particlePos,
    Pointer<Float> particleVel,
    int fNumX, int fNumY, double h, double invH,
    int numParticles
);

typedef UpdateParticleDensityGridNative = Void Function( // Renamed
    Int32 numParticles, Float particleRestDensity, Float invH,
    Int32 fNumX, Int32 fNumY, Float h,
    Pointer<Float> particlePos,
    // Pointer<Int32> cellType, // Was unused in C++, removed from C++ signature
    Pointer<Float> particleDensityGrid
    // Pointer<Float> particleColor, // REMOVED
    // Bool enableDynamicColoring // REMOVED
);
typedef UpdateParticleDensityGridDart = void Function( // Renamed
    int numParticles, double particleRestDensity, double invH,
    int fNumX, int fNumY, double h,
    Pointer<Float> particlePos,
    // Pointer<Int32> cellType, // Was unused in C++, removed from C++ signature
    Pointer<Float> particleDensityGrid
    // Pointer<Float> particleColor, // REMOVED
    // bool enableDynamicColoring // REMOVED
);

// New typedefs for dynamic color updates
typedef UpdateDynamicParticleColorsNative = Void Function(
    Int32 numParticles, Float particleRestDensity, Float invH,
    Int32 fNumX, Int32 fNumY, Float h,
    Pointer<Float> particlePos, Pointer<Float> particleDensityGrid,
    Pointer<Float> particleColor
);
typedef UpdateDynamicParticleColorsDart = void Function(
    int numParticles, double particleRestDensity, double invH,
    int fNumX, int fNumY, double h,
    Pointer<Float> particlePos, Pointer<Float> particleDensityGrid,
    Pointer<Float> particleColor
);

typedef DiffuseParticleColorsNative = Void Function(
    Pointer<Float> particlePos,
    Pointer<Float> particleColor,
    Pointer<Int32> firstCellParticle,
    Pointer<Int32> cellParticleIds,
    Int32 numParticles,
    Int32 pNumX,
    Int32 pNumY,
    Float pInvSpacing,
    Float particleRadius,
    Bool enableDynamicColoring,
    Float colorDiffusionCoeff);

typedef DiffuseParticleColorsDart = void Function(
    Pointer<Float> particlePos,
    Pointer<Float> particleColor,
    Pointer<Int32> firstCellParticle,
    Pointer<Int32> cellParticleIds,
    int numParticles,
    int pNumX,
    int pNumY,
    double pInvSpacing,
    double particleRadius,
    bool enableDynamicColoring,
    double colorDiffusionCoeff);

typedef HandleCollisionsNative = Void Function(
    Pointer<Float> particlePos, Pointer<Float> particleVel,
    Int32 numParticles, Float particleRadius,
    Bool isObstacleActive, Float obstacleX, Float obstacleY, Float obstacleRadius,
    Float obstacleVelX, Float obstacleVelY,
    Float sceneCircleCenterX, Float sceneCircleCenterY, Float sceneCircleRadius
);
typedef HandleCollisionsDart = void Function(
    Pointer<Float> particlePos, Pointer<Float> particleVel,
    int numParticles, double particleRadius,
    bool isObstacleActive, double obstacleX, double obstacleY, double obstacleRadius,
    double obstacleVelX, double obstacleVelY,
    double sceneCircleCenterX, double sceneCircleCenterY, double sceneCircleRadius
);

class _SimulationFFI {
  static final _SimulationFFI _instance = _SimulationFFI._internal();
  factory _SimulationFFI() => _instance;

  late final DynamicLibrary _dylib;
  late final SolveIncompressibilityDart solveIncompressibility;
  late final PushParticlesApartDart pushParticlesApart;
  late final TransferVelocitiesDart transferVelocities;
  late final UpdateParticleDensityGridDart updateParticleDensityGrid; // Renamed
  late final UpdateDynamicParticleColorsDart updateDynamicParticleColors; // New
  late final HandleCollisionsDart handleCollisions;
  late final DiffuseParticleColorsDart diffuseParticleColors;

  _SimulationFFI._internal() {
    _dylib = _loadLibrary();
    solveIncompressibility = _dylib
        .lookup<NativeFunction<SolveIncompressibilityNative>>(
            'solveIncompressibility_native')
        .asFunction<SolveIncompressibilityDart>(isLeaf: true);
    pushParticlesApart = _dylib
        .lookup<NativeFunction<PushParticlesApartNative>>(
            'pushParticlesApart_native')
        .asFunction<PushParticlesApartDart>(isLeaf: true);
    transferVelocities = _dylib
        .lookup<NativeFunction<TransferVelocitiesNative>>(
            'transferVelocities_native')
        .asFunction<TransferVelocitiesDart>(isLeaf: true);
    updateParticleDensityGrid = _dylib // Renamed
        .lookup<NativeFunction<UpdateParticleDensityGridNative>>( // Renamed
            'updateParticleDensityGrid_native') // Renamed C++ function name
        .asFunction<UpdateParticleDensityGridDart>(isLeaf: true); // Renamed
    updateDynamicParticleColors = _dylib // New
        .lookup<NativeFunction<UpdateDynamicParticleColorsNative>>( // New
            'updateDynamicParticleColors_native') // New C++ function name
        .asFunction<UpdateDynamicParticleColorsDart>(isLeaf: true); // New
    handleCollisions = _dylib
        .lookup<NativeFunction<HandleCollisionsNative>>(
            'handleCollisions_native')
        .asFunction<HandleCollisionsDart>(isLeaf: true);
    diffuseParticleColors = _dylib
        .lookup<NativeFunction<DiffuseParticleColorsNative>>(
            'diffuseParticleColors_native')
        .asFunction<DiffuseParticleColorsDart>(isLeaf: true);
  }

  DynamicLibrary _loadLibrary() {
    const libName = 'simulation_native';
    try {
      if (Platform.isAndroid || Platform.isLinux) return DynamicLibrary.open('lib$libName.so');
      if (Platform.isIOS || Platform.isMacOS) return DynamicLibrary.open('$libName.dylib');
      if (Platform.isWindows) return DynamicLibrary.open('$libName.dll');
      throw UnsupportedError('Unsupported platform for FFI');
    } catch (e) {
      devLog.log("Error loading native library 'lib$libName': $e", name: 'FlipFluidSim.FFIError');
      rethrow;
    }
  }
}

class Vector2 {
  final double dx, dy;
  Vector2(this.dx, this.dy);

  Vector2 operator +(Vector2 other) => Vector2(dx + other.dx, dy + other.dy);
  Vector2 operator -(Vector2 other) => Vector2(dx - other.dx, dy + other.dy);
  Vector2 operator *(double scalar) => Vector2(dx * scalar, dy * scalar);
  double dot(Vector2 other) => dx * other.dx + dy * other.dy;
  double get length => math.sqrt(dx * dx + dy * dy);
  double get length2 => dx * dx + dy * dy;
  Vector2 normalized() =>
      length > 1e-8 ? this * (1.0 / length) : Vector2(0.0, 0.0);
  Vector2 projectOnto(Vector2 other) {
    final double otherLength2 = other.length2;
    if (otherLength2 < 1e-8) return Vector2(0.0, 0.0);
    final double dotProduct = dot(other);
    return other * (dotProduct / otherLength2);
  }
}

class FlipFluidSimulation {
  static const int U_FIELD = 0;
  static const int V_FIELD = 1;
  static const int FLUID_CELL = 0;
  static const int AIR_CELL = 1;
  static const int SOLID_CELL = 2;

  final double density;
  final double worldWidth;
  final double worldHeight;
  final int fNumX;
  late final int fNumY;
  late final int fNumCells;
  late final double h;
  late final double fInvSpacing;

  late final Float32List u, v, du, dv, prevU, prevV, p, s, cellColor;
  late final Int32List cellType;

  final int maxParticles;
  int numParticles = 0;
  final Float32List particlePos, particleVel, particleColor;
  late final Float32List particleDensity;
  late final Int32List numCellParticles, firstCellParticle;
  final Int32List cellParticleIds;

  double particleRestDensity = 0.0;
  final double particleRadius, pInvSpacing;
  final int pNumX, pNumY;
  late final int pNumCells;

  double obstacleX = 0.0, obstacleY = 0.0;
  double obstacleVelX = 0.0, obstacleVelY = 0.0;
  double obstacleRadius;
  bool isObstacleActive = false;

  bool _lastLoggedObstActiveForCollisions = false;
  double _lastLoggedObstXForCollisions = 0.0;
  double _lastLoggedObstYForCollisions = 0.0;
  double _lastLoggedObstRForCollisions = 0.0;
  double _lastLoggedObstVelXForCollisions = 0.0;
  double _lastLoggedObstVelYForCollisions = 0.0;

  bool _lastLoggedObstActiveForSolveIncompressibility = false;
  double _lastLoggedObstXForSolveIncompressibility = 0.0;
  double _lastLoggedObstYForSolveIncompressibility = 0.0;
  double _lastLoggedObstRForSolveIncompressibility = 0.0;
  double _lastLoggedObstVelXForSolveIncompressibility = 0.0;
  double _lastLoggedObstVelYForSolveIncompressibility = 0.0;

  late final double sceneCircleCenterX;
  late final double sceneCircleCenterY;
  late final double sceneCircleRadius;
  final bool enableDynamicColoring;

  final _ffi = _SimulationFFI();

  late final Pointer<Float> _nativeUPtr;
  late final Pointer<Float> _nativeVPtr;
  late final Pointer<Float> _nativePPtr;
  late final Pointer<Float> _nativeSPtr;
  late final Pointer<Int32> _nativeCellTypePtr;
  late final Pointer<Float> _nativeParticleDensityPtr;
  late final Pointer<Float> _nativeParticlePosPtr;
  late final Pointer<Int32> _nativeFirstCellParticlePtr;
  late final Pointer<Int32> _nativeCellParticleIdsPtr;
  late final Pointer<Float> _nativeDuPtr;
  late final Pointer<Float> _nativeDvPtr;
  late final Pointer<Float> _nativePrevUPtr;
  late final Pointer<Float> _nativePrevVPtr;
  late final Pointer<Float> _nativeParticleVelPtr;
  late final Pointer<Float> _nativeParticleColorPtr;

  FlipFluidSimulation({
    required this.density,
    required double width,
    required double height,
    required int cellsWide,
    required this.particleRadius,
    required this.maxParticles,
    required this.obstacleRadius,
    required this.enableDynamicColoring,
  })  : worldWidth = width,
        worldHeight = height,
        fNumX = cellsWide,
        pInvSpacing = 1.0 / (2.2 * particleRadius),
        pNumX = (width * (1.0 / (2.2 * particleRadius))).floor() + 1,
        pNumY = (height * (1.0 / (2.2 * particleRadius))).floor() + 1,
        particlePos = Float32List(2 * maxParticles),
        particleVel = Float32List(2 * maxParticles),
        particleColor = Float32List(4 * maxParticles), // Changed for RGBA
        cellParticleIds = Int32List(maxParticles) {
    h = worldWidth / fNumX.toDouble();
    fNumY = (worldHeight / h).floor() + 1;
    fInvSpacing = 1.0 / h;
    fNumCells = fNumX * fNumY;

    u = Float32List(fNumCells);
    v = Float32List(fNumCells);
    du = Float32List(fNumCells);
    dv = Float32List(fNumCells);
    prevU = Float32List(fNumCells);
    prevV = Float32List(fNumCells);
    p = Float32List(fNumCells);
    s = Float32List(fNumCells);
    cellColor = Float32List(3 * fNumCells);
    cellType = Int32List(fNumCells);
    particleDensity = Float32List(fNumCells);

    pNumCells = pNumX * pNumY;

    for (int i = 0; i < maxParticles; ++i) {
      particleColor[4 * i] = 0.0;         // R
      particleColor[4 * i + 1] = 0.0;     // G
      particleColor[4 * i + 2] = 1.0;     // B
      particleColor[4 * i + 3] = 1.0;     // A (opaque)
    }
    
    numCellParticles = Int32List(this.pNumCells);
    firstCellParticle = Int32List(this.pNumCells + 1);

    final double simDomainWidth = fNumX.toDouble() * h;
    final double simDomainHeight = fNumY.toDouble() * h;
    sceneCircleCenterX = simDomainWidth / 2.0;
    sceneCircleCenterY = simDomainHeight / 2.0;
    sceneCircleRadius = 0.95 * 0.5 * math.min(simDomainWidth, simDomainHeight);

    try {
      _nativeUPtr = ffiMemory.calloc<Float>(u.length);
      _nativeVPtr = ffiMemory.calloc<Float>(v.length);
      _nativePPtr = ffiMemory.calloc<Float>(p.length);
      _nativeSPtr = ffiMemory.calloc<Float>(s.length);
      _nativeCellTypePtr = ffiMemory.calloc<Int32>(cellType.length);
      _nativeParticleDensityPtr = ffiMemory.calloc<Float>(particleDensity.length);
      _nativeParticlePosPtr = ffiMemory.calloc<Float>(particlePos.length);
      _nativeFirstCellParticlePtr = ffiMemory.calloc<Int32>(firstCellParticle.length);
      _nativeCellParticleIdsPtr = ffiMemory.calloc<Int32>(cellParticleIds.length);
      _nativeDuPtr = ffiMemory.calloc<Float>(du.length);
      _nativeDvPtr = ffiMemory.calloc<Float>(dv.length);
      _nativePrevUPtr = ffiMemory.calloc<Float>(prevU.length);
      _nativePrevVPtr = ffiMemory.calloc<Float>(prevV.length);
      _nativeParticleVelPtr = ffiMemory.calloc<Float>(particleVel.length);
      _nativeParticleColorPtr = ffiMemory.calloc<Float>(particleColor.length);

      if (_nativeUPtr == nullptr || _nativeVPtr == nullptr || _nativePPtr == nullptr ||
          _nativeSPtr == nullptr || _nativeCellTypePtr == nullptr ||
          _nativeParticleDensityPtr == nullptr || _nativeParticlePosPtr == nullptr ||
          _nativeFirstCellParticlePtr == nullptr || _nativeCellParticleIdsPtr == nullptr ||
          _nativeDuPtr == nullptr || _nativeDvPtr == nullptr || _nativePrevUPtr == nullptr ||
          _nativePrevVPtr == nullptr || _nativeParticleVelPtr == nullptr ||
          _nativeParticleColorPtr == nullptr ) {
       throw Exception("Failed to allocate persistent native FFI buffers.");
      }
    } catch (e) {
      devLog.log("FATAL ERROR during native buffer allocation: $e", name: 'FlipFluidSim.Error');
      rethrow;
    }
    initializeGrid();
  }

  void initializeGrid() {
    final int n = fNumY;
    final double rSq = sceneCircleRadius * sceneCircleRadius;

    for (int i = 0; i < fNumX; i++) {
      for (int j = 0; j < fNumY; j++) {
        int idx = i * n + j;
        double cellRealX = (i + 0.5) * h;
        double cellRealY = (j + 0.5) * h;

        double dx = cellRealX - sceneCircleCenterX;
        double dy = cellRealY - sceneCircleCenterY;
        double distSqToCenter = dx * dx + dy * dy;

        s[idx] = (distSqToCenter > rSq) ? 0.0 : 1.0;
        u[idx] = v[idx] = du[idx] = dv[idx] = prevU[idx] = prevV[idx] = p[idx] = 0.0;
      }
    }
  }

  void setObstacle(double x, double y, bool reset, double dt) {
    devLog.log(
        '[Sim.setObstacle] INPUT: x=$x, y=$y, reset=$reset, dt=$dt. Current obstacle: oldX=$obstacleX, oldY=$obstacleY, oldVelX=$obstacleVelX, oldVelY=$obstacleVelY, active=$isObstacleActive', name: 'FlipFluidSim');

    final double newObstacleVelX = reset ? 0.0 : (x - obstacleX) / dt;
    final double newObstacleVelY = reset ? 0.0 : (y - obstacleY) / dt;
    obstacleX = x;
    obstacleY = y;
    obstacleVelX = newObstacleVelX;
    obstacleVelY = newObstacleVelY;

    devLog.log(
        '[Sim.setObstacle] UPDATED: obstacleX=$obstacleX, obstacleY=$obstacleY, obstacleVelX=$obstacleVelX, obstacleVelY=$obstacleVelY', name: 'FlipFluidSim');

    final int n = fNumY;
    final double mainRSq = sceneCircleRadius * sceneCircleRadius;
    final double draggableRSq = this.obstacleRadius * this.obstacleRadius;

    for (int i = 0; i < fNumX; i++) {
      for (int j = 0; j < fNumY; j++) {
        int idx = i * n + j;
        double cellRealX = (i + 0.5) * h;
        double cellRealY = (j + 0.5) * h;

        double dxMain = cellRealX - sceneCircleCenterX;
        double dyMain = cellRealY - sceneCircleCenterY;
        double distSqToMainCenter = dxMain * dxMain + dyMain * dyMain;
        
        bool isStaticWall = distSqToMainCenter > mainRSq;

        if (isStaticWall) {
          s[idx] = 0.0;
        } else {
          s[idx] = 1.0;
          if (this.isObstacleActive) {
            double dxDrag = cellRealX - obstacleX;
            double dyDrag = cellRealY - obstacleY;
            double distSqToDraggableCenter = dxDrag * dxDrag + dyDrag * dyDrag;

            if (i > fNumX / 2 - 2 && i < fNumX / 2 + 2 && j > fNumY / 2 - 2 && j < fNumY / 2 + 2 && (idx % 10 == 0)) {
                 devLog.log('[Sim.setObstacle Loop] cell($i,$j) real($cellRealX,$cellRealY) vs obst($obstacleX,$obstacleY). distSq=$distSqToDraggableCenter, rSqLimit=$draggableRSq. s[$idx] before=${s[idx]}', name: 'FlipFluidSim.Loop');
            }

            if (distSqToDraggableCenter < draggableRSq) {
              if (idx % 10 == 0) {
                devLog.log('[Sim.setObstacle Loop] Cell ($i,$j) INSIDE obstacle. Setting s[$idx]=0.0. Applying vel: $obstacleVelX, $obstacleVelY', name: 'FlipFluidSim.Loop');
              }
              s[idx] = 0.0;
              if (i < fNumX) u[idx] = obstacleVelX;
              if (i + 1 < fNumX) u[(i + 1) * n + j] = obstacleVelX;
              if (j < fNumY) v[idx] = obstacleVelY;
              if (j + 1 < fNumY) v[i * n + (j + 1)] = obstacleVelY;
            }
          }
        }
      }
    }
  }

  int _countParticlesForHeight(double testFillHeightFromBottom, int targetMaxCount) {
    final dx = 2 * particleRadius;
    final dy = math.sqrt(3.0) / 2 * dx;
    if (dx <= 0 || dy <= 0) return 0;

    final double actualCircleBottomEdgeY_count = sceneCircleCenterY - sceneCircleRadius;
    final double waterSurfaceLineY_count = actualCircleBottomEdgeY_count + testFillHeightFromBottom;

    final double iterationStartX = sceneCircleCenterX - sceneCircleRadius;
    final double iterationStartY = sceneCircleCenterY - sceneCircleRadius;
    final int numPotentialRows = (2 * sceneCircleRadius / dy).ceil() + 2;
    final int numPotentialCols = (2 * sceneCircleRadius / dx).ceil() + 2;

    int currentSimulatedParticles = 0;

    for (int j = 0; j < numPotentialRows; j++) {
      final double yj = iterationStartY + j * dy;
      if (yj - particleRadius > sceneCircleCenterY + sceneCircleRadius && j > 0) break;

      for (int i = 0; i < numPotentialCols; i++) {
        if (currentSimulatedParticles >= targetMaxCount) return currentSimulatedParticles;

        final double xi = iterationStartX + i * dx + (j.isOdd ? particleRadius : 0);
        if (xi - particleRadius > sceneCircleCenterX + sceneCircleRadius && i > 0) break;
        if (xi + particleRadius < sceneCircleCenterX - sceneCircleRadius) continue;

        bool isInWaterRegion = yj < waterSurfaceLineY_count;
        double dxCircle = xi - sceneCircleCenterX;
        double dyCircle = yj - sceneCircleCenterY;
        double distSqToCenter = dxCircle * dxCircle + dyCircle * dyCircle;
        bool isInsideCircle = distSqToCenter < math.pow(sceneCircleRadius - particleRadius, 2).toDouble();

        if (isInWaterRegion && isInsideCircle) {
          currentSimulatedParticles++;
        }
      }
    }
    return currentSimulatedParticles;
  }

  void fillCircleBottom(double initialGuessFillHeightFromBottom, {int? maxCount}) {
    final int targetParticleCount = maxCount ?? this.maxParticles;
    if (targetParticleCount == 0) return;

    final dx = 2 * particleRadius;
    final dy = math.sqrt(3.0) / 2 * dx;

    if (dx <= 0 || dy <= 0) {
      devLog.log("Error: particleRadius ($particleRadius) results in non-positive dx ($dx) or dy ($dy) for particle placement.", name: 'FlipFluidSim.Error');
      return;
    }

    double determinedFillHeight = 0;
    int iterationSafetyNet = 0;
    const int maxIterations = 100;
    double heightStep = particleRadius;

    double currentTestHeight = heightStep;
    while(iterationSafetyNet < maxIterations) {
      int potentialParticles = _countParticlesForHeight(currentTestHeight, targetParticleCount);
      
      if (potentialParticles >= targetParticleCount || currentTestHeight >= 2 * sceneCircleRadius) {
        determinedFillHeight = currentTestHeight;
        break;
      }
      currentTestHeight += heightStep;
      iterationSafetyNet++;
      if (iterationSafetyNet == maxIterations) {
         devLog.log("Warning: Max iterations reached in fillCircleBottom height determination. Using currentTestHeight: $currentTestHeight", name: 'FlipFluidSim.Warning');
         determinedFillHeight = currentTestHeight;
      }
    }
    if (determinedFillHeight == 0 && initialGuessFillHeightFromBottom > 0) {
        devLog.log("Warning: Dynamic height determination failed, using initial guess: $initialGuessFillHeightFromBottom", name: 'FlipFluidSim.Warning');
        determinedFillHeight = initialGuessFillHeightFromBottom;
    } else if (determinedFillHeight == 0) {
        devLog.log("Error: Could not determine a valid fill height. Defaulting to a small portion.", name: 'FlipFluidSim.Error');
        determinedFillHeight = sceneCircleRadius * 0.2;
    }

    final double actualCircleBottomEdgeY = sceneCircleCenterY - sceneCircleRadius;
    final double waterSurfaceLineY = actualCircleBottomEdgeY + determinedFillHeight;

    final double iterationStartX = sceneCircleCenterX - sceneCircleRadius;
    final double iterationStartY = sceneCircleCenterY - sceneCircleRadius;
    final int numPotentialRows = (2 * sceneCircleRadius / dy).ceil() + 2;
    final int numPotentialCols = (2 * sceneCircleRadius / dx).ceil() + 2;

    for (int j = 0; j < numPotentialRows; j++) {
      final double yj = iterationStartY + j * dy;
      if (yj - particleRadius > sceneCircleCenterY + sceneCircleRadius && j > 0) break;

      for (int i = 0; i < numPotentialCols; i++) {
        if (numParticles >= targetParticleCount || numParticles >= this.maxParticles) return;

        final double xi = iterationStartX + i * dx + (j.isOdd ? particleRadius : 0);
        if (xi - particleRadius > sceneCircleCenterX + sceneCircleRadius && i > 0) break;
        if (xi + particleRadius < sceneCircleCenterX - sceneCircleRadius) continue;

        bool isInWaterRegion = yj < waterSurfaceLineY;
        double dxCircle = xi - sceneCircleCenterX;
        double dyCircle = yj - sceneCircleCenterY;
        double distSqToCenter = dxCircle * dxCircle + dyCircle * dyCircle;
        bool isInsideCircle = distSqToCenter < math.pow(sceneCircleRadius - particleRadius, 2).toDouble();

        if (isInWaterRegion && isInsideCircle) {
          particlePos[2 * numParticles] = xi;
          particlePos[2 * numParticles + 1] = yj;
          particleVel[2 * numParticles] = 0.0;
          particleVel[2 * numParticles + 1] = 0.0;
          numParticles++;
        }
      }
    }
     devLog.log("fillCircleBottom completed. Target: $targetParticleCount, Actual: $numParticles, Determined Height: $determinedFillHeight", name: 'FlipFluidSim');
  }

  double clamp(double x, double minVal, double maxVal) {
    return math.min(math.max(x, minVal), maxVal);
  }

  void integrateParticles(double dt, double gravityX, double gravityY) {
    for (int i = 0; i < numParticles; i++) {
      final int b = 2 * i;
      particleVel[b] += dt * gravityX; 
      particleVel[b + 1] += dt * gravityY;
      particlePos[b] += particleVel[b] * dt;
      particlePos[b + 1] += particleVel[b + 1] * dt;
    }
  }

  void _setSciColor(int cellNr, double val, double minVal, double maxVal) {
    val = math.min(math.max(val, minVal), maxVal - 0.0001);
    double d = maxVal - minVal;
    val = (d == 0.0) ? 0.5 : (val - minVal) / d;
    double m = 0.25;
    int num = (val / m).floor();
    double sVal = (val - num * m) / m;
    double r=0.5, g=0.5, b=0.5;
    switch (num) {
      case 0: r=0.0; g=sVal; b=1.0; break;
      case 1: r=0.0; g=1.0; b=1.0-sVal; break;
      case 2: r=sVal; g=1.0; b=0.0; break;
      case 3: r=1.0; g=1.0-sVal; b=0.0; break;
    }
    final int ci = 3*cellNr;
    if(ci+2 < cellColor.length){ cellColor[ci]=r; cellColor[ci+1]=g; cellColor[ci+2]=b; }
  }

  void updateCellColors() {
    cellColor.fillRange(0, cellColor.length, 0.0);
    for (int i = 0; i < fNumCells; i++) {
      final int ci = 3 * i;
      if (ci + 2 >= cellColor.length) continue;
      if (cellType[i] == SOLID_CELL) {
        cellColor[ci]=0.5; cellColor[ci+1]=0.5; cellColor[ci+2]=0.5;
      } else if (cellType[i] == FLUID_CELL) {
        double d_val = particleDensity[i];
        if(particleRestDensity>0.0) d_val/=particleRestDensity;
        _setSciColor(i, d_val, 0.0, 2.0);
      } else { 
        cellColor[ci]=0.0; cellColor[ci+1]=0.0; cellColor[ci+2]=0.0;
      }
    }
  }

  void _stepOnce(double dt, double gX, double gY, double flipR, int pIters, int partIters, double oRelax, bool compDrift, bool sepParts) {
    integrateParticles(dt, gX, gY);

    if (sepParts) {
      numCellParticles.fillRange(0, pNumCells, 0);
      for (int i = 0; i < numParticles; i++) {
        final double x = particlePos[2 * i], y = particlePos[2 * i + 1];
        final int xi = clamp((x * pInvSpacing).floorToDouble(), 0, pNumX - 1).toInt();
        final int yi = clamp((y * pInvSpacing).floorToDouble(), 0, pNumY - 1).toInt();
        final int cellIdx = xi * pNumY + yi;
        if (cellIdx >= 0 && cellIdx < pNumCells) numCellParticles[cellIdx]++;
      }
      int sum = 0;
      for (int c = 0; c < pNumCells; c++) {
        firstCellParticle[c] = sum;
        sum += numCellParticles[c];
      }
      if (firstCellParticle.length > pNumCells) {
        firstCellParticle[pNumCells] = sum;
      } else {
        devLog.log("Error: firstCellParticle array is too small for pushParticlesApart data prep!", name: 'FlipFluidSim.Error');
      }

      var currentCellIndices = Int32List(pNumCells);
      for(int c=0; c < pNumCells; ++c) {
          currentCellIndices[c] = firstCellParticle[c];
      }

      for (int i = 0; i < numParticles; i++) {
        final double x = particlePos[2 * i], y = particlePos[2 * i + 1];
        final int xi = clamp((x * pInvSpacing).floorToDouble(), 0, pNumX - 1).toInt();
        final int yi = clamp((y * pInvSpacing).floorToDouble(), 0, pNumY - 1).toInt();
        final int cellIdx = xi * pNumY + yi;
        if (cellIdx >= 0 && cellIdx < pNumCells) {
          int insertPos = currentCellIndices[cellIdx];
          if (insertPos >= 0 && insertPos < cellParticleIds.length) {
            cellParticleIds[insertPos] = i;
            currentCellIndices[cellIdx]++;
          } else {
            devLog.log("Error: insertPos $insertPos out of bounds for cellParticleIds (len: ${cellParticleIds.length}) in pushParticlesApart data prep.", name: 'FlipFluidSim.Error');
          }
        }
      }
      final double minDist = 2.0 * particleRadius;
      final double minDist2 = minDist * minDist;

      try {
        _nativeParticlePosPtr.asTypedList(particlePos.length).setAll(0, particlePos);
        _nativeFirstCellParticlePtr.asTypedList(firstCellParticle.length).setAll(0, firstCellParticle);
        _nativeCellParticleIdsPtr.asTypedList(cellParticleIds.length).setAll(0, cellParticleIds);

        _ffi.pushParticlesApart(
            _nativeParticlePosPtr, 
            _nativeFirstCellParticlePtr, 
            _nativeCellParticleIdsPtr,
            numParticles, pNumX, pNumY, pInvSpacing, partIters, particleRadius, minDist2
        );

        particlePos.setAll(0, _nativeParticlePosPtr.asTypedList(particlePos.length));
      } catch (e) { devLog.log("Error during FFI call/copy for pushParticlesApart: $e", name: 'FlipFluidSim.FFIError'); }
    }

    if (sepParts && this.enableDynamicColoring) {
      try {
        _nativeParticleColorPtr.asTypedList(particleColor.length).setAll(0, particleColor);
        
        double colorDiffusionCoefficient = 0.001; // From JS

        _ffi.diffuseParticleColors(
            _nativeParticlePosPtr, // Assumed to be up-to-date in native memory from pushParticlesApart
            _nativeParticleColorPtr,
            _nativeFirstCellParticlePtr, // Assumed to be up-to-date from pushParticlesApart
            _nativeCellParticleIdsPtr,   // Assumed to be up-to-date from pushParticlesApart
            numParticles,
            pNumX, pNumY,
            pInvSpacing,
            particleRadius,
            this.enableDynamicColoring,
            colorDiffusionCoefficient
        );
        
        particleColor.setAll(0, _nativeParticleColorPtr.asTypedList(particleColor.length));

      } catch (e) { devLog.log("Error during FFI call/copy for diffuseParticleColors: $e", name: 'FlipFluidSim.FFIError'); }
    }

    try {
      _nativeParticlePosPtr.asTypedList(particlePos.length).setAll(0, particlePos);
      _nativeParticleVelPtr.asTypedList(particleVel.length).setAll(0, particleVel);

      bool obstDataChangedForCollisions = isObstacleActive != _lastLoggedObstActiveForCollisions ||
                                          obstacleX != _lastLoggedObstXForCollisions ||
                                          obstacleY != _lastLoggedObstYForCollisions ||
                                          obstacleRadius != _lastLoggedObstRForCollisions ||
                                          obstacleVelX != _lastLoggedObstVelXForCollisions ||
                                          obstacleVelY != _lastLoggedObstVelYForCollisions;

      if (obstDataChangedForCollisions) {
        devLog.log(
            '[Sim._stepOnce Pre-FFI.handleCollisions] obstActive=$isObstacleActive, obstX=$obstacleX, obstY=$obstacleY, obstR=$obstacleRadius, obstVelX=$obstacleVelX, obstVelY=$obstacleVelY', name: 'FlipFluidSim');
        _lastLoggedObstActiveForCollisions = isObstacleActive;
        _lastLoggedObstXForCollisions = obstacleX;
        _lastLoggedObstYForCollisions = obstacleY;
        _lastLoggedObstRForCollisions = obstacleRadius;
        _lastLoggedObstVelXForCollisions = obstacleVelX;
        _lastLoggedObstVelYForCollisions = obstacleVelY;
      }
      _ffi.handleCollisions(
          _nativeParticlePosPtr, _nativeParticleVelPtr,
          numParticles, particleRadius,
          isObstacleActive, obstacleX, obstacleY, obstacleRadius,
          obstacleVelX, obstacleVelY,
          sceneCircleCenterX, sceneCircleCenterY, sceneCircleRadius
      );

      particlePos.setAll(0, _nativeParticlePosPtr.asTypedList(particlePos.length));
      particleVel.setAll(0, _nativeParticleVelPtr.asTypedList(particleVel.length));
    } catch (e) { devLog.log("Error during FFI call/copy for handleCollisions: $e", name: 'FlipFluidSim.FFIError'); }

    try {
      _nativeUPtr.asTypedList(u.length).setAll(0, u);
      _nativeVPtr.asTypedList(v.length).setAll(0, v);
      _nativeSPtr.asTypedList(s.length).setAll(0, s);
      _nativeParticlePosPtr.asTypedList(particlePos.length).setAll(0, particlePos);
      _nativeParticleVelPtr.asTypedList(particleVel.length).setAll(0, particleVel);

      _ffi.transferVelocities(
          true, flipR,
          _nativeUPtr, _nativeVPtr, _nativeDuPtr, _nativeDvPtr,
          _nativePrevUPtr, _nativePrevVPtr,
          _nativeCellTypePtr,
          _nativeSPtr,
          _nativeParticlePosPtr,
          _nativeParticleVelPtr,
          fNumX, fNumY, h, fInvSpacing,
          numParticles
      );

      u.setAll(0, _nativeUPtr.asTypedList(u.length));
      v.setAll(0, _nativeVPtr.asTypedList(v.length));
      du.setAll(0, _nativeDuPtr.asTypedList(du.length));
      dv.setAll(0, _nativeDvPtr.asTypedList(dv.length));
      prevU.setAll(0, _nativePrevUPtr.asTypedList(prevU.length));
      prevV.setAll(0, _nativePrevVPtr.asTypedList(prevV.length));
      cellType.setAll(0, _nativeCellTypePtr.asTypedList(cellType.length));

    } catch (e) { devLog.log("Error during FFI call/copy for transferVelocities(toGrid=true): $e", name: 'FlipFluidSim.FFIError'); }

    try {
      // Update particle density grid (always done)
      _nativeParticlePosPtr.asTypedList(particlePos.length).setAll(0, particlePos);
      // _nativeCellTypePtr.asTypedList(cellType.length).setAll(0, cellType); // Not needed for density grid update

      _ffi.updateParticleDensityGrid( // Renamed
          numParticles, particleRestDensity, fInvSpacing,
          fNumX, fNumY, h,
          _nativeParticlePosPtr,
          // _nativeCellTypePtr, // Not needed
          _nativeParticleDensityPtr
          // _nativeParticleColorPtr, // Removed
          // this.enableDynamicColoring // Removed
      );
      particleDensity.setAll(0, _nativeParticleDensityPtr.asTypedList(particleDensity.length));

      // Conditionally update particle colors
      if (this.enableDynamicColoring) {
        _nativeParticleColorPtr.asTypedList(particleColor.length).setAll(0, particleColor);
        // particlePos and particleDensityGrid are already in native memory from the previous call or earlier steps.
        // No need to copy particlePos again if it hasn't changed.
        // particleDensityGrid was just updated in native memory.

        _ffi.updateDynamicParticleColors(
            numParticles, particleRestDensity, fInvSpacing,
            fNumX, fNumY, h,
            _nativeParticlePosPtr, // Assumed up-to-date
            _nativeParticleDensityPtr, // Is up-to-date
            _nativeParticleColorPtr
        );
        particleColor.setAll(0, _nativeParticleColorPtr.asTypedList(particleColor.length));
      }

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

    } catch (e) { devLog.log("Error during FFI call/copy for updateParticleProperties: $e", name: 'FlipFluidSim.FFIError'); }

    try {
      p.fillRange(0, p.length, 0.0); 

      prevU.setAll(0, u);
      prevV.setAll(0, v);

      _nativeUPtr.asTypedList(u.length).setAll(0, u);
      _nativeVPtr.asTypedList(v.length).setAll(0, v);
      _nativePPtr.asTypedList(p.length).setAll(0, p);
      _nativeSPtr.asTypedList(s.length).setAll(0, s);
      _nativeCellTypePtr.asTypedList(cellType.length).setAll(0, cellType);
      _nativeParticleDensityPtr.asTypedList(particleDensity.length).setAll(0, particleDensity);
      
      bool obstDataChangedForSolveIncompressibility = isObstacleActive != _lastLoggedObstActiveForSolveIncompressibility ||
                                                      obstacleX != _lastLoggedObstXForSolveIncompressibility ||
                                                      obstacleY != _lastLoggedObstYForSolveIncompressibility ||
                                                      obstacleRadius != _lastLoggedObstRForSolveIncompressibility ||
                                                      obstacleVelX != _lastLoggedObstVelXForSolveIncompressibility ||
                                                      obstacleVelY != _lastLoggedObstVelYForSolveIncompressibility;

      if (obstDataChangedForSolveIncompressibility) {
        devLog.log(
            '[Sim._stepOnce Pre-FFI.solveIncompressibility] obstActive=$isObstacleActive, obstX=$obstacleX, obstY=$obstacleY, obstR=$obstacleRadius, obstVelX=$obstacleVelX, obstVelY=$obstacleVelY', name: 'FlipFluidSim');
        _lastLoggedObstActiveForSolveIncompressibility = isObstacleActive;
        _lastLoggedObstXForSolveIncompressibility = obstacleX;
        _lastLoggedObstYForSolveIncompressibility = obstacleY;
        _lastLoggedObstRForSolveIncompressibility = obstacleRadius;
        _lastLoggedObstVelXForSolveIncompressibility = obstacleVelX;
        _lastLoggedObstVelYForSolveIncompressibility = obstacleVelY;
      }
      _ffi.solveIncompressibility(
          _nativeUPtr, _nativeVPtr, _nativePPtr, _nativeSPtr, _nativeCellTypePtr,
          _nativeParticleDensityPtr, fNumX, fNumY, pIters, h, dt, density, oRelax,
          particleRestDensity, compDrift, sceneCircleCenterX, sceneCircleCenterY,
          sceneCircleRadius, this.isObstacleActive, this.obstacleX, this.obstacleY,
          this.obstacleRadius, this.obstacleVelX, this.obstacleVelY);

       u.setAll(0, _nativeUPtr.asTypedList(u.length));
       v.setAll(0, _nativeVPtr.asTypedList(v.length));
       p.setAll(0, _nativePPtr.asTypedList(p.length));

    } catch (e) { devLog.log("Error during FFI call/copy for solveIncompressibility: $e", name: 'FlipFluidSim.FFIError'); }

    try {
      _nativeUPtr.asTypedList(u.length).setAll(0, u);
      _nativeVPtr.asTypedList(v.length).setAll(0, v);
      _nativePrevUPtr.asTypedList(prevU.length).setAll(0, prevU);
      _nativePrevVPtr.asTypedList(prevV.length).setAll(0, prevV);
      _nativeCellTypePtr.asTypedList(cellType.length).setAll(0, cellType);
      _nativeSPtr.asTypedList(s.length).setAll(0, s);
      _nativeParticlePosPtr.asTypedList(particlePos.length).setAll(0, particlePos);
      _nativeParticleVelPtr.asTypedList(particleVel.length).setAll(0, particleVel);

      _ffi.transferVelocities(
          false, flipR,
          _nativeUPtr, _nativeVPtr, _nativeDuPtr, _nativeDvPtr,
          _nativePrevUPtr, _nativePrevVPtr,
          _nativeCellTypePtr,
          _nativeSPtr,
          _nativeParticlePosPtr,
          _nativeParticleVelPtr,
          fNumX, fNumY, h, fInvSpacing,
          numParticles
      );

      particleVel.setAll(0, _nativeParticleVelPtr.asTypedList(particleVel.length));

    } catch (e) { devLog.log("Error during FFI call/copy for transferVelocities(toGrid=false): $e", name: 'FlipFluidSim.FFIError'); }
  }

  void simulate({
    required double dt, required double gravityX, required double gravityY,
    required double flipRatio, required int numPressureIters, required int numParticleIters,
    required double overRelaxation, required bool compensateDrift, required bool separateParticles,
  }) {
    _stepOnce(dt, gravityX, gravityY, flipRatio, numPressureIters, numParticleIters,
              overRelaxation, compensateDrift, separateParticles);
    updateCellColors();
  }

  void dispose() {
    devLog.log("Disposing FlipFluidSimulation...", name: 'FlipFluidSim');
    try {
      ffiMemory.calloc.free(_nativeUPtr); ffiMemory.calloc.free(_nativeVPtr); ffiMemory.calloc.free(_nativePPtr);
      ffiMemory.calloc.free(_nativeSPtr); ffiMemory.calloc.free(_nativeCellTypePtr);
      ffiMemory.calloc.free(_nativeParticleDensityPtr); ffiMemory.calloc.free(_nativeParticlePosPtr);
      ffiMemory.calloc.free(_nativeFirstCellParticlePtr); ffiMemory.calloc.free(_nativeCellParticleIdsPtr);
      ffiMemory.calloc.free(_nativeDuPtr); ffiMemory.calloc.free(_nativeDvPtr); ffiMemory.calloc.free(_nativePrevUPtr);
      ffiMemory.calloc.free(_nativePrevVPtr); ffiMemory.calloc.free(_nativeParticleVelPtr);
      ffiMemory.calloc.free(_nativeParticleColorPtr);
     devLog.log("Native buffers freed.", name: 'FlipFluidSim');
    } catch (e) { devLog.log("Error freeing native buffers: $e", name: 'FlipFluidSim.Error'); }
  }
}