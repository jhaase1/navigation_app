import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/models/height_range.dart';
import 'package:navigation_app/models/person.dart';
import 'package:navigation_app/models/position.dart';
import 'package:navigation_app/models/service.dart';

void main() {
  group('Position', () {
    test('round-trips through JSON', () {
      final p = Position(id: 'abc', name: 'Lectern');
      final copy = Position.fromJson(p.toJson());
      expect(copy.id, p.id);
      expect(copy.name, p.name);
    });

    test('generatePositionId returns a non-empty numeric string', () {
      final id = generatePositionId();
      expect(id, isNotEmpty);
      expect(int.tryParse(id), isNotNull);
    });
  });

  group('Person', () {
    test('round-trips with empty positionPresets', () {
      final p = Person(id: 'p1', name: 'Alice');
      final copy = Person.fromJson(p.toJson());
      expect(copy.id, 'p1');
      expect(copy.name, 'Alice');
      expect(copy.positionPresets, isEmpty);
    });

    test('round-trips with nested positionPresets', () {
      final p = Person(
        id: 'p2',
        name: 'Bob',
        positionPresets: {
          'pos-a': {'10.0.0.1': 0, '10.0.0.2': 4},
          'pos-b': {'10.0.0.1': 11},
        },
      );
      final copy = Person.fromJson(p.toJson());
      expect(copy.positionPresets['pos-a']?['10.0.0.1'], 0);
      expect(copy.positionPresets['pos-a']?['10.0.0.2'], 4);
      expect(copy.positionPresets['pos-b']?['10.0.0.1'], 11);
    });

    test('missing positionPresets key in JSON yields empty map', () {
      final p = Person.fromJson({'id': 'p3', 'name': 'Carol'});
      expect(p.positionPresets, isEmpty);
    });

    test('round-trips with heightCm set', () {
      final p = Person(id: 'p4', name: 'Dave', heightCm: 180);
      final copy = Person.fromJson(p.toJson());
      expect(copy.heightCm, 180);
    });

    test('null heightCm is omitted from JSON and round-trips as null', () {
      final p = Person(id: 'p5', name: 'Eve');
      expect(p.toJson().containsKey('heightCm'), isFalse);
      expect(Person.fromJson(p.toJson()).heightCm, isNull);
    });
  });

  group('HeightRange', () {
    test('round-trips with bounded maxHeightCm and presets', () {
      final r = HeightRange(
        id: 'hr1',
        name: 'Short',
        maxHeightCm: 163,
        positionPresets: {
          'pos1': {'10.0.0.1': 2, '10.0.0.2': 5},
        },
      );
      final copy = HeightRange.fromJson(r.toJson());
      expect(copy.id, 'hr1');
      expect(copy.name, 'Short');
      expect(copy.maxHeightCm, 163);
      expect(copy.positionPresets['pos1']?['10.0.0.1'], 2);
      expect(copy.positionPresets['pos1']?['10.0.0.2'], 5);
    });

    test('null maxHeightCm is omitted from JSON and round-trips as null', () {
      final r = HeightRange(id: 'hr2', name: 'Tall');
      expect(r.toJson().containsKey('maxHeightCm'), isFalse);
      expect(HeightRange.fromJson(r.toJson()).maxHeightCm, isNull);
    });

    test('missing positionPresets key in JSON yields empty map', () {
      final r = HeightRange.fromJson({'id': 'x', 'name': 'Test'});
      expect(r.positionPresets, isEmpty);
    });

    test('generateHeightRangeId returns a non-empty numeric string', () {
      final id = generateHeightRangeId();
      expect(id, isNotEmpty);
      expect(int.tryParse(id), isNotNull);
    });
  });

  group('Participant', () {
    test('round-trips through JSON', () {
      final p = Participant(id: 'pt1', name: 'Reader 1');
      final copy = Participant.fromJson(p.toJson());
      expect(copy.id, 'pt1');
      expect(copy.name, 'Reader 1');
    });
  });

  group('ServiceStep', () {
    test('ministry type round-trips', () {
      const s = ServiceStep(
        id: 's1',
        type: StepType.ministry,
        participantId: 'pt1',
        positionId: 'pos1',
      );
      final copy = ServiceStep.fromJson(s.toJson());
      expect(copy.type, StepType.ministry);
      expect(copy.participantId, 'pt1');
      expect(copy.positionId, 'pos1');
      expect(copy.macroNumber, isNull);
      expect(copy.cameraIp, isNull);
      expect(copy.subServiceId, isNull);
    });

    test('macro type round-trips', () {
      const s = ServiceStep(id: 's2', type: StepType.macro, macroNumber: 7);
      final copy = ServiceStep.fromJson(s.toJson());
      expect(copy.type, StepType.macro);
      expect(copy.macroNumber, 7);
    });

    test('shot type round-trips', () {
      const s = ServiceStep(
        id: 's3',
        type: StepType.shot,
        cameraIp: '10.0.0.1',
        cameraPresetIndex: 3,
      );
      final copy = ServiceStep.fromJson(s.toJson());
      expect(copy.type, StepType.shot);
      expect(copy.cameraIp, '10.0.0.1');
      expect(copy.cameraPresetIndex, 3);
    });

    test('block type round-trips', () {
      const s =
          ServiceStep(id: 's4', type: StepType.block, subServiceId: 'svc-2');
      final copy = ServiceStep.fromJson(s.toJson());
      expect(copy.type, StepType.block);
      expect(copy.subServiceId, 'svc-2');
    });

    test('unknown type in JSON falls back to ministry', () {
      final s = ServiceStep.fromJson({'id': 'x', 'type': 'bogus'});
      expect(s.type, StepType.ministry);
    });

    test('toJson omits null optional fields', () {
      const s = ServiceStep(id: 'y', type: StepType.macro, macroNumber: 3);
      final json = s.toJson();
      expect(json.containsKey('participantId'), isFalse);
      expect(json.containsKey('positionId'), isFalse);
      expect(json.containsKey('cameraIp'), isFalse);
      expect(json.containsKey('subServiceId'), isFalse);
      expect(json['macroNumber'], 3);
    });

    test('all four StepType values are deserializable', () {
      for (final type in StepType.values) {
        final s = ServiceStep.fromJson({'id': 'z', 'type': type.name});
        expect(s.type, type);
      }
    });
  });

  group('Service', () {
    test('round-trips with no participants and no steps', () {
      final s = Service(id: 'svc1', name: 'Standard Mass');
      final copy = Service.fromJson(s.toJson());
      expect(copy.id, 'svc1');
      expect(copy.name, 'Standard Mass');
      expect(copy.participants, isEmpty);
      expect(copy.steps, isEmpty);
    });

    test('round-trips with participants and mixed steps', () {
      final s = Service(
        id: 'svc2',
        name: 'Vigil',
        participants: [
          Participant(id: 'pt1', name: 'Reader 1'),
          Participant(id: 'pt2', name: 'Priest'),
        ],
        steps: [
          const ServiceStep(
              id: 'st1', type: StepType.macro, macroNumber: 1),
          const ServiceStep(
              id: 'st2',
              type: StepType.ministry,
              participantId: 'pt1',
              positionId: 'pos1'),
          const ServiceStep(
              id: 'st3', type: StepType.block, subServiceId: 'svc1'),
        ],
      );
      final copy = Service.fromJson(s.toJson());
      expect(copy.participants.length, 2);
      expect(copy.participants[0].name, 'Reader 1');
      expect(copy.steps.length, 3);
      expect(copy.steps[0].type, StepType.macro);
      expect(copy.steps[1].participantId, 'pt1');
      expect(copy.steps[2].subServiceId, 'svc1');
    });

    test('missing participants/steps keys in JSON yield empty lists', () {
      final s = Service.fromJson({'id': 'x', 'name': 'Empty'});
      expect(s.participants, isEmpty);
      expect(s.steps, isEmpty);
    });

    test('participants and steps default to empty when not provided', () {
      final s = Service(id: 's', name: 'Test');
      expect(s.participants, isEmpty);
      expect(s.steps, isEmpty);
    });

    test('generateServiceId returns a non-empty numeric string', () {
      final id = generateServiceId();
      expect(id, isNotEmpty);
      expect(int.tryParse(id), isNotNull);
    });
  });
}
