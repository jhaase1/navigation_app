import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/backup_controller.dart';
import 'package:navigation_app/services/backup/backup_scheduler.dart';
import 'package:navigation_app/services/backup/backup_service.dart';
import 'package:navigation_app/services/backup/device_label.dart';
import 'package:navigation_app/services/backup/mock/mock_backup_target.dart';
import 'package:navigation_app/widgets/backup/device_name_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> settleDialog(WidgetTester tester) async {
    // Autofocus on the name field starts a blinking cursor;
    // pumpAndSettle never returns while that animation is scheduled.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> open(WidgetTester tester, BackupController controller) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => nameThisMachine(context, controller),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await settleDialog(tester);
  }

  testWidgets('a typed name is saved and unblocks the first backup',
      (tester) async {
    final controller = BackupController.disabled();
    await open(tester, controller);

    await tester.enterText(find.byType(TextField), 'Sanctuary Mac mini');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settleDialog(tester);

    expect(await DeviceLabel.load(), 'Sanctuary Mac mini');
    expect(await DeviceLabel.require(), 'Sanctuary Mac mini');
    await controller.dispose();
  });

  testWidgets('naming the machine retries the backup there and then',
      (tester) async {
    // The name was saved but nothing retried the backup, so "Name this
    // machine" stayed on the pill until the next ten-minute sweep.
    final service = BackupService(
      target: MockBackupTarget(),
      targetIdentity: 'mock:test',
      deviceLabel: DeviceLabel.require,
      readBundleJson: () async => {'schemaVersion': 1},
      localIsPristine: () async => true,
    );
    final scheduler = BackupScheduler(
      service: service,
      sweepInterval: const Duration(days: 1),
      sleep: (_) async {},
    );
    final controller =
        BackupController.forService(service, scheduler: scheduler);
    await open(tester, controller);
    final pullsBefore = scheduler.pullCount;

    await tester.enterText(find.byType(TextField), 'Tech Booth iPad');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settleDialog(tester);

    expect(await DeviceLabel.load(), 'Tech Booth iPad');
    expect(scheduler.pullCount, greaterThan(pullsBefore));
    // As in backup_wiring_test: the scheduler's stream has to be cancelled
    // off the widget-test fake clock.
    await tester.runAsync(scheduler.stop);
    await controller.dispose();
  });

  testWidgets('a worthless name is refused and nothing is saved',
      (tester) async {
    final controller = BackupController.disabled();
    await open(tester, controller);

    await tester.enterText(find.byType(TextField), 'localhost');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settleDialog(tester);

    expect(await DeviceLabel.load(), isNull,
        reason: 'a machine labelled localhost is a lie the conflict UI '
            'would repeat back');
    expect(find.textContaining('not specific enough'), findsOneWidget);
    await controller.dispose();
  });

  testWidgets('reopening it offers the saved name back, not a blank field',
      (tester) async {
    // The collision check used to count this machine's own revisions, which
    // blanked the field the moment the name started working.
    await DeviceLabel.save('Sanctuary Mac mini');
    final controller = BackupController.disabled();
    await open(tester, controller);

    expect(
        find.widgetWithText(TextField, 'Sanctuary Mac mini'), findsOneWidget);
    await controller.dispose();
  });
}
