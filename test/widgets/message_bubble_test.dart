import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/models/message.dart';
import 'package:vitalis_app/widgets/message_bubble.dart';

void main() {
  testWidgets('announces an assistant reply once', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: Message(
              chatId: 1,
              role: MessageRole.assistant,
              content: 'VISIBLE_PASS',
            ),
          ),
        ),
      ),
    );

    final semantics = tester.getSemantics(
      find.bySemanticsLabel('Assistant response: VISIBLE_PASS'),
    );
    expect(semantics.label, 'Assistant response: VISIBLE_PASS');
    expect(find.text('VISIBLE_PASS'), findsOneWidget);
  });
}
