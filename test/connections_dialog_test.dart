import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/models/panasonic_camera_config.dart';
import 'package:navigation_app/services/device_config_store.dart';
import 'package:navigation_app/widgets/connections_dialog.dart';

// Open the ConnectionsDialog via showDialog so Navigator.pop works normally.
Future<void> _openDialog(
  WidgetTester tester, {
  TextEditingController? rolandIpCtrl,
  String rolandIp = '10.0.1.20',
  bool rolandConnected = false,
  List<PanasonicCameraConfig> cameras = const [],
  DeviceConfigCallback? onSaved,
}) async {
  final ctrl = rolandIpCtrl ?? TextEditingController(text: rolandIp);
  final connected = ValueNotifier(rolandConnected);
  final connecting = ValueNotifier(false);
  final error = ValueNotifier<String>('');

  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(useMaterial3: false),
    home: Builder(builder: (context) => TextButton(
      onPressed: () => showDialog<void>(
        context: context,
        builder: (_) => ConnectionsDialog(
          rolandIpController: ctrl,
          rolandConnected: connected,
          rolandConnecting: connecting,
          rolandConnectionError: error,
          onConnectRoland: () {},
          panasonicCameras: cameras,
          onConnectPanasonic: (_) {},
          onSaved: onSaved ?? (_, __) {},
        ),
      ),
      child: const Text('Open'),
    )),
  ));

  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  group('ConnectionsDialog — Roland section', () {
    testWidgets('shows Roland IP in a text field', (tester) async {
      await _openDialog(tester, rolandIp: '192.168.1.50');
      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(fields.any((f) => f.controller?.text == '192.168.1.50'), isTrue);
    });

    testWidgets('Roland IP field is disabled when connected', (tester) async {
      await _openDialog(tester, rolandConnected: true);
      // First TextField is Roland IP; enabled is false when connected
      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(fields.any((f) => f.enabled == false), isTrue);
    });

    testWidgets('shows Disconnect when Roland is connected', (tester) async {
      await _openDialog(tester, rolandConnected: true);
      expect(find.text('Disconnect'), findsWidgets);
    });

    testWidgets('shows Connect when Roland is not connected', (tester) async {
      await _openDialog(tester);
      expect(find.text('Connect'), findsWidgets);
    });
  });

  group('ConnectionsDialog — camera section', () {
    testWidgets('shows name and IP fields for each camera', (tester) async {
      final cam = PanasonicCameraConfig(name: 'Main Cam', ipAddress: '10.0.1.10');
      addTearDown(cam.dispose);

      await _openDialog(tester, cameras: [cam]);

      final texts = tester
          .widgetList<TextField>(find.byType(TextField))
          .map((f) => f.controller?.text ?? '')
          .toList();
      expect(texts, contains('Main Cam'));
      expect(texts, contains('10.0.1.10'));
    });

    testWidgets('Add button appends a new camera row', (tester) async {
      await _openDialog(tester);
      final before = tester.widgetList(find.byType(TextField)).length;

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(tester.widgetList(find.byType(TextField)).length,
          greaterThan(before));
    });

    testWidgets('delete icon removes that camera row', (tester) async {
      final cam = PanasonicCameraConfig(name: 'Cam 1', ipAddress: '10.0.1.10');
      addTearDown(cam.dispose);

      await _openDialog(tester, cameras: [cam]);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      final texts = tester
          .widgetList<TextField>(find.byType(TextField))
          .map((f) => f.controller?.text ?? '')
          .toList();
      expect(texts, isNot(contains('10.0.1.10')));
    });

    testWidgets('delete icon is disabled for a connected camera', (tester) async {
      final cam = PanasonicCameraConfig(name: 'Cam 1', ipAddress: '10.0.1.10');
      cam.isConnected.value = true;
      addTearDown(cam.dispose);

      await _openDialog(tester, cameras: [cam]);

      final btn = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.delete_outline));
      expect(btn.onPressed, isNull);
    });

    testWidgets('multiple cameras each show their own fields', (tester) async {
      final cam1 = PanasonicCameraConfig(name: 'Wide', ipAddress: '10.0.1.10');
      final cam2 = PanasonicCameraConfig(name: 'Tight', ipAddress: '10.0.1.11');
      addTearDown(cam1.dispose);
      addTearDown(cam2.dispose);

      await _openDialog(tester, cameras: [cam1, cam2]);

      final texts = tester
          .widgetList<TextField>(find.byType(TextField))
          .map((f) => f.controller?.text ?? '')
          .toList();
      expect(texts, contains('Wide'));
      expect(texts, contains('10.0.1.10'));
      expect(texts, contains('Tight'));
      expect(texts, contains('10.0.1.11'));
    });
  });

  group('ConnectionsDialog — Save & Close', () {
    testWidgets('calls onSaved with current Roland IP', (tester) async {
      String? capturedIp;
      final ctrl = TextEditingController(text: '10.0.1.99');
      addTearDown(ctrl.dispose);

      await _openDialog(tester,
          rolandIpCtrl: ctrl,
          onSaved: (ip, _) => capturedIp = ip);

      await tester.tap(find.text('Save & Close'));
      await tester.pumpAndSettle();

      expect(capturedIp, '10.0.1.99');
    });

    testWidgets('calls onSaved with camera name and IP', (tester) async {
      List<CameraEntry>? captured;
      final cam = PanasonicCameraConfig(name: 'Cam A', ipAddress: '10.0.0.5');
      addTearDown(cam.dispose);

      await _openDialog(tester,
          cameras: [cam],
          onSaved: (_, cams) => captured = cams);

      await tester.tap(find.text('Save & Close'));
      await tester.pumpAndSettle();

      expect(captured?.length, 1);
      expect(captured?.first.name, 'Cam A');
      expect(captured?.first.ip, '10.0.0.5');
    });

    testWidgets('includes a newly added camera in onSaved', (tester) async {
      List<CameraEntry>? captured;

      await _openDialog(tester, onSaved: (_, cams) => captured = cams);

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      // The dialog now has camera rows; save should include the new one
      await tester.tap(find.text('Save & Close'));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.length, 1);
    });

    testWidgets('excludes a removed camera from onSaved', (tester) async {
      List<CameraEntry>? captured;
      final cam = PanasonicCameraConfig(name: 'Removable', ipAddress: '9.9.9.9');
      addTearDown(cam.dispose);

      await _openDialog(tester,
          cameras: [cam],
          onSaved: (_, cams) => captured = cams);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save & Close'));
      await tester.pumpAndSettle();

      expect(captured, isEmpty);
    });
  });

  group('ConnectionsDialog — Cancel', () {
    testWidgets('Cancel does not call onSaved', (tester) async {
      bool called = false;
      await _openDialog(tester, onSaved: (_, __) => called = true);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(called, isFalse);
    });

    testWidgets('Cancel dismisses the dialog', (tester) async {
      await _openDialog(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Save & Close'), findsNothing);
    });
  });
}
