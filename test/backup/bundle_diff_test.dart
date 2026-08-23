import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/bundle_diff.dart';

void main() {
  Map<String, dynamic> bundle({
    List<Map<String, dynamic>> people = const [],
    List<Map<String, dynamic>> positions = const [],
    Map<String, dynamic> presetNames = const {},
    String? rolandIp,
  }) =>
      {
        'schemaVersion': 1,
        'positions': positions,
        'people': people,
        'services': const [],
        'heightRanges': const [],
        'presetNames': presetNames,
        'visibilities': const {},
        if (rolandIp != null) 'rolandIp': rolandIp,
      };

  test('identical bundles report nothing', () {
    final b = bundle(people: [
      {'id': 'p1', 'name': 'Joel'}
    ]);
    expect(BundleDiff.between(b, b).isEmpty, isTrue);
    expect(BundleDiff.between(b, b).lines, isEmpty);
  });

  test('key order does not fake a difference', () {
    // The whole hash guard rests on canonical ordering; the diff must agree.
    final mine = bundle(people: [
      {'id': 'p1', 'name': 'Joel'}
    ]);
    final theirs = bundle(people: [
      {'name': 'Joel', 'id': 'p1'}
    ]);
    expect(BundleDiff.between(mine, theirs).isEmpty, isTrue);
  });

  test('counts additions, removals and edits separately', () {
    final mine = bundle(people: [
      {'id': 'p1', 'name': 'Joel'},
      {'id': 'p2', 'name': 'Isaiah'},
    ]);
    final theirs = bundle(people: [
      {'id': 'p1', 'name': 'Joel Greig'},
      {'id': 'p3', 'name': 'Katherine'},
    ]);

    expect(BundleDiff.between(mine, theirs).lines,
        contains('People: 1 more, 1 missing, 1 changed'));
  });

  test('a per-device preset map counts by BUTTON, not by device', () {
    final mine = bundle(presetNames: {
      '10.0.1.10': {'1': 'Pulpit', '2': 'Lectern', '3': 'Choir'}
    });
    final theirs = bundle(presetNames: {
      '10.0.1.10': {'1': 'Pulpit', '2': 'Lectern (new)', '3': 'Choir loft'},
      '10.0.1.11': {'1': 'Balcony'},
    });

    // Two renamed buttons on one camera plus one new button on another.
    expect(BundleDiff.between(mine, theirs).lines,
        contains('Preset labels: 1 more, 2 changed'));
  });

  test('device addresses report as changed, not counted', () {
    final mine = bundle(rolandIp: '10.0.1.20');
    final theirs = bundle(rolandIp: '10.0.1.21');
    expect(BundleDiff.between(mine, theirs).lines,
        contains('Switcher address: 1 changed'));
  });

  test('a list with no ids still reports a difference', () {
    final mine = bundle(positions: [
      {'name': 'Pulpit'}
    ]);
    final theirs = bundle(positions: [
      {'name': 'Lectern'}
    ]);
    expect(BundleDiff.between(mine, theirs).isEmpty, isFalse);
  });
}
