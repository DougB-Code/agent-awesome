/// Builds environment maps for app-managed local service processes.
library;

import 'dart:io';

import 'app_config.dart';
import 'runtime_profile.dart';

const _managedGatewaySlackEnvironmentKeys = <String>[
  'SLACK_SIGNING_SECRET',
  'SLACK_BOT_TOKEN',
  'SLACK_APP_TOKEN',
  'SLACK_ALLOWED_TEAM_ID',
  'SLACK_ALLOWED_USER_ID',
  'SLACK_ALLOWED_CHANNEL_ID',
];

/// Builds the shared environment for subprocesses launched by the UI.
Map<String, String> buildLocalServiceEnvironment({
  required AppConfig config,
  required String goCachePath,
  Map<String, String>? baseEnvironment,
}) {
  final env = Map<String, String>.of(baseEnvironment ?? Platform.environment);
  _applyGatewayAuthorizationEnvironment(config, env);
  env.putIfAbsent(
    'AGENTAWESOME_CONFIG_DIR',
    () => agentAwesomeConfigDirectoryPath(),
  );
  env.putIfAbsent(
    'AGENTAWESOME_DATA_DIR',
    () => agentAwesomeDataDirectoryPath(),
  );
  env['GOCACHE'] = env['GOCACHE'] ?? goCachePath;
  return env;
}

/// Builds the environment for the UI-managed chat gateway process.
Map<String, String> buildManagedGatewayEnvironment({
  required AppConfig config,
  required String goCachePath,
  Map<String, String>? baseEnvironment,
}) {
  final env = buildLocalServiceEnvironment(
    config: config,
    goCachePath: goCachePath,
    baseEnvironment: baseEnvironment,
  );
  _disableSlackIngress(env);
  return env;
}

/// Exposes the UI-resolved gateway bearer header to managed child services.
void _applyGatewayAuthorizationEnvironment(
  AppConfig config,
  Map<String, String> env,
) {
  final header = config.gatewayAuthorizationHeader.trim();
  if (header.isEmpty) {
    return;
  }
  env.putIfAbsent('AGENTAWESOME_GATEWAY_AUTHORIZATION', () => header);
  final token = config.gatewayBearerToken;
  if (token.isNotEmpty) {
    env.putIfAbsent('AGENTAWESOME_GATEWAY_TOKEN', () => token);
  }
}

/// Prevents ambient Slack config from enabling the local chat gateway.
void _disableSlackIngress(Map<String, String> env) {
  env['SLACK_ENABLED'] = 'false';
  env['SLACK_SOCKET_MODE'] = 'false';
  for (final key in _managedGatewaySlackEnvironmentKeys) {
    env[key] = '';
  }
}
