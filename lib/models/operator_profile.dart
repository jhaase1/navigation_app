class OperatorProfile {
  static const defaultId = 'default';

  final String id;
  final String name;

  /// Maps device storageKey → ordered list of item indices visible to this operator.
  /// Ignored for the Default operator (which always shows all items).
  final Map<String, List<int>> items;

  const OperatorProfile({
    required this.id,
    required this.name,
    this.items = const {},
  });

  bool get isDefault => id == defaultId;

  OperatorProfile copyWith({String? name, Map<String, List<int>>? items}) =>
      OperatorProfile(id: id, name: name ?? this.name, items: items ?? this.items);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'items': items.map((k, v) => MapEntry(k, v)),
      };

  factory OperatorProfile.fromJson(Map<String, dynamic> j) => OperatorProfile(
        id: j['id'] as String,
        name: j['name'] as String,
        items: (j['items'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, (v as List<dynamic>).cast<int>()),
        ),
      );

  static const defaultProfile = OperatorProfile(
    id: defaultId,
    name: 'Default',
  );
}

String generateOperatorId() => DateTime.now().microsecondsSinceEpoch.toString();
