import 'dart:math' as math;
import 'pixel_clock_style.dart'; // For PixelClockConfig

// Utility functions and data structures for clock rendering.

// Defines the MASTER pixel patterns for digits 0-9 and the colon.
// Each pattern is a list of lists, representing rows and columns.
// A '1' indicates a pixel is "on", and a '0' indicates it's "off".
// These are based on a 7-row height.
// Digit width is 5 pixels, Colon width is 3 pixels.
const Map<String, List<List<int>>> kPixelDigitPatterns = {
  '0': [
    [0, 1, 1, 1, 0],
    [1, 1, 0, 1, 1],
    [1, 1, 0, 1, 1],
    [1, 1, 0, 1, 1],
    [1, 1, 0, 1, 1],
    [1, 1, 0, 1, 1],
    [0, 1, 1, 1, 0]
  ],
  '1': [
    [0, 0, 1, 1, 0],
    [0, 1, 1, 1, 0],
    [0, 0, 1, 1, 0],
    [0, 0, 1, 1, 0],
    [0, 0, 1, 1, 0],
    [0, 0, 1, 1, 0],
    [0, 1, 1, 1, 1]
  ],
  '2': [
    [0, 1, 1, 1, 0],
    [1, 1, 0, 1, 1],
    [0, 0, 0, 1, 1],
    [0, 0, 1, 1, 0],
    [0, 1, 1, 0, 0],
    [1, 1, 0, 0, 0],
    [1, 1, 1, 1, 1]
  ],
  '3': [
    [0, 1, 1, 1, 0],
    [1, 1, 0, 1, 1],
    [0, 0, 0, 1, 1],
    [0, 0, 1, 1, 1],
    [0, 0, 0, 1, 1],
    [1, 1, 0, 1, 1],
    [0, 1, 1, 1, 0]
  ],
  '4': [
    [1, 1, 0, 1, 1],
    [1, 1, 0, 1, 1],
    [1, 1, 0, 1, 1],
    [1, 1, 1, 1, 1],
    [0, 0, 0, 1, 1],
    [0, 0, 0, 1, 1],
    [0, 0, 0, 1, 1]
  ],
  '5': [
    [1, 1, 1, 1, 1],
    [1, 1, 0, 0, 0],
    [1, 1, 1, 1, 0],
    [0, 0, 0, 1, 1],
    [0, 0, 0, 1, 1],
    [1, 1, 0, 1, 1],
    [0, 1, 1, 1, 0]
  ],
  '6': [
    [0, 1, 1, 1, 0],
    [1, 1, 0, 0, 0],
    [1, 1, 0, 0, 0],
    [1, 1, 1, 1, 0],
    [1, 1, 0, 1, 1],
    [1, 1, 0, 1, 1],
    [0, 1, 1, 1, 0]
  ],
  '7': [
    [1, 1, 1, 1, 1],
    [0, 0, 0, 1, 1],
    [0, 0, 1, 1, 0],
    [0, 0, 1, 1, 0],
    [0, 1, 1, 0, 0],
    [0, 1, 1, 0, 0],
    [0, 1, 1, 0, 0]
  ],
  '8': [
    [0, 1, 1, 1, 0],
    [1, 1, 0, 1, 1],
    [1, 1, 0, 1, 1],
    [0, 1, 1, 1, 0],
    [1, 1, 0, 1, 1],
    [1, 1, 0, 1, 1],
    [0, 1, 1, 1, 0]
  ],
  '9': [
    [0, 1, 1, 1, 0],
    [1, 1, 0, 1, 1],
    [1, 1, 0, 1, 1],
    [0, 1, 1, 1, 1],
    [0, 0, 0, 1, 1],
    [0, 0, 0, 1, 1],
    [0, 1, 1, 1, 0]
  ],
  ':': [ // Master 7H x 4W for colon, with 2x2 dots
    [0, 0, 0, 0],
    [0, 1, 1, 0],
    [0, 1, 1, 0],
    [0, 0, 0, 0],
    [0, 1, 1, 0],
    [0, 1, 1, 0],
    [0, 0, 0, 0]
  ],
};

// Generates a character pattern scaled to the target dimensions specified in PixelClockConfig.
// This uses nearest-neighbor style resampling.
List<List<int>> generateScaledCharacterPattern(String char, PixelClockConfig config) {
  final List<List<int>>? masterPattern = kPixelDigitPatterns[char];

  if (masterPattern == null || masterPattern.isEmpty || masterPattern[0].isEmpty) {
    // Return an empty pattern or a default placeholder if char is not found or master is invalid
    int fallbackWidth = (char == ':') ? config.targetColonPixelWidth : config.targetDigitPixelWidth;
    fallbackWidth = math.max(1, fallbackWidth); // Ensure at least 1x1
    int fallbackHeight = math.max(1, config.targetDigitPixelHeight);
    return List.generate(fallbackHeight, (_) => List.filled(fallbackWidth, 0));
  }

  final int masterH = masterPattern.length;
  final int masterW = masterPattern[0].length;

  int targetW, targetH;
  if (char == ':') {
    targetW = config.targetColonPixelWidth;
    targetH = config.targetDigitPixelHeight; // Colon height usually matches digit height
  } else {
    targetW = config.targetDigitPixelWidth;
    targetH = config.targetDigitPixelHeight;
  }
  
  // Ensure target dimensions are at least 1x1 to avoid issues with empty lists or division by zero
  targetW = math.max(1, targetW);
  targetH = math.max(1, targetH);


  final List<List<int>> newPattern = [];
  for (int r = 0; r < targetH; r++) {
    final List<int> row = [];
    for (int c = 0; c < targetW; c++) {
      // Calculate corresponding source pixel in the master pattern
      // Equivalent to: Math.floor(r * masterH / targetH)
      // but ensuring it doesn't exceed masterH-1 due to potential floating point inaccuracies at the boundary.
      final int sourceR = math.min(masterH - 1, (r * masterH / targetH).floor());
      final int sourceC = math.min(masterW - 1, (c * masterW / targetW).floor());
      row.add(masterPattern[sourceR][sourceC]);
    }
    newPattern.add(row);
  }
  return newPattern;
}
// Appended by Roo: Utility classes and functions for dynamic clock sizing.

/// Holds the effective pixel metrics after adjusting for display constraints.
class AdjustedClockMetrics {
  /// The calculated pixel size to make the clock fit the constraints.
  final double effectivePixelSize;

  /// The pixel spacing to be used (taken from the original config).
  final double effectivePixelSpacing;

  /// The original configuration, useful for accessing other parameters like
  /// targetDigitPixelWidth, targetDigitPixelHeight, etc.
  final PixelClockConfig originalConfig;

  AdjustedClockMetrics({
    required this.effectivePixelSize,
    required this.effectivePixelSpacing,
    required this.originalConfig,
  });
}

/// Calculates adjusted pixel metrics for the clock to fit within given display constraints.
///
/// The clock is assumed to display "HH:MM" format.
/// It aims to fit within 80% of the display width and 50% of the display height.
/// The `pixelSpacing` from the `config` is treated as a fixed value.
///
/// Args:
///   config: The base PixelClockConfig.
///   displayWidth: The total width of the display area.
///   displayHeight: The total height of the display area.
///
/// Returns:
///   An AdjustedClockMetrics object with the effectivePixelSize and effectivePixelSpacing.
AdjustedClockMetrics calculateAdjustedClockMetrics({
  required PixelClockConfig config,
  required double displayWidth,
  required double displayHeight,
}) {
  final double availableWidth = displayWidth * 0.80;
  final double availableHeight = displayHeight * 0.50;

  final int dpw = config.targetDigitPixelWidth;
  final int dph = config.targetDigitPixelHeight;
  final int cpw = config.targetColonPixelWidth;
  final int csp = config.characterSpacingPixels; // Number of pixelSize units for inter-character space

  final double configuredPixelSpacing = config.pixelSpacing;

  // For "HH:MM" format: 4 digits, 1 colon, 4 inter-character spaces.

  // Coefficient of effectivePixelSize for total width:
  // Sum of pixel widths from digits, colon, and character spaces.
  final double widthCoeffPs = (4.0 * dpw) + (1.0 * cpw) + (4.0 * csp);

  // Constant term for total width (from pixelSpacing within digits/colon):
  double widthConstPsp = 0;
  if (dpw > 1) { // Each of the 4 digits has (dpw - 1) internal spaces
    widthConstPsp += 4.0 * (dpw - 1);
  }
  if (cpw > 1) { // The colon has (cpw - 1) internal spaces
    widthConstPsp += 1.0 * (cpw - 1);
  }
  widthConstPsp *= configuredPixelSpacing;

  // Coefficient of effectivePixelSize for total height (from one digit/colon):
  final double heightCoeffPs = dph.toDouble();

  // Constant term for total height (from pixelSpacing within one digit/colon):
  double heightConstPsp = 0;
  if (dph > 1) {
    heightConstPsp = (dph - 1).toDouble();
  }
  heightConstPsp *= configuredPixelSpacing;

  double psFromWidth = double.maxFinite;
  if (widthCoeffPs > 0.000001) { // Avoid division by zero or near-zero
    if (availableWidth >= widthConstPsp) {
      psFromWidth = (availableWidth - widthConstPsp) / widthCoeffPs;
    } else {
      // Fixed spacing alone is too large for available width.
      psFromWidth = 0.1; // Make pixels tiny, indicating a fit issue with given spacing.
    }
  } else if (availableWidth < widthConstPsp) {
    // No variable pixel part (widthCoeffPs is zero), but fixed spacing is too large.
    psFromWidth = 0.1;
  }


  double psFromHeight = double.maxFinite;
  if (heightCoeffPs > 0.000001) { // Avoid division by zero or near-zero
    if (availableHeight >= heightConstPsp) {
      psFromHeight = (availableHeight - heightConstPsp) / heightCoeffPs;
    } else {
      // Fixed spacing alone is too large for available height.
      psFromHeight = 0.1;
    }
  } else if (availableHeight < heightConstPsp) {
    // No variable pixel part (heightCoeffPs is zero), but fixed spacing is too large.
    psFromHeight = 0.1;
  }

  double finalPixelSize = math.min(psFromWidth, psFromHeight);
  // Ensure pixel size is positive and practical, even if calculated as very small or negative.
  finalPixelSize = math.max(0.1, finalPixelSize);

  return AdjustedClockMetrics(
    effectivePixelSize: finalPixelSize,
    effectivePixelSpacing: configuredPixelSpacing, // Use original spacing from config
    originalConfig: config,
  );
}

/// Helper class to store calculated total dimensions of the clock.
class CalculatedDimensions {
  final double totalWidth;
  final double totalHeight;
  CalculatedDimensions({required this.totalWidth, required this.totalHeight});
}

/// Calculates the total visual dimensions of the clock given an effective pixel size.
/// This is useful for centering the clock on the display.
///
/// Args:
///   config: The original PixelClockConfig.
///   effectivePixelSize: The calculated effective pixel size to be used for rendering.
///
/// Returns:
///   A CalculatedDimensions object with the totalWidth and totalHeight.
CalculatedDimensions getClockTotalDimensions({
  required PixelClockConfig config,
  required double effectivePixelSize,
}) {
  final int dpw = config.targetDigitPixelWidth;
  final int dph = config.targetDigitPixelHeight;
  final int cpw = config.targetColonPixelWidth;
  final int csp = config.characterSpacingPixels;
  final double psp = config.pixelSpacing; // This is the effectivePixelSpacing

  // Total width calculation using effectivePixelSize
  // Contribution from pixelSize blocks:
  double totalWidth = effectivePixelSize * ((4.0 * dpw) + (1.0 * cpw) + (4.0 * csp));
  // Contribution from internal spacing:
  double widthSpacingContribution = 0;
  if (dpw > 1) widthSpacingContribution += 4.0 * (dpw - 1);
  if (cpw > 1) widthSpacingContribution += 1.0 * (cpw - 1);
  totalWidth += widthSpacingContribution * psp;

  // Total height calculation using effectivePixelSize
  // Contribution from pixelSize blocks:
  double totalHeight = effectivePixelSize * dph.toDouble();
  // Contribution from internal spacing:
  double heightSpacingContribution = 0;
  if (dph > 1) heightSpacingContribution = (dph - 1).toDouble();
  totalHeight += heightSpacingContribution * psp;
  
  return CalculatedDimensions(totalWidth: totalWidth, totalHeight: totalHeight);
}