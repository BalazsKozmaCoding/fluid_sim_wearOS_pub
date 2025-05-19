// Defines the configuration for the pixelated clock style.
class PixelClockConfig {
  // The size (width and height) of each individual "pixel" block in logical units.
  final double pixelSize;

  // The spacing between adjacent "pixels" in logical units.
  final double pixelSpacing;

  // The target width of a standard digit (0-9) in terms of the number of "clock pixels" after scaling.
  final int targetDigitPixelWidth;

  // The target height of a standard digit (0-9) and the colon in terms of "clock pixels" after scaling.
  final int targetDigitPixelHeight;

  // The target width of the colon (':') character in terms of "clock pixels" after scaling.
  final int targetColonPixelWidth;

  // The spacing between characters (e.g., between 'H' and 'H', or 'M' and 'M', or ':' and 'M')
  // in terms of the number of pixel units (not logical units).
  final int characterSpacingPixels;

  const PixelClockConfig({
    this.pixelSize = 5.0, // Base size, effectivePixelSize will be calculated
    this.pixelSpacing = 1.0,
    this.targetDigitPixelWidth = 10, // 7H x 5W master -> 28H x 20W target
    this.targetDigitPixelHeight = 14, // Adjusted for 7-row master pattern
    this.targetColonPixelWidth = 5,  // 7H x 4W master -> 28H x 16W target
    this.characterSpacingPixels = 2, // Increased spacing
  });
}