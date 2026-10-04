import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/app_fault.dart';
import 'package:navigation_app/services/backup/backup_controller.dart';
import 'package:navigation_app/services/backup/backup_service.dart';
import 'package:navigation_app/services/backup/backup_status.dart';
import 'package:navigation_app/services/backup/mock/mock_backup_target.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  AppFault switcherDown() => AppFault.device(
      FaultDomain.roland, 'Roland', 'The switcher is not connected.');
  AppFault cameraDown(String name) => AppFault.device(
      FaultDomain.camera, name, '$name is not answering.');

  group('the pill names the device', () {
    test('a lost switcher reads "Switcher offline", in red', () {
      final s = BackupStatus(activeCondition: switcherDown());

      expect(s.state, BackupPillState.failing);
      expect(s.label(DateTime.now()), 'Switcher offline');
    });

    test('a lost camera reads by its name', () {
      final s = BackupStatus(activeCondition: cameraDown('Camera 2'));

      expect(s.label(DateTime.now()), 'Camera 2 offline');
    });
  });

  group('device faults on the status surface', () {
    // Production builds without Drive run a disabled controller. Device
    // faults must reach the pill there too: that is most machines today.
    late BackupController controller;
    setUp(() => controller = BackupController.disabled());
    tearDown(() => controller.dispose());

    test('a reported fault turns the pill red and is logged', () async {
      await controller.reportDeviceFault(switcherDown());

      expect(controller.status.value.state, BackupPillState.failing);
      expect(controller.status.value.label(DateTime.now()), 'Switcher offline');
      expect(controller.log.entries.value.single.domain, 'roland');
    });

    test('clearing it puts the pill back', () async {
      await controller.reportDeviceFault(switcherDown());

      await controller.clearDeviceFault(FaultDomain.roland, 'Roland');

      expect(controller.status.value.activeCondition, isNull);
      expect(controller.status.value.state, BackupPillState.notBackedUp);
    });

    test('each camera is its own condition', () async {
      await controller.reportDeviceFault(cameraDown('Camera 1'));
      await controller.reportDeviceFault(cameraDown('Camera 2'));

      await controller.clearDeviceFault(FaultDomain.camera, 'Camera 2');

      expect(controller.status.value.label(DateTime.now()), 'Camera 1 offline');
    });

    test('clearing a device that never failed changes nothing', () async {
      await controller.reportDeviceFault(cameraDown('Camera 1'));

      await controller.clearDeviceFault(FaultDomain.roland, 'Roland');

      expect(controller.status.value.label(DateTime.now()), 'Camera 1 offline');
    });
  });

  test('a backup success does not clear a device fault', () async {
    final controller = BackupController.forService(BackupService(
      target: MockBackupTarget(),
      targetIdentity: 'mock:test',
      deviceLabel: () async => 'Mac mini',
      readBundleJson: () async => {'schemaVersion': 1},
      localIsPristine: () async => true,
    ));
    await controller.reportDeviceFault(switcherDown());

    await controller.handleEvent(const PullResult(PullOutcome.nothingToDo));

    expect(controller.status.value.label(DateTime.now()), 'Switcher offline');
    await controller.dispose();
  });
}
