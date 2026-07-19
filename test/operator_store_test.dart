import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navigation_app/models/operator_profile.dart';
import 'package:navigation_app/services/operator_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('OperatorProfile — serialisation', () {
    test('toJson/fromJson round-trips id, name, and items', () {
      const op = OperatorProfile(
        id: 'abc',
        name: 'Sound',
        items: {
          'roland_10.0.1.20': [1, 5, 10],
          '10.0.1.10': [0, 3],
        },
      );
      final copy = OperatorProfile.fromJson(op.toJson());
      expect(copy.id, 'abc');
      expect(copy.name, 'Sound');
      expect(copy.items['roland_10.0.1.20'], [1, 5, 10]);
      expect(copy.items['10.0.1.10'], [0, 3]);
    });

    test('fromJson with missing items field produces empty map', () {
      final op = OperatorProfile.fromJson({'id': 'x', 'name': 'X'});
      expect(op.items, isEmpty);
    });

    test('isDefault returns true only for default id', () {
      expect(OperatorProfile.defaultProfile.isDefault, isTrue);
      expect(
          const OperatorProfile(id: 'other', name: 'Other').isDefault, isFalse);
    });

    test('copyWith updates name and keeps id', () {
      const op = OperatorProfile(id: 'abc', name: 'Old');
      final updated = op.copyWith(name: 'New');
      expect(updated.id, 'abc');
      expect(updated.name, 'New');
    });

    test('copyWith updates items and keeps name', () {
      const op = OperatorProfile(id: 'abc', name: 'Cam Op');
      final updated = op.copyWith(items: {'k': [1, 2]});
      expect(updated.name, 'Cam Op');
      expect(updated.items['k'], [1, 2]);
    });
  });

  group('OperatorStore — operators', () {
    test('loadAll returns default profile when nothing saved', () async {
      final ops = await OperatorStore.loadAll();
      expect(ops.length, 1);
      expect(ops.first.isDefault, isTrue);
    });

    test('saveAll then loadAll returns the saved operators', () async {
      final ops = [
        OperatorProfile.defaultProfile,
        const OperatorProfile(id: 'op1', name: 'Camera Op'),
        const OperatorProfile(id: 'op2', name: 'Sound'),
      ];
      await OperatorStore.saveAll(ops);
      final loaded = await OperatorStore.loadAll();
      expect(loaded.length, 3);
      expect(loaded[1].name, 'Camera Op');
      expect(loaded[2].name, 'Sound');
    });

    test('loadAll inserts default profile when missing from saved list',
        () async {
      // Save a list without the default profile
      await OperatorStore.saveAll([
        const OperatorProfile(id: 'op1', name: 'Camera Op'),
      ]);
      final loaded = await OperatorStore.loadAll();
      expect(loaded.any((o) => o.isDefault), isTrue);
    });

    test('saveAll persists items per device key', () async {
      final ops = [
        OperatorProfile.defaultProfile,
        const OperatorProfile(
          id: 'op1',
          name: 'Camera Op',
          items: {'roland_10.0.1.20': [1, 5, 9]},
        ),
      ];
      await OperatorStore.saveAll(ops);
      final loaded = await OperatorStore.loadAll();
      expect(loaded[1].items['roland_10.0.1.20'], [1, 5, 9]);
    });

    test('overwriting saveAll replaces the previous list', () async {
      await OperatorStore.saveAll([
        OperatorProfile.defaultProfile,
        const OperatorProfile(id: 'old', name: 'Old'),
      ]);
      await OperatorStore.saveAll([
        OperatorProfile.defaultProfile,
        const OperatorProfile(id: 'new', name: 'New'),
      ]);
      final loaded = await OperatorStore.loadAll();
      expect(loaded.any((o) => o.name == 'Old'), isFalse);
      expect(loaded.any((o) => o.name == 'New'), isTrue);
    });
  });

  group('OperatorStore — active operator', () {
    test('loadActiveId returns default id when nothing saved', () async {
      expect(await OperatorStore.loadActiveId(), OperatorProfile.defaultId);
    });

    test('saveActiveId then loadActiveId returns saved id', () async {
      await OperatorStore.saveActiveId('op1');
      expect(await OperatorStore.loadActiveId(), 'op1');
    });

    test('saveActiveId overwrites previous value', () async {
      await OperatorStore.saveActiveId('op1');
      await OperatorStore.saveActiveId('op2');
      expect(await OperatorStore.loadActiveId(), 'op2');
    });
  });
}
