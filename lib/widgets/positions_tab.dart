import 'package:flutter/material.dart';
import '../models/panasonic_camera_config.dart';
import '../models/person.dart';
import '../models/position.dart';

class PositionsTab extends StatefulWidget {
  final List<PanasonicCameraConfig> cameras;
  final List<Position> positions;
  final List<Person> people;
  final ValueChanged<String> onResponse;

  const PositionsTab({
    super.key,
    required this.cameras,
    required this.positions,
    required this.people,
    required this.onResponse,
  });

  @override
  State<PositionsTab> createState() => _PositionsTabState();
}

class _PositionsTabState extends State<PositionsTab> {
  int _selectedCameraIndex = 0;

  Future<void> _executePerson(Position position, Person person) async {
    final idx = _selectedCameraIndex.clamp(0, widget.cameras.length - 1);
    final camera = widget.cameras[idx];
    final ip = camera.ipController.text;
    final presetIndex = person.positionPresets[position.id]?[ip];

    if (presetIndex == null) {
      widget.onResponse(
          'No preset linked for ${camera.name} — ${person.name} at ${position.name}');
      return;
    }
    if (!camera.isConnected.value || camera.service == null) {
      widget.onResponse('${camera.name} not connected');
      return;
    }
    try {
      final response = await camera.service!.recallPreset(presetIndex);
      widget.onResponse(
          '${person.name} · ${position.name} → ${camera.name}: $response');
    } catch (e) {
      widget.onResponse('Error: $e');
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
        .where((p) => p.positionPresets[position.id]?[cameraIp] != null)
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
                          onPressed: () => _executePerson(position, person),
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
