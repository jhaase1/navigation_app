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

/// Fires each queued (message, failed, link) in turn, one per tap.
Widget _sequence(List<(String, bool, String?)> shots) {
  var i = 0;
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () {
            final (message, failed, link) = shots[i++];
            showDeviceResponse(context, message, failed: failed, link: link);
          },
          child: const Text('fire'),
        ),
      ),
    ),
  );
}

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

  testWidgets('a success does not knock a failure off the screen',
      (tester) async {
    var msg = 'Cam 2 not connected';
    var failed = true;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDeviceResponse(context, msg, failed: failed),
            child: const Text('fire'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('fire'));
    await tester.pump();

    // The next cue succeeds half a second later.
    await tester.pump(const Duration(milliseconds: 500));
    msg = 'Macro 4 executed';
    failed = false;
    await tester.tap(find.text('fire'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('Cam 2 not connected'), findsOneWidget,
        reason: 'the failure is the message the operator must not miss');
    expect(find.text('Macro 4 executed'), findsNothing);
  });

  testWidgets('a newer failure replaces an older one', (tester) async {
    var msg = 'Cam 2 not connected';
    await tester.pumpWidget(_host(() => msg, failed: true));
    await tester.tap(find.text('fire'));
    await tester.pump();
    msg = 'Roland not connected';
    await tester.tap(find.text('fire'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('Cam 2 not connected'), findsNothing);
    expect(find.text('Roland not connected'), findsOneWidget);
  });

  testWidgets('a success shows again once the failure has gone',
      (tester) async {
    var msg = 'Cam 2 not connected';
    var failed = true;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDeviceResponse(context, msg, failed: failed),
            child: const Text('fire'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('fire'));
    await tester.pumpAndSettle(); // in, then its 6 s clock starts
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.text('Cam 2 not connected'), findsNothing);

    msg = 'Macro 4 executed';
    failed = false;
    await tester.tap(find.text('fire'));
    await tester.pump();

    expect(find.text('Macro 4 executed'), findsOneWidget);
  });

  testWidgets('a reconnect replaces the lost-link message it answers',
      (tester) async {
    await tester.pumpWidget(_sequence([
      ('Roland connection lost. Reconnecting…', true, 'roland'),
      ('Roland reconnected', false, 'roland'),
    ]));
    await tester.tap(find.text('fire'));
    await tester.pump();
    await tester.tap(find.text('fire'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('Roland reconnected'), findsOneWidget);
  });

  testWidgets('a link coming back does not hide a failed command',
      (tester) async {
    // A lost reply drops the link. The cue's failure — "it may have run" —
    // is what the operator needs before firing again, not the link's
    // round trip, which the pill and the badge already show.
    await tester.pumpWidget(_sequence([
      ('Macro error: no reply. It may have run.', true, null),
      ('Roland connection lost. Reconnecting…', true, 'roland'),
      ('Roland reconnected', false, 'roland'),
    ]));
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('fire'));
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('Macro error: no reply. It may have run.'),
        findsOneWidget);
    expect(find.text('Roland reconnected'), findsNothing);
  });

  testWidgets("one device's recovery does not clear another's failure",
      (tester) async {
    await tester.pumpWidget(_sequence([
      ('Camera 2 not responding', true, 'camera:Camera 2'),
      ('Roland reconnected', false, 'roland'),
    ]));
    await tester.tap(find.text('fire'));
    await tester.pump();
    await tester.tap(find.text('fire'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('Camera 2 not responding'), findsOneWidget);
  });
}
