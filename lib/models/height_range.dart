class HeightRange {
  final String id;
  final String name;
  // null means no upper bound — catch-all for the tallest group
  final int? maxHeightCm;
  // positionId → cameraIp → preset index (0-based)
  final Map<String, Map<String, int>> positionPresets;

  HeightRange({
    required this.id,
    required this.name,
    this.maxHeightCm,
    Map<String, Map<String, int>>? positionPresets,
  }) : positionPresets = positionPresets ?? {};

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (maxHeightCm != null) 'maxHeightCm': maxHeightCm,
        'positionPresets': positionPresets.map(
          (posId, cameraMap) =>
              MapEntry(posId, Map<String, dynamic>.from(cameraMap)),
        ),
      };

  factory HeightRange.fromJson(Map<String, dynamic> json) => HeightRange(
        id: json['id'] as String,
        name: json['name'] as String,
        maxHeightCm: json['maxHeightCm'] as int?,
        positionPresets:
            (json['positionPresets'] as Map<String, dynamic>? ?? {}).map(
          (posId, cameraMap) => MapEntry(
            posId,
            (cameraMap as Map<String, dynamic>)
                .map((ip, preset) => MapEntry(ip, preset as int)),
          ),
        ),
      );
}

String generateHeightRangeId() =>
    DateTime.now().microsecondsSinceEpoch.toString();
