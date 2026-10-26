class Chat {
  final int? id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  Chat({
    this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  Chat copyWith({
    int? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Chat(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'title': title,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory Chat.fromMap(Map<String, dynamic> map) => Chat(
    id: map['id'] as int?,
    title: map['title'] as String? ?? 'New Chat',
    createdAt: DateTime.parse(map['created_at'] as String),
    updatedAt: DateTime.parse(map['updated_at'] as String),
  );
}
