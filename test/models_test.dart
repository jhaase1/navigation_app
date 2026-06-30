import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/models/person.dart';
import 'package:navigation_app/models/role.dart';
import 'package:navigation_app/models/scene.dart';
import 'package:navigation_app/models/service_order.dart';

void main() {
  group('Scene', () {
    test('round-trips through JSON', () {
      final scene = Scene(id: 'abc', name: 'Lectern');
      final copy = Scene.fromJson(scene.toJson());
      expect(copy.id, scene.id);
      expect(copy.name, scene.name);
    });

    test('generateSceneId returns a non-empty numeric string', () {
      final id = generateSceneId();
      expect(id, isNotEmpty);
      expect(int.tryParse(id), isNotNull);
    });
  });

  group('Person', () {
    test('round-trips with empty scenePresets', () {
      final p = Person(id: 'p1', name: 'Alice');
      final copy = Person.fromJson(p.toJson());
      expect(copy.id, 'p1');
      expect(copy.name, 'Alice');
      expect(copy.scenePresets, isEmpty);
    });

    test('round-trips with nested scenePresets', () {
      final p = Person(
        id: 'p2',
        name: 'Bob',
        scenePresets: {
          'scene-a': {'10.0.0.1': 0, '10.0.0.2': 4},
          'scene-b': {'10.0.0.1': 11},
        },
      );
      final copy = Person.fromJson(p.toJson());
      expect(copy.scenePresets['scene-a']?['10.0.0.1'], 0);
      expect(copy.scenePresets['scene-a']?['10.0.0.2'], 4);
      expect(copy.scenePresets['scene-b']?['10.0.0.1'], 11);
    });

    test('missing scenePresets key in JSON yields empty map', () {
      final p = Person.fromJson({'id': 'p3', 'name': 'Carol'});
      expect(p.scenePresets, isEmpty);
    });
  });

  group('Role', () {
    test('round-trips through JSON', () {
      final r = Role(id: 'r1', name: 'Reader 1');
      final copy = Role.fromJson(r.toJson());
      expect(copy.id, 'r1');
      expect(copy.name, 'Reader 1');
    });

    test('generateRoleId returns a non-empty numeric string', () {
      final id = generateRoleId();
      expect(id, isNotEmpty);
      expect(int.tryParse(id), isNotNull);
    });
  });

  group('OrderMoment', () {
    test('roleScene type round-trips', () {
      final m = OrderMoment(
        id: 'm1',
        type: MomentType.roleScene,
        roleId: 'r1',
        sceneId: 's1',
      );
      final copy = OrderMoment.fromJson(m.toJson());
      expect(copy.type, MomentType.roleScene);
      expect(copy.roleId, 'r1');
      expect(copy.sceneId, 's1');
      expect(copy.macroNumber, isNull);
      expect(copy.cameraIp, isNull);
      expect(copy.subOrderId, isNull);
    });

    test('macro type round-trips', () {
      final m = OrderMoment(id: 'm2', type: MomentType.macro, macroNumber: 5);
      final copy = OrderMoment.fromJson(m.toJson());
      expect(copy.type, MomentType.macro);
      expect(copy.macroNumber, 5);
    });

    test('camera type round-trips', () {
      final m = OrderMoment(
        id: 'm3',
        type: MomentType.camera,
        cameraIp: '10.0.0.1',
        cameraPresetIndex: 2,
      );
      final copy = OrderMoment.fromJson(m.toJson());
      expect(copy.type, MomentType.camera);
      expect(copy.cameraIp, '10.0.0.1');
      expect(copy.cameraPresetIndex, 2);
    });

    test('subOrder type round-trips', () {
      final m = OrderMoment(
        id: 'm4',
        type: MomentType.subOrder,
        subOrderId: 'order-2',
      );
      final copy = OrderMoment.fromJson(m.toJson());
      expect(copy.type, MomentType.subOrder);
      expect(copy.subOrderId, 'order-2');
    });

    test('unknown type in JSON falls back to roleScene', () {
      final m = OrderMoment.fromJson({'id': 'x', 'type': 'bogus'});
      expect(m.type, MomentType.roleScene);
    });

    test('toJson omits null optional fields', () {
      final m = OrderMoment(id: 'y', type: MomentType.macro, macroNumber: 3);
      final json = m.toJson();
      expect(json.containsKey('roleId'), isFalse);
      expect(json.containsKey('sceneId'), isFalse);
      expect(json.containsKey('cameraIp'), isFalse);
      expect(json.containsKey('subOrderId'), isFalse);
      expect(json['macroNumber'], 3);
    });

    test('all four MomentType values are deserializable', () {
      for (final type in MomentType.values) {
        final m = OrderMoment.fromJson({'id': 'z', 'type': type.name});
        expect(m.type, type);
      }
    });
  });

  group('ServiceOrder', () {
    test('round-trips with no moments', () {
      final o = ServiceOrder(id: 'o1', name: 'Standard Mass');
      final copy = ServiceOrder.fromJson(o.toJson());
      expect(copy.id, 'o1');
      expect(copy.name, 'Standard Mass');
      expect(copy.moments, isEmpty);
    });

    test('round-trips with mixed moment types', () {
      final o = ServiceOrder(
        id: 'o2',
        name: 'Vigil',
        moments: [
          OrderMoment(id: 'm1', type: MomentType.macro, macroNumber: 1),
          OrderMoment(
              id: 'm2',
              type: MomentType.roleScene,
              roleId: 'r1',
              sceneId: 's1'),
          OrderMoment(
              id: 'm3', type: MomentType.subOrder, subOrderId: 'o1'),
        ],
      );
      final copy = ServiceOrder.fromJson(o.toJson());
      expect(copy.moments.length, 3);
      expect(copy.moments[0].type, MomentType.macro);
      expect(copy.moments[1].roleId, 'r1');
      expect(copy.moments[2].subOrderId, 'o1');
    });

    test('missing moments key in JSON yields empty list', () {
      final o = ServiceOrder.fromJson({'id': 'x', 'name': 'Empty'});
      expect(o.moments, isEmpty);
    });

    test('moments list defaults to empty when not provided', () {
      final o = ServiceOrder(id: 'o3', name: 'Test');
      expect(o.moments, isEmpty);
    });
  });
}
