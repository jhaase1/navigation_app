import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navigation_app/services/backup/config_mutation_notifier.dart';
import 'package:navigation_app/services/config_bundle.dart';
import 'package:navigation_app/services/lineup_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a saved lineup loads back for the same service', () async {
    await LineupStore.save('mass', {'reader1': 'alice', 'reader2': 'bob'});

    expect(await LineupStore.load('mass'),
        {'reader1': 'alice', 'reader2': 'bob'});
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
}
