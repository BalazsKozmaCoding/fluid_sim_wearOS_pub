**1. Brief Technical Analysis**

- **Simulation Performance:**  
  Porting the FLIP loop involves tight, nested loops over particles and grid cells (e.g. `integrateParticles`, velocity transfers, pressure solves) that execute every frame . Dart’s JIT/AOT can handle these, but you must avoid per-frame allocations—use pre-allocated `Float32List`/`Int32List` buffers and manual indexing. If pure-Dart becomes a bottleneck, consider moving inner kernels to native via FFI (e.g. C/C++ or Rust), but start with Dart Typed Lists for rapid iteration.

- **Rendering Performance:**  
  Rendering tens of thousands of particles each frame can be costly. For an initial version, use Flutter’s `CustomPainter.drawPoints` or batched `Canvas.drawVertices` in a `CustomPaint` (leveraging `Float32List` for vertex data). If you hit frame-rate limits, profile and then explore SkSL shaders via `FragmentProgram` for GPU‐accelerated point drawing.

- **Touch & Sensor Input:**  
  Mapping touch (pan) events and accelerometer data to the simulation domain requires coordinate transforms (screen → simulation space) and smoothing of raw sensor readings. Use Flutter’s `GestureDetector` for obstacle dragging and the `sensors` package (or platform channels) for accelerometer gravity vectors.

- **Cross-Platform Adaptation:**  
  Wear OS has a smaller, round screen and lower compute budget. Architect input and rendering behind interfaces (e.g. `TouchInputHandler`, `SensorService`) so you can swap in Wear OS–specific implementations (digital crown, reduced resolution, lower particle count) without touching the core simulation.

---

**2. High-Level Project Plan**

| Phase                                | Key Tasks                                                                                         |
|--------------------------------------|---------------------------------------------------------------------------------------------------|
| **1. Mobile Core Sim**               | • Port data structures (`Float32List`, `Int32List`) and constants<br>• Implement `integrateParticles`, transfer & solve kernels<br>• Unit-test against JS demo outputs |
| **2. Mobile Render**                 | • Create `ParticleRenderer` (CustomPainter)<br>• Hook simulation buffers to Flutter canvas<br>• Add optional grid/velocity field overlay |
| **3. Mobile Interaction**            | • Build `SensorService` for gravity vector<br>• Build `TouchInputHandler` for obstacle drag<br>• Wire Start/Stop/Reset controls |
| **4. Wear OS Adapt**                 | • Abstract UI to allow round/square layouts<br>• Swap input handlers (crown, touch)<br>• Profile and reduce resolution/particle count |
| **5. Polish & Performance Tuning**   | • Profile hotspots, consider FFI for hot loops<br>• Add color mapping, settings UI, sliders<br>• Integration tests, documentation, CI |

---

**3. Proposed File Structure**

```
lib/
├── common/
│   └── models.dart
├── simulation/
│   └── flip_fluid_simulation.dart
├── rendering/
│   └── particle_renderer.dart
├── sensors/
│   └── sensor_service.dart
├── input/
│   └── touch_input_handler.dart
├── ui/
│   ├── simulation_screen.dart
│   └── widgets/
│       └── control_buttons.dart
└── main.dart
```

---

**4. Core Class Structure**

```dart
// simulation/flip_fluid_simulation.dart
class FlipFluidSimulation {
  final int maxParticles;
  int numParticles = 0;
  final Float32List particlePos, particleVel;
  final Float32List u, v, du, dv, prevU, prevV; // grid fields
  // ... other buffers: cellType, cellColor, density, etc.

  FlipFluidSimulation({ required this.maxParticles, /* width, height, spacing... */ });

  /// Integrate particle positions & velocities under gravity.
  void integrateParticles(double dt, double gravity);

  /// Transfer velocities particles→grid and grid→particles.
  void transferVelocities({ required bool toGrid, required double flipRatio });

  /// Enforce incompressibility with Gauss-Seidel.
  void solveIncompressibility(int numIters, double dt, double overRelax);

  /// Runs one full FLIP substep.
  void simulateFrame({
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
  });
}

// rendering/particle_renderer.dart
class ParticleRenderer extends CustomPainter {
  final FlipFluidSimulation sim;
  ParticleRenderer(this.sim);
  @override
  void paint(Canvas canvas, Size size) { /* drawPoints/sprites */ }
  @override
  bool shouldRepaint(covariant _) => true;
}

// sensors/sensor_service.dart
abstract class SensorService {
  Stream<AccelerometerEvent> get accelerometerStream;
  void start();
  void stop();
}

// input/touch_input_handler.dart
class TouchInputHandler {
  double obstacleX = 0, obstacleY = 0;
  void onPanStart(DragStartDetails d);
  void onPanUpdate(DragUpdateDetails d);
  void onPanEnd(DragEndDetails d);
}

// ui/simulation_screen.dart
class SimulationScreen extends StatefulWidget { /* ... */ }
class _SimulationScreenState extends State<SimulationScreen>
    with SingleTickerProviderStateMixin { /* ticker + handlers */ }

// main.dart
void main() => runApp(MyApp());
class MyApp extends StatelessWidget { /* MaterialApp → SimulationScreen */ }
```

---

**5. Algorithm Implementation Snippet (Dart)**

*Translating `integrateParticles` from JS → Dart using `Float32List`* 

```dart
// In flip_fluid_simulation.dart

void integrateParticles(double dt, double gravity) {
  // particleVel and particlePos are length 2 * maxParticles
  for (int i = 0; i < numParticles; i++) {
    final int base = 2 * i;
    // v_y += dt * gravity
    particleVel[base + 1] += dt * gravity;
    // x    += v_x * dt
    particlePos[base]     += particleVel[base]     * dt;
    // y    += v_y * dt
    particlePos[base + 1] += particleVel[base + 1] * dt;
  }
}
```

---

**6. Initial Structural Code Skeleton**

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'ui/simulation_screen.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext ctx) => MaterialApp(
    title: 'Water Slosher',
    home: SimulationScreen(),
  );
}
```

```dart
// lib/ui/simulation_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../simulation/flip_fluid_simulation.dart';
import '../rendering/particle_renderer.dart';
import '../input/touch_input_handler.dart';
import '../sensors/sensor_service.dart';

class SimulationScreen extends StatefulWidget {
  @override
  _SimulationScreenState createState() => _SimulationScreenState();
}

class _SimulationScreenState extends State<SimulationScreen>
    with SingleTickerProviderStateMixin {
  late final FlipFluidSimulation sim;
  late final ParticleRenderer renderer;
  late final TouchInputHandler inputHandler;
  late final SensorService sensorService;
  late Ticker _ticker;
  bool running = false;

  @override
  void initState() {
    super.initState();
    // Placeholder init; replace params later
    sim = FlipFluidSimulation(maxParticles: 10000);
    renderer = ParticleRenderer(sim);
    inputHandler = TouchInputHandler();
    // TODO: provide a concrete SensorService
    sensorService = /* your implementation */;
    _ticker = this.createTicker(_onTick)..start();
    running = true;
  }

  void _onTick(Duration elapsed) {
    if (!running) return;
    // TODO: sample gravity from sensorService
    final gravity = -9.81;
    sim.simulateFrame(
      dt: 1/60, gravity: gravity,
      flipRatio: 0.9,
      numPressureIters: 50,
      numParticleIters: 2,
      overRelaxation: 1.9,
      compensateDrift: true,
      separateParticles: true,
      obstacleX: inputHandler.obstacleX,
      obstacleY: inputHandler.obstacleY,
      obstacleRadius: 0.15,
    );
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    sensorService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Water Slosher')),
      body: GestureDetector(
        onPanStart: inputHandler.onPanStart,
        onPanUpdate: inputHandler.onPanUpdate,
        onPanEnd: inputHandler.onPanEnd,
        child: CustomPaint(
          painter: renderer,
          child: Container(), // fills available space
        ),
      ),
      bottomNavigationBar: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          ElevatedButton(
            onPressed: () => setState(() => running = !running),
            child: Text(running ? 'Stop' : 'Start'),
          ),
          ElevatedButton(
            onPressed: () {
              // TODO: reset simulation
            },
            child: Text('Reset'),
          ),
        ],
      ),
    );
  }
}
```

```dart
// lib/simulation/flip_fluid_simulation.dart
import 'dart:typed_data';

class FlipFluidSimulation {
  final int maxParticles;
  int numParticles = 0;
  late final Float32List particlePos, particleVel;
  // ... other buffers

  FlipFluidSimulation({ required this.maxParticles }) {
    particlePos = Float32List(2 * maxParticles);
    particleVel = Float32List(2 * maxParticles);
    // TODO: init grid buffers
  }

  void integrateParticles(double dt, double gravity) {
    for (int i = 0; i < numParticles; i++) {
      final int b = 2 * i;
      particleVel[b + 1] += dt * gravity;
      particlePos[b]     += particleVel[b]     * dt;
      particlePos[b + 1] += particleVel[b + 1] * dt;
    }
  }

  void transferVelocities({ required bool toGrid, required double flipRatio }) {
    // placeholder
  }

  void solveIncompressibility(int numIters, double dt, double overRelax) {
    // placeholder
  }

  void simulateFrame({
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
  }) {
    integrateParticles(dt, gravity);
    // ... call other steps as placeholders
  }
}
```

```dart
// lib/rendering/particle_renderer.dart
import 'package:flutter/material.dart';
import '../simulation/flip_fluid_simulation.dart';

class ParticleRenderer extends CustomPainter {
  final FlipFluidSimulation sim;
  ParticleRenderer(this.sim);

  @override
  void paint(Canvas canvas, Size size) {
    // TODO: draw points from sim.particlePos
  }

  @override
  bool shouldRepaint(covariant ParticleRenderer old) => true;
}
```

```dart
// lib/input/touch_input_handler.dart
import 'package:flutter/gestures.dart';

class TouchInputHandler {
  double obstacleX = 0.0, obstacleY = 0.0;

  void onPanStart(DragStartDetails d) { /* map to sim coords */ }
  void onPanUpdate(DragUpdateDetails d) { /* update obstacleX/Y */ }
  void onPanEnd(DragEndDetails d)   { /* zero obstacle velocity */ }
}
```

```dart
// lib/sensors/sensor_service.dart
import 'package:sensors_plus/sensors_plus.dart';

class SensorService {
  Stream<AccelerometerEvent> get accelerometerStream => accelerometerEvents;
  void start() { /* no-op for sensors_plus */ }
  void stop()  { /* no-op for sensors_plus */ }
}
```

---

This “starter pack” gives you a clear roadmap, directory layout, class skeletons and a proof-of-concept snippet demonstrating algorithmic fidelity (using `Float32List`). From here you can iteratively fill in each placeholder, profile performance, and—when needed—swap in native FFI or SkSL shaders for peak efficiency.