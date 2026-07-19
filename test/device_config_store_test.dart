import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navigation_app/services/device_config_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CameraEntry — serialisation', () {
    test('toJson produces name and ip keys', () {
      const entry = CameraEntry(name: 'Camera 1', ip: '10.0.1.10');
      expect(entry.toJson(), {'name': 'Camera 1', 'ip': '10.0.1.10'});
    });

    test('fromJson round-trips name and ip', () {
      const entry = CameraEntry(name: 'Main Cam', ip: '192.168.1.5');
      final copy = CameraEntry.fromJson(entry.toJson());
      expect(copy.name, 'Main Cam');
      expect(copy.ip, '192.168.1.5');
    });
  });

  group('DeviceConfigStore — Roland IP', () {
    test('loadRolandIp returns defaultRolandIp when nothing saved', () async {
      expect(
          await DeviceConfigStore.loadRolandIp(), DeviceConfigStore.defaultRolandIp);
    });

    test('save then loadRolandIp returns the saved IP', () async {
      await DeviceConfigStore.save('192.168.1.100', []);
      expect(await DeviceConfigStore.loadRolandIp(), '192.168.1.100');
    });

    test('save overwrites previous Roland IP', () async {
      await DeviceConfigStore.save('10.0.0.1', []);
      await DeviceConfigStore.save('10.0.0.2', []);
      expect(await DeviceConfigStore.loadRolandIp(), '10.0.0.2');
    });
  });

  group('DeviceConfigStore — cameras', () {
    test('loadCameras returns defaultCameras when nothing saved', () async {
      final cameras = await DeviceConfigStore.loadCameras();
      expect(cameras.length, DeviceConfigStore.defaultCameras.length);
      for (int i = 0; i < cameras.length; i++) {
        expect(cameras[i].name, DeviceConfigStore.defaultCameras[i].name);
        expect(cameras[i].ip, DeviceConfigStore.defaultCameras[i].ip);
      }
    });

    test('save then loadCameras returns the saved list', () async {
      const cameras = [
        CameraEntry(name: 'Front', ip: '10.0.0.1'),
        CameraEntry(name: 'Side', ip: '10.0.0.2'),
      ];
      await DeviceConfigStore.save(DeviceConfigStore.defaultRolandIp, cameras);
      final loaded = await DeviceConfigStore.loadCameras();
      expect(loaded.length, 2);
      expect(loaded[0].name, 'Front');
      expect(loaded[0].ip, '10.0.0.1');
      expect(loaded[1].name, 'Side');
      expect(loaded[1].ip, '10.0.0.2');
    });

    test('save with empty list persists empty list (overrides defaults)', () async {
      await DeviceConfigStore.save(DeviceConfigStore.defaultRolandIp, []);
      expect(await DeviceConfigStore.loadCameras(), isEmpty);
    });

    test('save overwrites the previous camera list', () async {
      await DeviceConfigStore.save(DeviceConfigStore.defaultRolandIp,
          [const CameraEntry(name: 'Old', ip: '1.1.1.1')]);
      await DeviceConfigStore.save(DeviceConfigStore.defaultRolandIp,
          [const CameraEntry(name: 'New', ip: '2.2.2.2')]);
      final loaded = await DeviceConfigStore.loadCameras();
      expect(loaded.length, 1);
      expect(loaded[0].name, 'New');
    });
  });

  group('DeviceConfigStore — save atomicity', () {
    test('save persists Roland IP and cameras together', () async {
      await DeviceConfigStore.save('10.99.99.99', [
        const CameraEntry(name: 'A', ip: '10.0.0.1'),
        const CameraEntry(name: 'B', ip: '10.0.0.2'),
      ]);
      expect(await DeviceConfigStore.loadRolandIp(), '10.99.99.99');
      final cams = await DeviceConfigStore.loadCameras();
      expect(cams.length, 2);
      expect(cams[0].name, 'A');
      expect(cams[1].name, 'B');
    });

    test('Roland IP and cameras are stored under independent keys', () async {
      // Saving cameras does not corrupt the Roland IP and vice versa
      await DeviceConfigStore.save('10.0.0.50', [
        const CameraEntry(name: 'X', ip: '10.0.0.9'),
      ]);
      expect(await DeviceConfigStore.loadRolandIp(), '10.0.0.50');
      expect((await DeviceConfigStore.loadCameras())[0].name, 'X');
    });
  });
}
