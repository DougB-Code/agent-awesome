/// Drives Flutter integration tests from `flutter drive`.
library;

import 'package:integration_test/integration_test_driver.dart';

/// Starts the integration-test driver used by release E2E automation.
Future<void> main() => integrationDriver();
