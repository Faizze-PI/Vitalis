class Persona {
  final int? id;
  final String name;
  final String systemPrompt;
  final bool isDefault;

  Persona({
    this.id,
    required this.name,
    required this.systemPrompt,
    this.isDefault = false,
  });

  Persona copyWith({
    int? id,
    String? name,
    String? systemPrompt,
    bool? isDefault,
  }) {
    return Persona(
      id: id ?? this.id,
      name: name ?? this.name,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'system_prompt': systemPrompt,
      'is_default': isDefault ? 1 : 0,
    };
  }

  factory Persona.fromMap(Map<String, dynamic> map) {
    return Persona(
      id: map['id'] as int?,
      name: map['name'] as String,
      systemPrompt: map['system_prompt'] as String,
      isDefault: (map['is_default'] as int) == 1,
    );
  }
}
