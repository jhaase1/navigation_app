class Person {
  final String id;
  final String name;
  // sceneId → cameraIp → preset index (0-based)
  final Map<String, Map<String, int>> scenePresets;

  Person({
    required this.id,
    required this.name,
    Map<String, Map<String, int>>? scenePresets,
  }) : scenePresets = scenePresets ?? {};

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'scenePresets': scenePresets.map(
          (sceneId, cameraMap) =>
              MapEntry(sceneId, Map<String, dynamic>.from(cameraMap)),
        ),
      };

  factory Person.fromJson(Map<String, dynamic> json) => Person(
        id: json['id'] as String,
        name: json['name'] as String,
        scenePresets:
            (json['scenePresets'] as Map<String, dynamic>? ?? {}).map(
          (sceneId, cameraMap) => MapEntry(
            sceneId,
            (cameraMap as Map<String, dynamic>)
                .map((ip, preset) => MapEntry(ip, preset as int)),
          ),
        ),
      );
}
