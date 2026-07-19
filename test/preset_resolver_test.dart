import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/models/height_range.dart';
import 'package:navigation_app/models/person.dart';
import 'package:navigation_app/utils/height_utils.dart';
import 'package:navigation_app/utils/preset_resolver.dart';

const _posId = 'pos1';
const _camIp = '10.0.0.1';

int? _resolve(Person person, List<HeightRange> ranges) =>
    resolvePreset(person: person, positionId: _posId, cameraIp: _camIp, heightRanges: ranges);

HeightRange _range({
  required String id,
  required String name,
  int? maxHeightCm,
  int? preset,
}) =>
    HeightRange(
      id: id,
      name: name,
      maxHeightCm: maxHeightCm,
      positionPresets: preset != null
          ? {_posId: {_camIp: preset}}
          : {},
    );

void main() {
  group('resolvePreset — no data', () {
    test('returns null when no ranges and no override', () {
      final p = Person(id: 'p1', name: 'Alice');
      expect(_resolve(p, []), isNull);
    });

    test('returns null when height matches a range that has no preset for this slot', () {
      final p = Person(id: 'p1', name: 'Alice', heightCm: 170);
      final range = HeightRange(
          id: 'r1', name: 'Medium', maxHeightCm: 175, positionPresets: {});
      expect(_resolve(p, [range]), isNull);
    });
  });

  group('resolvePreset — personal override', () {
    test('returns override when set, even with no height', () {
      final p = Person(
          id: 'p1',
          name: 'Alice',
          positionPresets: {_posId: {_camIp: 7}});
      expect(_resolve(p, []), 7);
    });

    test('override takes precedence over matching height range', () {
      final p = Person(
          id: 'p1',
          name: 'Alice',
          heightCm: 170,
          positionPresets: {_posId: {_camIp: 7}});
      final range = _range(id: 'r1', name: 'Medium', maxHeightCm: 175, preset: 3);
      expect(_resolve(p, [range]), 7);
    });

    test('override only applies to the matching position+camera', () {
      final p = Person(
          id: 'p1',
          name: 'Alice',
          positionPresets: {'other-pos': {_camIp: 7}});
      expect(_resolve(p, []), isNull);
    });
  });

  group('resolvePreset — height range lookup', () {
    test('person with height in range returns that range preset', () {
      final p = Person(id: 'p1', name: 'Alice', heightCm: 163);
      final range = _range(id: 'r1', name: 'Short', maxHeightCm: 165, preset: 2);
      expect(_resolve(p, [range]), 2);
    });

    test('person at exact max boundary is included in that range', () {
      final p = Person(id: 'p1', name: 'Alice', heightCm: 165);
      final range = _range(id: 'r1', name: 'Short', maxHeightCm: 165, preset: 2);
      expect(_resolve(p, [range]), 2);
    });

    test('person above a bounded range falls to the next range', () {
      final p = Person(id: 'p1', name: 'Alice', heightCm: 175);
      final short = _range(id: 'r1', name: 'Short', maxHeightCm: 163, preset: 1);
      final tall = _range(id: 'r2', name: 'Tall', maxHeightCm: null, preset: 5);
      expect(_resolve(p, [short, tall]), 5);
    });

    test('selects the lowest matching range when multiple could match', () {
      final p = Person(id: 'p1', name: 'Alice', heightCm: 160);
      final short = _range(id: 'r1', name: 'Short', maxHeightCm: 163, preset: 1);
      final medium = _range(id: 'r2', name: 'Medium', maxHeightCm: 175, preset: 3);
      final tall = _range(id: 'r3', name: 'Tall', maxHeightCm: null, preset: 5);
      // 160 ≤ 163, so Short matches first
      expect(_resolve(p, [short, medium, tall]), 1);
    });

    test('ranges are matched by ascending maxHeightCm regardless of list order', () {
      final p = Person(id: 'p1', name: 'Alice', heightCm: 168);
      // deliberately pass in reverse order
      final tall = _range(id: 'r3', name: 'Tall', maxHeightCm: null, preset: 5);
      final medium = _range(id: 'r2', name: 'Medium', maxHeightCm: 175, preset: 3);
      final short = _range(id: 'r1', name: 'Short', maxHeightCm: 163, preset: 1);
      // 168 > 163 (skip short), 168 ≤ 175 → medium
      expect(_resolve(p, [tall, medium, short]), 3);
    });

    test('null-max range acts as catch-all for very tall person', () {
      final p = Person(id: 'p1', name: 'Alice', heightCm: 200);
      final catchAll = _range(id: 'r1', name: 'Tall', maxHeightCm: null, preset: 6);
      expect(_resolve(p, [catchAll]), 6);
    });
  });

  group('resolvePreset — default height (5\'8" = 173 cm)', () {
    test('person with no heightCm uses defaultHeightCm for range lookup', () {
      final p = Person(id: 'p1', name: 'Alice'); // heightCm == null
      // Range covering 173
      final range = _range(id: 'r1', name: 'Average', maxHeightCm: 175, preset: 4);
      expect(_resolve(p, [range]), 4);
    });

    test('person with no heightCm is NOT matched by a range below 5\'8"', () {
      final p = Person(id: 'p1', name: 'Alice');
      // Only a short range (max 160 cm < 173 default)
      final range = _range(id: 'r1', name: 'Short', maxHeightCm: 160, preset: 2);
      expect(_resolve(p, [range]), isNull);
    });

    test('defaultHeightCm constant is 173', () => expect(defaultHeightCm, 173));
  });
}
