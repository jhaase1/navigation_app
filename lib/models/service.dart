enum StepType { ministry, macro, shot, block }

class Participant {
  final String id;
  final String name;

  Participant({required this.id, required this.name});

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory Participant.fromJson(Map<String, dynamic> json) => Participant(
        id: json['id'] as String,
        name: json['name'] as String,
      );
}

class ServiceStep {
  final String id;
  final StepType type;

  // ministry — person at a position, shot on cameraIp (preset resolved at run time)
  final String? participantId;
  final String? positionId;

  // macro — Roland macro
  final int? macroNumber;

  // shot — hardcoded camera preset; also used by ministry to pick the camera
  final String? cameraIp;
  final int? cameraPresetIndex; // 0-based, shot only

  // block — sub-service reference
  final String? subServiceId;

  const ServiceStep({
    required this.id,
    required this.type,
    this.participantId,
    this.positionId,
    this.macroNumber,
    this.cameraIp,
    this.cameraPresetIndex,
    this.subServiceId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        if (participantId != null) 'participantId': participantId,
        if (positionId != null) 'positionId': positionId,
        if (macroNumber != null) 'macroNumber': macroNumber,
        if (cameraIp != null) 'cameraIp': cameraIp,
        if (cameraPresetIndex != null) 'cameraPresetIndex': cameraPresetIndex,
        if (subServiceId != null) 'subServiceId': subServiceId,
      };

  factory ServiceStep.fromJson(Map<String, dynamic> json) {
    final type = StepType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => StepType.ministry,
    );
    return ServiceStep(
      id: json['id'] as String,
      type: type,
      participantId: json['participantId'] as String?,
      positionId: json['positionId'] as String?,
      macroNumber: json['macroNumber'] as int?,
      cameraIp: json['cameraIp'] as String?,
      cameraPresetIndex: json['cameraPresetIndex'] as int?,
      subServiceId: json['subServiceId'] as String?,
    );
  }
}

class Service {
  final String id;
  final String name;
  final List<Participant> participants;
  final List<ServiceStep> steps;

  Service({
    required this.id,
    required this.name,
    List<Participant>? participants,
    List<ServiceStep>? steps,
  })  : participants = participants ?? [],
        steps = steps ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'participants': participants.map((p) => p.toJson()).toList(),
        'steps': steps.map((s) => s.toJson()).toList(),
      };

  factory Service.fromJson(Map<String, dynamic> json) => Service(
        id: json['id'] as String,
        name: json['name'] as String,
        participants: (json['participants'] as List<dynamic>? ?? [])
            .map((p) => Participant.fromJson(p as Map<String, dynamic>))
            .toList(),
        steps: (json['steps'] as List<dynamic>? ?? [])
            .map((s) => ServiceStep.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}

String generateServiceId() => DateTime.now().microsecondsSinceEpoch.toString();
