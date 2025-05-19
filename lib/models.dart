
import 'pixel_clock_style.dart';

class SimulationConfig {
  // Config for the pixelated clock style, if used.
  // This is not part of the JSON config for now.
  final PixelClockConfig pixelClockConfig;
  final bool usePixelatedClock;

  final double density;
  final int cellsWide;
  final double particleRadius;
  final int maxParticles;
  final double obstacleRadius;
  final double gravityX;
  final double gravityY;
  final double flipRatio;
  final int numPressureIters;
  final int numParticleIters;
  final double overRelaxation;
  final bool compensateDrift;
  final bool separateParticles;
  final bool enableDynamicColoring; // New field for dynamic coloring

  SimulationConfig({
    PixelClockConfig? customPixelClockConfig, // Allow providing a custom config
    this.usePixelatedClock = false, // Default to smooth clock
    required this.density,
    required this.cellsWide,
    required this.particleRadius,
    required this.maxParticles,
    required this.obstacleRadius,
    required this.gravityX,
    required this.gravityY,
    required this.flipRatio,
    required this.numPressureIters,
    required this.numParticleIters,
    required this.overRelaxation,
    required this.compensateDrift,
    required this.separateParticles,
    this.enableDynamicColoring = false, // Default to false
    // pixelClockConfig and usePixelatedClock are not included in fromJson/toJson for now
  }) : pixelClockConfig = customPixelClockConfig ?? const PixelClockConfig(); // Use provided or default

  factory SimulationConfig.fromJson(Map<String, dynamic> json) {
    return SimulationConfig(
      // pixelClockConfig and usePixelatedClock are initialized with defaults
      // and not read from JSON for now.
      density: (json['density'] as num?)?.toDouble() ?? 1000.0,
      cellsWide: (json['cellsWide'] as num?)?.toInt() ?? 60,
      particleRadius: (json['particleRadius'] as num?)?.toDouble() ?? 0.025,
      maxParticles: (json['maxParticles'] as num?)?.toInt() ?? 5000,
      obstacleRadius: (json['obstacleRadius'] as num?)?.toDouble() ?? 0.15,
      gravityX: (json['gravityX'] as num?)?.toDouble() ?? 0.0,
      gravityY: (json['gravityY'] as num?)?.toDouble() ?? -9.81,
      flipRatio: (json['flipRatio'] as num?)?.toDouble() ?? 0.9,
      numPressureIters: (json['numPressureIters'] as num?)?.toInt() ?? 50,
      numParticleIters: (json['numParticleIters'] as num?)?.toInt() ?? 2,
      overRelaxation: (json['overRelaxation'] as num?)?.toDouble() ?? 1.9,
      compensateDrift: json['compensateDrift'] as bool? ?? true,
      separateParticles: json['separateParticles'] as bool? ?? true,
      enableDynamicColoring: json['enableDynamicColoring'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    // pixelClockConfig and usePixelatedClock are not included in toJson for now
    return {
      'density': density,
      'cellsWide': cellsWide,
      'particleRadius': particleRadius,
      'maxParticles': maxParticles,
      'obstacleRadius': obstacleRadius,
      'gravityX': gravityX,
      'gravityY': gravityY,
      'flipRatio': flipRatio,
      'numPressureIters': numPressureIters,
      'numParticleIters': numParticleIters,
      'overRelaxation': overRelaxation,
      'compensateDrift': compensateDrift,
      'separateParticles': separateParticles,
      'enableDynamicColoring': enableDynamicColoring,
    };
  }
}