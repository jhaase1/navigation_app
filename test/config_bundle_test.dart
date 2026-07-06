import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navigation_app/models/person.dart';
import 'package:navigation_app/models/role.dart';
import 'package:navigation_app/models/scene.dart';
import 'package:navigation_app/models/service_order.dart';
import 'package:navigation_app/services/config_bundle.dart';
import 'package:navigation_app/services/people_store.dart';
import 'package:navigation_app/services/role_store.dart';
import 'package:navigation_app/services/scene_store.dart';
import 'package:navigation_app/services/service_order_store.dart';

ConfigBundle _full() => ConfigBundle(
      scenes: [
        Scene(id: 's1', name: 'Lectern'),
        Scene(id: 's2', name: 'Pulpit'),
      ],
      people: [
        Person(
          id: 'p1',
          name: 'Alice',
          scenePresets: {
            's1': {'10.0.0.1': 2},
          },
        ),
      ],
      roles: [
        Role(id: 'r1', name: 'Reader 1'),
        Role(id: 'r2', name: 'Priest'),
      ],
      orders: [
        ServiceOrder(
          id: 'o1',
          name: 'Standard Mass',
          moments: [
            const OrderMoment(
                id: 'm1', type: MomentType.macro, macroNumber: 3),
            const OrderMoment(
                id: 'm2',
                type: MomentType.roleScene,
                roleId: 'r1',
                sceneId: 's1'),
          ],
        ),
      ],
    );

void main() {
  group('ConfigBundle — serialisation', () {
    test('toJson/fromJson round-trips all four collections', () {
      final bundle = _full();
      final copy = ConfigBundle.fromJson(bundle.toJson());

      expect(copy.scenes.length, 2);
      expect(copy.scenes[0].name, 'Lectern');
      expect(copy.scenes[1].name, 'Pulpit');

      expect(copy.people.length, 1);
      expect(copy.people[0].name, 'Alice');
      expect(copy.people[0].scenePresets['s1']?['10.0.0.1'], 2);

      expect(copy.roles.length, 2);
      expect(copy.roles[0].name, 'Reader 1');

      expect(copy.orders.length, 1);
      expect(copy.orders[0].name, 'Standard Mass');
      expect(copy.orders[0].moments.length, 2);
      expect(copy.orders[0].moments[0].macroNumber, 3);
      expect(copy.orders[0].moments[1].roleId, 'r1');
    });

    test('missing keys in JSON produce empty collections', () {
      final bundle = ConfigBundle.fromJson({});
      expect(bundle.scenes, isEmpty);
      expect(bundle.people, isEmpty);
      expect(bundle.roles, isEmpty);
      expect(bundle.orders, isEmpty);
    });

    test('toJson uses serviceOrders key for orders', () {
      final bundle = ConfigBundle(
          scenes: [], people: [], roles: [], orders: []);
      expect(bundle.toJson().containsKey('serviceOrders'), isTrue);
      expect(bundle.toJson().containsKey('orders'), isFalse);
    });

    test('fromJson reads serviceOrders key', () {
      final json = {
        'serviceOrders': [
          {
            'id': 'o1',
            'name': 'Test',
            'moments': [],
          }
        ],
      };
      final bundle = ConfigBundle.fromJson(json);
      expect(bundle.orders.length, 1);
      expect(bundle.orders[0].name, 'Test');
    });

    test('empty bundle round-trips', () {
      final bundle =
          const ConfigBundle(scenes: [], people: [], roles: [], orders: []);
      final copy = ConfigBundle.fromJson(bundle.toJson());
      expect(copy.scenes, isEmpty);
      expect(copy.people, isEmpty);
      expect(copy.roles, isEmpty);
      expect(copy.orders, isEmpty);
    });
  });

  group('ConfigBundle — store integration', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('fromStores returns empty bundle when stores are empty', () async {
      final bundle = await ConfigBundle.fromStores();
      expect(bundle.scenes, isEmpty);
      expect(bundle.people, isEmpty);
      expect(bundle.roles, isEmpty);
      expect(bundle.orders, isEmpty);
    });

    test('saveToStores persists all four collections', () async {
      await _full().saveToStores();

      final scenes = await SceneStore.loadAll();
      expect(scenes.length, 2);
      expect(scenes[0].name, 'Lectern');

      final people = await PeopleStore.loadAll();
      expect(people.length, 1);
      expect(people[0].scenePresets['s1']?['10.0.0.1'], 2);

      final roles = await RoleStore.loadAll();
      expect(roles.length, 2);

      final orders = await ServiceOrderStore.loadAll();
      expect(orders.length, 1);
      expect(orders[0].moments.length, 2);
    });

    test('fromStores reflects what saveToStores wrote', () async {
      await _full().saveToStores();
      final loaded = await ConfigBundle.fromStores();

      expect(loaded.scenes.map((s) => s.id), containsAll(['s1', 's2']));
      expect(loaded.people[0].name, 'Alice');
      expect(loaded.roles.map((r) => r.name),
          containsAll(['Reader 1', 'Priest']));
      expect(loaded.orders[0].name, 'Standard Mass');
    });

    test('saveToStores overwrites previous store contents', () async {
      // Save a full bundle first
      await _full().saveToStores();

      // Save a minimal bundle — should replace, not merge
      await const ConfigBundle(
        scenes: [],
        people: [],
        roles: [],
        orders: [],
      ).saveToStores();

      final bundle = await ConfigBundle.fromStores();
      expect(bundle.scenes, isEmpty);
      expect(bundle.people, isEmpty);
      expect(bundle.roles, isEmpty);
      expect(bundle.orders, isEmpty);
    });

    test('toJson/fromJson/saveToStores/fromStores full round-trip', () async {
      final original = _full();
      final json = original.toJson();
      final decoded = ConfigBundle.fromJson(json);
      await decoded.saveToStores();
      final reloaded = await ConfigBundle.fromStores();

      expect(reloaded.scenes.length, original.scenes.length);
      expect(reloaded.people[0].scenePresets['s1']?['10.0.0.1'], 2);
      expect(reloaded.roles.length, original.roles.length);
      expect(reloaded.orders[0].moments[0].macroNumber, 3);
    });
  });
}
