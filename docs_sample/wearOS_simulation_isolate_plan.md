# Wear OS Simulation Isolate Implementation Plan

This document outlines the plan to refactor the fluid simulation to run in a separate Dart Isolate, improving UI responsiveness on Wear OS.

## Phase 1: Isolate Setup & Communication

1.  **Create Isolate Entry Point (`lib/simulation_isolate.dart`):**
    *   Create a new file: `lib/simulation_isolate.dart`.
    *   Define a top-level function, e.g., `simulationIsolateEntry(IsolateInitMessage initialMessage)`.
    *   `IsolateInitMessage` will contain the initial `SendPort` from the main isolate and initial `SimOptions`.
    *   Inside `simulationIsolateEntry`:
        *   Create a `ReceivePort` for this isolate.
        *   Send the new isolate's `SendPort` back to the main isolate.
        *   Instantiate `FlipFluidSimulation`.
        *   Listen to the isolate's `ReceivePort` for commands.

2.  **Define Communication Messages:**
    *   **Commands (Main -> Sim):**
        *   `SimulateStepCommand(double dt, double gravityX, double gravityY)`
        *   `UpdateParamsCommand(SimOptions options)`
        *   `SetObstacleCommand(double x, double y, bool active, double radius)`
        *   `ResetCommand(SimOptions options)`
        *   `DisposeCommand`
    *   **Results (Sim -> Main):**
        *   `SimulationResult(TransferableTypedData particlePos, TransferableTypedData particleColor, int numParticles)`

## Phase 2: Modify UI Isolate (`lib/simulation_screen.dart`)

1.  **State Management:**
    *   Remove `FlipFluidSimulation sim;`.
    *   Add: `SendPort? _simSendPort;`, `ReceivePort? _mainReceivePort;`, `Float32List? _latestParticlePos;`, `Float32List? _latestParticleColor;`, `int _latestNumParticles = 0;`, `bool _isolateReady = false;`.

2.  **Isolate Initialization (`initState`):**
    *   Create `_mainReceivePort`.
    *   Prepare `IsolateInitMessage`.
    *   Spawn the isolate: `Isolate.spawn(simulationIsolateEntry, initialMessage);`.
    *   Listen to `_mainReceivePort` for the simulation isolate's `SendPort` and subsequent `SimulationResult` messages. Materialize `TransferableTypedData` upon receiving results and call `setState`.

3.  **Triggering Simulation (`_onTick`):**
    *   Remove direct `sim.simulate(...)` call.
    *   If `_isolateReady` and `running`, send `SimulateStepCommand` via `_simSendPort`.

4.  **Handling Inputs:**
    *   **Gravity:** Include current gravity in `SimulateStepCommand`.
    *   **Obstacle:** Send `SetObstacleCommand` on pan events.
    *   **Bezel:** Send `UpdateParamsCommand` with new radius.
    *   **Reset:** Fetch config, then send `ResetCommand`.

5.  **Rendering (`ParticleRenderer`):**
    *   Modify `ParticleRenderer` to accept particle data (`Float32List?`, `int`) directly in its constructor or via setters.
    *   Update `CustomPaint` in `SimulationScreen`'s `build` method to pass the latest particle data.

6.  **Cleanup (`dispose`):**
    *   Send `DisposeCommand` via `_simSendPort`.
    *   Close `_mainReceivePort`.
    *   Cancel other subscriptions.

## Phase 3: Adapt Simulation Isolate Logic (`lib/simulation_isolate.dart`)

1.  **`simulationIsolateEntry`:**
    *   Implement the command processing loop:
        *   On `SimulateStepCommand`: Call `sim.simulate(...)`, package results into `TransferableTypedData`, send `SimulationResult`.
        *   On `UpdateParamsCommand`: Update simulation parameters.
        *   On `SetObstacleCommand`: Call `sim.setObstacle(...)` or update relevant fields.
        *   On `ResetCommand`: Call `sim.dispose()`, create new `FlipFluidSimulation`, call `sim.addBlock(...)`.
        *   On `DisposeCommand`: Call `sim.dispose()`, close isolate's `ReceivePort`, exit.

2.  **`FlipFluidSimulation` (`lib/flip_fluid_simulation.dart`):**
    *   Ensure methods take necessary parameters directly. FFI and `dispose` remain largely unchanged.

## Communication Diagram

```mermaid
sequenceDiagram
    participant Main Isolate (SimulationScreen)
    participant Sim Isolate (simulationIsolateEntry)
    participant FlipFluidSimulation

    Main Isolate->>Sim Isolate: spawn(simulationIsolateEntry, IsolateInitMessage(mainSendPort, initialOpts))
    Sim Isolate->>FlipFluidSimulation: new FlipFluidSimulation(initialOpts)
    Sim Isolate->>Main Isolate: simSendPort (via mainSendPort)
    Note over Main Isolate: Store simSendPort, _isolateReady = true

    loop Simulation Loop (driven by Ticker)
        Main Isolate->>Sim Isolate: SimulateStepCommand(dt, gravityX, gravityY)
        Sim Isolate->>FlipFluidSimulation: simulate(dt, gravityX, gravityY, ...)
        FlipFluidSimulation-->>Sim Isolate: Simulation done (updates internal particlePos/Color)
        Note over Sim Isolate: Get sim.particlePos, sim.particleColor\nCreate TransferableTypedData\nSend SimulationResult
        Sim Isolate->>Main Isolate: SimulationResult(transferablePos, transferableColor, numParticles)
        Note over Main Isolate: Receive Result\nMaterialize Data\nStore _latestPos/_latestColor\nsetState() -> triggers repaint
    end

    alt User Input (e.g., Touch)
        Main Isolate->>Sim Isolate: SetObstacleCommand(x, y, active, radius)
        Sim Isolate->>FlipFluidSimulation: setObstacle(x, y, active, radius)
    else User Input (e.g., Reset)
        Main Isolate->>Sim Isolate: ResetCommand(newOpts)
        Sim Isolate->>FlipFluidSimulation: dispose()
        Sim Isolate->>FlipFluidSimulation: new FlipFluidSimulation(newOpts)
        Sim Isolate->>FlipFluidSimulation: addBlock(...)
    end

    Note over Main Isolate: Screen dispose()
    Main Isolate->>Sim Isolate: DisposeCommand
    Sim Isolate->>FlipFluidSimulation: dispose()
    Note over Sim Isolate: Close ReceivePort, Isolate exits.