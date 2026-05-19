/// Hosts first-run setup separately from the main workspace shell.
library;

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../theme.dart';
import 'getting_started_wizard.dart';

/// SetupWizardShell renders only the first-run model connection experience.
class SetupWizardShell extends StatelessWidget {
  /// Creates the setup shell bound to the shared app controller.
  const SetupWizardShell({super.key, required this.controller});

  /// Shared app controller used to persist setup choices.
  final AgentAwesomeAppController controller;

  /// Builds the dedicated setup shell without workspace navigation.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SizedBox.expand(
        child: ColoredBox(
          color: colors.surface,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: GettingStartedWizard(
                  controller: controller,
                  onComplete: () => controller.setGettingStartedCompleted(true),
                ),
              ),
              Positioned(
                top: 22,
                right: 24,
                child: TextButton(
                  onPressed: () => controller.setGettingStartedCompleted(true),
                  child: const Text('Continue to app'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
