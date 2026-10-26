import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/models/model_verification_phase.dart';
import 'package:vitalis_app/services/model_recovery_controller.dart';
import 'package:vitalis_app/widgets/model_recovery_status_label.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final width in [320.0, 768.0]) {
      testWidgets(
        'recovery status wraps in $brightness at $width with large text',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          for (final state in ModelRecoveryState.values) {
            await tester.pumpWidget(
              MaterialApp(
                theme: ThemeData(brightness: brightness),
                home: MediaQuery(
                  data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                  child: Scaffold(body: ModelRecoveryStatusLabel(state: state)),
                ),
              ),
            );
            expect(
              find.text(ModelRecoveryStatusLabel.message(state, null)),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          }
          for (final phase in ModelVerificationPhase.values) {
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: ModelRecoveryStatusLabel(
                    state: ModelRecoveryState.verifying,
                    phase: phase,
                  ),
                ),
              ),
            );
            expect(
              find.text(
                ModelRecoveryStatusLabel.message(
                  ModelRecoveryState.verifying,
                  phase,
                ),
              ),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }
}
