import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/utils/height_utils.dart';

void main() {
  group('cmToFeetInches', () {
    test('0 cm → 0\'0"', () => expect(cmToFeetInches(0), (0, 0)));
    test('30 cm → 0\'12" rounds to 1\'0"', () {
      // 30 / 2.54 = 11.81 → 12 inches = 1 foot
      expect(cmToFeetInches(30), (1, 0));
    });
    test('173 cm (default 5\'8")', () => expect(cmToFeetInches(173), (5, 8)));
    test('180 cm → 5\'11"', () => expect(cmToFeetInches(180), (5, 11)));
    test('152 cm → 5\'0"', () => expect(cmToFeetInches(152), (5, 0)));
    test('160 cm → 5\'3"', () => expect(cmToFeetInches(160), (5, 3)));
  });

  group('feetInchesToCm', () {
    test('0\'0" → 0 cm', () => expect(feetInchesToCm(0, 0), 0));
    test('5\'8" → 173 cm', () => expect(feetInchesToCm(5, 8), 173));
    test('5\'11" → 180 cm', () => expect(feetInchesToCm(5, 11), 180));
    test('5\'0" → 152 cm', () => expect(feetInchesToCm(5, 0), 152));
    test('6\'0" → 183 cm', () => expect(feetInchesToCm(6, 0), 183));
  });

  group('round-trip', () {
    for (final cm in [152, 160, 165, 170, 173, 175, 180, 183, 188]) {
      test('$cm cm survives feetInchesToCm(cmToFeetInches())', () {
        final (f, i) = cmToFeetInches(cm);
        expect(feetInchesToCm(f, i), cm);
      });
    }
  });

  group('formatHeightCm', () {
    test('173 cm → 5\'8"', () => expect(formatHeightCm(173), '5\'8"'));
    test('180 cm → 5\'11"', () => expect(formatHeightCm(180), '5\'11"'));
    test('152 cm → 5\'0"', () => expect(formatHeightCm(152), '5\'0"'));
  });

  group('defaultHeightCm', () {
    test('is 173 (5\'8")', () {
      expect(defaultHeightCm, 173);
      expect(cmToFeetInches(defaultHeightCm), (5, 8));
    });
  });
}
