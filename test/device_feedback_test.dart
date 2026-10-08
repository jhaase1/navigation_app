import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/utils/device_feedback.dart';

Widget _host(String Function() message, {bool failed = false}) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showDeviceResponse(context, message(), failed: failed),
            child: const Text('fire'),
          ),
        ),
      ),
    );

void main() {
  testWidgets('shows the device message to the operator', (tester) async {
    await tester.pumpWidget(_host(() => 'Cam 1 not connected'));
    await tester.tap(find.text('fire'));
    await tester.pump();

    expect(find.text('Cam 1 not connected'), findsOneWidget);
  });

  testWidgets('a newer message replaces the one on screen', (tester) async {
    var msg = 'first';
    await tester.pumpWidget(_host(() => msg));
    await tester.tap(find.text('fire'));
    await tester.pump();
    msg = 'second';
    await tester.tap(find.text('fire'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);
  });

  testWidgets('ignores empty messages', (tester) async {
    await tester.pumpWidget(_host(() => ''));
    await tester.tap(find.text('fire'));
    await tester.pump();

    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a failure is marked as a failure', (tester) async {
    await tester.pumpWidget(_host(() => 'Cam 1 not connected', failed: true));
    await tester.tap(find.text('fire'));
    await tester.pump();

    expect(find.descendant(
            of: find.byType(SnackBar), matching: find.byIcon(Icons.error)),
        findsOneWidget);
  });

  testWidgets('a success is not marked as a failure', (tester) async {
    await tester.pumpWidget(_host(() => 'Macro 3 executed'));
    await tester.tap(find.text('fire'));
    await tester.pump();

    expect(find.text('Macro 3 executed'), findsOneWidget);
    expect(find.byIcon(Icons.error), findsNothing);
  });

  testWidgets('a failure stays up longer than a success', (tester) async {
    await tester.pumpWidget(_host(() => 'Cam 1 not connected', failed: true));
    await tester.tap(find.text('fire'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));

    expect(find.text('Cam 1 not connected'), findsOneWidget,
        reason: 'a success is gone after 3 s; a failure must outlast a glance');
  });
}
