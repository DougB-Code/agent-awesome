/// Tests shared settings form feedback primitives.
library;

import 'package:agentawesome_ui/ui/theme.dart';
import 'package:agentawesome_ui/domain/config_files.dart';
import 'package:agentawesome_ui/domain/model_config.dart';
import 'package:agentawesome_ui/ui/panels/panels.dart';
import 'package:agentawesome_ui/ui/settings/settings_form.dart';
import 'package:agentawesome_ui/ui/settings/settings_logic.dart';
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

  test('summary model labels collapse duplicate provider names', () {
    const choice = ModelConfigChoice(
      providerId: 'litert-lm',
      providerName: 'LiteRT-LM',
      modelId: 'gemma-4-e2b-it',
      modelName: 'gemma-4-E2B-it',
      isDefault: true,
    );
    const entry = ConfigFileEntry(
      path: '/tmp/model.yaml',
      kind: ConfigFileKind.model,
      assigned: false,
      displayName: 'LiteRT-LM',
    );

    expect(
      SettingsConfigLabels.summaryModelLabel(
        entry: entry,
        choice: choice,
        includeConfig: true,
      ),
      'LiteRT-LM / gemma-4-e2b-it',
    );
  });

  test('summary model labels keep distinct endpoint labels', () {
    const choice = ModelConfigChoice(
      providerId: 'openai',
      providerName: 'OpenAI',
      modelId: 'gpt-mini',
      modelName: 'gpt-5-mini',
      isDefault: true,
    );
    const entry = ConfigFileEntry(
      path: '/tmp/model.yaml',
      kind: ConfigFileKind.model,
      assigned: false,
      displayName: 'OpenAI staging',
    );

    expect(
      SettingsConfigLabels.summaryModelLabel(
        entry: entry,
        choice: choice,
        includeConfig: true,
      ),
      'OpenAI staging / OpenAI / gpt-mini',
    );
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

      expect(_enabledBorderColor(tester), AgentAwesomeColors.border);

      await controller.run(() async {});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(_enabledBorderColor(tester), AgentAwesomeColors.green);
    } finally {
      controller.dispose();
    }
  });

  testWidgets('multiline form decorations use textarea padding', (
    tester,
  ) async {
    InputDecoration? settingsSingleLine;
    InputDecoration? settingsTextArea;
    InputDecoration? panelSingleLine;
    InputDecoration? panelTextArea;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            settingsSingleLine = SettingsInputDecoration.field(
              context,
              label: 'Name',
            );
            settingsTextArea = SettingsInputDecoration.field(
              context,
              label: 'Description',
              multiline: true,
            );
            panelSingleLine = PanelFormDecoration.field(context, label: 'Name');
            panelTextArea = PanelFormDecoration.field(
              context,
              label: 'Description',
              multiline: true,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(
      settingsSingleLine?.contentPadding,
      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
    expect(
      settingsTextArea?.contentPadding,
      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
    expect(
      panelSingleLine?.contentPadding,
      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
    expect(
      panelTextArea?.contentPadding,
      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  });
}

/// Returns the enabled border color from the test field decoration.
Color _enabledBorderColor(WidgetTester tester) {
  final field = tester.widget<TextField>(find.byType(TextField));
  final border = field.decoration?.enabledBorder;
  expect(border, isA<OutlineInputBorder>());
  return (border! as OutlineInputBorder).borderSide.color;
}
