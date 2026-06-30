import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navigation_app/models/person.dart';
import 'package:navigation_app/models/role.dart';
import 'package:navigation_app/models/scene.dart';
import 'package:navigation_app/models/service_order.dart';
import 'package:navigation_app/services/people_store.dart';
import 'package:navigation_app/services/role_store.dart';
import 'package:navigation_app/services/scene_store.dart';
import 'package:navigation_app/services/service_order_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SceneStore', () {
    test('loadAll returns empty list before anything is saved', () async {
      expect(await SceneStore.loadAll(), isEmpty);
    });

    test('saveAll then loadAll returns the same scenes', () async {
      final scenes = [
        Scene(id: '1', name: 'Lectern'),
        Scene(id: '2', name: 'Pulpit'),
      ];
      await SceneStore.saveAll(scenes);
      final loaded = await SceneStore.loadAll();
      expect(loaded.length, 2);
      expect(loaded[0].id, '1');
      expect(loaded[0].name, 'Lectern');
      expect(loaded[1].name, 'Pulpit');
    });

    test('overwriting with empty list clears stored scenes', () async {
      await SceneStore.saveAll([Scene(id: '1', name: 'Lectern')]);
      await SceneStore.saveAll([]);
      expect(await SceneStore.loadAll(), isEmpty);
    });

    test('overwrites previous save entirely', () async {
      await SceneStore.saveAll([Scene(id: '1', name: 'Lectern')]);
      await SceneStore.saveAll([Scene(id: '2', name: 'Pulpit')]);
      final loaded = await SceneStore.loadAll();
      expect(loaded.length, 1);
      expect(loaded[0].name, 'Pulpit');
    });
  });

  group('PeopleStore', () {
    test('loadAll returns empty list before anything is saved', () async {
      expect(await PeopleStore.loadAll(), isEmpty);
    });

    test('saveAll then loadAll preserves person with scenePresets', () async {
      final person = Person(
        id: 'p1',
        name: 'Alice',
        scenePresets: {
          's1': {'10.0.0.1': 3, '10.0.0.2': 7},
        },
      );
      await PeopleStore.saveAll([person]);
      final loaded = await PeopleStore.loadAll();
      expect(loaded.length, 1);
      expect(loaded[0].name, 'Alice');
      expect(loaded[0].scenePresets['s1']?['10.0.0.1'], 3);
      expect(loaded[0].scenePresets['s1']?['10.0.0.2'], 7);
    });

    test('saves multiple people', () async {
      final people = [
        Person(id: 'p1', name: 'Alice'),
        Person(id: 'p2', name: 'Bob'),
      ];
      await PeopleStore.saveAll(people);
      final loaded = await PeopleStore.loadAll();
      expect(loaded.length, 2);
      expect(loaded.map((p) => p.name), containsAll(['Alice', 'Bob']));
    });
  });

  group('RoleStore', () {
    test('loadAll returns empty list before anything is saved', () async {
      expect(await RoleStore.loadAll(), isEmpty);
    });

    test('saveAll then loadAll returns the same roles', () async {
      final roles = [
        Role(id: 'r1', name: 'Reader 1'),
        Role(id: 'r2', name: 'Priest'),
        Role(id: 'r3', name: 'Deacon'),
      ];
      await RoleStore.saveAll(roles);
      final loaded = await RoleStore.loadAll();
      expect(loaded.length, 3);
      expect(loaded[0].name, 'Reader 1');
      expect(loaded[1].name, 'Priest');
      expect(loaded[2].name, 'Deacon');
    });

    test('overwriting with empty list clears stored roles', () async {
      await RoleStore.saveAll([Role(id: 'r1', name: 'Reader 1')]);
      await RoleStore.saveAll([]);
      expect(await RoleStore.loadAll(), isEmpty);
    });
  });

  group('ServiceOrderStore', () {
    test('loadAll returns empty list before anything is saved', () async {
      expect(await ServiceOrderStore.loadAll(), isEmpty);
    });

    test('saveAll then loadAll preserves order with moments', () async {
      final order = ServiceOrder(
        id: 'o1',
        name: 'Standard Mass',
        moments: [
          const OrderMoment(id: 'm1', type: MomentType.macro, macroNumber: 2),
          const OrderMoment(
              id: 'm2',
              type: MomentType.roleScene,
              roleId: 'r1',
              sceneId: 's1'),
          const OrderMoment(
              id: 'm3', type: MomentType.subOrder, subOrderId: 'o2'),
        ],
      );
      await ServiceOrderStore.saveAll([order]);
      final loaded = await ServiceOrderStore.loadAll();
      expect(loaded.length, 1);
      expect(loaded[0].name, 'Standard Mass');
      expect(loaded[0].moments.length, 3);
      expect(loaded[0].moments[0].macroNumber, 2);
      expect(loaded[0].moments[1].roleId, 'r1');
      expect(loaded[0].moments[2].subOrderId, 'o2');
    });

    test('saves multiple orders', () async {
      final orders = [
        ServiceOrder(id: 'o1', name: 'Mass'),
        ServiceOrder(id: 'o2', name: 'Vespers'),
      ];
      await ServiceOrderStore.saveAll(orders);
      final loaded = await ServiceOrderStore.loadAll();
      expect(loaded.length, 2);
      expect(loaded.map((o) => o.name), containsAll(['Mass', 'Vespers']));
    });

    test('each store uses its own key (no cross-contamination)', () async {
      await SceneStore.saveAll([Scene(id: 's1', name: 'Lectern')]);
      await RoleStore.saveAll([Role(id: 'r1', name: 'Priest')]);

      // loading the other stores should still be empty
      expect(await PeopleStore.loadAll(), isEmpty);
      expect(await ServiceOrderStore.loadAll(), isEmpty);
    });
  });
}
