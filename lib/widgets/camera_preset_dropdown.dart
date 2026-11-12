import 'dart:async';

import 'package:flutter/material.dart';

import '../models/panasonic_camera_config.dart';
import '../utils/label_utils.dart';

/// Asks each connected camera which presets it holds: the same question the
/// Panel tab asks. Returns cameraIp → 0-based indices of its saved presets.
///
/// A camera with no entry (not connected, or it did not answer) should be
/// offered all 100, so people and height ranges can still be set up before
/// the rack is on.
Future<Map<String, Set<int>>> loadSavedPresets(
    List<PanasonicCameraConfig> cameras) async {
  final result = <String, Set<int>>{};
  await Future.wait(cameras.map((camera) async {
    final service = camera.service;
    if (service == null || !camera.isConnected.value) return;
    try {
      final statuses = await service
          .getAllPresetStatuses()
          .timeout(const Duration(seconds: 15));
      result[camera.ipController.text] = {
        for (final e in statuses.entries)
          if (e.value) e.key
      };
    } catch (_) {
      // No answer: leave this camera offering all 100.
    }
  }));
  return result;
}

/// The "Preset #" picker shared by the People and Height Range editors.
///
/// Lists the presets in [savedPresets] (0-based), or all 100 when it is
/// null. [value] is 1-based, as shown.
class CameraPresetDropdown extends StatelessWidget {
  final int? value;
  final Map<int, String> presetNames;
  final Set<int>? savedPresets;
  final ValueChanged<int?> onChanged;

  const CameraPresetDropdown({
    super.key,
    required this.value,
    required this.presetNames,
    required this.savedPresets,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final saved = savedPresets;
    // The chosen preset is always offered, saved on the camera or not:
    // leaving it out would clear the assignment on the next Save.
    final offered = [
      for (var n = 1; n <= 100; n++)
        if (saved == null || saved.contains(n - 1) || n == value) n
    ];
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Preset #',
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: value,
          isDense: true,
          isExpanded: true,
          hint: const Text('—', style: TextStyle(color: Colors.grey)),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('—')),
            for (final n in offered)
              DropdownMenuItem<int?>(
                value: n,
                child: Text(
                  saved != null && !saved.contains(n - 1)
                      ? '${formatItemLabel(presetNames[n - 1], '$n')} · not saved on camera'
                      : formatItemLabel(presetNames[n - 1], '$n'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
