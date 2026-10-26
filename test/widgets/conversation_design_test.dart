import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/models/message.dart';
import 'package:vitalis_app/theme/app_theme.dart';
import 'package:vitalis_app/widgets/conversation_status_bar.dart';
import 'package:vitalis_app/constants/app_strings.dart';
import 'package:vitalis_app/widgets/message_bubble.dart';
import 'package:vitalis_app/widgets/chat_input_field.dart';
import 'package:vitalis_app/services/chat_state_controller.dart';

void main() {
  testWidgets(
    'unknown device measurements stay unknown and errors retain Retry',
    (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Column(
              children: [
                const ConversationStatusBar(
                  safe: false,
                  rssMb: 0,
                  lastTps: double.nan,
                ),
                MessageBubble(
                  message: Message(
                    chatId: 1,
                    role: MessageRole.assistant,
                    content: 'A recoverable failure',
                    isError: true,
                  ),
                  onRetry: () => retries++,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('Device protection active'));
      await tester.pumpAndSettle();
      expect(find.text('Memory: Unknown'), findsOneWidget);
      expect(find.text('Battery: Unknown'), findsOneWidget);
      expect(find.text('Last generation: Not measured'), findsOneWidget);
      await tester.tap(find.text(AppStrings.retry));
      expect(retries, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final theme in [AppTheme.light, AppTheme.dark]) {
    test(
      'conversation colour pairs remain readable in ${theme.brightness}',
      () {
        final c = theme.colorScheme;
        for (final pair in [
          (c.onSurface, c.surface),
          (c.onSurface, c.surfaceContainerHighest),
          (c.onPrimary, c.primary),
          (c.onErrorContainer, c.errorContainer),
        ]) {
          final a = pair.$1.computeLuminance();
          final b = pair.$2.computeLuminance();
          final contrast =
              (a > b ? a + 0.05 : b + 0.05) / (a > b ? b + 0.05 : a + 0.05);
          expect(contrast, greaterThanOrEqualTo(4.5));
        }
      },
    );
  }

  testWidgets(
    'conversation messages use theme surfaces without repeated avatars',
    (tester) async {
      final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorScheme: scheme),
          home: Scaffold(
            body: Column(
              children: [
                MessageBubble(
                  message: Message(
                    chatId: 1,
                    role: MessageRole.user,
                    content: 'A short question',
                  ),
                ),
                MessageBubble(
                  message: Message(
                    chatId: 1,
                    role: MessageRole.assistant,
                    content: 'A short reply',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(CircleAvatar), findsNothing);
      final surfaces = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.color);
      expect(surfaces, contains(scheme.surfaceContainerHighest));
      expect(
        find.bySemanticsLabel('Assistant response: A short reply'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'assistant copy action is visible and uses the original message',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData')
            copied = (call.arguments as Map)['text'] as String;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: Message(
                chatId: 1,
                role: MessageRole.assistant,
                content: '**Original** reply',
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Copy message'));
      await tester.pump();
      expect(copied, '**Original** reply');
      expect(
        find.bySemanticsLabel('Assistant response: **Original** reply'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'empty composer disables Send and a failed submission keeps its draft',
    (tester) async {
      final pending = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChatInputField(onSend: (_) => pending.future)),
        ),
      );
      IconButton send() => tester.widget<IconButton>(
        find.byWidgetPredicate(
          (widget) =>
              widget is IconButton && widget.tooltip == AppStrings.sendMessage,
        ),
      );
      expect(send().onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'Recover this draft');
      await tester.pump();
      expect(send().onPressed, isNotNull);
      await tester.tap(find.byTooltip(AppStrings.sendMessage));
      await tester.pump();
      expect(send().onPressed, isNull);
      pending.completeError(StateError('private failure detail'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Recover this draft',
      );
      expect(find.textContaining('private failure detail'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Stop stays reachable while native cancellation is pending', (
    tester,
  ) async {
    var stops = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputField(
            status: ChatStatus.generating,
            onSend: (_) async {},
            onStop: () async {
              stops++;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip(AppStrings.stopGenerating));
    await tester.pump();
    expect(stops, 1);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
  });
}
