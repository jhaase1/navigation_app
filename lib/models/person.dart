class Person {
  final String id;
  final String name;
  // null means "not set" — preset_resolver defaults to 5'8" (173 cm)
  final int? heightCm;
  // positionId → cameraIp → preset index (0-based); stored values are overrides
  final Map<String, Map<String, int>> positionPresets;

  Person({
    required this.id,
    required this.name,
    this.heightCm,
    Map<String, Map<String, int>>? positionPresets,
  }) : positionPresets = positionPresets ?? {};

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (heightCm != null) 'heightCm': heightCm,
        'positionPresets': positionPresets.map(
          (positionId, cameraMap) =>
              MapEntry(positionId, Map<String, dynamic>.from(cameraMap)),
        ),
      };

  factory Person.fromJson(Map<String, dynamic> json) => Person(
        id: json['id'] as String,
        name: json['name'] as String,
        heightCm: json['heightCm'] as int?,
        positionPresets:
            (json['positionPresets'] as Map<String, dynamic>? ?? {}).map(
          (positionId, cameraMap) => MapEntry(
            positionId,
            (cameraMap as Map<String, dynamic>)
                .map((ip, preset) => MapEntry(ip, preset as int)),
          ),
        ),
      );
}
