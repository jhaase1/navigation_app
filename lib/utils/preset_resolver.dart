import '../models/height_range.dart';
import '../models/person.dart';
import 'height_utils.dart';

/// Resolves the camera preset index for [person] at [positionId] on [cameraIp].
///
/// Lookup order:
///   1. Person's explicit override in [person.positionPresets]
///   2. Matching [HeightRange] by person height (defaulting to [defaultHeightCm])
///   3. null — no preset available
int? resolvePreset({
  required Person person,
  required String positionId,
  required String cameraIp,
  required List<HeightRange> heightRanges,
}) {
  // 1. Personal override
  final override = person.positionPresets[positionId]?[cameraIp];
  if (override != null) return override;

  // 2. Height-range lookup
  final h = person.heightCm ?? defaultHeightCm;
  final sorted = [...heightRanges]..sort((a, b) {
      if (a.maxHeightCm == null && b.maxHeightCm == null) return 0;
      if (a.maxHeightCm == null) return 1;
      if (b.maxHeightCm == null) return -1;
      return a.maxHeightCm!.compareTo(b.maxHeightCm!);
    });

  for (final range in sorted) {
    if (range.maxHeightCm == null || h <= range.maxHeightCm!) {
      return range.positionPresets[positionId]?[cameraIp];
    }
  }

  return null;
}
