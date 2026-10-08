import 'dart:ui' show AppLifecycleState;

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/lineup_lease.dart';
import 'package:navigation_app/services/lineup_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late DateTime start;
  late Duration elapsed;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    start = DateTime(2026, 10, 4, 9, 0);
    elapsed = Duration.zero;
    LineupStore.now = () => start.add(elapsed);
  });
  tearDown(() => LineupStore.now = DateTime.now);

  /// Moves the test's fake timers and the store's clock forward together.
  Future<void> advance(WidgetTester tester, Duration by) async {
    final end = elapsed + by;
    while (elapsed < end) {
      elapsed += const Duration(minutes: 1);
      await tester.pump(const Duration(minutes: 1));
    }
  }

  void setLifecycle(WidgetTester tester, AppLifecycleState state) =>
      tester.binding.handleAppLifecycleStateChanged(state);

  testWidgets('while the app is on screen the lineup does not expire',
      (tester) async {
    setLifecycle(tester, AppLifecycleState.resumed);
    final lease = LineupLease()..start();
    await LineupStore.save('mass', {'reader1': 'alice'});

    await advance(tester, const Duration(minutes: 90));

    expect(await LineupStore.load('mass'), {'reader1': 'alice'});
    // Stopped in the test body: the binding checks for live timers before
    // tear-downs run.
    lease.dispose();
  });

  testWidgets('a Mac window behind another app still counts as on screen',
      (tester) async {
    // macOS reports a visible but unfocused window as inactive. The
    // operator running slides in another app must not lose the lineup.
    setLifecycle(tester, AppLifecycleState.resumed);
    final lease = LineupLease()..start();
    await LineupStore.save('mass', {'reader1': 'alice'});
    setLifecycle(tester, AppLifecycleState.inactive);

    await advance(tester, const Duration(minutes: 60));

    expect(await LineupStore.load('mass'), {'reader1': 'alice'});
    // Stopped in the test body: the binding checks for live timers before
    // tear-downs run.
    lease.dispose();
  });

  testWidgets('with the screen off it lapses after 20 minutes',
      (tester) async {
    setLifecycle(tester, AppLifecycleState.resumed);
    final lease = LineupLease()..start();
    await LineupStore.save('mass', {'reader1': 'alice'});

    setLifecycle(tester, AppLifecycleState.inactive);
    setLifecycle(tester, AppLifecycleState.hidden);
    await advance(tester, const Duration(minutes: 21));

    expect(await LineupStore.load('mass'), isEmpty);
    // Stopped in the test body: the binding checks for live timers before
    // tear-downs run.
    lease.dispose();
  });

  testWidgets('coming back inside 20 minutes keeps it, and renewal resumes',
      (tester) async {
    setLifecycle(tester, AppLifecycleState.resumed);
    final lease = LineupLease()..start();
    await LineupStore.save('mass', {'reader1': 'alice'});

    setLifecycle(tester, AppLifecycleState.inactive);
    setLifecycle(tester, AppLifecycleState.hidden);
    await advance(tester, const Duration(minutes: 15));
    setLifecycle(tester, AppLifecycleState.inactive);
    setLifecycle(tester, AppLifecycleState.resumed);
    await advance(tester, const Duration(minutes: 60));

    expect(await LineupStore.load('mass'), {'reader1': 'alice'});
    // Stopped in the test body: the binding checks for live timers before
    // tear-downs run.
    lease.dispose();
  });

  testWidgets('coming back after 20 minutes clears it and says so',
      (tester) async {
    setLifecycle(tester, AppLifecycleState.resumed);
    final lease = LineupLease()..start();
    await LineupStore.save('mass', {'reader1': 'alice'});
    var announced = 0;
    void listener() => announced++;
    LineupStore.expirations.addListener(listener);
    addTearDown(() => LineupStore.expirations.removeListener(listener));

    setLifecycle(tester, AppLifecycleState.inactive);
    setLifecycle(tester, AppLifecycleState.hidden);
    await advance(tester, const Duration(minutes: 30));
    setLifecycle(tester, AppLifecycleState.inactive);
    setLifecycle(tester, AppLifecycleState.resumed);
    await tester.pump();

    expect(announced, 1,
        reason: 'a Service tab still on screen must drop its copy too');
    // Stopped in the test body: the binding checks for live timers before
    // tear-downs run.
    lease.dispose();
  });
}
