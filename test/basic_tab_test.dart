import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/abstract/roland_service_abstract.dart';
import 'package:navigation_app/widgets/basic_tab.dart';

class _FakeRoland extends RolandServiceAbstract {
  final List<String> calls = [];
  bool shouldThrow = false;

  void _maybeThrow(String op) {
    if (shouldThrow) throw Exception('$op failed');
  }

  @override Future<void> cut() async { _maybeThrow('cut'); calls.add('cut'); }
  @override Future<void> auto({String? input, int? time}) async { _maybeThrow('auto'); calls.add('auto'); }
  @override Future<void> setProgram(String input) async { _maybeThrow('setProgram'); calls.add('setProgram:$input'); }
  @override Future<void> setPreview(String input) async { _maybeThrow('setPreview'); calls.add('setPreview:$input'); }
  @override Future<void> executeMacro(int macro) async { _maybeThrow('executeMacro'); calls.add('executeMacro:$macro'); }
  @override Future<void> setPinPSource(String pinp, String source) async {}
  @override Future<void> getPinPSource(String pinp) async {}
  @override Future<void> setPinPPosition(String pinp, int h, int v) async {}
  @override Future<void> getPinPPosition(String pinp) async {}
  @override Future<void> setPinPPgm(String pinp, bool on) async {}
  @override Future<void> getPinPPgm(String pinp) async {}
  @override Future<void> setPinPPvw(String pinp, bool on) async {}
  @override Future<void> getPinPPvw(String pinp) async {}
  @override Future<String> getMacroName(int macro) async => 'Macro $macro';
  @override Future<bool> macroExists(int macro) async => true;
  @override Future<void> disconnect() async {}
}

Widget _build({
  ValueNotifier<bool>? connected,
  bool initialConnected = false,
  RolandServiceAbstract? service,
  ValueChanged<String>? onResponse,
}) {
  final notifier = connected ?? ValueNotifier(initialConnected);
  return MaterialApp(
    theme: ThemeData(useMaterial3: false),
    home: Scaffold(
      body: SingleChildScrollView(
        child: BasicTab(
          rolandConnected: notifier,
          onRolandResponse: onResponse ?? (_) {},
          rolandService: service,
        ),
      ),
    ),
  );
}

void main() {
  group('BasicTab — disconnected state', () {
    testWidgets('shows connect prompt when not connected', (tester) async {
      await tester.pumpWidget(_build());
      expect(find.text('Connect to Roland device first'), findsOneWidget);
    });

    testWidgets('does not show CUT or AUTO when disconnected', (tester) async {
      await tester.pumpWidget(_build());
      expect(find.text('CUT'), findsNothing);
      expect(find.text('AUTO'), findsNothing);
    });

    testWidgets('does not show section headers when disconnected', (tester) async {
      await tester.pumpWidget(_build());
      expect(find.text('Transitions'), findsNothing);
      expect(find.text('Program Select (PGM)'), findsNothing);
    });
  });

  group('BasicTab — connected state', () {
    testWidgets('does not show connect prompt when connected', (tester) async {
      await tester.pumpWidget(_build(initialConnected: true));
      expect(find.text('Connect to Roland device first'), findsNothing);
    });

    testWidgets('shows Transitions section with CUT and AUTO', (tester) async {
      await tester.pumpWidget(_build(initialConnected: true));
      expect(find.text('Transitions'), findsOneWidget);
      expect(find.text('CUT'), findsOneWidget);
      expect(find.text('AUTO'), findsOneWidget);
    });

    testWidgets('shows Program Select section with 8 chips', (tester) async {
      await tester.pumpWidget(_build(initialConnected: true));
      expect(find.text('Program Select (PGM)'), findsOneWidget);
      expect(find.text('Input 1'), findsWidgets);
      expect(find.text('Input 8'), findsWidgets);
    });

    testWidgets('shows Preview Select section', (tester) async {
      await tester.pumpWidget(_build(initialConnected: true));
      expect(find.text('Preview Select (PST)'), findsOneWidget);
    });

    testWidgets('shows Macros section with 8 buttons', (tester) async {
      await tester.pumpWidget(_build(initialConnected: true));
      expect(find.text('Macros'), findsOneWidget);
      for (int i = 1; i <= 8; i++) {
        expect(find.text('Macro $i'), findsOneWidget);
      }
    });
  });

  group('BasicTab — service interactions', () {
    testWidgets('CUT calls rolandService.cut() and fires success response',
        (tester) async {
      final svc = _FakeRoland();
      String? response;
      await tester.pumpWidget(
          _build(initialConnected: true, service: svc, onResponse: (r) => response = r));

      await tester.tap(find.text('CUT'));
      await tester.pumpAndSettle();

      expect(svc.calls, contains('cut'));
      expect(response, 'CUT executed');
    });

    testWidgets('AUTO calls rolandService.auto() and fires success response',
        (tester) async {
      final svc = _FakeRoland();
      String? response;
      await tester.pumpWidget(
          _build(initialConnected: true, service: svc, onResponse: (r) => response = r));

      await tester.tap(find.text('AUTO'));
      await tester.pumpAndSettle();

      expect(svc.calls, contains('auto'));
      expect(response, 'AUTO transition executed');
    });

    testWidgets('PGM chip calls setProgram(INPUT1) and fires success response',
        (tester) async {
      final svc = _FakeRoland();
      String? response;
      await tester.pumpWidget(
          _build(initialConnected: true, service: svc, onResponse: (r) => response = r));

      // Two 'Input 1' chips exist (PGM first, PST second)
      await tester.tap(find.text('Input 1').first);
      await tester.pumpAndSettle();

      expect(svc.calls, contains('setProgram:INPUT1'));
      expect(response, 'Set Program to INPUT1');
    });

    testWidgets('PST chip calls setPreview(INPUT1) and fires success response',
        (tester) async {
      final svc = _FakeRoland();
      String? response;
      await tester.pumpWidget(
          _build(initialConnected: true, service: svc, onResponse: (r) => response = r));

      // Two 'Input 1' chips: first is PGM, last is PST
      await tester.tap(find.text('Input 1').last);
      await tester.pumpAndSettle();

      expect(svc.calls, contains('setPreview:INPUT1'));
      expect(response, 'Set Preview to INPUT1');
    });

    testWidgets('Macro 1 button calls executeMacro(1) and fires success response',
        (tester) async {
      final svc = _FakeRoland();
      String? response;
      await tester.pumpWidget(
          _build(initialConnected: true, service: svc, onResponse: (r) => response = r));

      await tester.tap(find.text('Macro 1'));
      await tester.pumpAndSettle();

      expect(svc.calls, contains('executeMacro:1'));
      expect(response, 'Executed Macro 1');
    });

    testWidgets('Macro 8 button calls executeMacro(8)', (tester) async {
      final svc = _FakeRoland();
      await tester.pumpWidget(
          _build(initialConnected: true, service: svc));

      await tester.tap(find.text('Macro 8'));
      await tester.pumpAndSettle();

      expect(svc.calls, contains('executeMacro:8'));
    });

    testWidgets('service error fires error response for CUT', (tester) async {
      final svc = _FakeRoland()..shouldThrow = true;
      String? response;
      await tester.pumpWidget(
          _build(initialConnected: true, service: svc, onResponse: (r) => response = r));

      await tester.tap(find.text('CUT'));
      await tester.pumpAndSettle();

      expect(svc.calls, isEmpty);
      expect(response, startsWith('Error:'));
    });

    testWidgets('null service — tapping CUT does not call onRolandResponse',
        (tester) async {
      bool called = false;
      await tester.pumpWidget(_build(
          initialConnected: true,
          service: null,
          onResponse: (_) => called = true));

      await tester.tap(find.text('CUT'));
      await tester.pumpAndSettle();

      expect(called, isFalse);
    });
  });

  group('BasicTab — live connection change', () {
    testWidgets('rebuilds to show controls when rolandConnected changes to true',
        (tester) async {
      final notifier = ValueNotifier(false);
      await tester.pumpWidget(_build(connected: notifier));

      expect(find.text('Connect to Roland device first'), findsOneWidget);

      notifier.value = true;
      await tester.pump();

      expect(find.text('Connect to Roland device first'), findsNothing);
      expect(find.text('CUT'), findsOneWidget);
    });

    testWidgets('rebuilds to show prompt when rolandConnected changes to false',
        (tester) async {
      final notifier = ValueNotifier(true);
      await tester.pumpWidget(_build(connected: notifier));
      expect(find.text('CUT'), findsOneWidget);

      notifier.value = false;
      await tester.pump();

      expect(find.text('CUT'), findsNothing);
      expect(find.text('Connect to Roland device first'), findsOneWidget);
    });
  });
}
