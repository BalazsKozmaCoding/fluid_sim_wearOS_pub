import 'package:flutter/material.dart';
import 'dart:ui' as ui; // Import for PointMode, Vertices, VertexMode, ui.Image
import 'dart:typed_data'; // Import for Float32List, Int32List
import 'simulation_screen.dart'; // Import SimOptions
import 'flip_fluid_simulation.dart';
import 'dart:math' as math;
import 'clock_utils.dart'; // Added for pixel clock patterns
import 'pixel_clock_style.dart'; // Added for pixel clock config
import 'models.dart'; // Added for SimulationConfig

class ParticleRenderer extends CustomPainter {
  final FlipFluidSimulation sim;
  final ui.Image? particleAtlas; // Add particle atlas field
  late SimOptions simOptions; // simulation options
  bool showTouchCircle = false;            // draw the obstacle circle
  bool isNight = true; // track day/night mode

  ParticleRenderer(this.sim, {this.particleAtlas}); // Update constructor

  @override
  void paint(Canvas canvas, Size size) {
    // Draw pixelated clock as background if enabled
    if (simOptions.simulationConfig.usePixelatedClock) {
      _drawPixelatedTimeBackground(canvas, size, simOptions.simulationConfig.pixelClockConfig);
    } else {
      // Placeholder: If there was a smooth clock drawing logic here, it would go here.
      // For now, the task is to add the pixelated one as an alternative.
      // If the smooth clock is drawn elsewhere (e.g., by a Text widget on top),
      // then this 'else' might not be needed in this painter.
    }

    final double simWidth = sim.fNumX * sim.h;
    final double simHeight = sim.fNumY * sim.h;

    // Calculate uniform scale to fit sim aspect ratio into screen size
    final double scale = math.min(size.width / simWidth, size.height / simHeight);
    final double renderedSimWidth = simWidth * scale;
    final double renderedSimHeight = simHeight * scale;

    // Calculate offsets to center the simulation on the canvas
    final double offsetX = (size.width - renderedSimWidth) / 2.0;
    final double offsetY = (size.height - renderedSimHeight) / 2.0;

    // --- Apply renderScale ---
    final double centerX = offsetX + renderedSimWidth / 2.0;
    final double centerY = offsetY + renderedSimHeight / 2.0;
    canvas.save();
    canvas.translate(centerX, centerY);
    canvas.scale(simOptions.renderScale, simOptions.renderScale); // Use renderScale from SimOptions
    canvas.translate(-centerX, -centerY);
    // --- End Apply renderScale ---

    // Draw grid if enabled (now within the scaled canvas state)
    if (simOptions.showGrid) {
      final double cellScreenSize = sim.h * scale;
      // Use strokeWidth for point size
      final cellPaint = Paint()
        ..strokeCap = StrokeCap.square // Keep square for grid cells
        ..strokeWidth = 1.05 * cellScreenSize; // Point size

      // Group grid points by color
      final Map<Color, List<Offset>> gridPointsByColor = {};

      for (int i = 0; i < sim.fNumX; i++) {
        for (int j = 0; j < sim.fNumY; j++) {
          final int cellIndex = i * sim.fNumY + j;
          final int colorIndex = 3 * cellIndex;

          bool isAirLike = sim.cellType[cellIndex] == FlipFluidSimulation.AIR_CELL &&
                           sim.particleDensity[cellIndex] < 0.1 * sim.particleRestDensity;

          if (sim.cellType[cellIndex] == FlipFluidSimulation.SOLID_CELL || !isAirLike) {
             final double r = sim.cellColor[colorIndex];
             final double g = sim.cellColor[colorIndex + 1];
             final double b = sim.cellColor[colorIndex + 2];

             if (r == 0.0 && g == 0.0 && b == 0.0 && sim.cellType[cellIndex] != FlipFluidSimulation.SOLID_CELL) {
                 continue;
             }

            final double simCellCenterX = (i + 0.5) * sim.h;
            final double simCellCenterY = (j + 0.5) * sim.h;

            // Apply uniform scale and centering offset
            // Sim Y=0 is bottom, Screen Y=0 is top
            final double screenX = offsetX + simCellCenterX * scale;
            final double screenY = offsetY + (simHeight - simCellCenterY) * scale;

            final Color color;
            if (sim.cellType[cellIndex] != FlipFluidSimulation.SOLID_CELL) {
              if (simOptions.enableDynamicColoring) {
                // Use r, g, b from sim.cellColor for fluid cells, maintaining 0.5 opacity
                color = Color.fromRGBO(
                  (r * 255).round(),
                  (g * 255).round(),
                  (b * 255).round(),
                  0.5, // Maintain 50% opacity for fluid grid cells
                );
              } else {
                // Use constant light blue color for fluid cells if dynamic coloring is disabled
                color = (Colors.lightBlueAccent[200] ?? Colors.lightBlueAccent).withOpacity(0.75);
              }
            } else {
              // Keep original color for solid cells
              // r, g, b are defined earlier (lines 50-52)
              color = Color.fromRGBO(
                (r * 255).round(),
                (g * 255).round(),
                (b * 255).round(),
                1.0,
              );
            }

            // Add point to the list for its color
            (gridPointsByColor[color] ??= []).add(Offset(screenX, screenY));
          }
        }
      }

      // Draw grid points grouped by color
      gridPointsByColor.forEach((color, points) {
        if (points.isNotEmpty) {
          // Convert List<Offset> to Float32List for drawRawPoints
          final pointBuffer = Float32List(points.length * 2);
          for (int k = 0; k < points.length; k++) {
            pointBuffer[k * 2] = points[k].dx;
            pointBuffer[k * 2 + 1] = points[k].dy;
          }
          cellPaint.color = color;
          canvas.drawRawPoints(ui.PointMode.points, pointBuffer, cellPaint);
        }
      });
    }

    // Draw particles if enabled
    if (simOptions.showParticles) {
      final int particleCount = sim.numParticles;
      if (particleCount > 0) {
        // --- New logic: Group particles by actual quantized color and use drawRawPoints ---
        final double particleDiameter = sim.particleRadius * scale * 2.0;
        final particlePaint = Paint()
          ..strokeCap = StrokeCap.square
          ..strokeWidth = particleDiameter;

        // Group particle points by their actual quantized color
        final Map<Color, List<Offset>> particlePointsByColor = {};

        for (int i = 0; i < particleCount; i++) {
          final double px = sim.particlePos[2 * i];
          final double py = sim.particlePos[2 * i + 1];
          final int colorIndex = 4 * i; // Changed for RGBA

          final double rFloat = sim.particleColor[colorIndex];
          final double gFloat = sim.particleColor[colorIndex + 1];
          final double bFloat = sim.particleColor[colorIndex + 2];
          final double aFloat = sim.particleColor[colorIndex + 3]; // Alpha component

          // New color logic: interpolate between particleDeepBlue and gridCellBlue
          // Define the two main colors for interpolation
          final Color deepBlue = Colors.blueAccent[700] ?? Colors.blueAccent; // Opaque Dark Blue
          final Color surfaceBlue = Colors.blueAccent[100] ?? Colors.blueAccent; // Color(0xFFADD8E6) -> (173, 216, 230)

          // Assume rFloat (from sim.particleColor[colorIndex]) is the primary factor for interpolation (0.0 to 1.0).
          // This 'interpolationFactorRaw' corresponds to 'alpha' in the user's formula before quantization.
          double interpolationFactorRaw = rFloat; // Using rFloat as the source for the grade.
                                                 // Consider if gFloat, bFloat, or an average might be more suitable
                                                 // depending on how sim.particleColor stores the "grade".

          // Quantization of interpolationFactorRaw
          const int numColorBuckets = 5; // Example: 5 buckets means 5 distinct colors.
                                         // Interpolation factor values will be 0.0, 0.25, 0.5, 0.75, 1.0
                                         // This could be made configurable via simOptions later.

          double quantizedInterpolationFactor;
          if (numColorBuckets <= 1) {
            // If 1 or fewer buckets, default to particleDeepBlue (or handle as a single color scenario)
            quantizedInterpolationFactor = 1.0;
          } else {
            // Map interpolationFactorRaw (0-1) to a bucket index (0 to numColorBuckets-1)
            int bucketIndex = (interpolationFactorRaw * (numColorBuckets - 1)).round();
            // Clamp bucketIndex to ensure it's within the valid range [0, numColorBuckets-1]
            bucketIndex = bucketIndex.clamp(0, numColorBuckets - 1);
            quantizedInterpolationFactor = bucketIndex / (numColorBuckets - 1.0);
          }

          // RGB components of the fixed colors (alpha is handled separately)
          final int rDeep = deepBlue.red;
          final int gDeep = deepBlue.green;
          final int bDeep = deepBlue.blue;

          final int rGrid = surfaceBlue.red;
          final int gGrid = surfaceBlue.green;
          final int bGrid = surfaceBlue.blue;

          // Interpolate RGB components based on the user's formula (reversed as per feedback):
          // (1-alpha_q) * RGB_deep + alpha_q * RGB_grid
          final int rFinal = ((1.0 - quantizedInterpolationFactor) * rDeep + quantizedInterpolationFactor * rGrid).round();
          final int gFinal = ((1.0 - quantizedInterpolationFactor) * gDeep + quantizedInterpolationFactor * gGrid).round();
          final int bFinal = ((1.0 - quantizedInterpolationFactor) * bDeep + quantizedInterpolationFactor * bGrid).round();

          // Create the final particle color, applying a consistent alpha (e.g., 200 from original code)
          final Color particleColor = Color.fromARGB(
            200, // Consistent alpha for all particles, as in the original code
            rFinal.clamp(0, 255), // Ensure RGB values are within the valid 0-255 range
            gFinal.clamp(0, 255),
            bFinal.clamp(0, 255),
          );

          final double sx = offsetX + px * scale;
          final double sy = offsetY + (simHeight - py) * scale; // Y-flip

          (particlePointsByColor[particleColor] ??= []).add(Offset(sx, sy));
        }

        // Draw particle points grouped by color
        particlePointsByColor.forEach((color, points) {
          if (points.isNotEmpty) {
            particlePaint.color = color;
            final pointBuffer = Float32List(points.length * 2);
            for (int k = 0; k < points.length; k++) {
              pointBuffer[k * 2] = points[k].dx;
              pointBuffer[k * 2 + 1] = points[k].dy;
            }
            canvas.drawRawPoints(ui.PointMode.points, pointBuffer, particlePaint);
          }
        });
        // --- End new logic ---
      }
    }

    // --- Restore canvas before drawing UI elements ---
    canvas.restore();
    // --- End Restore canvas ---

    // Draw touch-obstacle circle when finger is down (drawn outside the scaled state)
    if (showTouchCircle) {
      // Apply uniform scale and centering offset to obstacle position
      // Sim Y=0 is bottom, Screen Y=0 is top
      final double sx = offsetX + sim.obstacleX * scale;
      final double sy = offsetY + (simHeight - sim.obstacleY) * scale;
      
      final double r_sim = sim.obstacleRadius + sim.particleRadius;
      final double r_screen  = r_sim * scale; // Use uniform scale for radius

      // filled semi-transparent blue
      final paintFill = Paint()
        ..color = Colors.blue.withOpacity(0.35)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(sx, sy), r_screen, paintFill);

      // bright border
      final paintStroke = Paint()
        ..color = Colors.blueAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(Offset(sx, sy), r_screen, paintStroke);
    }
  }

  @override
  bool shouldRepaint(ParticleRenderer old) => true;

  void _drawPixelatedTimeBackground(Canvas canvas, Size size, PixelClockConfig baseClockConfig) {
    DateTime now = DateTime.now();
    String timeText = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

    // 1. Calculate Adjusted Metrics
    final AdjustedClockMetrics metrics = calculateAdjustedClockMetrics(
      config: baseClockConfig,
      displayWidth: size.width,
      displayHeight: size.height,
    );

    final double effectivePixelSize = metrics.effectivePixelSize;
    final double effectivePixelSpacing = metrics.effectivePixelSpacing;
    // configForPatternScaling is the original baseClockConfig, used for structural properties.
    final PixelClockConfig configForPatternScaling = metrics.originalConfig;

    // 2. Get Total Clock Dimensions for Centering
    final CalculatedDimensions clockDimensions = getClockTotalDimensions(
      config: configForPatternScaling, // Use the original config for structural properties
      effectivePixelSize: effectivePixelSize,
      // effectivePixelSpacing is implicitly used via config.pixelSpacing inside getClockTotalDimensions
    );

    final double totalVisualWidth = clockDimensions.totalWidth;
    final double totalVisualHeight = clockDimensions.totalHeight;

    // Centering the clock on the canvas
    double startX = (size.width - totalVisualWidth) / 2;
    double startY = (size.height - totalVisualHeight) / 2;

    final Paint pixelPaint = Paint()..color = (isNight ? Colors.white : Colors.black87);

    // blockVisualWidth is the width one "cell" of a character's pixel grid takes up on screen
    final double blockVisualWidth = effectivePixelSize + effectivePixelSpacing;
    final double blockVisualHeight = effectivePixelSize + effectivePixelSpacing;

    double currentX = startX;

    for (int charIdx = 0; charIdx < timeText.length; charIdx++) {
      String charStr = timeText[charIdx];
      // Generate the scaled pattern using the original config's structural properties
      List<List<int>> scaledPattern = generateScaledCharacterPattern(charStr, configForPatternScaling);

      int charPatternPixelHeight = scaledPattern.length; // Height from the pattern (e.g., 7 for master, targetDigitPixelHeight for scaled)
      int charPatternPixelWidth = (scaledPattern.isNotEmpty) ? scaledPattern[0].length : 0; // Width from the pattern

      if (charPatternPixelWidth == 0 || charPatternPixelHeight == 0) continue;

      for (int r = 0; r < charPatternPixelHeight; r++) {
        List<int> rowPattern = scaledPattern[r];
        for (int c = 0; c < charPatternPixelWidth; c++) {
          if (rowPattern[c] == 1) {
            final Rect pixelRect = Rect.fromLTWH(
              currentX + c * blockVisualWidth,
              startY + r * blockVisualHeight, // startY is the top of the whole clock block
              effectivePixelSize, // The visible part of the block
              effectivePixelSize, // The visible part of the block
            );
            canvas.drawRect(pixelRect, pixelPaint);
          }
        }
      }
      // Advance currentX by the width of the character just drawn
      currentX += charPatternPixelWidth * blockVisualWidth;

      if (charIdx < timeText.length - 1) { // If not the last character
        // Add spacing based on configured pixel units (from original config) and effective sizes
        currentX += configForPatternScaling.characterSpacingPixels * blockVisualWidth;
      }
    }
  }
}