/// Tests Aurora controller shutdown boundaries.
library;

import 'package:agentawesome_ui/app/app_config.dart';
import 'package:agentawesome_ui/app/app_controller.dart';
import 'package:agentawesome_ui/app/local_services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs controller shutdown tests.
void main() {
  test('closeClients leaves managed local services running', () {
    final localServices = _TrackingLocalServiceSupervisor();
    final controller = AuroraAppController(
      config: _testConfig(),
      localServices: localServices,
    );

    controller.closeClients();

    expect(localServices.closeCount, 0);
  });

  test('close stops managed local services once', () async {
    final localServices = _TrackingLocalServiceSupervisor();
    final controller = AuroraAppController(
      config: _testConfig(),
      localServices: localServices,
    );

    await controller.close();
    await controller.close();

    expect(localServices.closeCount, 1);
  });
}

/// Tracking supervisor records whether service shutdown was requested.
class _TrackingLocalServiceSupervisor extends LocalServiceSupervisor {
  /// Creates a tracking local service supervisor.
  _TrackingLocalServiceSupervisor() : super(config: _testConfig());

  /// Number of service shutdown requests.
  int closeCount = 0;

  /// Records service shutdown without touching real processes.
  @override
  Future<void> close() async {
    closeCount++;
  }
}

/// Builds a minimal app config for controller shutdown tests.
AppConfig _testConfig() {
  return const AppConfig(
    agentApiBaseUrl: 'http://127.0.0.1:8080/api',
    memoryMcpUrl: 'http://127.0.0.1:8090/mcp',
    agentAppName: 'personal_pilot',
    agentUserId: 'doug',
    workspaceRoot: '/tmp/agentawesome-ui-test',
    autoStartLocalServices: true,
    runtimeProfilePath: '',
  );
}
