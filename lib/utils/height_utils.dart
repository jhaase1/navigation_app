const int defaultHeightCm = 173; // 5'8"

/// Convert centimetres to (feet, inches). Rounds to nearest inch.
(int feet, int inches) cmToFeetInches(int cm) {
  final totalInches = (cm / 2.54).round();
  return (totalInches ~/ 12, totalInches % 12);
}

/// Convert feet + inches to centimetres (rounded to nearest cm).
int feetInchesToCm(int feet, int inches) =>
    ((feet * 12 + inches) * 2.54).round();

/// Format as a display string, e.g. 175 cm → "5'9""
String formatHeightCm(int cm) {
  final (feet, inches) = cmToFeetInches(cm);
  return "$feet'$inches\"";
}
