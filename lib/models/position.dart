class Position {
  final String id;
  final String name;

  Position({required this.id, required this.name});

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory Position.fromJson(Map<String, dynamic> json) => Position(
        id: json['id'] as String,
        name: json['name'] as String,
      );
}

String generatePositionId() => DateTime.now().microsecondsSinceEpoch.toString();
