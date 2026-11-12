import 'package:flutter/material.dart';
import '../models/height_range.dart';
import '../models/panasonic_camera_config.dart';
import '../models/person.dart';
import '../models/position.dart';
import '../services/service_recorder.dart';
import '../utils/preset_resolver.dart';
import 'recording_controls.dart';

class PositionsTab extends StatefulWidget {
  final List<PanasonicCameraConfig> cameras;
  final List<Position> positions;
  final List<Person> people;
  final List<HeightRange> heightRanges;
  final ValueChanged<String> onResponse;
  /// Where failures go. Falls back to [onResponse] when not given, so a
  /// caller that only wants text still gets every message.
  final ValueChanged<String>? onFailure;

  /// The shared recording, started from Settings. While it is recording,
  /// tapping a person fires the shot and then asks which role they are
  /// playing, so the saved step follows the role rather than this person.
  final ServiceRecorder? recorder;

  const PositionsTab({
    super.key,
    required this.cameras,
    required this.positions,
    required this.people,
    required this.heightRanges,
    required this.onResponse,
    this.onFailure,
    this.recorder,
  });

  @override
  State<PositionsTab> createState() => _PositionsTabState();
}

class _PositionsTabState extends State<PositionsTab> {

  void _fail(String message) =>
      (widget.onFailure ?? widget.onResponse)(message);
  int _selectedCameraIndex = 0;

  /// While recording, a tap is in flight from the shot until its role
  /// prompt closes. A second tap in that window is ignored, so prompts never
  /// stack and steps are recorded in the order the shots were fired.
  bool _recordingTapInFlight = false;

  Future<void> _onPersonTapped(Position position, Person person) async {
    final recording = widget.recorder?.isRecording ?? false;
    if (!recording) {
      await _executePerson(position, person);
      return;
    }
    if (_recordingTapInFlight) {
      const msg = 'Still waiting on the last shot — tap again once it answers';
      widget.onResponse(msg);
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text(msg)));
      return;
    }
    _recordingTapInFlight = true;
    try {
      await _recordPersonTap(position, person);
    } finally {
      _recordingTapInFlight = false;
    }
  }

  Future<void> _recordPersonTap(Position position, Person person) async {
    final cameraIp = widget.cameras[
            _selectedCameraIndex.clamp(0, widget.cameras.length - 1)]
        .ipController
        .text;
    final fired = await _executePerson(position, person);
    final recorder = widget.recorder;
    if (!fired || recorder == null || !recorder.isRecording || !mounted) {
      return;
    }
    final role = await askForRole(
      context,
      personName: person.name,
      positionName: position.name,
      existingRoles: recorder.participants.map((p) => p.name).toList(),
      initialRole: recorder.roleNameFor(person.id),
    );
    if (role == null) return;
    recorder.recordMinistry(
      roleName: role,
      personId: person.id,
      positionId: position.id,
      cameraIp: cameraIp,
    );
  }

  /// Fires the shot. Returns true when the camera accepted it.
  Future<bool> _executePerson(Position position, Person person) async {
    final idx = _selectedCameraIndex.clamp(0, widget.cameras.length - 1);
    final camera = widget.cameras[idx];
    final ip = camera.ipController.text;
    final presetIndex = resolvePreset(
      person: person,
      positionId: position.id,
      cameraIp: ip,
      heightRanges: widget.heightRanges,
    );

    if (presetIndex == null) {
      _fail(
          'No preset linked for ${camera.name} — ${person.name} at ${position.name}');
      return false;
    }
    if (!camera.isConnected.value || camera.service == null) {
      _fail('${camera.name} not connected');
      return false;
    }
    try {
      final response = await camera.service!.recallPreset(presetIndex);
      widget.onResponse(
          '${person.name} · ${position.name} → ${camera.name}: $response');
      return true;
    } catch (e) {
      _fail('Error: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cameras.isEmpty) {
      return const Center(child: Text('No cameras configured'));
    }

    final selectedIdx =
        _selectedCameraIndex.clamp(0, widget.cameras.length - 1);
    final ip = widget.cameras[selectedIdx].ipController.text;

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ToggleButtons(
              isSelected: List.generate(
                  widget.cameras.length, (i) => i == selectedIdx),
              onPressed: (i) => setState(() => _selectedCameraIndex = i),
              children: widget.cameras
                  .map((c) => Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(c.name),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: widget.positions.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.place, size: 48, color: Colors.grey),
                        SizedBox(height: 8),
                        Text('No positions configured',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                        SizedBox(height: 4),
                        Text(
                            'Use Settings → Manage Positions to define physical locations',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView(
                    children: widget.positions
                        .map((p) => _buildPositionCard(p, ip))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPositionCard(Position position, String cameraIp) {
    final peopleHere = widget.people
        .where((p) => resolvePreset(
              person: p,
              positionId: position.id,
              cameraIp: cameraIp,
              heightRanges: widget.heightRanges,
            ) != null)
        .toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(position.name,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (peopleHere.isEmpty)
              Text(
                'No one configured here for this camera',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: peopleHere
                    .map((person) => FilledButton(
                          onPressed: () => _onPersonTapped(position, person),
                          child: Text(person.name),
                        ))
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }
}
