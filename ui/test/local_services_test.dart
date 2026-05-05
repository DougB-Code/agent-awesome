/// Tests managed local service process launch planning.
library;

import 'package:agentawesome_ui/app/local_services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs local service launch plan tests.
void main() {
  test('linux launch plan isolates service group and redirects output', () {
    final plan = buildServiceProcessLaunchPlan(
      executable: '/tmp/service-bin',
      arguments: const <String>['--addr', '127.0.0.1:9090'],
      outputLogPath: '/tmp/service.log',
      canStartProcessGroup: true,
      isWindows: false,
    );

    expect(plan.executable, 'setsid');
    expect(plan.ownsProcessGroup, isTrue);
    expect(plan.arguments, <String>[
      'sh',
      '-c',
      r'exec "$@" >> "$0" 2>&1',
      '/tmp/service.log',
      '/tmp/service-bin',
      '--addr',
      '127.0.0.1:9090',
    ]);
  });

  test('linux launch plan still redirects output without setsid support', () {
    final plan = buildServiceProcessLaunchPlan(
      executable: '/tmp/service-bin',
      arguments: const <String>['--flag'],
      outputLogPath: '/tmp/service.log',
      canStartProcessGroup: false,
      isWindows: false,
    );

    expect(plan.executable, 'sh');
    expect(plan.ownsProcessGroup, isFalse);
    expect(plan.arguments, <String>[
      '-c',
      r'exec "$@" >> "$0" 2>&1',
      '/tmp/service.log',
      '/tmp/service-bin',
      '--flag',
    ]);
  });

  test('windows launch plan keeps direct process command', () {
    final plan = buildServiceProcessLaunchPlan(
      executable: r'C:\service.exe',
      arguments: const <String>['--flag'],
      outputLogPath: r'C:\service.log',
      canStartProcessGroup: true,
      isWindows: true,
    );

    expect(plan.executable, r'C:\service.exe');
    expect(plan.ownsProcessGroup, isFalse);
    expect(plan.arguments, const <String>['--flag']);
  });

  test('go build arguments disable VCS stamping', () {
    final arguments = buildGoBuildArguments(
      outputPath: '/tmp/service-bin',
      packagePath: './cmd/service',
    );

    expect(arguments, const <String>[
      'build',
      '-buildvcs=false',
      '-o',
      '/tmp/service-bin',
      './cmd/service',
    ]);
  });
}
