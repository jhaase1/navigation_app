import 'scene.dart';

enum MomentType { roleScene, macro, camera, subOrder }

class OrderMoment {
  final String id;
  final MomentType type;

  // roleScene
  final String? roleId;
  final String? sceneId;

  // macro
  final int? macroNumber;

  // camera — fires a hardcoded preset on a specific camera
  final String? cameraIp;
  final int? cameraPresetIndex; // 0-based

  // subOrder
  final String? subOrderId;

  const OrderMoment({
    required this.id,
    required this.type,
    this.roleId,
    this.sceneId,
    this.macroNumber,
    this.cameraIp,
    this.cameraPresetIndex,
    this.subOrderId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        if (roleId != null) 'roleId': roleId,
        if (sceneId != null) 'sceneId': sceneId,
        if (macroNumber != null) 'macroNumber': macroNumber,
        if (cameraIp != null) 'cameraIp': cameraIp,
        if (cameraPresetIndex != null) 'cameraPresetIndex': cameraPresetIndex,
        if (subOrderId != null) 'subOrderId': subOrderId,
      };

  factory OrderMoment.fromJson(Map<String, dynamic> json) {
    final type = MomentType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => MomentType.roleScene,
    );
    return OrderMoment(
      id: json['id'] as String,
      type: type,
      roleId: json['roleId'] as String?,
      sceneId: json['sceneId'] as String?,
      macroNumber: json['macroNumber'] as int?,
      cameraIp: json['cameraIp'] as String?,
      cameraPresetIndex: json['cameraPresetIndex'] as int?,
      subOrderId: json['subOrderId'] as String?,
    );
  }
}

class ServiceOrder {
  final String id;
  final String name;
  final List<OrderMoment> moments;

  ServiceOrder({
    required this.id,
    required this.name,
    List<OrderMoment>? moments,
  }) : moments = moments ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'moments': moments.map((m) => m.toJson()).toList(),
      };

  factory ServiceOrder.fromJson(Map<String, dynamic> json) => ServiceOrder(
        id: json['id'] as String,
        name: json['name'] as String,
        moments: (json['moments'] as List<dynamic>? ?? [])
            .map((m) => OrderMoment.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
}

String generateOrderId() => generateSceneId();
