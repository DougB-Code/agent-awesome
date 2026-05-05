/// Tests app-owned settings serialization.
library;

import 'package:agentawesome_ui/app/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs app settings tests.
void main() {
  test('serializes exact summary model selection', () {
    const settings = AuroraAppSettings(
      defaultChatProfilePath: '/tmp/profile.json',
      summaryModelConfigPath: '/tmp/models.yaml',
      summaryModelRef: 'openai:gpt-nano',
      chatTitleSummariesEnabled: true,
    );

    final encoded = settings.toJson();
    final decoded = AuroraAppSettings.fromJson(encoded);

    expect(encoded['summary_model_ref'], 'openai:gpt-nano');
    expect(decoded.summaryModelConfigPath, '/tmp/models.yaml');
    expect(decoded.summaryModelRef, 'openai:gpt-nano');
  });
}
