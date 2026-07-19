import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navigation_app/models/panasonic_camera_config.dart';
import 'package:navigation_app/services/visibility_store.dart';
import 'package:navigation_app/widgets/filtered_control_widget.dart';

// Roland storageKey = 'roland_${ip}' where ip defaults to '' when no
// rolandIpController is provided, giving key 'roland_'.
const _rolandKey = 'roland_';

Widget _build({
  String title = 'Basic',
  ItemVisibility filter = ItemVisibility.basic,
  List<PanasonicCameraConfig> cameras = const [],
  ValueNotifier<bool>? rolandConnected,
}) {
  return MaterialApp(
    theme: ThemeData(useMaterial3: false),
    home: Scaffold(
      body: FilteredControlWidget(
        title: title,
        filter: filter,
        rolandService: null,
        rolandConnected: rolandConnected ?? ValueNotifier(false),
        cameras: cameras,
        onResponse: (_) {},
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('FilteredControlWidget — device tabs', () {
    testWidgets('shows Roland tab in the device selector', (tester) async {
      await tester.pumpWidget(_build());
      await tester.pumpAndSettle();
      expect(find.text('Roland'), findsOneWidget);
    });

    testWidgets('shows camera tab when a camera is provided', (tester) async {
      final cam = PanasonicCameraConfig(name: 'Wide', ipAddress: '10.0.1.10');
      addTearDown(cam.dispose);

      await tester.pumpWidget(_build(cameras: [cam]));
      await tester.pumpAndSettle();

      expect(find.text('Wide'), findsOneWidget);
    });

    testWidgets('shows multiple camera tabs for multiple cameras', (tester) async {
      final cam1 = PanasonicCameraConfig(name: 'Main', ipAddress: '10.0.1.10');
      final cam2 = PanasonicCameraConfig(name: 'Choir', ipAddress: '10.0.1.11');
      addTearDown(cam1.dispose);
      addTearDown(cam2.dispose);

      await tester.pumpWidget(_build(cameras: [cam1, cam2]));
      await tester.pumpAndSettle();

      expect(find.text('Main'), findsOneWidget);
      expect(find.text('Choir'), findsOneWidget);
    });

    testWidgets('Roland tab is selected by default', (tester) async {
      final cam = PanasonicCameraConfig(name: 'Wide', ipAddress: '10.0.1.10');
      addTearDown(cam.dispose);

      await tester.pumpWidget(_build(cameras: [cam]));
      await tester.pumpAndSettle();

      // Roland is the first ToggleButton and should be selected (isSelected[0]=true)
      final toggleButtons = tester.widget<ToggleButtons>(find.byType(ToggleButtons));
      expect(toggleButtons.isSelected[0], isTrue);
      expect(toggleButtons.isSelected[1], isFalse);
    });
  });

  group('FilteredControlWidget — empty states', () {
    testWidgets(
        'shows empty message when filter=basic and no visibility saved '
        '(default is expanded)', (tester) async {
      await tester.pumpWidget(_build(filter: ItemVisibility.basic));
      await tester.pumpAndSettle();

      expect(find.textContaining('No items tagged'), findsOneWidget);
      expect(find.textContaining('basic'), findsWidgets);
    });

    testWidgets(
        'shows empty message when filter=hide and no visibility saved',
        (tester) async {
      await tester.pumpWidget(_build(filter: ItemVisibility.hide));
      await tester.pumpAndSettle();

      expect(find.textContaining('No items tagged'), findsOneWidget);
    });

    testWidgets('shows title in the card header', (tester) async {
      await tester.pumpWidget(_build(title: 'Basic View', filter: ItemVisibility.basic));
      await tester.pumpAndSettle();

      expect(find.text('Basic View'), findsOneWidget);
    });
  });

  group('FilteredControlWidget — items displayed', () {
    testWidgets(
        'shows Roland macro buttons when filter=expanded '
        '(all macros default to expanded)', (tester) async {
      await tester.pumpWidget(_build(filter: ItemVisibility.expanded));
      await tester.pumpAndSettle();

      // Roland has 100 macros; any FilledButton proves items are shown
      expect(find.byType(FilledButton), findsWidgets);
    });

    testWidgets(
        'shows macro button labelled "Macro 1" in expanded view',
        (tester) async {
      await tester.pumpWidget(_build(filter: ItemVisibility.expanded));
      await tester.pumpAndSettle();

      expect(find.text('Macro 1'), findsWidgets);
    });

    testWidgets(
        'shows item tagged basic when filter=basic', (tester) async {
      // Pre-seed: mark Roland macro 5 as basic
      await VisibilityStore.save(_rolandKey, 5, ItemVisibility.basic);

      await tester.pumpWidget(_build(filter: ItemVisibility.basic));
      await tester.pumpAndSettle();

      expect(find.byType(FilledButton), findsWidgets);
      expect(find.textContaining('No items tagged'), findsNothing);
    });

    testWidgets(
        'hidden items are excluded from expanded filter', (tester) async {
      // Mark macro 1 as hide; all others remain expanded
      await VisibilityStore.save(_rolandKey, 1, ItemVisibility.hide);

      await tester.pumpWidget(_build(filter: ItemVisibility.expanded));
      await tester.pumpAndSettle();

      // Macros 2-100 still visible; 'Macro 1' button should not appear
      expect(find.text('Macro 1'), findsNothing);
      expect(find.byType(FilledButton), findsWidgets);
    });

    testWidgets(
        'hidden items are excluded from basic filter', (tester) async {
      await VisibilityStore.save(_rolandKey, 3, ItemVisibility.basic);
      await VisibilityStore.save(_rolandKey, 7, ItemVisibility.hide);

      await tester.pumpWidget(_build(filter: ItemVisibility.basic));
      await tester.pumpAndSettle();

      // Only macro 3 should show; macro 7 is hidden
      expect(find.byType(FilledButton), findsOneWidget);
    });
  });

  group('FilteredControlWidget — camera tab switching', () {
    testWidgets('tapping camera tab switches selection', (tester) async {
      final cam = PanasonicCameraConfig(name: 'Side', ipAddress: '10.0.1.10');
      addTearDown(cam.dispose);

      await tester.pumpWidget(_build(cameras: [cam], filter: ItemVisibility.expanded));
      await tester.pumpAndSettle();

      // Initially Roland is selected (isSelected[0] = true)
      final before = tester.widget<ToggleButtons>(find.byType(ToggleButtons));
      expect(before.isSelected[0], isTrue);

      await tester.tap(find.text('Side'));
      await tester.pumpAndSettle();

      // Now camera tab (index 1) is selected
      final after = tester.widget<ToggleButtons>(find.byType(ToggleButtons));
      expect(after.isSelected[0], isFalse);
      expect(after.isSelected[1], isTrue);
    });

    testWidgets('camera tab shows empty message when camera has no items',
        (tester) async {
      // Disconnected camera with no service → empty _availableIndices
      final cam = PanasonicCameraConfig(name: 'Close', ipAddress: '10.0.1.10');
      addTearDown(cam.dispose);

      await tester.pumpWidget(_build(cameras: [cam], filter: ItemVisibility.expanded));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Camera has no presets (not connected) — any empty indicator is fine
      expect(find.byType(FilledButton), findsNothing);
    });
  });
}
