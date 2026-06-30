class Scene {
  final String id;
  final String name;

  Scene({required this.id, required this.name});

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory Scene.fromJson(Map<String, dynamic> json) => Scene(
        id: json['id'] as String,
        name: json['name'] as String,
      );
}

String generateSceneId() => DateTime.now().microsecondsSinceEpoch.toString();
