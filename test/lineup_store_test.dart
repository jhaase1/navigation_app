import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navigation_app/services/backup/config_mutation_notifier.dart';
import 'package:navigation_app/services/config_bundle.dart';
import 'package:navigation_app/services/lineup_store.dart';

void main() {
  late DateTime clock;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    clock = DateTime(2026, 10, 4, 9, 0);
    LineupStore.now = () => clock;
  });
  tearDown(() => LineupStore.now = DateTime.now);

  test('a saved lineup loads back for the same service', () async {
    await LineupStore.save('mass', {'reader1': 'alice', 'reader2': 'bob'});

    expect(
        await LineupStore.load('mass'), {'reader1': 'alice', 'reader2': 'bob'});
  });

  test('each service keeps its own lineup', () async {
    await LineupStore.save('mass', {'reader1': 'alice'});
    await LineupStore.save('vespers', {'reader1': 'bob'});

    expect(await LineupStore.load('mass'), {'reader1': 'alice'});
    expect(await LineupStore.load('vespers'), {'reader1': 'bob'});
  });

  test('unassigned roles are not stored', () async {
    await LineupStore.save('mass', {'reader1': 'alice', 'reader2': null});

    expect(await LineupStore.load('mass'), {'reader1': 'alice'});
  });

  test('an emptied lineup leaves nothing behind', () async {
    await LineupStore.save('mass', {'reader1': 'alice'});
    await LineupStore.save('mass', {'reader1': null});

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k) => k.startsWith(LineupStore.keyPrefix)),
        isEmpty);
    expect(await LineupStore.load('mass'), isEmpty);
  });

  test('a service with no saved lineup loads empty', () async {
    expect(await LineupStore.load('mass'), isEmpty);
  });

  test('the selected service round-trips and can be cleared', () async {
    expect(await LineupStore.loadSelectedServiceId(), isNull);

    await LineupStore.saveSelectedServiceId('mass');
    expect(await LineupStore.loadSelectedServiceId(), 'mass');

    await LineupStore.saveSelectedServiceId(null);
    expect(await LineupStore.loadSelectedServiceId(), isNull);
  });

  test('the lineup is day-of state, not configuration to back up', () async {
    final prefs = await SharedPreferences.getInstance();
    final before = prefs.get(ConfigMutationNotifier.generationKey);

    await LineupStore.save('mass', {'reader1': 'alice'});
    await LineupStore.saveSelectedServiceId('mass');

    expect(prefs.get(ConfigMutationNotifier.generationKey), before);
    expect(await ConfigBundle.localIsPristine(), isTrue);
  });

  group('the lineup lives 20 minutes past its last renewal', () {
    // Services run several times a week. A lineup saved on Saturday evening
    // must not walk into Sunday morning and aim a reader cue at the wrong
    // person.
    test('a lineup left alone for over 20 minutes is gone', () async {
      await LineupStore.save('mass', {'reader1': 'alice'});
      await LineupStore.saveSelectedServiceId('mass');

      clock = clock.add(const Duration(minutes: 21));

      expect(await LineupStore.load('mass'), isEmpty);
      expect(await LineupStore.loadSelectedServiceId(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.startsWith(LineupStore.keyPrefix)),
          isEmpty,
          reason: 'expired lineups are deleted, not just hidden');
    });

    test('one still inside its 20 minutes is kept', () async {
      await LineupStore.save('mass', {'reader1': 'alice'});

      clock = clock.add(const Duration(minutes: 19));

      expect(await LineupStore.load('mass'), {'reader1': 'alice'});
    });

    test('renewing keeps it alive well past the first 20 minutes', () async {
      await LineupStore.save('mass', {'reader1': 'alice'});
      for (var i = 0; i < 12; i++) {
        clock = clock.add(const Duration(minutes: 5));
        expect(await LineupStore.renew(), isTrue);
      }

      expect(await LineupStore.load('mass'), {'reader1': 'alice'});
    });

    test('renewing an expired lineup does not bring it back', () async {
      await LineupStore.save('mass', {'reader1': 'alice'});
      clock = clock.add(const Duration(minutes: 21));

      expect(await LineupStore.renew(), isFalse);
      clock = clock.add(const Duration(minutes: 1));
      expect(await LineupStore.load('mass'), isEmpty);
    });

    test('an expiry that deletes a lineup is announced', () async {
      var announced = 0;
      void listener() => announced++;
      LineupStore.expirations.addListener(listener);
      addTearDown(() => LineupStore.expirations.removeListener(listener));

      await LineupStore.renew(); // nothing stored: nothing to announce
      expect(announced, 0);

      await LineupStore.save('mass', {'reader1': 'alice'});
      clock = clock.add(const Duration(minutes: 21));
      await LineupStore.renew();
      expect(announced, 1);
    });

    test('saving after an expiry starts a fresh lineup', () async {
      await LineupStore.save('mass', {'reader1': 'alice'});
      clock = clock.add(const Duration(minutes: 21));

      await LineupStore.save('vespers', {'reader1': 'bob'});

      expect(await LineupStore.load('mass'), isEmpty,
          reason: "last service's lineup does not ride along");
      expect(await LineupStore.load('vespers'), {'reader1': 'bob'});
    });
  });

  group('the lineup belongs to the service day it was saved (4 AM to 4 AM)',
      () {
    // A Mac mini left on with the app open stays on screen all night, so
    // the 20-minute lease alone would carry one day's readers into the
    // next day's Mass.
    test('4 AM clears it even inside its 20 minutes', () async {
      clock = DateTime(2026, 10, 4, 3, 55);
      await LineupStore.save('mass', {'reader1': 'alice'});
      await LineupStore.saveSelectedServiceId('mass');

      clock = DateTime(2026, 10, 4, 4, 10);

      expect(await LineupStore.load('mass'), isEmpty);
      expect(await LineupStore.loadSelectedServiceId(), isNull);
    });

    test('renewing across 4 AM does not carry it over', () async {
      clock = DateTime(2026, 10, 4, 3, 50);
      await LineupStore.save('mass', {'reader1': 'alice'});
      clock = DateTime(2026, 10, 4, 3, 55);
      expect(await LineupStore.renew(), isTrue);

      clock = DateTime(2026, 10, 4, 4, 0);
      expect(await LineupStore.renew(), isFalse);
      expect(await LineupStore.load('mass'), isEmpty);
    });

    test('renewed all day, it is kept until 4 AM', () async {
      clock = DateTime(2026, 10, 3, 9, 0);
      await LineupStore.save('mass', {'reader1': 'alice'});
      while (clock.isBefore(DateTime(2026, 10, 4, 3, 55))) {
        clock = clock.add(const Duration(minutes: 5));
        expect(await LineupStore.renew(), isTrue);
      }

      clock = DateTime(2026, 10, 4, 3, 59);
      expect(await LineupStore.load('mass'), {'reader1': 'alice'});
    });
  });

  test('a Mass that runs past midnight keeps its lineup', () async {
    // Christmas Midnight Mass and a late Easter Vigil cross midnight: a
    // midnight cutoff would empty the readers halfway through.
    clock = DateTime(2026, 12, 24, 23, 30);
    await LineupStore.save('midnight', {'reader1': 'alice'});
    while (clock.isBefore(DateTime(2026, 12, 25, 1, 30))) {
      clock = clock.add(const Duration(minutes: 5));
      expect(await LineupStore.renew(), isTrue);
    }

    expect(await LineupStore.load('midnight'), {'reader1': 'alice'});
  });

  test('the stored bytes are pinned', () async {
    await LineupStore.save('mass', {'reader1': 'alice', 'reader2': 'bob'});
    await LineupStore.saveSelectedServiceId('mass');

    final prefs = await SharedPreferences.getInstance();
    expect({
      for (final k in prefs.getKeys()) k: prefs.get(k)
    }, {
      'service_lineup_mass': '{"reader1":"alice","reader2":"bob"}',
      'service_tab_selected_service': 'mass',
      'lineup_lease_expires_at':
          DateTime(2026, 10, 4, 9, 20).millisecondsSinceEpoch,
    });
  });

  group('corrupt saved data loads as nothing and is cleared', () {
    // A service whose saved lineup cannot be read must still open, or every
    // pick of it raises an error and the cue list never comes up.
    Future<void> storeRaw(Map<String, Object> values) async {
      SharedPreferences.setMockInitialValues({
        LineupStore.leaseKey:
            clock.add(const Duration(minutes: 10)).millisecondsSinceEpoch,
        ...values,
      });
    }

    for (final (label, raw) in [
      ('a role mapped to a non-string', '{"reader1": 42}'),
      ('text that is not JSON', 'not json'),
      ('JSON that is not an object', '["alice"]'),
    ]) {
      test(label, () async {
        await storeRaw({'${LineupStore.keyPrefix}mass': raw});

        expect(await LineupStore.load('mass'), isEmpty);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey('${LineupStore.keyPrefix}mass'), isFalse);
      });
    }

    test('a lineup stored as the wrong type', () async {
      await storeRaw({'${LineupStore.keyPrefix}mass': 42});

      expect(await LineupStore.load('mass'), isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('${LineupStore.keyPrefix}mass'), isFalse);
    });

    test('a selected service stored as the wrong type', () async {
      await storeRaw({LineupStore.selectedServiceKey: 42});

      expect(await LineupStore.loadSelectedServiceId(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(LineupStore.selectedServiceKey), isFalse);
    });

    test('an unreadable expiry counts as expired', () async {
      SharedPreferences.setMockInitialValues({
        LineupStore.leaseKey: 'tomorrow',
        '${LineupStore.keyPrefix}mass': '{"reader1":"alice"}',
      });

      expect(await LineupStore.renew(), isFalse);
      expect(await LineupStore.load('mass'), isEmpty);
    });
  });
}
