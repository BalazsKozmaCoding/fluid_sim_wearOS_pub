Below are the **minimal edits** you need to wire your finger & sensor as a moving obstacle, and to add a rounded “config panel” like in the HTML demo. You’ll touch only three places:  

---

## 1. Expose `setObstacle(...)` on your sim  

In your `FlipFluidSimulation` (in `flip_fluid_simulation.dart`), add this method (we had shown it before) so you can carve the grid and record obstacle velocity:

```dart
  double obstacleX = 0.0, obstacleY = 0.0;
  double obstacleVelX = 0.0, obstacleVelY = 0.0;
  double obstacleRadius = 0.15;

  /// Carve grid cells under the obstacle and record its velocity.
  void setObstacle(double x, double y, bool reset, double dt) {
    final int n = fNumY;
    final double vx = reset ? 0.0 : (x - obstacleX) / dt;
    final double vy = reset ? 0.0 : (y - obstacleY) / dt;
    obstacleX = x; obstacleY = y;
    obstacleVelX = vx; obstacleVelY = vy;

    // reset s[] to fluid/walls, then carve circle:
    initializeGrid();            
    for (int i = 1; i < fNumX - 1; i++) {
      for (int j = 1; j < fNumY - 1; j++) {
        final double cx = (i + .5) * h, cy = (j + .5) * h;
        if ((cx - x)*(cx - x) + (cy - y)*(cy - y) < obstacleRadius * obstacleRadius) {
          int idx = i * n + j;
          s[idx] = 0.0;
          // stamp grid velocity so transferVelocities sees moving wall:
          u[idx] = vx;        u[(i+1)*n + j] = vx;
          v[idx] = vy;        v[i*n + (j+1)] = vy;
        }
      }
    }
  }
```

Also be sure you have the `initializeGrid()` method we gave you before, and call it once in your constructor or reset.

---

## 2. Hook your finger events to `setObstacle(...)`  

In **`simulation_screen.dart`** change your `GestureDetector` from merely passing positions into the handler, to actually calling `sim.setObstacle(...)` every frame:

```diff
// inside build() around CustomPaint:
 GestureDetector(
-  onPanStart: (_) { inputHandler.startDrag(_); },
-  onPanUpdate: (_) { inputHandler.drag(_); },
-  onPanEnd: (_) { inputHandler.resetObstacleVelocity(); },
+  onPanStart: (d) {
+    final p = _toSimCoords(d.localPosition);
+    sim.setObstacle(p.dx, p.dy, true, 1/60);
+  },
+  onPanUpdate: (d) {
+    final p = _toSimCoords(d.localPosition);
+    sim.setObstacle(p.dx, p.dy, false, 1/60);
+  },
+  onPanEnd: (_) {
+    sim.obstacleVelX = sim.obstacleVelY = 0.0;
+  },
   child: CustomPaint(
     painter: renderer,
     child: Container(),
   ),
 ),
```

Add the helper to convert from screen → sim coordinates:

```dart
  // map from localPosition in widget to simulation space:
  Offset _toSimCoords(Offset lp) {
    final Size s = context.size!;
    return Offset(
      lp.dx / s.width  * (sim.fNumX * sim.h),
      (s.height - lp.dy) / s.height * (sim.fNumY * sim.h),
    );
  }
```

---

## 3. Read the accelerometer and tilt the tank  

In `initState()` of your `_SimulationScreenState`:

```dart
  double gravityX = 0.0, gravityY = -9.81;

  @override
  void initState() {
    super.initState();
    // … your existing sim, renderer, ticker setup …

    // subscribe to accelerometer:
    sensorService.accelerometerStream.listen((event) {
      setState(() {
        // choose axes so that tilting phone tilts the “vessel”
        gravityX = event.x * 9.81;    
        gravityY = event.y * 9.81;
      });
    });
  }
```

Then in your `_onTick` replace the fixed gravity with the vector magnitude in the sim call:

```diff
- final gravity = -9.81;
- sim.simulate(dt:1/60, gravity: gravity, …);
+ // combine device tilt into a net downward accel in sim coords:
+ final g = sqrt(gravityX*gravityX + gravityY*gravityY);
+ sim.simulate(
+   dt: 1/60,
+   gravity: -g,               // negative = downward
+   flipRatio: simOptions.flipRatio,
+   numPressureIters: simOptions.pressureIters,
+   numParticleIters: simOptions.particleIters,
+   overRelaxation: simOptions.overRelax,
+   compensateDrift: simOptions.compensateDrift,
+   separateParticles: simOptions.separateParticles,
+   obstacleX: sim.obstacleX,
+   obstacleY: sim.obstacleY,
+   obstacleRadius: sim.obstacleRadius,
+   obstacleVelX: sim.obstacleVelX,
+   obstacleVelY: sim.obstacleVelY,
+ );
```

---

## 4. Add a rounded “config panel” (eltuno/megnyilo)  

In your AppBar add an action button:

```dart
appBar: AppBar(
  title: Text('Water Slosher'),
  actions: [
    IconButton(
      icon: Icon(Icons.settings),
      onPressed: _openConfigPanel,
    )
  ],
),
```

Then implement `_openConfigPanel()` to show a bottom sheet with rounded corners and the same toggles/sliders from the HTML demo:

```dart
void _openConfigPanel() {
  showModalBottomSheet(
    context: context,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              title: Text('Show Particles'),
              value: simOptions.showParticles,
              onChanged: (v) => setState(() => simOptions.showParticles = v),
            ),
            SwitchListTile(
              title: Text('Show Grid'),
              value: simOptions.showGrid,
              onChanged: (v) => setState(() => simOptions.showGrid = v),
            ),
            SwitchListTile(
              title: Text('Compensate Drift'),
              value: simOptions.compensateDrift,
              onChanged: (v) => setState(() => simOptions.compensateDrift = v),
            ),
            ListTile(
              title: Text('FLIP / PIC ratio'),
              subtitle: Slider(
                min: 0.0, max: 1.0, divisions: 10,
                value: simOptions.flipRatio,
                onChanged: (v) => setState(() => simOptions.flipRatio = v),
              ),
            ),
            // add more controls as needed…
          ],
        ),
      );
    }
  );
}
```

Define a simple `simOptions` holder in your state:

```dart
class _SimulationScreenState extends State<…> {
  var simOptions = SimOptions();
  …
}

class SimOptions {
  bool showParticles = true;
  bool showGrid = false;
  bool compensateDrift = true;
  bool separateParticles = true;
  double flipRatio = 0.9;
  int pressureIters = 50;
  int particleIters = 2;
  double overRelax = 1.9;
}
```

Then pass these into your rendering and simulate call (`renderer` can read `simOptions.showParticles/showGrid`).

---

With just these additions you will have:

1. **Finger** acts as a moving obstacle in the FLIP grid.  
2. **Tilt** drives gravity via the accelerometer.  
3. A **rounded config sheet** (“eltuno/megnyilo”) where you can toggle particles, grid, drift-compensation, and adjust the FLIP/PIC slider exactly like the HTML demo.  

Give that a try—your water will now truly slosh under finger-drag and device tilt, with an on-screen control panel!