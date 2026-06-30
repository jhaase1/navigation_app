import 'scene.dart';

class Role {
  final String id;
  final String name;

  Role({required this.id, required this.name});

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory Role.fromJson(Map<String, dynamic> json) => Role(
        id: json['id'] as String,
        name: json['name'] as String,
      );
}

String generateRoleId() => generateSceneId();
