import 'package:flutter/material.dart';
import '../models/panasonic_camera_config.dart';
import '../models/person.dart';
import '../models/scene.dart';

class ScenesTab extends StatefulWidget {
  final List<PanasonicCameraConfig> cameras;
  final List<Scene> scenes;
  final List<Person> people;
  final ValueChanged<String> onResponse;

  const ScenesTab({
    super.key,
    required this.cameras,
    required this.scenes,
    required this.people,
    required this.onResponse,
  });

  @override
  State<ScenesTab> createState() => _ScenesTabState();
}

class _ScenesTabState extends State<ScenesTab> {
  int _selectedCameraIndex = 0;

  Future<void> _executePerson(Scene scene, Person person) async {
    final idx = _selectedCameraIndex.clamp(0, widget.cameras.length - 1);
    final camera = widget.cameras[idx];
    final ip = camera.ipController.text;
    final presetIndex = person.scenePresets[scene.id]?[ip];

    if (presetIndex == null) {
      widget.onResponse(
          'No preset linked for ${camera.name} — ${person.name} at ${scene.name}');
      return;
    }
    if (!camera.isConnected.value || camera.service == null) {
      widget.onResponse('${camera.name} not connected');
      return;
    }
    try {
      final response = await camera.service!.recallPreset(presetIndex);
      widget.onResponse('${person.name} · ${scene.name} → ${camera.name}: $response');
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
            child: widget.scenes.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.place, size: 48, color: Colors.grey),
                        SizedBox(height: 8),
                        Text('No scenes configured',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                        SizedBox(height: 4),
                        Text(
                            'Use Settings → Manage Scenes to add positions',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView(
                    children: widget.scenes
                        .map((scene) => _buildSceneCard(scene, ip))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSceneCard(Scene scene, String cameraIp) {
    final peopleHere = widget.people
        .where((p) => p.scenePresets[scene.id]?[cameraIp] != null)
        .toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(scene.name,
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
                          onPressed: () => _executePerson(scene, person),
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
