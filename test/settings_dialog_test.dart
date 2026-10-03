import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navigation_app/models/height_range.dart';
import 'package:navigation_app/models/operator_profile.dart';
import 'package:navigation_app/services/backup/config_mutation_notifier.dart';
import 'package:navigation_app/services/config_bundle.dart';
import 'package:navigation_app/services/config_file_picker.dart';
import 'package:navigation_app/services/height_range_store.dart';
import 'package:navigation_app/services/operator_store.dart';
import 'package:navigation_app/utils/height_utils.dart';
import 'package:navigation_app/widgets/settings_dialog.dart';

Widget _settingsDialog({
  List<HeightRange> heightRanges = const [],
  VoidCallback? onHeightRangesChanged,
  VoidCallback? onPeopleChanged,
  ValueChanged<String>? onResponse,
  ConfigFilePicker? configFilePicker,
}) {
  return MaterialApp(
    theme: ThemeData(useMaterial3: false),
    home: Builder(
      builder: (ctx) => TextButton(
        onPressed: () => showDialog<void>(
          context: ctx,
          builder: (_) => SettingsDialog(
            mockMode: true,
            onMockModeChanged: (_) {},
            rolandService: null,
            rolandIpController: TextEditingController(),
            rolandConnected: ValueNotifier(false),
            rolandConnecting: ValueNotifier(false),
            rolandConnectionError: ValueNotifier(''),
            onConnectRoland: () async {},
            panasonicCameras: const [],
            onConnectPanasonic: (_) async {},
            onResponse: onResponse ?? (_) {},
            positions: const [],
            heightRanges: heightRanges,
            onPositionsChanged: () {},
            onServicesChanged: () {},
            onHeightRangesChanged: onHeightRangesChanged ?? () {},
            onPeopleChanged: onPeopleChanged ?? () {},
            onAllDataChanged: () {},
            onDeviceConfigSaved: (_, __) {},
            onOperatorsChanged: () {},
            configFilePicker: configFilePicker ?? _FakePicker(),
          ),
        ),
        child: const Text('Open'),
      ),
    ),
  );
}

/// Stands in for the native save/open dialogs.
class _FakePicker implements ConfigFilePicker {
  _FakePicker({this.openResult, this.saveLocation = '/picked/nav.json'});

  /// What the operator "chose" to import; null means they cancelled.
  final String? openResult;

  /// Where the export "landed"; null means they cancelled.
  final String? saveLocation;

  String? savedName;
  String? savedContents;
  int opens = 0;

  @override
  Future<String?> save(String suggestedName, String contents) async {
    savedName = suggestedName;
    savedContents = contents;
    return saveLocation;
  }

  @override
  Future<String?> open() async {
    opens++;
    return openResult;
  }
}

Future<void> _openSettingsAndTap(WidgetTester tester, String tile) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(tile));
  await tester.tap(find.text(tile));
}

/// The import path awaits real async work, so pump until [text] shows up.
Future<void> _pumpUntil(WidgetTester tester, String text) async {
  for (var attempt = 0;
      attempt < 20 && find.text(text).evaluate().isEmpty;
      attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
}

final _emptyConfig = jsonEncode({
  'schemaVersion': 1,
  'positions': <dynamic>[],
  'people': <dynamic>[],
  'services': <dynamic>[],
  'heightRanges': <dynamic>[],
});

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows a Manage Height Ranges tile', (tester) async {
    await tester.pumpWidget(_settingsDialog());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Manage Height Ranges'), findsOneWidget);
  });

  testWidgets('tapping the tile opens the HeightRangeManagerDialog',
      (tester) async {
    await tester.pumpWidget(_settingsDialog());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Manage Height Ranges'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage Height Ranges'));
    await tester.pumpAndSettle();

    expect(find.text('Add Height Range'), findsOneWidget);
  });

  testWidgets('saving a new height range calls onHeightRangesChanged',
      (tester) async {
    bool changed = false;
    await tester.pumpWidget(
        _settingsDialog(onHeightRangesChanged: () => changed = true));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Manage Height Ranges'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage Height Ranges'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Height Range'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Max Height — ft'), '5');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(changed, isTrue);
    final stored = await HeightRangeStore.loadAll();
    expect(stored.single.maxHeightCm, feetInchesToCm(5, 0));
  });

  testWidgets('shows a Manage People tile', (tester) async {
    await tester.pumpWidget(_settingsDialog());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Manage People'), findsOneWidget);
  });

  testWidgets('tapping the tile opens the PeopleManagerDialog',
      (tester) async {
    await tester.pumpWidget(_settingsDialog());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Manage People'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage People'));
    await tester.pumpAndSettle();

    expect(find.text('Add Person'), findsOneWidget);
  });

  testWidgets('import commits the active-operator reset as pending work',
      (tester) async {
    await OperatorStore.saveActiveId('operator-who-will-not-exist');
    final seen = <int>[];
    final sub = ConfigMutationNotifier.instance.onMutated.listen(seen.add);
    addTearDown(sub.cancel);
    String? response;

    await tester.pumpWidget(_settingsDialog(
      onResponse: (value) => response = value,
      configFilePicker: _FakePicker(openResult: _emptyConfig),
    ));
    await _openSettingsAndTap(tester, 'Import Configuration');
    await _pumpUntil(tester, 'Replace all');
    expect(find.text('Replace all'), findsOneWidget);
    await tester.tap(find.text('Replace all'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(response, 'Configuration imported successfully');
    expect(await OperatorStore.loadActiveId(), OperatorProfile.defaultId);
    expect(seen, [2],
        reason: 'the prior operator edit was generation 1; import is one edit');
    expect(await ConfigMutationNotifier.instance.isDirty(), isTrue,
        reason: 'manual import must remain pending across app termination');
  });

  group('export', () {
    testWidgets('saves the configuration through the native save dialog',
        (tester) async {
      final picker = _FakePicker(saveLocation: '/Users/op/Desktop/nav.json');
      await tester.pumpWidget(_settingsDialog(configFilePicker: picker));

      await _openSettingsAndTap(tester, 'Export Configuration');
      await _pumpUntil(tester, 'Export complete');

      expect(picker.savedName, matches(RegExp(r'^nav_config_\d{8}\.json$')));
      final saved = jsonDecode(picker.savedContents!) as Map<String, dynamic>;
      expect(() => ConfigBundle.fromJsonValidated(saved), returnsNormally);
      expect(find.text('Export complete'), findsOneWidget);
      expect(find.text('/Users/op/Desktop/nav.json'), findsOneWidget);
    });

    testWidgets('cancelling the save dialog shows nothing', (tester) async {
      final picker = _FakePicker(saveLocation: null);
      await tester.pumpWidget(_settingsDialog(configFilePicker: picker));

      await _openSettingsAndTap(tester, 'Export Configuration');
      await _pumpUntil(tester, 'Export complete');

      expect(picker.savedContents, isNotNull);
      expect(find.text('Export complete'), findsNothing);
      expect(find.text('Export failed'), findsNothing);
    });
  });

  group('import', () {
    testWidgets('opens the native picker instead of asking for a path',
        (tester) async {
      final picker = _FakePicker(openResult: null);
      await tester.pumpWidget(_settingsDialog(configFilePicker: picker));

      await _openSettingsAndTap(tester, 'Import Configuration');
      await tester.pumpAndSettle();

      expect(picker.opens, 1);
      expect(find.text('File path'), findsNothing);
    });

    testWidgets('cancelling the picker changes nothing', (tester) async {
      await OperatorStore.saveActiveId('keep-me');
      await tester.pumpWidget(
          _settingsDialog(configFilePicker: _FakePicker(openResult: null)));

      await _openSettingsAndTap(tester, 'Import Configuration');
      await tester.pumpAndSettle();

      expect(find.text('Replace all'), findsNothing);
      expect(find.text('Import failed'), findsNothing);
      expect(await OperatorStore.loadActiveId(), 'keep-me');
    });

    testWidgets('a file that is not a configuration reports the failure',
        (tester) async {
      await tester.pumpWidget(_settingsDialog(
          configFilePicker: _FakePicker(openResult: 'not json')));

      await _openSettingsAndTap(tester, 'Import Configuration');
      await _pumpUntil(tester, 'Import failed');

      expect(find.text('Import failed'), findsOneWidget);
      expect(find.text('Replace all'), findsNothing);
    });
  });
}
