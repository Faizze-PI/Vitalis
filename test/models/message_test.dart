import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/models/message.dart';

void main() {
  group('Message', () {
    test('fromMap and toMap round trip', () {
      final message = Message(
        id: 1,
        chatId: 1,
        role: MessageRole.user,
        content: 'Hello world',
      );

      final map = message.toMap();
      final restored = Message.fromMap(map);

      expect(restored.id, message.id);
      expect(restored.chatId, message.chatId);
      expect(restored.role, message.role);
      expect(restored.content, message.content);
    });

    test('copyWith creates a copy with overridden fields', () {
      final original = Message(
        id: 1,
        chatId: 1,
        role: MessageRole.user,
        content: 'Original',
      );

      final modified = original.copyWith(content: 'Modified');
      expect(modified.id, 1);
      expect(modified.content, 'Modified');
      expect(original.content, 'Original');
    });
  });
}
