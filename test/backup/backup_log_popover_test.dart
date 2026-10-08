import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/app_fault.dart';
import 'package:navigation_app/services/backup/backup_controller.dart';
import 'package:navigation_app/services/backup/backup_service.dart';
import 'package:navigation_app/services/backup/backup_status.dart';
import 'package:navigation_app/services/backup/mock/mock_backup_target.dart';
import 'package:navigation_app/widgets/backup/backup_log_popover.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Opened from a plain button, not from the pill: this task ships before the
  // pill does, and a test that needs the next task's widget cannot run.
  Future<BackupController> openPopover(WidgetTester tester) async {
    final controller = BackupController.disabled();
    await controller.log.recordFault(AppFault.backup(
        BackupFailureKind.transientServer, 'Drive returned an error.',
        operation: 'push', targetIdentity: 'mock:test'));
    controller.status.value = const BackupStatus(configured: true);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        // The Builder must sit INSIDE the body, wrapping the button.
        // showBackupLogPopover anchors to the context it is handed: with the
        // Builder above Scaffold, findRenderObject() returns the full-screen
        // Scaffold, so the panel is positioned 8px below y=600 and renders off
        // the 800x600 test surface entirely. Test 1 then cannot reach 'Mark as
        // read'; tests 2 and 3 passed only because find/ works on off-screen
        // widgets — they were asserting against a popover that was never shown.
        // Anchoring to the button also matches how Task 8's pill will call it.
        body: Align(
          alignment: Alignment.topLeft,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showBackupLogPopover(context, controller),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('a history row can be marked as read, and it sticks',
      (tester) async {
    final controller = await openPopover(tester);

    expect(find.text('Drive returned an error.'), findsOneWidget);
    await tester.tap(find.byTooltip('Mark as read'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Mark as read'), findsNothing);
    expect(controller.log.entries.value.single.dismissed, isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('backup_log'), contains('"read":true'));

    await controller.dispose();
  });

  testWidgets('a tap outside closes it AND reaches what was underneath',
      (tester) async {
    // The reason this is an overlay and not a dialog route. A transparent
    // barrier still eats the tap, which during a service costs the operator a
    // wasted press on a dead screen before they can hit a camera preset.
    var pressedBehind = 0;
    final controller = BackupController.disabled();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            // Same anchor fix as above: the Builder wraps the button, so the
            // panel is positioned under the button rather than under the
            // full-screen Scaffold. Without it this test passed vacuously —
            // it proved a tap reached the button behind a popover that was
            // never on screen.
            Builder(
              builder: (context) => TextButton(
                onPressed: () => showBackupLogPopover(context, controller),
                child: const Text('open'),
              ),
            ),
            const SizedBox(height: 300),
            TextButton(
              onPressed: () => pressedBehind++,
              child: const Text('camera preset'),
            ),
          ],
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Backup'), findsOneWidget);

    await tester.tap(find.text('camera preset'));
    await tester.pumpAndSettle();

    expect(find.text('Backup'), findsNothing, reason: 'the popover closed');
    expect(pressedBehind, 1,
        reason: 'and the tap was not swallowed by a barrier');

    await controller.dispose();
  });

  testWidgets('the active condition is pinned and has no dismiss control',
      (tester) async {
    final controller = BackupController.disabled();
    final fault = AppFault.backup(
        BackupFailureKind.authExpired, 'Sign in again.',
        operation: 'pull', targetIdentity: 'mock:test');
    await controller.log.recordFault(fault);
    controller.status.value =
        BackupStatus(configured: true, activeCondition: fault);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        // The Builder must sit INSIDE the body, wrapping the button.
        // showBackupLogPopover anchors to the context it is handed: with the
        // Builder above Scaffold, findRenderObject() returns the full-screen
        // Scaffold, so the panel is positioned 8px below y=600 and renders off
        // the 800x600 test surface entirely. Test 1 then cannot reach 'Mark as
        // read'; tests 2 and 3 passed only because find/ works on off-screen
        // widgets — they were asserting against a popover that was never shown.
        // Anchoring to the button also matches how Task 8's pill will call it.
        body: Align(
          alignment: Alignment.topLeft,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showBackupLogPopover(context, controller),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Shown once — pinned — and not as a dismissable history row.
    expect(find.text('Sign in again.'), findsOneWidget);
    expect(find.byTooltip('Mark as read'), findsNothing);

    await controller.dispose();
  });

  testWidgets('a device fault offers no backup retry', (tester) async {
    final controller = BackupController.forService(BackupService(
      target: MockBackupTarget(),
      targetIdentity: 'mock:test',
      deviceLabel: () async => 'Mac mini',
      readBundleJson: () async => {'schemaVersion': 1},
      localIsPristine: () async => true,
    ));
    await controller.reportDeviceFault(AppFault.device(
        FaultDomain.camera, 'Camera 2', 'Camera 2 is not answering.'));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showBackupLogPopover(context, controller),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Camera 2 is not answering.'), findsOneWidget);
    expect(find.text('Retry now'), findsNothing,
        reason: 'retrying the backup cannot bring a camera back');
    await controller.dispose();
  });
}
