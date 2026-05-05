/// Tests shared settings form feedback primitives.
library;

import 'package:agentawesome_ui/app/theme.dart';
import 'package:agentawesome_ui/ui/settings/settings_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs settings form primitive tests.
void main() {
  test('save feedback retries and returns to idle after success', () async {
    final controller = SettingsSaveFeedbackController(
      retryDelay: Duration.zero,
      successDuration: const Duration(milliseconds: 1),
    );
    addTearDown(controller.dispose);
    var attempts = 0;

    final saved = await controller.run(() async {
      attempts++;
      if (attempts < 2) {
        throw StateError('transient failure');
      }
    });

    expect(saved, isTrue);
    expect(attempts, 2);
    expect(controller.state, SettingsSaveFeedbackState.success);

    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(controller.state, SettingsSaveFeedbackState.idle);
  });

  test('save feedback holds failure after retry limit', () async {
    final controller = SettingsSaveFeedbackController(
      maxAttempts: 2,
      retryDelay: Duration.zero,
    );
    addTearDown(controller.dispose);
    var attempts = 0;

    final saved = await controller.run(() async {
      attempts++;
      throw StateError('persistent failure');
    });

    expect(saved, isFalse);
    expect(attempts, 2);
    expect(controller.state, SettingsSaveFeedbackState.failure);
  });

  testWidgets('save feedback colors inherited field borders', (tester) async {
    final controller = SettingsSaveFeedbackController(
      successDuration: const Duration(seconds: 5),
    );
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsSaveFeedback(
              controller: controller,
              child: Builder(
                builder: (context) {
                  return TextField(
                    decoration: SettingsInputDecoration.field(
                      context,
                      label: 'Name',
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );

      expect(_enabledBorderColor(tester), AuroraColors.border);

      await controller.run(() async {});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(_enabledBorderColor(tester), AuroraColors.green);
    } finally {
      controller.dispose();
    }
  });
}

/// Returns the enabled border color from the test field decoration.
Color _enabledBorderColor(WidgetTester tester) {
  final field = tester.widget<TextField>(find.byType(TextField));
  final border = field.decoration?.enabledBorder;
  expect(border, isA<OutlineInputBorder>());
  return (border! as OutlineInputBorder).borderSide.color;
}
