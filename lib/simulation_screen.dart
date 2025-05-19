import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart'; // For MethodChannel and rootBundle
import 'package:flutter/gestures.dart'; // For gesture recognizers
import 'package:flutter/foundation.dart'; // For Factory

import 'flip_fluid_simulation.dart';
import 'dart:math' as math;
import 'particle_renderer.dart';
import 'pixel_clock_style.dart'; // Added for PixelClockConfig
import 'sensor_service.dart';
import 'bezel_channel.dart'; // Added for rotary input
import 'dart:async'; // Added for StreamSubscription
import 'dart:convert'; // Added for jsonDecode
import 'package:http/http.dart' as http;
import 'dart:developer' as devLog; // Corrected alias usage
import 'dart:ui' as ui; // Added for ui.Image
import 'models.dart'; // Added for SimulationConfig

enum WatchFaceStyle { normal, pixelated }

class SimulationScreen extends StatefulWidget {
  @override
_SimulationScreenState createState() => _SimulationScreenState();
}

const String _kUpdateObstacleMethod = 'updateObstacle';
const String _kSetNativeTouchModeMethod = 'setNativeTouchMode';

class _SimulationScreenState extends State<SimulationScreen>
    with SingleTickerProviderStateMixin {
  bool _isNativeTouchMode = true;
  MethodChannel? _fluidViewMethodChannel;
  int? _nativeViewId; 
  Timer? _clockUpdateTimer;
  String _currentTimeString = "--:--";
  bool isNight = true;
  late FlipFluidSimulation sim;
  late ParticleRenderer renderer;

  static const String _configServerUrl = 'http://192.168.0.129:8080/config';
  late final SensorService sensorService;
  late final BezelChannelService bezelChannelService;
  StreamSubscription? _bezelSubscription;
  StreamSubscription? _temperatureSubscription;
  int _initialParticleCountForBezel = 0;
  int _bezelClickCount = 0;
  Timer? _bezelStopTimer;
  static const Duration _bezelStopDelay = Duration(milliseconds: 500);

  late Ticker _ticker;
  bool running = false;
  bool isTouching = false;
  String? _configErrorMessage;
  Timer? _errorMessageTimer;

  List<Map<String, dynamic>> _bundledConfigs = [];
  int _currentBundledConfigIndex = 0;
  String _currentConfigName = "Default";
  bool _isInitialized = false;
  ui.Image? _particleAtlas;
  WatchFaceStyle _currentWatchStyle = WatchFaceStyle.normal;

  var simOptions = SimOptions();
  double gravityX = 0.0, gravityY = -9.81;
  double _temperature = 25.0;


void _startClockTimer() {
    _clockUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
       final now = DateTime.now();
       if (now.second == 0) {
         _updateClockDisplay();
       }
    });
  }

  void _updateClockDisplay() {
    if (!mounted) return;
    final now = DateTime.now();
    final String formattedTime = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    if (formattedTime != _currentTimeString) {
      setState(() {
        _currentTimeString = formattedTime;
        // devLog.log("Updating clock display text to: $_currentTimeString", name: 'SimulationScreen'); // Optional: re-enable if needed
      });
    }
  }
  @override
  void initState() {
    super.initState();
    sensorService = SensorService();
    bezelChannelService = BezelChannelService();

    _initializeSimulationAsync();

    _startClockTimer();
    _updateClockDisplay();

    _setupSensorListeners();
    _setupBezelListener();
  }

  Future<void> _createParticleAtlas() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = Colors.white;
    // Draw a 2x2 white square. This will be our particle texture.
    // The actual particle size will be controlled by RSTransform's scale.
    canvas.drawRect(Rect.fromLTWH(0, 0, 2, 2), paint);
    final picture = recorder.endRecording();
    // Convert the picture to an image. The dimensions here are for the image itself.
    _particleAtlas = await picture.toImage(2, 2);
    devLog.log("Particle atlas created.", name: 'SimulationScreen');
  }

  Future<void> _initializeSimulationAsync() async {
    devLog.log("Starting async initialization...", name: 'SimulationScreen');
    bool configApplied = false;

    // Load all bundled configs first, so they are available for fallback
    await _loadAllBundledConfigs();

    try {
      devLog.log("Attempting to fetch config from server: $_configServerUrl", name: 'SimulationScreen');
      final response = await http.get(Uri.parse(_configServerUrl)).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final Map<String, dynamic> serverConfig = json.decode(response.body);
        _applyConfigData(serverConfig, _configServerUrl);
        devLog.log("Successfully fetched and applied config from server.", name: 'SimulationScreen');
        configApplied = true;
      } else {
        devLog.log("Server responded with status: ${response.statusCode}. Will use first bundled config or defaults.", name: 'SimulationScreen');
      }
    } catch (e) {
      devLog.log("Failed to fetch config from server: $e. Will use first bundled config or defaults.", name: 'SimulationScreen', error: e);
    }

    if (!configApplied) {
      if (_bundledConfigs.isNotEmpty) {
        devLog.log("Server config failed. Applying first bundled config from sorted list.", name: 'SimulationScreen');
        final firstConfigData = _bundledConfigs[0]['config'] as Map<String, dynamic>;
        final firstConfigPath = _bundledConfigs[0]['path'] as String;
        _applyConfigData(firstConfigData, firstConfigPath);
        _currentBundledConfigIndex = 0; // Set index to the loaded config
        devLog.log("Successfully applied first bundled config: $firstConfigPath", name: 'SimulationScreen');
        configApplied = true;
      } else {
        devLog.log("Server config failed and no bundled configs found. Using built-in SimOptions.", name: 'SimulationScreen');
        _applyConfigData({}, "Built-in Defaults");
        configApplied = true;
      }
    }

    const double targetWidth = 4.0;
    const double targetHeight = 4.0;
    final double tempHForParticles = targetWidth / simOptions.cellsWide;
    final double initialParticleRadius = simOptions.particleRadiusRatio * tempHForParticles;

    sim = FlipFluidSimulation(
      density: 1000.0,
      width: targetWidth,
      height: targetHeight,
      cellsWide: simOptions.cellsWide,
      particleRadius: initialParticleRadius,
      maxParticles: 25000,
      obstacleRadius: simOptions.obstacleRadius,
      enableDynamicColoring: simOptions.enableDynamicColoring, // Pass the flag
    );

    await _createParticleAtlas(); // Create atlas before renderer if renderer needs it in constructor
    renderer = ParticleRenderer(sim, particleAtlas: _particleAtlas);
    _addInitialFluid();
    gravityY = -simOptions.gravityMagnitude;

    _ticker = this.createTicker(_onTick)..start();
    running = true;

    if (mounted) {
      setState(() {
        _isInitialized = true;
        devLog.log("Async initialization complete, setting _isInitialized=true and triggering setState.", name: 'SimulationScreen');
      });
    }
  }

  void _setupSensorListeners() {
    sensorService.accelerometerStream.listen((event) {
      if (!mounted) return;
      setState(() {
        final double currentGravityMagnitude = simOptions.gravityMagnitude;
        gravityX = event.x;
        gravityY = event.y;
        gravityX *= currentGravityMagnitude / 9.81;
        gravityY *= currentGravityMagnitude / 9.81;
      });
    });

    _temperatureSubscription = sensorService.temperatureStream.listen((temperature) {
      if (!mounted) return;
      setState(() {
        _temperature = temperature;
      });
    }, onError: (error) {
      devLog.log("Error receiving temperature: $error", name: 'SimulationScreen.SensorService', error: error);
      if (mounted) {
        setState(() {
          _temperature = -999.0;
        });
      }
    });
  }

  void _setupBezelListener() {
    _bezelSubscription = bezelChannelService.bezelEvents.listen((delta) {
      if (!mounted) return;

      if (_bezelClickCount == 0) {
        _initialParticleCountForBezel = simOptions.particleCount;
        devLog.log("Bezel interaction started. Initial particles: $_initialParticleCountForBezel", name: 'SimulationScreen');
      }

      if (delta > 0) {
        _bezelClickCount++;
      } else if (delta < 0) {
        _bezelClickCount--;
      } else {
        return;
      }

      double newParticleTarget = _initialParticleCountForBezel * (math.pow(0.8, _bezelClickCount) as double);
      int newParticleCountRounded = ((newParticleTarget / 100).round() * 100);
      newParticleCountRounded = newParticleCountRounded.clamp(100, 10000);

      _showConfigError("Target: ${newParticleCountRounded}p");
      devLog.log("Bezel delta: $delta, click count: $_bezelClickCount, target particles: $newParticleCountRounded", name: 'SimulationScreen');

      _bezelStopTimer?.cancel();
      _bezelStopTimer = Timer(_bezelStopDelay, () {
        if (!mounted) return;
        devLog.log("Bezel stopped. Applying particle count: $newParticleCountRounded and restarting.", name: 'SimulationScreen');
        setState(() {
          simOptions.particleCount = newParticleCountRounded;
          _bezelClickCount = 0;
          _initialParticleCountForBezel = simOptions.particleCount;
        });
        _restartSimulationWithNewParticleCount();
        _showConfigError("Particles: ${simOptions.particleCount}");
      });
    });
  }

  Future<void> _restartSimulationWithNewParticleCount() async {
    devLog.log("Restarting simulation with new particle count: ${simOptions.particleCount}", name: 'SimulationScreen');
    if (!mounted || !_isInitialized) {
      devLog.log("Cannot restart: not mounted or not initialized.", name: 'SimulationScreen');
      return;
    }

    bool wasRunning = running;
    if (running) {
      _ticker.stop();
      devLog.log("Ticker stopped for re-initialization.", name: 'SimulationScreen');
    }

    sim.dispose();

    const double targetWidth = 4.0;
    const double targetHeight = 4.0;
    final double tempHForParticlesReset = targetWidth / simOptions.cellsWide;
    final double calculatedParticleRadius = simOptions.particleRadiusRatio * tempHForParticlesReset;
    devLog.log("Re-init with cellsWide=${simOptions.cellsWide}, particleRadius=$calculatedParticleRadius", name: 'SimulationScreen');

    sim = FlipFluidSimulation(
      density: 1000.0,
      width: targetWidth,
      height: targetHeight,
      cellsWide: simOptions.cellsWide,
      particleRadius: calculatedParticleRadius,
      maxParticles: 25000,
      obstacleRadius: simOptions.obstacleRadius,
      enableDynamicColoring: simOptions.enableDynamicColoring, // Pass the flag
    );

    // Atlas should already be created, just pass it
    renderer = ParticleRenderer(sim, particleAtlas: _particleAtlas);
    sim.numParticles = 0;
    _addInitialFluid();

    isTouching = false;
    sim.isObstacleActive = false;
    sim.obstacleVelX = 0.0;
    sim.obstacleVelY = 0.0;

    if (mounted) {
      setState(() {});
    }

    if (wasRunning) {
      _ticker.start();
      devLog.log("Ticker restarted after re-initialization.", name: 'SimulationScreen');
    }
    devLog.log("Simulation restarted. Actual particle count: ${sim.numParticles}", name: 'SimulationScreen');
  }

  void _addInitialFluid() {
    final double initialTargetFillHeightFromBottom = sim.sceneCircleRadius * 0.8;
    sim.fillCircleBottom(initialTargetFillHeightFromBottom, maxCount: simOptions.particleCount);
    devLog.log("Added initial fluid using fillCircleBottom. Target height: $initialTargetFillHeightFromBottom, Max particles: ${simOptions.particleCount}. Actual count: ${sim.numParticles}", name: 'SimulationScreen');
  }

  Future<void> _loadAllBundledConfigs() async {
    try {
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);

      final List<String> configAssetPaths = manifestMap.keys
          .where((String key) => key.startsWith('configs/') && key.endsWith('.json'))
          .toList();

      if (configAssetPaths.isEmpty) {
        devLog.log("No bundled configs found in configs/ directory.", name: 'SimulationScreen');
        _showConfigError("No bundled configs.");
        return;
      }

      List<Map<String, dynamic>> loadedConfigs = [];
      for (String path in configAssetPaths) {
        try {
          final String jsonString = await rootBundle.loadString(path);
          final Map<String, dynamic> configJson = json.decode(jsonString);
          loadedConfigs.add({'path': path, 'config': configJson});
          devLog.log("Loaded bundled config: $path", name: 'SimulationScreen');
        } catch (e) {
          devLog.log("Error loading or parsing bundled config $path: $e", name: 'SimulationScreen', error: e);
        }
      }
      setState(() {
        _bundledConfigs = loadedConfigs;
        _bundledConfigs.sort((a, b) {
          final String pathA = a['path'] as String; // e.g. "configs/1_particles_static.json"
          final String pathB = b['path'] as String; // e.g. "configs/2_grid.json"
          
          // Extract file names for comparison, e.g., "1_particles_static.json", "2_grid.json"
          final String nameA = pathA.split('/').last;
          final String nameB = pathB.split('/').last;
          
          // Sort by filename alphanumerically
          return nameA.compareTo(nameB);
        });
        devLog.log("All bundled configs loaded and sorted: ${_bundledConfigs.length} found.", name: 'SimulationScreen');
      });
    } catch (e) {
      devLog.log("Error loading asset manifest or bundled configs: $e", name: 'SimulationScreen', error: e);
      _showConfigError("Error loading configs.");
    }
  }

  Future<bool> _loadAndApplySpecificConfig(String assetPath) async {
    devLog.log("Attempting to load and apply config: $assetPath", name: 'SimulationScreen');
    try {
      final String jsonString = await rootBundle.loadString(assetPath);
      final Map<String, dynamic> config = json.decode(jsonString);
      devLog.log("Successfully loaded $assetPath: $config", name: 'SimulationScreen');
      _applyConfigData(config, assetPath);
      return true;
    } catch (e) {
      devLog.log("Error loading or parsing config $assetPath: $e", name: 'SimulationScreen', error: e);
      _showConfigError("Failed to load $assetPath");
      return false;
    }
  }

  void _applyConfigData(Map<String, dynamic> config, String configPath) {
     if (!mounted) return;

     String configName = configPath.split('/').last;
     if (configName.isEmpty) {
       configName = "Unknown Config";
     }

     setState(() {
        _currentConfigName = configName;
        simOptions.timeScale = (config['timeScale'] as num?)?.toDouble() ?? simOptions.timeScale;
        simOptions.overRelax = (config['overRelax'] as num?)?.toDouble() ?? simOptions.overRelax;
        simOptions.flipRatio = (config['flipRatio'] as num?)?.toDouble() ?? simOptions.flipRatio;
        simOptions.showParticles = (config['showParticles'] as bool?) ?? simOptions.showParticles;
        simOptions.showGrid = (config['showGrid'] as bool?) ?? simOptions.showGrid;
        simOptions.compensateDrift = (config['compensateDrift'] as bool?) ?? simOptions.compensateDrift;
        simOptions.separateParticles = (config['separateParticles'] as bool?) ?? simOptions.separateParticles;
        simOptions.pressureIters = (config['pressureIters'] as int?) ?? simOptions.pressureIters;
        simOptions.particleIters = (config['particleIters'] as int?) ?? simOptions.particleIters;
        simOptions.particleCount = (config['particleCount'] as int?) ?? simOptions.particleCount;
        simOptions.obstacleRadius = (config['obstacleRadius'] as num?)?.toDouble() ?? simOptions.obstacleRadius;
        simOptions.particleRadiusRatio = (config['particleRadiusRatio'] as num?)?.toDouble() ?? simOptions.particleRadiusRatio;
        simOptions.gravityMagnitude = (config['gravityMagnitude'] as num?)?.toDouble() ?? simOptions.gravityMagnitude;
        simOptions.cellsWide = (config['cellsWide'] as int?) ?? simOptions.cellsWide;
        simOptions.renderScale = (config['renderScale'] as num?)?.toDouble() ?? simOptions.renderScale;
        final dynamic debugValue = config['debug'];
        if (debugValue is bool) {
          simOptions.debug = debugValue;
        } else if (debugValue is num) {
          simOptions.debug = debugValue != 0;
        } else {
          simOptions.debug = false;
        }
        simOptions.enableDynamicColoring = (config['enableDynamicColoring'] as bool?) ?? simOptions.enableDynamicColoring;
        simOptions.intensityMin = (config['intensityMin'] as num?)?.toDouble() ?? simOptions.intensityMin;
        simOptions.intensityMax = (config['intensityMax'] as num?)?.toDouble() ?? simOptions.intensityMax;

        devLog.log("SimOptions updated from: $configPath. DynamicColoring: ${simOptions.enableDynamicColoring}, IntensityMin: ${simOptions.intensityMin}, IntensityMax: ${simOptions.intensityMax}", name: 'SimulationScreen');
        _showConfigError("Using: $configName");
     });
  }

  void _showConfigError(String message) {
    if (!mounted) return;
    setState(() {
      _configErrorMessage = message;
    });
    _errorMessageTimer?.cancel();
    _errorMessageTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _configErrorMessage = null;
      });
    });
  }

  void _applyNextBundledConfig() {
    if (_bundledConfigs.isEmpty) {
      devLog.log("No bundled configs to apply.", name: 'SimulationScreen');
      _showConfigError("No bundled configs available.");
      return;
    }

    _currentBundledConfigIndex = (_currentBundledConfigIndex + 1) % _bundledConfigs.length;
    final Map<String, dynamic> configData = _bundledConfigs[_currentBundledConfigIndex]['config'];
    final String configPath = _bundledConfigs[_currentBundledConfigIndex]['path'];
    
    devLog.log("Applying bundled config index: $_currentBundledConfigIndex, path: $configPath, data: $configData", name: 'SimulationScreen');
    _applyConfigData(configData, configPath);
  }

  Future<void> _resetSimulation() async {
    devLog.log("Reset button pressed. Applying next config and resetting simulation...", name: 'SimulationScreen');
    _applyNextBundledConfig();
    if (!mounted) return;

    sim.dispose();

    const double targetWidth = 4.0;
    const double targetHeight = 4.0;
    final double tempHForParticlesReset = targetWidth / simOptions.cellsWide;
    final double calculatedParticleRadius = simOptions.particleRadiusRatio * tempHForParticlesReset;
    devLog.log("Resetting with cellsWide=${simOptions.cellsWide}, tempHForParticles=$tempHForParticlesReset, particleRadius=$calculatedParticleRadius (Ratio=${simOptions.particleRadiusRatio})", name: 'SimulationScreen');

    sim = FlipFluidSimulation(
      density: 1000.0,
      width: targetWidth,
      height: targetHeight,
      cellsWide: simOptions.cellsWide,
      particleRadius: calculatedParticleRadius,
      maxParticles: 25000,
      obstacleRadius: simOptions.obstacleRadius,
      enableDynamicColoring: simOptions.enableDynamicColoring, // Pass the flag
    );
    
    // Atlas should already be created, just pass it
    renderer = ParticleRenderer(sim, particleAtlas: _particleAtlas);
    sim.numParticles = 0;
    _addInitialFluid();

    isTouching = false;
    sim.isObstacleActive = false;
    sim.obstacleVelX = 0.0;
    sim.obstacleVelY = 0.0;

    setState(() {});
  }

  Offset _toSimCoords(Offset lp) {
    final Size s = context.size!;
    return Offset(
      lp.dx / s.width  * (sim.fNumX * sim.h),
      (s.height - lp.dy) / s.height * (sim.fNumY * sim.h),
    );
  }

  double _calculateCircularLeftOffset(Size size, double topOffset) {
    final double radius = size.width / 2;
    final double centerY = size.height / 2;
    final double yDistFromCenter = centerY - topOffset;
    // Ensure the value inside sqrt is not negative
    final double xDistFromCenter = math.sqrt(math.max(0.0, math.pow(radius, 2) - math.pow(yDistFromCenter, 2)));
    return radius - xDistFromCenter;
  }

  int _frameCount = 0;
  double _elapsedTimeInSeconds = 0;
  double _fps = 0;
  DateTime _lastTimestamp = DateTime.now();
  // double _temperature = 25.0; // Already defined above

  void _onTick(Duration elapsed) {
    if (!running || !_isInitialized) return;

    final now = DateTime.now();
    final delta = now.difference(_lastTimestamp);
    _lastTimestamp = now;

    _elapsedTimeInSeconds += delta.inMilliseconds / 1000.0;
    _frameCount++;

    if (_elapsedTimeInSeconds >= 1.0) {
      _fps = _frameCount / _elapsedTimeInSeconds;
      _frameCount = 0;
      _elapsedTimeInSeconds = 0;
    }
    
    double simGx = -gravityX;
    double simGy = -gravityY;

    final dtSim = simOptions.timeScale * (1/60.0);

    sim.simulate(
      dt: dtSim,
      gravityX: simGx,
      gravityY: simGy,
      flipRatio: simOptions.flipRatio,
      numPressureIters: simOptions.pressureIters,
      numParticleIters: simOptions.particleIters,
      overRelaxation: simOptions.overRelax,
      compensateDrift: simOptions.compensateDrift,
      separateParticles: simOptions.separateParticles,
    );
    if (mounted) {
      setState(() {});
    }
  }

  void _toggleApplicationMode() {
    if (!mounted) return;
    setState(() {
      _isNativeTouchMode = !_isNativeTouchMode;
    });
    _updateNativeViewTouchInteractivity(_isNativeTouchMode);
    devLog.log("Application mode toggled. Native touch: $_isNativeTouchMode", name: 'SimulationScreen');
  }

  Future<void> _updateNativeViewTouchInteractivity(bool enableNativeTouch) async {
    devLog.log(
        "[SIM_SCREEN_DEBUG] _updateNativeViewTouchInteractivity entered. enableNativeTouch: $enableNativeTouch. Channel is null: ${_fluidViewMethodChannel == null}",
        name: 'SimulationScreen.TouchMode');
    if (_fluidViewMethodChannel == null) {
      devLog.log("[SIM_SCREEN_DEBUG] Error: _fluidViewMethodChannel is null in _updateNativeViewTouchInteractivity.", name: 'SimulationScreen.TouchMode');
      return;
    }
    try {
      devLog.log("[SIM_SCREEN_DEBUG] Attempting to invoke $_kSetNativeTouchModeMethod with enabled: $enableNativeTouch", name: 'SimulationScreen.TouchMode');
      await _fluidViewMethodChannel!.invokeMethod(_kSetNativeTouchModeMethod, {'enabled': enableNativeTouch});
      devLog.log("[SIM_SCREEN_DEBUG] Called $_kSetNativeTouchModeMethod on native view with enable: $enableNativeTouch - SUCCESS", name: 'SimulationScreen.TouchMode');
    } catch (e) {
      devLog.log("[SIM_SCREEN_DEBUG] Error invoking setNativeTouchMode: $e", name: 'SimulationScreen.TouchMode', error: e);
    }
  }

  Future<void> _handleNativeViewMethodCalls(MethodCall call) async {
    if (!mounted) return;
    devLog.log("Native call received: ${call.method} with args: ${call.arguments}", name: 'SimulationScreen');
    switch (call.method) {
      case _kUpdateObstacleMethod:
        final Map<dynamic, dynamic> args = call.arguments as Map<dynamic, dynamic>;
        final double normalizedSimX = (args['simX'] as num).toDouble();
        final double normalizedSimY = (args['simY'] as num).toDouble();
        final bool isDragging = args['isDragging'] as bool;
        final bool isNewDrag = args['isNewDrag'] as bool;

        final double worldSimX = normalizedSimX * sim.worldWidth;
        final double worldSimY = (1.0 - normalizedSimY) * sim.worldHeight;

        devLog.log(
            "ObstacleMoved (Dart): normX=$normalizedSimX, normY=$normalizedSimY -> worldX=$worldSimX, worldY=$worldSimY, isDragging=$isDragging, isNewDrag=$isNewDrag",
            name: 'SimulationScreen.NativeCall');

        setState(() {
          isTouching = isDragging;
        });

        sim.isObstacleActive = isDragging;
        if (isDragging) {
          sim.setObstacle(worldSimX, worldSimY, isNewDrag, simOptions.timeScale * (1 / 60.0));
        } else {
          sim.initializeGrid();
          sim.obstacleVelX = 0.0;
          sim.obstacleVelY = 0.0;
        }
        break;
      default:
        devLog.log('Unknown method call from native: ${call.method}', name: 'SimulationScreen');
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clockUpdateTimer?.cancel();
    sensorService.dispose();
    _bezelSubscription?.cancel();
    _temperatureSubscription?.cancel();
    _bezelStopTimer?.cancel();
    bezelChannelService.dispose();
    _errorMessageTimer?.cancel();
    _fluidViewMethodChannel?.setMethodCallHandler(null);
    _particleAtlas?.dispose();
    _particleAtlas = null;
    sim.dispose();
    super.dispose();
  }

  void _cycleWatchStyle() {
    if (!mounted) return;
    setState(() {
      // Toggle the usePixelatedClock flag in the simulationConfig
      bool newPixelatedState = !simOptions.simulationConfig.usePixelatedClock;
      simOptions.simulationConfig = SimulationConfig(
        // Copy existing simConfig values if any were important,
        // for now, we only care about toggling usePixelatedClock
        density: simOptions.simulationConfig.density,
        cellsWide: simOptions.simulationConfig.cellsWide,
        particleRadius: simOptions.simulationConfig.particleRadius,
        maxParticles: simOptions.simulationConfig.maxParticles,
        obstacleRadius: simOptions.simulationConfig.obstacleRadius,
        gravityX: simOptions.simulationConfig.gravityX,
        gravityY: simOptions.simulationConfig.gravityY,
        flipRatio: simOptions.simulationConfig.flipRatio,
        numPressureIters: simOptions.simulationConfig.numPressureIters,
        numParticleIters: simOptions.simulationConfig.numParticleIters,
        overRelaxation: simOptions.simulationConfig.overRelaxation,
        compensateDrift: simOptions.simulationConfig.compensateDrift,
        separateParticles: simOptions.simulationConfig.separateParticles,
        enableDynamicColoring: simOptions.simulationConfig.enableDynamicColoring,
        // Update the toggled value
        usePixelatedClock: newPixelatedState,
      );

      if (newPixelatedState) {
        _currentWatchStyle = WatchFaceStyle.pixelated;
        _showConfigError("Style: Pixelated");
      } else {
        _currentWatchStyle = WatchFaceStyle.normal;
        _showConfigError("Style: Normal");
      }
      devLog.log("Watch style changed. usePixelatedClock: ${simOptions.simulationConfig.usePixelatedClock}", name: 'SimulationScreen.WatchStyle');
    });
  }

  void _turnOffApp() {
    devLog.log("Turn off button pressed. Exiting app.", name: 'SimulationScreen.Power');
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: isNight ? Colors.black : Colors.white,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final Color clockColor = isNight ? Colors.grey[300]! : Colors.grey[800]!;
    renderer.simOptions = simOptions;
    renderer.showTouchCircle = isTouching;
    renderer.isNight = isNight;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) {
          _toggleApplicationMode();
        }
      },
      child: Scaffold(
        extendBody: true,
        extendBodyBehindAppBar: true,
        backgroundColor: isNight ? Colors.black : Colors.white,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final Size size = constraints.biggest;
              return Stack(
                children: [
                  Center(
                    child: LayoutBuilder(
                      builder: (context, clockConstraints) {
                        return SizedBox(
                          width: clockConstraints.maxWidth * 0.70,
                          height: clockConstraints.maxHeight * 0.50,
                          child: FittedBox(
                            fit: BoxFit.contain,
                            // Conditionally hide the default text clock if pixelated clock is active
                            // The pixelated clock is drawn by ParticleRenderer directly on its canvas
                            child: simOptions.simulationConfig.usePixelatedClock
                                ? Container() // Empty container if pixelated clock is on
                                : Text(
                                    _currentTimeString,
                                    style: TextStyle(
                                      color: clockColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        );
                      },
                    ),
                  ),
                  SizedBox(
                    width: size.width,
                    height: size.height,
                    child: CustomPaint(painter: renderer),
                  ),
                  SizedBox(
                    width: size.width,
                    height: size.height,
                    child: AndroidView(
                      viewType: 'com.example.water_slosher_wearos/fluidSimulationNativeView',
                      onPlatformViewCreated: (id) {
                        _nativeViewId = id;
                        _fluidViewMethodChannel = MethodChannel('com.example.water_slosher_wearos/fluidSimulationNativeViewChannel_$id');
                        _fluidViewMethodChannel!.setMethodCallHandler(_handleNativeViewMethodCalls);
                        devLog.log("[SIM_SCREEN_DEBUG] onPlatformViewCreated: _isNativeTouchMode before call is: $_isNativeTouchMode. View ID: $id", name: 'SimulationScreen.PlatformView');
                        _updateNativeViewTouchInteractivity(_isNativeTouchMode);
                        devLog.log("[SIM_SCREEN_DEBUG] AndroidView created with ID: $id, MethodChannel initialized. _isNativeTouchMode at time of call was: $_isNativeTouchMode", name: 'SimulationScreen.PlatformView');
                      },
                      creationParams: {
                        'simWorldWidth': sim.worldWidth,
                        'simWorldHeight': sim.worldHeight,
                      },
                      creationParamsCodec: const StandardMessageCodec(),
                      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                        Factory<TapGestureRecognizer>(
                          () => TapGestureRecognizer()
                            ..onTap = !_isNativeTouchMode
                                ? () {
                                    devLog.log("Flutter Tap in Config Mode", name: 'SimulationScreen');
                                  }
                                : null,
                        ),
                        Factory<PanGestureRecognizer>(
                          () => PanGestureRecognizer()
                            ..onStart = !_isNativeTouchMode
                                ? (details) {
                                    setState(() => isTouching = true);
                                    sim.isObstacleActive = true;
                                    sim.obstacleRadius = simOptions.obstacleRadius;
                                    final Offset simCoords = _toSimCoords(details.localPosition);
                                    sim.setObstacle(simCoords.dx, simCoords.dy, true, simOptions.timeScale * (1 / 60.0));
                                    if (mounted) setState(() {});
                                  }
                                : null
                            ..onUpdate = !_isNativeTouchMode
                                ? (details) {
                                    if (!isTouching) return;
                                    final Offset simCoords = _toSimCoords(details.localPosition);
                                    sim.setObstacle(simCoords.dx, simCoords.dy, false, simOptions.timeScale * (1 / 60.0));
                                    if (mounted) setState(() {});
                                  }
                                : null
                            ..onEnd = !_isNativeTouchMode
                                ? (_) {
                                    setState(() => isTouching = false);
                                    sim.isObstacleActive = false;
                                    sim.initializeGrid();
                                    sim.obstacleVelX = 0.0;
                                    sim.obstacleVelY = 0.0;
                                    if (mounted) setState(() {});
                                  }
                                : null,
                        ),
                      },
                    ),
                  ),
                  Visibility(
                    visible: !_isNativeTouchMode,
                    child: Positioned(
                      top: 0, left: 0, right: 0,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        color: Colors.transparent,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Center(child: Text('Slosh O\'Clock', style: TextStyle(color: (isNight ? Colors.white : Colors.black).withOpacity(0.4), fontSize: 16, fontWeight: FontWeight.bold))),
                            // Day/Night button has been moved and its style updated
                          ],
                        ),
                      ),
                    ),
                  ),
                  Visibility(
                    visible: !_isNativeTouchMode,
                    child: Positioned(
                      bottom: 32, left: 0, right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FloatingActionButton(heroTag: 'start_stop', backgroundColor: Colors.blue.withOpacity(0.3), foregroundColor: Colors.white, child: Icon(running ? Icons.pause : Icons.play_arrow), onPressed: () => setState(() => running = !running)),
                          SizedBox(width: 24),
                          FloatingActionButton(heroTag: 'reset', backgroundColor: Colors.blue.withOpacity(0.3), foregroundColor: Colors.white, child: Icon(Icons.replay), onPressed: _resetSimulation),
                        ],
                      ),
                    ),
                  ),
                  Visibility(
                    visible: !_isNativeTouchMode,
                    child: Positioned(
                      top: 32.0, // Mirrored position from bottom buttons
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FloatingActionButton(
                            heroTag: 'turn_off_app',
                            backgroundColor: Colors.blue.withOpacity(0.3), foregroundColor: Colors.white,
                            // mini: true, // Removed to match size of other buttons
                            child: const Icon(Icons.power_settings_new),
                            onPressed: _turnOffApp,
                          ),
                          const SizedBox(width: 24),
                          FloatingActionButton(
                            heroTag: 'watch_style',
                            backgroundColor: Colors.blue.withOpacity(0.3), foregroundColor: Colors.white,
                            // mini: true, // Removed to match size of other buttons
                            child: const Icon(Icons.watch_later),
                            onPressed: _cycleWatchStyle,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // New Day/Night Toggle Button
                  Visibility(
                    visible: !_isNativeTouchMode, // Only visible in config mode
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 16.0), // Add some padding from the edge
                        child: IconButton(
                          icon: Icon(
                            isNight ? Icons.dark_mode : Icons.light_mode,
                            color: (isNight ? Colors.white : Colors.black).withOpacity(0.3), // Adjusted transparency
                            size: 30.0, // Slightly larger icon
                          ),
                          onPressed: () => setState(() => isNight = !isNight),
                        ),
                      ),
                    ),
                  ),
                  if (simOptions.debug && !_isNativeTouchMode)
                    Positioned(
                      top: 150, // Adjusted to be below new buttons if debug is on
                      left: _calculateCircularLeftOffset(size, 50),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'FPS: ${_fps.toStringAsFixed(1)}',
                            style: TextStyle(color: (isNight ? Colors.white : Colors.black).withOpacity(0.7), fontSize: 12),
                          ),
                          SizedBox(height: 2),
                          Text(
                            _temperature < -900
                                ? 'T: N/A'
                                : 'T: ${_temperature.toStringAsFixed(1)}°C',
                            style: TextStyle(color: (isNight ? Colors.white : Colors.black).withOpacity(0.7), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  if (_configErrorMessage != null)
                    Positioned(
                      bottom: _isNativeTouchMode ? 32 : 100,
                      left: 0, right: 0,
                      child: Center(
                        child: Material(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                            child: Text(
                              _configErrorMessage!,
                              style: TextStyle(color: Colors.white, fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class SimOptions {
  SimulationConfig simulationConfig; // Added field

  double timeScale = 1.0;
  double overRelax = 1.9;
  double flipRatio = 0.9;
  bool showParticles = true;
  bool showGrid = true;
  bool compensateDrift = true;
  bool separateParticles = true;
  int pressureIters = 30;
  int particleIters = 2;
  int particleCount = 1500;
  double obstacleRadius = 0.15;
  double particleRadiusRatio = 0.3;
  double gravityMagnitude = 9.81;
  int cellsWide = 64;
  double renderScale = 1.0;
  bool debug = false;
  bool enableDynamicColoring = false; // Added field
  double intensityMin = 0.0; // Default min intensity for particle color
  double intensityMax = 150.0; // Default max intensity for particle color

  SimOptions({SimulationConfig? initialConfig})
      : simulationConfig = initialConfig ?? SimulationConfig(
          // Provide default values for SimulationConfig if not passed
          // These should match the defaults in SimulationConfig constructor or be sensible.
          density: 1000.0,
          cellsWide: 60, // Default from SimulationConfig
          particleRadius: 0.025, // Default from SimulationConfig
          maxParticles: 5000, // Default from SimulationConfig
          obstacleRadius: 0.15, // Default from SimulationConfig
          gravityX: 0.0, // Default from SimulationConfig
          gravityY: -9.81, // Default from SimulationConfig
          flipRatio: 0.9, // Default from SimulationConfig
          numPressureIters: 50, // Default from SimulationConfig
          numParticleIters: 2, // Default from SimulationConfig
          overRelaxation: 1.9, // Default from SimulationConfig
          compensateDrift: true, // Default from SimulationConfig
          separateParticles: true, // Default from SimulationConfig
          enableDynamicColoring: false, // Default from SimulationConfig
          usePixelatedClock: false, // Default
        );
}