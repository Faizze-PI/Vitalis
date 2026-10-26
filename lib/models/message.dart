enum MessageRole { user, assistant, system }

class Message {
  final int? id;
  final int chatId;
  final MessageRole role;
  final String content;
  final DateTime timestamp;
  final bool isError;

  Message({
    this.id,
    required this.chatId,
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.isError = false,
  }) : timestamp = timestamp ?? DateTime.now();

  Message copyWith({
    int? id,
    int? chatId,
    MessageRole? role,
    String? content,
    DateTime? timestamp,
    bool? isError,
  }) {
    return Message(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      isError: isError ?? this.isError,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'chat_id': chatId,
      'role': role.name,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      if (isError) 'is_error': 1,
    };
  }

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'] as int?,
      chatId: map['chat_id'] as int,
      role: MessageRole.values.firstWhere(
        (r) => r.name == map['role'],
        orElse: () => MessageRole.user,
      ),
      content: map['content'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
      isError: (map['is_error'] as int?) == 1,
    );
  }
}
