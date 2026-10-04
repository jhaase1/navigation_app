import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navigation_app/models/service.dart';
import 'package:navigation_app/services/mock/mock_roland_service.dart';
import 'package:navigation_app/widgets/service_tab.dart';

/// A switcher whose macros finish only when the test says so.
class _GatedRoland extends MockRolandService {
  final calls = <int>[];
  Completer<void> gate = Completer<void>();

  @override
  Future<void> executeMacro(int macro) {
    calls.add(macro);
    return gate.future;
  }
}

final _service = Service(
  id: 's1',
  name: 'Mass',
  steps: [
    const ServiceStep(id: 'st1', type: StepType.macro, macroNumber: 1),
    const ServiceStep(id: 'st2', type: StepType.macro, macroNumber: 2),
  ],
);

final _other = Service(
  id: 's2',
  name: 'Vespers',
  steps: [
    const ServiceStep(id: 'st3', type: StepType.macro, macroNumber: 3),
  ],
);

// Fixed pumps rather than pumpAndSettle: an in-flight cue's spinner never
// settles.
Future<void> _pick(WidgetTester tester, String name) async {
  await tester.tap(find.byType(DropdownButton<String?>));
  await tester.pump(const Duration(seconds: 1));
  await tester.tap(find.text(name).last);
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _open(WidgetTester tester, _GatedRoland roland,
    {bool connected = true}) async {
  await _show(tester, roland, [_service, _other], connected: connected);
  await _pick(tester, 'Mass');
}

Future<void> _show(
    WidgetTester tester, _GatedRoland roland, List<Service> services,
    {bool connected = true}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ServiceTab(
        cameras: const [],
        people: const [],
        positions: const [],
        services: services,
        heightRanges: const [],
        rolandService: roland,
        rolandConnected: ValueNotifier(connected),
        onResponse: (_) {},
      ),
    ),
  ));
}

Finder _inStep(String label, Finder matching) => find.descendant(
    of: find.ancestor(of: find.text(label), matching: find.byType(ListTile)),
    matching: matching);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a cue shows a spinner while its command is in flight',
      (tester) async {
    final roland = _GatedRoland();
    await _open(tester, roland);

    await tester.tap(find.text('1. Macro 1'));
    await tester.pump();

    expect(_inStep('1. Macro 1', find.byType(CircularProgressIndicator)),
        findsOneWidget);
    roland.gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a cue shows a check once the device confirms it',
      (tester) async {
    final roland = _GatedRoland();
    await _open(tester, roland);

    await tester.tap(find.text('1. Macro 1'));
    await tester.pump();
    roland.gate.complete();
    await tester.pumpAndSettle();

    expect(_inStep('1. Macro 1', find.byIcon(Icons.check_circle)),
        findsOneWidget);
    expect(_inStep('1. Macro 1', find.byType(CircularProgressIndicator)),
        findsNothing);
  });

  testWidgets('a cue shows a failure badge when the device errors',
      (tester) async {
    final roland = _GatedRoland();
    await _open(tester, roland);

    await tester.tap(find.text('1. Macro 1'));
    await tester.pump();
    roland.gate.completeError(Exception('NACK'));
    await tester.pumpAndSettle();

    expect(_inStep('1. Macro 1', find.byIcon(Icons.error)), findsOneWidget);
  });

  testWidgets('a cue that cannot be sent at all is marked failed',
      (tester) async {
    final roland = _GatedRoland();
    await _open(tester, roland, connected: false);

    await tester.tap(find.text('1. Macro 1'));
    await tester.pumpAndSettle();

    expect(roland.calls, isEmpty);
    expect(_inStep('1. Macro 1', find.byIcon(Icons.error)), findsOneWidget);
  });

  testWidgets('re-tapping an in-flight cue does not send it twice',
      (tester) async {
    final roland = _GatedRoland();
    await _open(tester, roland);

    await tester.tap(find.text('1. Macro 1'));
    await tester.pump();
    await tester.tap(find.text('1. Macro 1'));
    await tester.pump();

    expect(roland.calls, [1]);
    roland.gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('another cue can fire while one is still in flight',
      (tester) async {
    final roland = _GatedRoland();
    await _open(tester, roland);

    await tester.tap(find.text('1. Macro 1'));
    await tester.pump();
    await tester.tap(find.text('2. Macro 2'));
    await tester.pump();

    expect(roland.calls, [1, 2]);
    roland.gate.complete();
    await tester.pumpAndSettle();
    expect(_inStep('1. Macro 1', find.byIcon(Icons.check_circle)),
        findsOneWidget);
    expect(_inStep('2. Macro 2', find.byIcon(Icons.check_circle)),
        findsOneWidget);
  });

  testWidgets('switching services clears cue states and ignores late results',
      (tester) async {
    final roland = _GatedRoland();
    await _open(tester, roland);

    await tester.tap(find.text('1. Macro 1'));
    await tester.pump();
    await _pick(tester, 'Vespers');
    roland.gate.complete();
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_circle), findsNothing);
    await _pick(tester, 'Mass');
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });

  testWidgets('a badge stays on its cue when a step is added above it',
      (tester) async {
    final roland = _GatedRoland()..gate.complete();
    await _open(tester, roland);
    await tester.tap(find.text('1. Macro 1'));
    await tester.pumpAndSettle();

    // Someone records a new opening step into the running service.
    await _show(tester, roland, [
      Service(id: 's1', name: 'Mass', steps: [
        const ServiceStep(id: 'st0', type: StepType.macro, macroNumber: 9),
        ..._service.steps,
      ]),
      _other,
    ]);
    await tester.pumpAndSettle();

    // A check on a cue that never ran tells the operator it is done.
    expect(_inStep('1. Macro 9', find.byIcon(Icons.check_circle)),
        findsNothing);
    expect(_inStep('2. Macro 1', find.byIcon(Icons.check_circle)),
        findsOneWidget);
  });

  testWidgets('a block used twice keeps a badge per occurrence',
      (tester) async {
    final roland = _GatedRoland()..gate.complete();
    final block = Service(id: 'b', name: 'Psalm', steps: [
      const ServiceStep(id: 'pb', type: StepType.macro, macroNumber: 5),
    ]);
    await _show(tester, roland, [
      Service(id: 's1', name: 'Mass', steps: [
        const ServiceStep(id: 'x1', type: StepType.block, subServiceId: 'b'),
        const ServiceStep(id: 'x2', type: StepType.block, subServiceId: 'b'),
      ]),
      block,
    ]);
    await _pick(tester, 'Mass');

    await tester.tap(find.text('1. Macro 5'));
    await tester.pumpAndSettle();

    expect(_inStep('2. Macro 5', find.byIcon(Icons.check_circle)),
        findsNothing);
  });
}
