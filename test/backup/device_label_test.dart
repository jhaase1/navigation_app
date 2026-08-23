import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/app_fault.dart';
import 'package:navigation_app/services/backup/device_label.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('sanitize rejects a default that is not an answer', () {
    for (final worthless in [
      'localhost',
      'localhost.local',
      'iPad',
      'iPhone',
      'Mac mini',
      'MacBook-Pro',
      '   ',
      '',
    ]) {
      test('"$worthless" is refused', () {
        expect(DeviceLabel.sanitize(worthless, namesInUse: const []), isNull);
      });
    }

    test('null in, null out', () {
      expect(DeviceLabel.sanitize(null, namesInUse: const []), isNull);
    });
  });

  test('a real macOS hostname is accepted, without .local', () {
    expect(
      DeviceLabel.sanitize('Sanctuary-Mac-mini.local', namesInUse: const []),
      'Sanctuary-Mac-mini',
    );
  });

  test('a name another machine already uses is refused', () {
    // Two Macs sharing a hostname, or two iPads: the conflict dialog would be
    // actively misleading.
    expect(
      DeviceLabel.sanitize('Sanctuary Mac mini',
          namesInUse: const ['sanctuary-mac-mini']),
      isNull,
    );
  });

  test('this machine\'s OWN name is not a collision with itself', () {
    // Every revision we have ever pushed carries our label. Counting those as
    // collisions makes the name field unusable the moment it works.
    expect(DeviceLabel.isSameName('Sanctuary-Mac-mini', 'Sanctuary Mac mini'),
        isTrue);
    expect(
        DeviceLabel.isSameName("Daniel's iPad", 'Sanctuary Mac mini'), isFalse);
  });

  test('require() refuses to invent a name', () async {
    await expectLater(
      DeviceLabel.require(),
      throwsA(isA<AppFault>()
          .having((f) => f.kind, 'kind', 'deviceUnnamed')
          .having((f) => f.needsUserAction, 'needsUserAction', isTrue)),
    );
  });

  test('require() returns the saved name once there is one', () async {
    await DeviceLabel.save('  The Mac mini  ');
    expect(await DeviceLabel.require(), 'The Mac mini');
  });
}
