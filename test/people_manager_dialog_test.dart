import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/models/panasonic_camera_config.dart';
import 'package:navigation_app/models/person.dart';
import 'package:navigation_app/models/position.dart';
import 'package:navigation_app/services/mock/mock_panasonic_service.dart';
import 'package:navigation_app/services/people_store.dart';
import 'package:navigation_app/widgets/people_manager_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _ip = '10.0.1.10';

/// A camera whose mock reports presets 1–10, 21–30, 51–60 and 81–90 saved.
PanasonicCameraConfig _camera({required bool connected}) {
  final camera = PanasonicCameraConfig(
      name: 'Wide', ipAddress: _ip, service: MockPanasonicService());
  camera.isConnected.value = connected;
  addTearDown(camera.dispose);
  return camera;
}

Future<void> _open(WidgetTester tester, PanasonicCameraConfig camera) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: PeopleManagerDialog(
        positions: [Position(id: 'ambo', name: 'Ambo')],
        cameras: [camera],
        heightRanges: const [],
        onSaved: () {},
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The preset numbers the one dropdown offers, without the "—" entry.
List<int> _offered(WidgetTester tester) => tester
    .widget<DropdownButton<int?>>(find.byType(DropdownButton<int?>))
    .items!
    .map((i) => i.value)
    .whereType<int>()
    .toList();

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a connected camera offers only the presets saved on it',
      (tester) async {
    await _open(tester, _camera(connected: true));
    await tester.tap(find.text('Add Person'));
    await tester.pumpAndSettle();

    final offered = _offered(tester);
    expect(offered, containsAll([1, 10, 21, 90]));
    expect(offered, isNot(contains(11)));
    expect(offered, hasLength(40));
  });

  testWidgets('a camera that is not connected still offers all 100',
      (tester) async {
    // People are set up at home, before the rack is on.
    await _open(tester, _camera(connected: false));
    await tester.tap(find.text('Add Person'));
    await tester.pumpAndSettle();

    expect(_offered(tester), hasLength(100));
  });

  testWidgets(
      'a preset already chosen stays chosen when the camera no longer has it',
      (tester) async {
    // Preset 15 (index 14) is not saved on the mock. Dropping it from the
    // list would clear the assignment the moment someone opened and saved.
    await PeopleStore.saveAll([
      Person(id: 'p1', name: 'Jane', positionPresets: {
        'ambo': {_ip: 14},
      }),
    ]);
    await _open(tester, _camera(connected: true));
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();

    expect(_offered(tester), contains(15));
    expect(find.textContaining('not saved on camera'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = await PeopleStore.loadAll();
    expect(saved.single.positionPresets['ambo']![_ip], 14);
  });
}
