import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/app_fault.dart';
import 'package:navigation_app/services/backup/backup_controller.dart';
import 'package:navigation_app/services/backup/backup_status.dart';
import 'package:navigation_app/widgets/backup/backup_status_pill.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows the derived label and opens the log when tapped',
      (tester) async {
    final controller = BackupController.disabled();
    controller.status.value = const BackupStatus(
      configured: true,
      hasDurableHead: true,
      isDirty: true,
      pendingCount: 3,
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          centerTitle: false,
          title: BackupStatusPill(controller: controller),
        ),
      ),
    ));

    expect(find.text('3 changes pending'), findsOneWidget);

    await tester.tap(find.text('3 changes pending'));
    await tester.pumpAndSettle();

    expect(find.text('Backup'), findsOneWidget); // the popover header

    await tester.pumpWidget(const SizedBox.shrink());
    await controller.dispose();
  });

  testWidgets('a red condition is still tappable', (tester) async {
    final controller = BackupController.disabled();
    controller.status.value = BackupStatus(
      configured: true,
      hasDurableHead: true,
      activeCondition: AppFault.backup(
          BackupFailureKind.authExpired, 'Sign in again.',
          operation: 'pull'),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          centerTitle: false,
          title: BackupStatusPill(controller: controller),
        ),
      ),
    ));

    expect(find.text('Sign-in expired'), findsOneWidget);
    await tester.tap(find.text('Sign-in expired'));
    await tester.pumpAndSettle();
    expect(find.text('Backup'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await controller.dispose();
  });
}
